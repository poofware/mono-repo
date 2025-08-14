//go:build (dev_test || staging_test) && integration

package integration

import (
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

/*
   We test optimistic locking (UpdateWithRetry) in two modes each for Worker & PM:
      1) "Stress": concurrent updaters try to cause collisions naturally.
      2) "ForcedConflict": we ensure all goroutines read the same row_version
         before any update runs, guaranteeing collisions. We verify that it
         still succeeds within the default 3 retries.

   Because concurrency is only 3, and the default maxRetries=3, it's enough
   that each collision eventually succeeds.
*/

const concurrency = 3 // number of goroutines in each test

/* ────────────────────────── WORKER TESTS ─────────────────────────── */

// --- Stress

func TestWorker_UpdateWithRetry_Stress(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	// Fresh Worker
	w := &models.Worker{
		ID:            uuid.New(),
		Email:         fmt.Sprintf("stress_worker_%s@example.com", uuid.NewString()[:8]),
		PhoneNumber:   "+15550001111",
		FirstName:     "Stress",
		LastName:      "Tester",
		AccountStatus: models.AccountStatusIncomplete,
		SetupProgress: models.SetupProgressIDVerify,
	}
	require.NoError(t, h.WorkerRepo.Create(ctx, w))
	defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, w.ID)

	var wg sync.WaitGroup
	errCh := make(chan error, concurrency)

	// Launch concurrency goroutines
	for i := range concurrency {
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			err := h.WorkerRepo.UpdateWithRetry(ctx, w.ID, func(wo *models.Worker) error {
				wo.LastName = fmt.Sprintf("stress_%d", n)
				// short sleep to widen the race window
				time.Sleep(10 * time.Millisecond)
				return nil
			})
			errCh <- err
		}(i)
	}

	wg.Wait()
	close(errCh)

	// All must succeed
	for e := range errCh {
		require.NoError(t, e, "Worker Stress: unexpected concurrency error")
	}

	// row_version = 1 (insert) + concurrency
	wFinal, err := h.WorkerRepo.GetByID(ctx, w.ID)
	require.NoError(t, err)
	require.Equal(t, int64(1+concurrency), wFinal.RowVersion,
		"row_version not advanced by concurrency in Worker Stress test")
}

// --- Forced Conflict

func TestWorker_UpdateWithRetry_ForcedConflict(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	// Fresh Worker
	w := &models.Worker{
		ID:            uuid.New(),
		Email:         fmt.Sprintf("forced_worker_%s@example.com", uuid.NewString()[:8]),
		PhoneNumber:   "+15550002222",
		FirstName:     "Forced",
		LastName:      "Tester",
		AccountStatus: models.AccountStatusIncomplete,
		SetupProgress: models.SetupProgressIDVerify,
	}
	require.NoError(t, h.WorkerRepo.Create(ctx, w))
	defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, w.ID)

	runForcedConflictTest(
		t,
		func(n int, count *int64) error {
			return h.WorkerRepo.UpdateWithRetry(ctx, w.ID, func(wo *models.Worker) error {
				// Track how many times mutate is called (including retries)
				atomic.AddInt64(count, 1)
				wo.LastName = fmt.Sprintf("forced_%d", n)
				return nil
			})
		},
		func() int64 {
			wNow, err := h.WorkerRepo.GetByID(ctx, w.ID)
			require.NoError(t, err)
			return wNow.RowVersion
		},
	)
}

/* ───────────────────── PROPERTY MANAGER TESTS ───────────────────── */

// --- Stress

func TestPM_UpdateWithRetry_Stress(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	pm := &models.PropertyManager{
		ID:            uuid.New(),
		Email:         fmt.Sprintf("stress_pm_%s@example.com", uuid.NewString()[:8]),
		PhoneNumber:   utils.Ptr("+15550003333"),
		BusinessName:  "Stress PM",
		AccountStatus: models.AccountStatusIncomplete,
		SetupProgress: models.SetupProgressIDVerify,
	}
	require.NoError(t, h.PMRepo.Create(ctx, pm))
	defer h.DB.Exec(ctx, `DELETE FROM property_managers WHERE id=$1`, pm.ID)

	var wg sync.WaitGroup
	errCh := make(chan error, concurrency)

	for i := range concurrency {
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			err := h.PMRepo.UpdateWithRetry(ctx, pm.ID, func(p *models.PropertyManager) error {
				p.BusinessName = fmt.Sprintf("stress_%d", n)
				time.Sleep(10 * time.Millisecond)
				return nil
			})
			errCh <- err
		}(i)
	}

	wg.Wait()
	close(errCh)

	for e := range errCh {
		require.NoError(t, e, "PM Stress: unexpected concurrency error")
	}

	pmFinal, err := h.PMRepo.GetByID(ctx, pm.ID)
	require.NoError(t, err)
	require.Equal(t, int64(1+concurrency), pmFinal.RowVersion,
		"row_version not advanced by concurrency in PM Stress test")
}

// --- Forced Conflict

func TestPM_UpdateWithRetry_ForcedConflict(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	pm := &models.PropertyManager{
		ID:            uuid.New(),
		Email:         fmt.Sprintf("forced_pm_%s@example.com", uuid.NewString()[:8]),
		PhoneNumber:   utils.Ptr("+15550004444"),
		BusinessName:  "Forced PM",
		AccountStatus: models.AccountStatusIncomplete,
		SetupProgress: models.SetupProgressIDVerify,
	}
	require.NoError(t, h.PMRepo.Create(ctx, pm))
	defer h.DB.Exec(ctx, `DELETE FROM property_managers WHERE id=$1`, pm.ID)

	runForcedConflictTest(
		t,
		func(n int, count *int64) error {
			return h.PMRepo.UpdateWithRetry(ctx, pm.ID, func(p *models.PropertyManager) error {
				atomic.AddInt64(count, 1)
				p.BusinessName = fmt.Sprintf("forced_%d", n)
				return nil
			})
		},
		func() int64 {
			pmNow, err := h.PMRepo.GetByID(ctx, pm.ID)
			require.NoError(t, err)
			return pmNow.RowVersion
		},
	)
}

/* ─────────────────────  SHARED FORCED‑CONFLICT LOGIC ──────────────────── */

func runForcedConflictTest(
	t *testing.T,
	doUpdate func(n int, mutateCount *int64) error,
	getRowVersion func() int64,
) {
	h.T = t
	var mutateCount int64

	gate := make(chan struct{})
	var ready sync.WaitGroup
	ready.Add(concurrency)

	var wg sync.WaitGroup
	errCh := make(chan error, concurrency)

	for i := range concurrency {
		wg.Add(1)
		go func(n int) {
			defer wg.Done()

			_ = getRowVersion()
			ready.Done()
			<-gate

			errCh <- doUpdate(n, &mutateCount)
		}(i)
	}

	ready.Wait()
	close(gate)

	wg.Wait()
	close(errCh)

	for e := range errCh {
		require.NoError(t, e, "ForcedConflict: UpdateWithRetry returned error")
	}

	require.Greater(t, atomic.LoadInt64(&mutateCount), int64(concurrency),
		"No forced conflict detected (mutate calls should exceed concurrency)")

	final := getRowVersion()
	require.Equal(t, int64(1+concurrency), final,
		"row_version not advanced by concurrency in forcedConflictTest")
}

