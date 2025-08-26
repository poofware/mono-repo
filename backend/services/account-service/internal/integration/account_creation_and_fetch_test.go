// backend/services/account-service/internal/integration/account_creation_and_fetch_test.go

//go:build (dev_test || staging_test) && integration

package integration

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	account_dtos "github.com/poofware/mono-repo/backend/services/account-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/services/account-service/internal/routes"
	"github.com/poofware/mono-repo/backend/shared/go-dtos"
	"github.com/poofware/mono-repo/backend/shared/go-middleware"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

// TestWorkerCreateAndFetch creates a worker via repository and fetches it back via repo and REST.
func TestWorkerCreateAndFetch(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	// --- define full worker for assertions later
	fullWorker := &models.Worker{
		ID:            uuid.New(),
		Email:         "inttest+" + uuid.NewString() + "@poof.test",
		PhoneNumber:   "+15551112222",
		TOTPSecret:    "my‑totp‑secret",
		FirstName:     "Will",
		LastName:      "Worker",
		StreetAddress: "123 Test St",
		AptSuite:      nil,
		City:          "Huntsville",
		State:         "AL",
		ZipCode:       "35806",
		VehicleYear:   2021,
		VehicleMake:   "Toyota",
		VehicleModel:  "Tacoma",
	}

	// --- create with minimal fields
	workerForCreate := &models.Worker{
		ID:          fullWorker.ID,
		Email:       fullWorker.Email,
		PhoneNumber: fullWorker.PhoneNumber,
		TOTPSecret:  fullWorker.TOTPSecret,
		FirstName:   fullWorker.FirstName,
		LastName:    fullWorker.LastName,
	}

	start := time.Now()
	require.NoError(t, h.WorkerRepo.Create(ctx, workerForCreate), "failed to insert test worker")
	defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, fullWorker.ID)

	// --- update with address and vehicle info
	require.NoError(t, h.WorkerRepo.UpdateWithRetry(ctx, fullWorker.ID, func(w *models.Worker) error {
		w.StreetAddress = fullWorker.StreetAddress
		w.AptSuite = fullWorker.AptSuite
		w.City = fullWorker.City
		w.State = fullWorker.State
		w.ZipCode = fullWorker.ZipCode
		w.VehicleYear = fullWorker.VehicleYear
		w.VehicleMake = fullWorker.VehicleMake
		w.VehicleModel = fullWorker.VehicleModel
		return nil
	}), "failed to update worker with address/vehicle info")

	// --- repo read‑back
	wGot, err := h.WorkerRepo.GetByID(ctx, fullWorker.ID)
	require.NoError(t, err)
	require.NotNil(t, wGot)

	// every persistent field
	require.Equal(t, fullWorker.ID, wGot.ID)
	require.Equal(t, fullWorker.Email, wGot.Email)
	require.Equal(t, fullWorker.PhoneNumber, wGot.PhoneNumber)
	require.Equal(t, fullWorker.TOTPSecret, wGot.TOTPSecret)
	require.Equal(t, fullWorker.FirstName, wGot.FirstName)
	require.Equal(t, fullWorker.LastName, wGot.LastName)
	require.Equal(t, fullWorker.StreetAddress, wGot.StreetAddress)
	require.Equal(t, fullWorker.AptSuite, wGot.AptSuite)
	require.Equal(t, fullWorker.City, wGot.City)
	require.Equal(t, fullWorker.State, wGot.State)
	require.Equal(t, fullWorker.ZipCode, wGot.ZipCode)
	require.Equal(t, fullWorker.VehicleYear, wGot.VehicleYear)
	require.Equal(t, fullWorker.VehicleMake, wGot.VehicleMake)
	require.Equal(t, fullWorker.VehicleModel, wGot.VehicleModel)
	require.Equal(t, models.AccountStatusIncomplete, wGot.AccountStatus)           // Assert default
	require.Equal(t, models.SetupProgressAwaitingPersonalInfo, wGot.SetupProgress) // Assert default
	require.Nil(t, wGot.StripeConnectAccountID)
	require.Nil(t, wGot.CurrentStripeIdvSessionID)
	require.Nil(t, wGot.CheckrCandidateID)
	require.Nil(t, wGot.CheckrInvitationID)
	require.Nil(t, wGot.CheckrReportID)
	require.Equal(t, models.ReportOutcomeUnknownStatus, wGot.CheckrReportOutcome)
	require.Nil(t, wGot.CheckrReportETA)
	require.Equal(t, int64(2), wGot.RowVersion) // 1 for create, 1 for update
	require.False(t, wGot.CreatedAt.IsZero())
	require.False(t, wGot.UpdatedAt.IsZero())
	require.WithinDuration(t, start, wGot.CreatedAt, 5*time.Second)
	require.True(t, wGot.UpdatedAt.After(wGot.CreatedAt), "UpdatedAt should be after CreatedAt")

	// --- REST read‑back (DTO)
	accessToken := h.CreateMobileJWT(fullWorker.ID, "test-device-id", "FAKE-PLAY")
	req := h.BuildAuthRequest(http.MethodGet, h.BaseURL+routes.WorkerBase, accessToken, nil, "android", "test-device-id")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	body := h.ReadBody(resp)
	var dtoResp dtos.Worker
	require.NoError(t, json.Unmarshal([]byte(body), &dtoResp))

	require.Equal(t, fullWorker.Email, dtoResp.Email)
	require.Equal(t, fullWorker.PhoneNumber, dtoResp.PhoneNumber)
	require.Equal(t, fullWorker.FirstName, dtoResp.FirstName)
	require.Equal(t, fullWorker.LastName, dtoResp.LastName)
	require.Equal(t, fullWorker.StreetAddress, dtoResp.StreetAddress)
	require.Equal(t, fullWorker.AptSuite, dtoResp.AptSuite)
	require.Equal(t, fullWorker.City, dtoResp.City)
	require.Equal(t, fullWorker.State, dtoResp.State)
	require.Equal(t, fullWorker.ZipCode, dtoResp.ZipCode)
	require.Equal(t, fullWorker.VehicleYear, dtoResp.VehicleYear)
	require.Equal(t, fullWorker.VehicleMake, dtoResp.VehicleMake)
	require.Equal(t, fullWorker.VehicleModel, dtoResp.VehicleModel)
	require.Equal(t, models.AccountStatusIncomplete, dtoResp.AccountStatus)           // Assert default
	require.Equal(t, models.SetupProgressAwaitingPersonalInfo, dtoResp.SetupProgress) // Assert default
	require.Equal(t, models.ReportOutcomeUnknownStatus, dtoResp.CheckrReportOutcome)
	require.Nil(t, dtoResp.CheckrReportETA)
}

