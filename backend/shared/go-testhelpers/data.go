// backend/shared/go-testhelpers/data.go

package testhelpers

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"sort"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
	"github.com/stretchr/testify/require"
)

// UniquePhone generates a unique phone number for testing.
func UniquePhone() string {
	return fmt.Sprintf("+1555%07d", rand.New(rand.NewSource(time.Now().UnixNano())).Int31n(1e7))
}

// UniqueEmail generates a unique email for testing.
func UniqueEmail(prefix string) string {
	return fmt.Sprintf("%s-%d@thepoofapp.com", prefix, time.Now().UnixNano())
}

// CreateTestPM creates and persists a new property manager.
func (h *TestHelper) CreateTestPM(ctx context.Context, emailPrefix string) *models.PropertyManager {
	pm := &models.PropertyManager{
		ID:              uuid.New(),
		Email:           UniqueEmail(emailPrefix),
		PhoneNumber:     utils.Ptr(UniquePhone()),
		TOTPSecret:      "pm-totp-" + uuid.NewString()[:8],
		BusinessName:    "Test Business",
		BusinessAddress: "456 Test Ave",
		City:            "Testville",
		State:           "TS",
		ZipCode:         "54321",
		AccountStatus:   models.PMAccountStatusActive,
		SetupProgress:   models.SetupProgressDone,
	}
	require.NoError(h.T, h.PMRepo.Create(ctx, pm), "Failed to create test property manager")

	createdPM, err := h.PMRepo.GetByID(ctx, pm.ID)
	require.NoError(h.T, err)
	require.NotNil(h.T, createdPM, "Failed to fetch PM immediately after creation")
	return createdPM
}

// CreateTestWorker creates and persists a new worker, then updates it to be ACTIVE and DONE.
func (h *TestHelper) CreateTestWorker(ctx context.Context, emailPrefix string, score ...int) *models.Worker {
	reliabilityScore := 100
	if len(score) > 0 {
		reliabilityScore = score[0]
	}

	// Create with only the fields accepted by the repository's Create method.
	w := &models.Worker{
		ID:          uuid.New(),
		Email:       UniqueEmail(emailPrefix),
		PhoneNumber: UniquePhone(),
		FirstName:   "Test",
		LastName:    emailPrefix,
		TOTPSecret:  "worker-totp-" + uuid.NewString()[:8],
	}
	require.NoError(h.T, h.WorkerRepo.Create(ctx, w), "Failed to create test worker")

	// Update the newly created worker with address, vehicle, and status info.
	updateErr := h.WorkerRepo.UpdateWithRetry(ctx, w.ID, func(workerToUpdate *models.Worker) error {
		workerToUpdate.StreetAddress = "123 Test St"
		workerToUpdate.City = "Testville"
		workerToUpdate.State = "TS"
		workerToUpdate.ZipCode = "12345"
		workerToUpdate.VehicleYear = 2022
		workerToUpdate.VehicleMake = "Test-Make"
		workerToUpdate.VehicleModel = "Test-Model"
		workerToUpdate.AccountStatus = models.AccountStatusActive
		workerToUpdate.SetupProgress = models.SetupProgressDone
		workerToUpdate.ReliabilityScore = reliabilityScore
		return nil
	})
	require.NoError(h.T, updateErr, "Failed to update test worker with details")

	createdWorker, err := h.WorkerRepo.GetByID(ctx, w.ID)
	require.NoError(h.T, err)
	require.NotNil(h.T, createdWorker, "Failed to fetch worker immediately after creation and update")
	return createdWorker
}

// CreateTestWorkerWithConnectID creates a worker and manually sets their Stripe Connect ID.
func (h *TestHelper) CreateTestWorkerWithConnectID(ctx context.Context, emailPrefix, connectID string) *models.Worker {
	w := h.CreateTestWorker(ctx, emailPrefix)

	// Manually update the connect ID
	err := h.WorkerRepo.UpdateWithRetry(ctx, w.ID, func(wToUpdate *models.Worker) error {
		wToUpdate.StripeConnectAccountID = &connectID
		return nil
	})
	require.NoError(h.T, err, "Failed to update worker with connect ID")

	updatedWorker, err := h.WorkerRepo.GetByID(ctx, w.ID)
	require.NoError(h.T, err)
	require.NotNil(h.T, updatedWorker.StripeConnectAccountID)
	require.Equal(h.T, connectID, *updatedWorker.StripeConnectAccountID)

	return updatedWorker
}

// UpdateWorkerWithConnectID updates an existing worker with a Stripe Connect ID.
func (h *TestHelper) UpdateWorkerWithConnectID(ctx context.Context, worker *models.Worker, connectID string) *models.Worker {
	// Manually update the connect ID using the repository's concurrency-safe method.
	err := h.WorkerRepo.UpdateWithRetry(ctx, worker.ID, func(wToUpdate *models.Worker) error {
		wToUpdate.StripeConnectAccountID = &connectID
		return nil
	})
	require.NoError(h.T, err, "Failed to update worker with connect ID")

	// Fetch the updated record to ensure the change was persisted and return the latest model.
	updatedWorker, err := h.WorkerRepo.GetByID(ctx, worker.ID)
	require.NoError(h.T, err)
	require.NotNil(h.T, updatedWorker.StripeConnectAccountID)
	require.Equal(h.T, connectID, *updatedWorker.StripeConnectAccountID)

	return updatedWorker
}

