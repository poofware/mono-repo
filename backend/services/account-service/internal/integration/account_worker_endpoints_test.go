//go:build (dev_test || staging_test) && integration

package integration

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/poofware/mono-repo/backend/services/account-service/internal/routes"
	"github.com/poofware/mono-repo/backend/shared/go-dtos"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

// TestWorkerPatch_Success tests a valid PATCH request.
func TestWorkerPatch_Success(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	smsRepo = h.WorkerSMSRepo

	// 1) Create a Worker with minimal info
	w := &models.Worker{
		ID:          uuid.New(),
		Email:       "inttest+" + uuid.NewString() + "@thepoofapp.com",
		PhoneNumber: utils.TestPhoneNumberBase + fmt.Sprintf("%09d", rand.Intn(1e9)),
		TOTPSecret:  "test-totp-secret",
		FirstName:   "Patch",
		LastName:    "Original",
	}
	require.NoError(t, h.WorkerRepo.Create(ctx, w))
	defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, w.ID)

	// Update with address, vehicle, and status info
	require.NoError(t, h.WorkerRepo.UpdateWithRetry(ctx, w.ID, func(workerToUpdate *models.Worker) error {
		workerToUpdate.StreetAddress = "123 Patch Ln"
		workerToUpdate.City = "Old City"
		workerToUpdate.State = "AL"
		workerToUpdate.ZipCode = "35801"
		workerToUpdate.VehicleYear = 2000
		workerToUpdate.VehicleMake = "Ford"
		workerToUpdate.VehicleModel = "Ranger"
		workerToUpdate.AccountStatus = models.AccountStatusIncomplete
		workerToUpdate.SetupProgress = models.SetupProgressIDVerify
		return nil
	}))

	// Verify phone number for the patch operation
	require.NoError(t, smsRepo.CreateCode(ctx, &w.ID, w.PhoneNumber, "999999", time.Now().Add(15*time.Minute)))
	rec, err := smsRepo.GetCode(ctx, w.PhoneNumber)
	require.NoError(t, err)
	require.NotNil(t, rec)
	require.NoError(t, smsRepo.MarkVerified(ctx, rec.ID, ""))

	ok, foundID, err := smsRepo.IsCurrentlyVerified(ctx, &w.ID, w.PhoneNumber, "")
	require.NoError(t, err)
	require.True(t, ok)
	require.NotNil(t, foundID)

	// 3) Build a Worker JWT
	token := h.CreateMobileJWT(w.ID, "test-device-id", "FAKE-PLAY")

	// 4) Attempt to PATCH with a new valid email, same phone, new city
	patchPayload := map[string]any{
		"email":        "inttest+" + uuid.NewString() + "@thepoofapp.com",
		"phone_number": w.PhoneNumber,
		"city":         "NewCityPatch",
	}
	bodyBytes, _ := json.Marshal(patchPayload)

	req := h.BuildAuthRequest(http.MethodPatch, h.BaseURL+routes.WorkerBase, token, bodyBytes, "android", "test-device-id")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()

	require.Equal(t, http.StatusOK, resp.StatusCode, "Expected 200 for successful patch")

	respBody := h.ReadBody(resp)
	var patched dtos.Worker
	require.NoError(t, json.Unmarshal([]byte(respBody), &patched))

	// Check updated fields
	require.Equal(t, patchPayload["email"], patched.Email)
	require.Equal(t, patchPayload["phone_number"], patched.PhoneNumber)
	require.Equal(t, patchPayload["city"], patched.City)
}