// TestPropertyManagerCreateAndFetch tests PM creation and fetching.
func TestPropertyManagerCreateAndFetch(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	pm := &models.PropertyManager{
		ID:              uuid.New(),
		Email:           "inttest+" + uuid.NewString() + "@pm.test",
		PhoneNumber:     utils.Ptr("+15553334444"),
		TOTPSecret:      "pm‑totp‑secret",
		BusinessName:    "Test PM LLC",
		BusinessAddress: "456 Admin Rd",
		City:            "Birmingham",
		State:           "AL",
		ZipCode:         "35203",
	}

	start := time.Now()
	require.NoError(t, h.PMRepo.Create(ctx, pm), "failed to insert test PM")
	defer h.DB.Exec(ctx, `DELETE FROM property_managers WHERE id=$1`, pm.ID)

	// --- repo read‑back
	pmGot, err := h.PMRepo.GetByID(ctx, pm.ID)
	require.NoError(t, err)
	require.NotNil(t, pmGot)

	require.Equal(t, pm.ID, pmGot.ID)
	require.Equal(t, pm.Email, pmGot.Email)
	require.Equal(t, *pm.PhoneNumber, *pmGot.PhoneNumber)
	require.Equal(t, pm.TOTPSecret, pmGot.TOTPSecret)
	require.Equal(t, pm.BusinessName, pmGot.BusinessName)
	require.Equal(t, pm.BusinessAddress, pmGot.BusinessAddress)
	require.Equal(t, pm.City, pmGot.City)
	require.Equal(t, pm.State, pmGot.State)
	require.Equal(t, pm.ZipCode, pmGot.ZipCode)
	require.Equal(t, models.PMAccountStatusIncomplete, pmGot.AccountStatus)   // Assert default
	require.Equal(t, models.PMSetupProgressAwaitingInfo, pmGot.SetupProgress) // Assert default
	require.Equal(t, int64(1), pmGot.RowVersion)
	require.False(t, pmGot.CreatedAt.IsZero())
	require.False(t, pmGot.UpdatedAt.IsZero())
	require.WithinDuration(t, start, pmGot.CreatedAt, 5*time.Second)
	require.WithinDuration(t, pmGot.CreatedAt, pmGot.UpdatedAt, 5*time.Second)

	// --- REST read‑back (DTO)
	accessToken := h.CreateWebJWT(pm.ID, "127.0.0.1")
	req := h.BuildAuthRequest(http.MethodGet, h.BaseURL+routes.PMBase, "", nil, "web", "127.0.0.1")
	req.AddCookie(&http.Cookie{
		Name:     middleware.AccessTokenCookieName,
		Value:    accessToken,
		Path:     "/",
		Secure:   true,
		HttpOnly: true,
	})

	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	body := h.ReadBody(resp)
	var dtoResp dtos.PropertyManager
	require.NoError(t, json.Unmarshal([]byte(body), &dtoResp))

	require.Equal(t, pm.Email, dtoResp.Email)
	require.NotNil(t, dtoResp.PhoneNumber)
	require.Equal(t, *pm.PhoneNumber, *dtoResp.PhoneNumber)
	require.Equal(t, pm.BusinessName, dtoResp.BusinessName)
	require.Equal(t, pm.BusinessAddress, dtoResp.BusinessAddress)
	require.Equal(t, pm.City, dtoResp.City)
	require.Equal(t, pm.State, dtoResp.State)
	require.Equal(t, pm.ZipCode, dtoResp.ZipCode)
	require.Equal(t, models.PMAccountStatusIncomplete, dtoResp.AccountStatus)   // Assert default
	require.Equal(t, models.PMSetupProgressAwaitingInfo, dtoResp.SetupProgress) // Assert default
}