// CreateTestProperty creates and persists a new property.
func (h *TestHelper) CreateTestProperty(ctx context.Context, propName string, managerID uuid.UUID, lat, lng float64) *models.Property {
	p := &models.Property{
		ID:           uuid.New(),
		ManagerID:    managerID,
		PropertyName: propName,
		Address:      fmt.Sprintf("%s Address", propName),
		City:         "Testville",
		State:        "TS",
		ZipCode:      "00000",
		TimeZone:     "UTC",
		Latitude:     lat,
		Longitude:    lng,
	}
	require.NoError(h.T, h.PropertyRepo.Create(ctx, p))
	return p
}

// CreateTestBuilding creates and persists a new building.
func (h *TestHelper) CreateTestBuilding(ctx context.Context, propID uuid.UUID, bldgName string) *models.PropertyBuilding {
	b := &models.PropertyBuilding{
		ID:           uuid.New(),
		PropertyID:   propID,
		BuildingName: bldgName,
		Address:      utils.Ptr(fmt.Sprintf("%s Address", bldgName)),
	}
	require.NoError(h.T, h.BldgRepo.Create(ctx, b))
	return b
}

// NEW: CreateTestUnit creates and persists a new unit.
func (h *TestHelper) CreateTestUnit(ctx context.Context, propID, bldgID uuid.UUID, unitNum string) *models.Unit {
	u := &models.Unit{
		ID:          uuid.New(),
		PropertyID:  propID,
		BuildingID:  bldgID,
		UnitNumber:  unitNum,
		TenantToken: uuid.NewString(),
	}
	require.NoError(h.T, h.UnitRepo.Create(ctx, u), "Failed to create test unit")
	return u
}

// CreateTestDumpster creates and persists a new dumpster.
func (h *TestHelper) CreateTestDumpster(ctx context.Context, propID uuid.UUID, dumpsterNum string) *models.Dumpster {
	d := &models.Dumpster{
		ID:             uuid.New(),
		PropertyID:     propID,
		DumpsterNumber: dumpsterNum,
	}
	require.NoError(h.T, h.DumpsterRepo.Create(ctx, d))
	return d
}

// CreateTestJobDefinition creates and persists a new job definition with sane defaults.
func (h *TestHelper) CreateTestJobDefinition(t *testing.T, ctx context.Context, managerID, propID uuid.UUID, title string,
	buildingIDs, dumpsterIDs []uuid.UUID, earliest, latest time.Time, status models.JobStatusType,
	dailyEstimates []models.DailyPayEstimate, freq models.JobFrequencyType, weekdays []int16) *models.JobDefinition {

	if len(buildingIDs) == 0 {
		b := h.CreateTestBuilding(ctx, propID, fmt.Sprintf("DefBldg-%s", title[:min(len(title), 10)]))
		buildingIDs = []uuid.UUID{b.ID}
	}
	if len(dumpsterIDs) == 0 {
		d := h.CreateTestDumpster(ctx, propID, fmt.Sprintf("DefDump-%s", title[:min(len(title), 10)]))
		dumpsterIDs = []uuid.UUID{d.ID}
	}

	if len(dailyEstimates) == 0 {
		dailyEstimates = make([]models.DailyPayEstimate, 7)
		for i := range 7 {
			dailyEstimates[i] = models.DailyPayEstimate{
				DayOfWeek:                   time.Weekday(i),
				BasePay:                     50.0,
				InitialBasePay:              50.0,
				EstimatedTimeMinutes:        60,
				InitialEstimatedTimeMinutes: 60,
			}
		}
	}

	duration := latest.Sub(earliest)
	hint := earliest.Add(duration / 2)

	assigned := make([]models.AssignedUnitGroup, len(buildingIDs))
	floorSet := make(map[int16]struct{})
	totalUnits := 0
	for i, bID := range buildingIDs {
		assigned[i] = models.AssignedUnitGroup{BuildingID: bID, UnitIDs: []uuid.UUID{}, Floors: []int16{1}}
		for _, f := range assigned[i].Floors {
			floorSet[f] = struct{}{}
		}
		totalUnits += len(assigned[i].UnitIDs)
	}
	floors := make([]int16, 0, len(floorSet))
	for f := range floorSet {
		floors = append(floors, f)
	}
	sort.Slice(floors, func(i, j int) bool { return floors[i] < floors[j] })

	def := &models.JobDefinition{
		ID:                      uuid.New(),
		ManagerID:               managerID,
		PropertyID:              propID,
		Title:                   title,
		AssignedUnitsByBuilding: assigned,
		Floors:                  floors,
		TotalUnits:              totalUnits,
		DumpsterIDs:             dumpsterIDs,
		Frequency:               freq,
		Weekdays:                weekdays,
		Status:                  status,
		StartDate:               time.Now().UTC().AddDate(0, 0, -1),
		EarliestStartTime:       earliest,
		LatestStartTime:         latest,
		StartTimeHint:           hint,
		DailyPayEstimates:       dailyEstimates,
	}
	require.NoError(t, h.JobDefRepo.Create(ctx, def))
	createdDef, err := h.JobDefRepo.GetByID(ctx, def.ID)
	require.NoError(t, err)
	require.NotNil(t, createdDef)
	return createdDef
}

