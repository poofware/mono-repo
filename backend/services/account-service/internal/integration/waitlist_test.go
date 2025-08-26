//go:build (dev_test || staging_test) && integration

package integration

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	internal_dtos "github.com/poofware/mono-repo/backend/services/account-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/services/account-service/internal/routes"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	testhelpers "github.com/poofware/mono-repo/backend/shared/go-testhelpers"
)

func TestSubmitPersonalInfo_Waitlist(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	_, err := h.DB.Exec(ctx, `DELETE FROM properties`)
	require.NoError(t, err)

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
	require.NotNil(t, wUpdated.WaitlistReason)
	require.Equal(t, models.WaitlistReasonGeographic, *wUpdated.WaitlistReason)
}

func TestSubmitPersonalInfo_InRange_NoWaitlist(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	_, err := h.DB.Exec(ctx, `DELETE FROM properties`)
	require.NoError(t, err)

	pm := &models.PropertyManager{
		ID:              uuid.New(),
		Email:           "pm+" + uuid.NewString() + "@test.com",
		TOTPSecret:      "test",
		BusinessName:    "Test PM",
		BusinessAddress: "1600 Amphitheatre Parkway",
		City:            "Mountain View",
		State:           "CA",
		ZipCode:         "94043",
		AccountStatus:   models.PMAccountStatusActive,
		SetupProgress:   models.SetupProgressDone,
	}
	require.NoError(t, h.PMRepo.Create(ctx, pm))
	defer h.DB.Exec(ctx, `DELETE FROM property_managers WHERE id=$1`, pm.ID)

	prop := &models.Property{
		ID:           uuid.New(),
		ManagerID:    pm.ID,
		PropertyName: "Test Property",
		Address:      "1600 Amphitheatre Parkway",
		City:         "Mountain View",
		State:        "CA",
		ZipCode:      "94043",
		TimeZone:     "America/Los_Angeles",
		Latitude:     37.4220,
		Longitude:    -122.0841,
	}
	require.NoError(t, h.PropertyRepo.Create(ctx, prop))
	defer h.DB.Exec(ctx, `DELETE FROM properties WHERE id=$1`, prop.ID)

	worker := &models.Worker{
		ID:          uuid.New(),
		Email:       "inrange+" + uuid.NewString() + "@thepoofapp.com",
		PhoneNumber: testhelpers.UniquePhone(),
		TOTPSecret:  "test-secret",
		FirstName:   "Geo",
		LastName:    "Range",
	}
	require.NoError(t, h.WorkerRepo.Create(ctx, worker))
	defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, worker.ID)

	token := h.CreateMobileJWT(worker.ID, "test-device-id", "FAKE-PLAY")

	reqPayload := internal_dtos.SubmitPersonalInfoRequest{
		StreetAddress: "1600 Amphitheatre Parkway",
		City:          "Mountain View",
		State:         "CA",
		ZipCode:       "94043",
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
	require.False(t, wUpdated.OnWaitlist)
	require.Nil(t, wUpdated.WaitlistReason)
	require.Equal(t, models.SetupProgressIDVerify, wUpdated.SetupProgress)
}

func TestWorkerRepository_WaitlistQueries(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	initialActive, err := h.WorkerRepo.GetActiveWorkerCount(ctx)
	require.NoError(t, err)

	w1 := &models.Worker{ID: uuid.New(), Email: "a1@wait.test", PhoneNumber: "+15552220001", TOTPSecret: "s1", FirstName: "A", LastName: "One"}
	w2 := &models.Worker{ID: uuid.New(), Email: "a2@wait.test", PhoneNumber: "+15552220002", TOTPSecret: "s2", FirstName: "B", LastName: "Two"}
	w3 := &models.Worker{ID: uuid.New(), Email: "a3@wait.test", PhoneNumber: "+15552220003", TOTPSecret: "s3", FirstName: "C", LastName: "Three"}
	require.NoError(t, h.WorkerRepo.Create(ctx, w1))
	require.NoError(t, h.WorkerRepo.Create(ctx, w2))
	require.NoError(t, h.WorkerRepo.Create(ctx, w3))
	defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id IN ($1,$2,$3)`, w1.ID, w2.ID, w3.ID)

	_, err = h.DB.Exec(ctx, `UPDATE workers SET on_waitlist=false WHERE id IN ($1,$2)`, w1.ID, w2.ID)
	require.NoError(t, err)
	_, err = h.DB.Exec(ctx, `UPDATE workers SET on_waitlist=true, waitlisted_at=$2, waitlist_reason='CAPACITY' WHERE id=$1`, w3.ID, time.Unix(0, 0).UTC())
	require.NoError(t, err)

	count, err := h.WorkerRepo.GetActiveWorkerCount(ctx)
	require.NoError(t, err)
	require.Equal(t, initialActive+2, count)

	list, err := h.WorkerRepo.ListOldestWaitlistedWorkers(ctx, 1, models.WaitlistReasonCapacity)
	require.NoError(t, err)
	require.Len(t, list, 1)
	require.Equal(t, w3.ID, list[0].ID)
}