func TestPMPropertyHierarchyCreateAndEndpointFetch(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	// ── 1) Property-Manager ───────────────────────────────────────
	pm := &models.PropertyManager{
		ID:              uuid.New(),
		Email:           "inttest+" + uuid.NewString() + "@pm.test",
		PhoneNumber:     utils.Ptr("+15554443333"),
		TOTPSecret:      "pm-totp-secret",
		BusinessName:    "Test PM LLC",
		BusinessAddress: "123 Admin Rd",
		City:            "Nashville",
		State:           "TN",
		ZipCode:         "37209",
	}
	require.NoError(t, h.PMRepo.Create(ctx, pm))
	defer h.DB.Exec(ctx, `DELETE FROM property_managers WHERE id=$1`, pm.ID)

	// ── 2) Property ───────────────────────────────────────────────
	prop := &models.Property{
		ID:           uuid.New(),
		ManagerID:    pm.ID,
		PropertyName: "Broadway Flats",
		Address:      "500 5th Ave",
		City:         "Nashville",
		State:        "TN",
		ZipCode:      "37209",
	}
	startProp := time.Now()
	require.NoError(t, h.PropertyRepo.Create(ctx, prop))
	defer h.DB.Exec(ctx, `DELETE FROM properties WHERE id=$1`, prop.ID)

	// ── 3) Building ───────────────────────────────────────────────
	bldgAddr := utils.Ptr("500-A 5th Ave")
	bldg := &models.PropertyBuilding{
		ID:           uuid.New(),
		PropertyID:   prop.ID,
		BuildingName: "Building A",
		Address:      bldgAddr,
		Latitude:     36.153981,
		Longitude:    -86.789888,
	}
	require.NoError(t, h.BldgRepo.Create(ctx, bldg))
	defer h.DB.Exec(ctx, `DELETE FROM property_buildings WHERE id=$1`, bldg.ID)

	// ── 4) Unit ───────────────────────────────────────────────────
	unit := &models.Unit{
		ID:          uuid.New(),
		PropertyID:  prop.ID,
		BuildingID:  bldg.ID,
		UnitNumber:  "101",
		TenantToken: uuid.NewString(),
	}
	startUnit := time.Now()
	require.NoError(t, h.UnitRepo.Create(ctx, unit))
	defer h.DB.Exec(ctx, `DELETE FROM units WHERE id=$1`, unit.ID)

	// ── 5) Dumpster ──────────────────────────────────────────────
	dump := &models.Dumpster{
		ID:             uuid.New(),
		PropertyID:     prop.ID,
		DumpsterNumber: "1",
		Latitude:       36.154901,
		Longitude:      -86.790512,
	}
	require.NoError(t, h.DumpsterRepo.Create(ctx, dump))
	defer h.DB.Exec(ctx, `DELETE FROM dumpsters WHERE id=$1`, dump.ID)

	// --- Repo read-backs – ensure every persistent field round-trips ---
	pGot, err := h.PropertyRepo.GetByID(ctx, prop.ID)
	require.NoError(t, err)
	require.Equal(t, prop.ID, pGot.ID)
	require.Equal(t, prop.ManagerID, pGot.ManagerID)
	require.WithinDuration(t, startProp, pGot.CreatedAt, 5*time.Second)

	bGot, err := h.BldgRepo.GetByID(ctx, bldg.ID)
	require.NoError(t, err)
	require.Equal(t, bldg.ID, bGot.ID)
	require.Equal(t, *bldg.Address, *bGot.Address)

	uGot, err := h.UnitRepo.GetByID(ctx, unit.ID)
	require.NoError(t, err)
	require.Equal(t, unit.ID, uGot.ID)
	require.WithinDuration(t, startUnit, uGot.CreatedAt, 5*time.Second)

	dGot, err := h.DumpsterRepo.GetByID(ctx, dump.ID)
	require.NoError(t, err)
	require.Equal(t, dump.ID, dGot.ID)

	// --- REST read-back – GET /pm/properties ---
	accessToken := h.CreateWebJWT(pm.ID, "127.0.0.1")
	req := h.BuildAuthRequest(http.MethodGet, h.BaseURL+routes.PMProperties, "", nil, "web", "127.0.0.1")
	req.AddCookie(&http.Cookie{
		Name:     middleware.AccessTokenCookieName,
		Value:    accessToken,
		Path:     "/",
		Secure:   true,
		HttpOnly: true,
	})

	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	body := h.ReadBody(resp)
	var dtoList []account_dtos.Property
	require.NoError(t, json.Unmarshal([]byte(body), &dtoList))
	require.Len(t, dtoList, 1)

	propDTO := dtoList[0]
	require.Equal(t, prop.ID, propDTO.ID)
	require.Equal(t, prop.PropertyName, propDTO.PropertyName)
	require.Len(t, propDTO.Buildings, 1)
	bDTO := propDTO.Buildings[0]
	require.Equal(t, bldg.ID, bDTO.ID)
	require.Len(t, bDTO.Units, 1)
	uDTO := bDTO.Units[0]
	require.Equal(t, unit.ID, uDTO.ID)
	require.Len(t, propDTO.Dumpsters, 1)
	dDTO := propDTO.Dumpsters[0]
	require.Equal(t, dump.ID, dDTO.ID)
}