// CreateTestJobInstance creates and persists a job instance. If an instance for the same definition
// and date already exists (a unique constraint violation), it fetches and returns the existing instance.
func (h *TestHelper) CreateTestJobInstance(t *testing.T, ctx context.Context, defID uuid.UUID, serviceDate time.Time, status models.InstanceStatusType, assignedWorkerID *uuid.UUID, pay ...float64) *models.JobInstance {
	var effectivePay float64
	if len(pay) > 0 {
		effectivePay = pay[0]
	} else {
		def, err := h.JobDefRepo.GetByID(ctx, defID)
		require.NoError(t, err, "Failed to get job definition in CreateTestJobInstance helper")
		require.NotNil(t, def, "Job definition not found in CreateTestJobInstance helper")

		dailyEstimate := def.GetDailyEstimate(serviceDate.Weekday())
		if dailyEstimate != nil {
			effectivePay = dailyEstimate.BasePay
		} else {
			effectivePay = 50.0 // Fallback test pay
		}
	}

	inst := &models.JobInstance{
		ID:               uuid.New(),
		DefinitionID:     defID,
		ServiceDate:      serviceDate.Truncate(24 * time.Hour),
		Status:           status,
		AssignedWorkerID: assignedWorkerID,
		EffectivePay:     effectivePay,
	}

	err := h.JobInstRepo.Create(ctx, inst)
	if err != nil {
		var pgErr *pgconn.PgError
		// If it's a unique violation, it means an instance for this day already exists.
		// This is acceptable for many test setups, so we'll fetch and return the existing one.
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			t.Logf("Job instance for def %s on %s already exists, fetching it instead.", defID, serviceDate.Format("2006-01-02"))
			dateOnly := serviceDate.Truncate(24 * time.Hour)
			existingInstances, fetchErr := h.JobInstRepo.ListInstancesByDefinitionIDs(ctx, []uuid.UUID{defID}, dateOnly, dateOnly)
			require.NoError(t, fetchErr, "Failed to fetch existing job instance after unique violation")
			require.Len(t, existingInstances, 1, "Expected to find exactly one existing instance after unique violation")
			return existingInstances[0]
		}
		// For any other error, fail the test.
		require.NoError(t, err, "Failed to create test job instance with a non-unique-violation error")
	}

	createdInst, err := h.JobInstRepo.GetByID(ctx, inst.ID)
	require.NoError(t, err)
	require.NotNil(t, createdInst)
	return createdInst
}

// MakeWorkerTenant associates a worker with a property by creating a unit and assigning the token.
func (h *TestHelper) MakeWorkerTenant(t *testing.T, ctx context.Context, worker *models.Worker, propertyID uuid.UUID) *models.Worker {
	bldg := h.CreateTestBuilding(ctx, propertyID, "TenantBldgFor"+worker.ID.String()[:4])
	unit := &models.Unit{
		ID:          uuid.New(),
		PropertyID:  propertyID,
		BuildingID:  bldg.ID,
		UnitNumber:  "T-" + worker.ID.String()[:4],
		TenantToken: uuid.NewString(),
	}
	require.NoError(t, h.UnitRepo.Create(ctx, unit))

	worker.TenantToken = &unit.TenantToken
	err := h.WorkerRepo.UpdateWithRetry(ctx, worker.ID, func(wToUpdate *models.Worker) error {
		wToUpdate.TenantToken = &unit.TenantToken
		return nil
	})
	require.NoError(t, err, "Failed to update worker with tenant token")

	updatedWorker, err := h.WorkerRepo.GetByID(ctx, worker.ID)
	require.NoError(t, err)
	require.NotNil(t, updatedWorker.TenantToken)
	require.Equal(t, unit.TenantToken, *updatedWorker.TenantToken)
	return updatedWorker
}

// FetchWorkerAccountID fetches a worker's Stripe Connect account ID from the database.
func (h *TestHelper) FetchWorkerAccountID(workerID uuid.UUID) string {
	w, err := h.WorkerRepo.GetByID(h.Ctx, workerID)
	require.NoError(h.T, err, "workerRepo.GetByID failed while fetching account ID")
	require.NotNil(h.T, w, "No worker returned by repo while fetching account ID")
	require.NotNil(h.T, w.StripeConnectAccountID, "stripe_connect_account_id is nil on worker record")
	return *w.StripeConnectAccountID
}
