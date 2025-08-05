//go:build (dev_test || staging_test) && integration

package integration

import (
        "encoding/json"
        "net/http"
        "testing"
        "time"

        "github.com/google/uuid"
        "github.com/stretchr/testify/require"

        internal_dtos "github.com/poofware/account-service/internal/dtos"
        "github.com/poofware/account-service/internal/routes"
        "github.com/poofware/go-models"
        testhelpers "github.com/poofware/go-testhelpers"
)

func TestSubmitPersonalInfo_Waitlist(t *testing.T) {
	h.T = t
	ctx := h.Ctx

        worker := &models.Worker{
                ID:          uuid.New(),
                Email:       "waitlist+" + uuid.NewString() + "@thepoofapp.com",
                PhoneNumber: testhelpers.UniquePhone(),
                TOTPSecret:  "test-secret",
                FirstName:   "Wait",
                LastName:    "Lister",
        }
	require.NoError(t, h.WorkerRepo.Create(ctx, worker))
	defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, worker.ID)

	token := h.CreateMobileJWT(worker.ID, "test-device-id", "FAKE-PLAY")

	reqPayload := internal_dtos.SubmitPersonalInfoRequest{
		StreetAddress: "123 Main St",
		City:          "Town",
		State:         "CA",
		ZipCode:       "90210",
		VehicleYear:   2020,
		VehicleMake:   "Toyota",
		VehicleModel:  "Prius",
	}
	body, _ := json.Marshal(reqPayload)
	req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.WorkerSubmitPersonalInfo, token, body, "android", "test-device-id")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	wUpdated, err := h.WorkerRepo.GetByID(ctx, worker.ID)
	require.NoError(t, err)
	require.True(t, wUpdated.OnWaitlist)
	require.NotNil(t, wUpdated.WaitlistedAt)
	require.Equal(t, models.SetupProgressIDVerify, wUpdated.SetupProgress)
}

func TestWorkerRepository_WaitlistQueries(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	w1 := &models.Worker{ID: uuid.New(), Email: "a1@wait.test", PhoneNumber: "+15552220001", TOTPSecret: "s1", FirstName: "A", LastName: "One"}
	w2 := &models.Worker{ID: uuid.New(), Email: "a2@wait.test", PhoneNumber: "+15552220002", TOTPSecret: "s2", FirstName: "B", LastName: "Two"}
	w3 := &models.Worker{ID: uuid.New(), Email: "a3@wait.test", PhoneNumber: "+15552220003", TOTPSecret: "s3", FirstName: "C", LastName: "Three"}
	require.NoError(t, h.WorkerRepo.Create(ctx, w1))
	require.NoError(t, h.WorkerRepo.Create(ctx, w2))
	require.NoError(t, h.WorkerRepo.Create(ctx, w3))
	defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id IN ($1,$2,$3)`, w1.ID, w2.ID, w3.ID)

	_, err := h.DB.Exec(ctx, `UPDATE workers SET on_waitlist=false WHERE id IN ($1,$2)`, w1.ID, w2.ID)
	require.NoError(t, err)
	_, err = h.DB.Exec(ctx, `UPDATE workers SET waitlisted_at=$2 WHERE id=$1`, w3.ID, time.Now().Add(-time.Minute))
	require.NoError(t, err)

	count, err := h.WorkerRepo.GetActiveWorkerCount(ctx)
	require.NoError(t, err)
	require.Equal(t, 2, count)

	list, err := h.WorkerRepo.ListOldestWaitlistedWorkers(ctx, 1)
	require.NoError(t, err)
	require.Len(t, list, 1)
	require.Equal(t, w3.ID, list[0].ID)
}