// TestWorkerPatch_TenantToken tests adding and removing a tenant token.
func TestWorkerPatch_TenantToken(t *testing.T) {
        h.T = t
        ctx := h.Ctx

        w := &models.Worker{
                ID:          uuid.New(),
                Email:       "inttest+" + uuid.NewString() + "@thepoofapp.com",
                PhoneNumber: utils.TestPhoneNumberBase + fmt.Sprintf("%09d", rand.Intn(1e9)),
                TOTPSecret:  "test-totp-secret",
                FirstName:   "Tenant",
                LastName:    "Token",
        }
        require.NoError(t, h.WorkerRepo.Create(ctx, w))
        defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, w.ID)

        pm := h.CreateTestPM(ctx, "tenant-pm")
        prop := h.CreateTestProperty(ctx, "TenantProp", pm.ID, 0, 0)
        bldg := h.CreateTestBuilding(ctx, prop.ID, "TenantBldg")
        unit := &models.Unit{ID: uuid.New(), PropertyID: prop.ID, BuildingID: bldg.ID, UnitNumber: "101", TenantToken: uuid.NewString()}
        require.NoError(t, h.UnitRepo.Create(ctx, unit))
        defer h.DB.Exec(ctx, `DELETE FROM units WHERE id=$1`, unit.ID)
        defer h.DB.Exec(ctx, `DELETE FROM property_buildings WHERE id=$1`, bldg.ID)
        defer h.DB.Exec(ctx, `DELETE FROM properties WHERE id=$1`, prop.ID)
        defer h.DB.Exec(ctx, `DELETE FROM property_managers WHERE id=$1`, pm.ID)

        token := h.CreateMobileJWT(w.ID, "test-device-id", "FAKE-PLAY")

        patchPayload := map[string]any{
                "tenant_token": unit.TenantToken,
        }
        bodyBytes, _ := json.Marshal(patchPayload)
        req := h.BuildAuthRequest(http.MethodPatch, h.BaseURL+routes.WorkerBase, token, bodyBytes, "android", "test-device-id")
        resp := h.DoRequest(req, http.DefaultClient)
        defer resp.Body.Close()
        require.Equal(t, http.StatusOK, resp.StatusCode)
        respBody := h.ReadBody(resp)
        var patched dtos.Worker
        require.NoError(t, json.Unmarshal([]byte(respBody), &patched))
        require.NotNil(t, patched.TenantToken)
        require.Equal(t, unit.TenantToken, *patched.TenantToken)

        // Remove association
        removePayload := map[string]any{"tenant_token": ""}
        body2, _ := json.Marshal(removePayload)
        req2 := h.BuildAuthRequest(http.MethodPatch, h.BaseURL+routes.WorkerBase, token, body2, "android", "test-device-id")
        resp2 := h.DoRequest(req2, http.DefaultClient)
        defer resp2.Body.Close()
        require.Equal(t, http.StatusOK, resp2.StatusCode)
        respBody2 := h.ReadBody(resp2)
        var patched2 dtos.Worker
        require.NoError(t, json.Unmarshal([]byte(respBody2), &patched2))
        require.Nil(t, patched2.TenantToken)
}

// TestWorkerPatch_InvalidTenantToken ensures invalid tokens are rejected.
func TestWorkerPatch_InvalidTenantToken(t *testing.T) {
        h.T = t
        ctx := h.Ctx

        w := &models.Worker{
                ID:          uuid.New(),
                Email:       "inttest+" + uuid.NewString() + "@thepoofapp.com",
                PhoneNumber: utils.TestPhoneNumberBase + fmt.Sprintf("%09d", rand.Intn(1e9)),
                TOTPSecret:  "test-totp-secret",
                FirstName:   "Invalid",
                LastName:    "Token",
        }
        require.NoError(t, h.WorkerRepo.Create(ctx, w))
        defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, w.ID)

        token := h.CreateMobileJWT(w.ID, "test-device-id", "FAKE-PLAY")
        patchPayload := map[string]any{"tenant_token": "does-not-exist"}
        bodyBytes, _ := json.Marshal(patchPayload)
        req := h.BuildAuthRequest(http.MethodPatch, h.BaseURL+routes.WorkerBase, token, bodyBytes, "android", "test-device-id")
        resp := h.DoRequest(req, http.DefaultClient)
        defer resp.Body.Close()
        require.Equal(t, http.StatusBadRequest, resp.StatusCode)
}

// TestWorkerPatch_InvalidEmail tests patching with a bad email.
func TestWorkerPatch_InvalidEmail(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	smsRepo = h.WorkerSMSRepo

	w := &models.Worker{
		ID:          uuid.New(),
		Email:       "inttest+" + uuid.NewString() + "@thepoofapp.com",
		PhoneNumber: "+999" + fmt.Sprintf("%09d", rand.Intn(1e9)),
		FirstName:   "InvalidEmail",
		LastName:    "Case",
	}
	require.NoError(t, h.WorkerRepo.Create(ctx, w))
	defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, w.ID)

	require.NoError(t, smsRepo.CreateCode(ctx, &w.ID, w.PhoneNumber, "999999", time.Now().Add(15*time.Minute)))
	rec, err := smsRepo.GetCode(ctx, w.PhoneNumber)
	require.NoError(t, err)
	require.NotNil(t, rec)
	require.NoError(t, smsRepo.MarkVerified(ctx, rec.ID, ""))

	token := h.CreateMobileJWT(w.ID, "test-device-id", "FAKE-PLAY")

	patchReq := map[string]any{
		"email": "somejunk@baddomain.xxxxx",
	}
	body, _ := json.Marshal(patchReq)

	req := h.BuildAuthRequest(http.MethodPatch, h.BaseURL+routes.WorkerBase, token, body, "android", "test-device-id")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()

	require.Truef(t, resp.StatusCode == http.StatusBadRequest || resp.StatusCode == http.StatusInternalServerError,
		"Expected 400 or 500 for invalid email, got %d", resp.StatusCode)

	wGot, err := h.WorkerRepo.GetByID(ctx, w.ID)
	require.NoError(t, err)
	require.Equal(t, w.Email, wGot.Email, "Email should remain the same")
}

// TestWorkerPatch_UnverifiedPhone tests patching with an unverified phone number.
func TestWorkerPatch_UnverifiedPhone(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	w := &models.Worker{
		ID:          uuid.New(),
		Email:       "inttest+" + uuid.NewString() + "@thepoofapp.com",
		PhoneNumber: "+999" + fmt.Sprintf("%09d", rand.Intn(1e9)),
		FirstName:   "UnverifiedPhone",
		LastName:    "Case",
	}
	require.NoError(t, h.WorkerRepo.Create(ctx, w))
	defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, w.ID)

	token := h.CreateMobileJWT(w.ID, "test-device-id", "FAKE-PLAY")

	newPhone := "+999" + fmt.Sprintf("%09d", rand.Intn(1e9))
	patchPayload := map[string]any{
		"phone_number": newPhone,
	}
	bodyBytes, _ := json.Marshal(patchPayload)

	req := h.BuildAuthRequest(http.MethodPatch, h.BaseURL+routes.WorkerBase, token, bodyBytes, "android", "test-device-id")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()

	require.Truef(t, resp.StatusCode == http.StatusForbidden || resp.StatusCode == http.StatusInternalServerError,
		"Expected 400/403 or 500 but got %d", resp.StatusCode)

	wGot, err := h.WorkerRepo.GetByID(ctx, w.ID)
	require.NoError(t, err)
	require.Equal(t, w.PhoneNumber, wGot.PhoneNumber, "Should not have updated phone")
}

// TestWorkerPatch_NotFound tests patching a non-existent worker.
func TestWorkerPatch_NotFound(t *testing.T) {
	h.T = t
	randomID := uuid.New()
	token := h.CreateMobileJWT(randomID, "test-device-id", "FAKE-PLAY")

	patchReq := map[string]any{
		"city": "DoesNotExistCity",
	}
	body, _ := json.Marshal(patchReq)

	req := h.BuildAuthRequest(http.MethodPatch, h.BaseURL+routes.WorkerBase, token, body, "android", "test-device-id")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()

	require.Equal(t, http.StatusNotFound, resp.StatusCode, "Expected 404 for missing worker")
}
