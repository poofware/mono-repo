// backend/services/account-service/internal/integration/admin_validation_test.go
package integration

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/google/uuid"
	"github.com/poofware/account-service/internal/dtos"
	shared_dtos "github.com/poofware/go-dtos"
	"github.com/poofware/account-service/internal/routes"
	"github.com/poofware/go-models"
	"github.com/poofware/go-testhelpers"
	"github.com/poofware/go-utils"
	"github.com/stretchr/testify/require"
)

// adminValidationTestSetup prepares a standard environment for validation tests.
// It returns a valid admin token for making authenticated requests.
func adminValidationTestSetup(t *testing.T) string {
	h.T = t
	ctx := h.Ctx

	adminUser, err := h.AdminRepo.GetByUsername(ctx, "seedadmin")
	require.NoError(t, err, "Failed to get seeded admin user")
	require.NotNil(t, adminUser, "Seeded admin user 'seedadmin' not found. Ensure DB is seeded.")
	adminToken := h.CreateWebJWT(adminUser.ID, "127.0.0.1")
	return adminToken
}

// TestCreatePM_Validation covers all validation scenarios for the Create Property Manager endpoint.
func TestCreatePM_Validation(t *testing.T) {
	adminToken := adminValidationTestSetup(t)
	baseURL := h.BaseURL + routes.AdminPM

	t.Run("Missing Required Fields", func(t *testing.T) {
		h.T = t
		// Missing email and other fields
		reqBody, _ := json.Marshal(dtos.CreatePropertyManagerRequest{BusinessName: "No Email Corp"})
		req := h.BuildAuthRequest(http.MethodPost, baseURL, adminToken, reqBody, "web", "127.0.0.1")
		resp := h.DoRequest(req, http.DefaultClient)
		defer resp.Body.Close()

		require.Equal(t, http.StatusBadRequest, resp.StatusCode)
		var errDetails []shared_dtos.ValidationErrorDetail
		json.NewDecoder(resp.Body).Decode(&errDetails)

		// The validator returns errors for all missing required fields
		foundEmailError := false
		for _, detail := range errDetails {
			if detail.Field == "Email" && detail.Code == "validation_required" {
				foundEmailError = true
				break
			}
		}
		require.True(t, foundEmailError, "Expected a validation error for the 'Email' field")
	})

	t.Run("Invalid Data Formats", func(t *testing.T) {
		h.T = t
		// Invalid email
		reqBody, _ := json.Marshal(dtos.CreatePropertyManagerRequest{
			Email:           "not-an-email",
			BusinessName:    "Bad Email Inc.",
			BusinessAddress: "123 Valid St", City: "Valid", State: "CA", ZipCode: "90210",
		})
		req := h.BuildAuthRequest(http.MethodPost, baseURL, adminToken, reqBody, "web", "127.0.0.1")
		resp := h.DoRequest(req, http.DefaultClient)
		defer resp.Body.Close()
		require.Equal(t, http.StatusBadRequest, resp.StatusCode)
		var errDetails []shared_dtos.ValidationErrorDetail
		json.NewDecoder(resp.Body).Decode(&errDetails)
		require.Len(t, errDetails, 1)
		require.Equal(t, "Email", errDetails[0].Field)
		require.Equal(t, "validation_email", errDetails[0].Code)

		// Invalid phone number (not E.164)
		reqBody, _ = json.Marshal(dtos.CreatePropertyManagerRequest{
			Email:           testhelpers.UniqueEmail("badphone"),
			PhoneNumber:     utils.Ptr("555-123-4567"),
			BusinessName:    "Bad Phone Inc.",
			BusinessAddress: "123 Valid St", City: "Valid", State: "CA", ZipCode: "90210",
		})
		req = h.BuildAuthRequest(http.MethodPost, baseURL, adminToken, reqBody, "web", "127.0.0.1")
		resp = h.DoRequest(req, http.DefaultClient)
		defer resp.Body.Close()
		require.Equal(t, http.StatusBadRequest, resp.StatusCode)
		json.NewDecoder(resp.Body).Decode(&errDetails)
		require.Len(t, errDetails, 1)
		require.Equal(t, "PhoneNumber", errDetails[0].Field)
		require.Equal(t, "validation_e164", errDetails[0].Code)
	})

	t.Run("Email Conflict", func(t *testing.T) {
		h.T = t
		ctx := h.Ctx
		// Create a PM first
		conflictEmail := testhelpers.UniqueEmail("conflict")
		pm := h.CreateTestPM(ctx, "conflict-pm")
		// Manually set email to a known value using UpdateWithRetry for safety
		require.NoError(t, h.PMRepo.UpdateWithRetry(ctx, pm.ID, func(p *models.PropertyManager) error {
			p.Email = conflictEmail
			return nil
		}))
		defer h.DB.Exec(ctx, `DELETE FROM property_managers WHERE id=$1`, pm.ID)

		// Attempt to create another with the same email
		reqBody, _ := json.Marshal(dtos.CreatePropertyManagerRequest{
			Email:           conflictEmail,
			BusinessName:    "Conflict Corp",
			BusinessAddress: "123 Valid St", City: "Valid", State: "CA", ZipCode: "90210",
		})
		req := h.BuildAuthRequest(http.MethodPost, baseURL, adminToken, reqBody, "web", "127.0.0.1")
		resp := h.DoRequest(req, http.DefaultClient)
		defer resp.Body.Close()
		require.Equal(t, http.StatusConflict, resp.StatusCode)

		var errResp utils.ErrorResponse
		json.NewDecoder(resp.Body).Decode(&errResp)
		require.Equal(t, utils.ErrCodeConflict, errResp.Code)
		require.Contains(t, errResp.Message, "Email already in use")
	})
}

func TestCreateChildEntity_WithInvalidParent(t *testing.T) {
	adminToken := adminValidationTestSetup(t)

	t.Run("Create Property with non-existent Manager", func(t *testing.T) {
		h.T = t
		nonExistentManagerID := uuid.New()
		reqBody, _ := json.Marshal(dtos.CreatePropertyRequest{
			ManagerID: nonExistentManagerID,
			PropertyName: "Phantom Property", Address: "123 Main", City: "City", State: "ST", ZipCode: "12345", TimeZone: "UTC",  Latitude: 34.7, Longitude: -86.5,
		})
		req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminProperties, adminToken, reqBody, "web", "127.0.0.1")
		resp := h.DoRequest(req, http.DefaultClient)
		defer resp.Body.Close()

		require.Equal(t, http.StatusNotFound, resp.StatusCode)
		var errResp utils.ErrorResponse
		json.NewDecoder(resp.Body).Decode(&errResp)
		require.Equal(t, utils.ErrCodeNotFound, errResp.Code)
		require.Contains(t, errResp.Message, "Parent property manager not found")
	})

	t.Run("Create Building with non-existent Property", func(t *testing.T) {
		h.T = t
		nonExistentPropertyID := uuid.New()
		reqBody, _ := json.Marshal(dtos.CreateBuildingRequest{PropertyID: nonExistentPropertyID, BuildingName: "Phantom Building"})
		req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminBuildings, adminToken, reqBody, "web", "127.0.0.1")
		resp := h.DoRequest(req, http.DefaultClient)
		defer resp.Body.Close()
		require.Equal(t, http.StatusNotFound, resp.StatusCode)
	})

	t.Run("Create Unit with mismatched Property and Building", func(t *testing.T) {
		h.T = t
		ctx := h.Ctx
		// Setup: Create two separate properties and a building in the first one
		pm := h.CreateTestPM(ctx, "mismatch")
		prop1 := h.CreateTestProperty(ctx, "Property One", pm.ID, 0, 0)
		prop2 := h.CreateTestProperty(ctx, "Property Two", pm.ID, 0, 0)
		bldgInProp1 := h.CreateTestBuilding(ctx, prop1.ID, "Building A")

		// Attempt to create a unit, associating it with Property TWO but Building ONE
		reqBody, _ := json.Marshal(dtos.CreateUnitRequest{
			PropertyID: prop2.ID,
			BuildingID: bldgInProp1.ID,
			UnitNumber: "101",
		})
		req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminUnits, adminToken, reqBody, "web", "127.0.0.1")
		resp := h.DoRequest(req, http.DefaultClient)
		defer resp.Body.Close()

		require.Equal(t, http.StatusBadRequest, resp.StatusCode)
		var errResp utils.ErrorResponse
		json.NewDecoder(resp.Body).Decode(&errResp)
		require.Equal(t, utils.ErrCodeInvalidPayload, errResp.Code)
		require.Contains(t, errResp.Message, "building does not belong to the specified property")
	})
}

func TestUniquenessConstraints(t *testing.T) {
	adminToken := adminValidationTestSetup(t)
	ctx := h.Ctx

	// Setup: A single PM, property, and two buildings
	pm := h.CreateTestPM(ctx, "uniqueness")
	prop := h.CreateTestProperty(ctx, "Unique Prop", pm.ID, 0, 0)
	bldg1 := h.CreateTestBuilding(ctx, prop.ID, "Building 1")
	bldg2 := h.CreateTestBuilding(ctx, prop.ID, "Building 2")

	t.Run("Unit number conflict within a building", func(t *testing.T) {
		h.T = t
		// Create unit 101 in building 1
		createUnitReq := dtos.CreateUnitRequest{PropertyID: prop.ID, BuildingID: bldg1.ID, UnitNumber: "101"}
		createUnitBody, _ := json.Marshal(createUnitReq)
		req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminUnits, adminToken, createUnitBody, "web", "127.0.0.1")
		resp := h.DoRequest(req, http.DefaultClient)
		defer resp.Body.Close()
		require.Equal(t, http.StatusCreated, resp.StatusCode)

		// Attempt to create unit 101 in building 1 again
		req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminUnits, adminToken, createUnitBody, "web", "127.0.0.1")
		resp = h.DoRequest(req, http.DefaultClient)
		defer resp.Body.Close()
		require.Equal(t, http.StatusConflict, resp.StatusCode)
		var errResp utils.ErrorResponse
		json.NewDecoder(resp.Body).Decode(&errResp)
		require.Equal(t, utils.ErrCodeConflict, errResp.Code)
		require.Contains(t, errResp.Message, "already exists in this building")
	})

	t.Run("Unit number is unique across buildings", func(t *testing.T) {
		h.T = t
		// Create unit 101 in building 2 (should succeed)
		createUnitReq := dtos.CreateUnitRequest{PropertyID: prop.ID, BuildingID: bldg2.ID, UnitNumber: "101"}
		createUnitBody, _ := json.Marshal(createUnitReq)
		req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminUnits, adminToken, createUnitBody, "web", "127.0.0.1")
		resp := h.DoRequest(req, http.DefaultClient)
		defer resp.Body.Close()
		require.Equal(t, http.StatusCreated, resp.StatusCode)
	})

	t.Run("Dumpster number conflict within a property", func(t *testing.T) {
		h.T = t
		// Create dumpster D1 on the property
		createDumpsterReq := dtos.CreateDumpsterRequest{PropertyID: prop.ID, DumpsterNumber: "D1"}
		createDumpsterBody, _ := json.Marshal(createDumpsterReq)
		req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminDumpsters, adminToken, createDumpsterBody, "web", "127.0.0.1")
		resp := h.DoRequest(req, http.DefaultClient)
		defer resp.Body.Close()
		require.Equal(t, http.StatusCreated, resp.StatusCode)

		// Attempt to create dumpster D1 again
		req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminDumpsters, adminToken, createDumpsterBody, "web", "127.0.0.1")
		resp = h.DoRequest(req, http.DefaultClient)
		defer resp.Body.Close()
		require.Equal(t, http.StatusConflict, resp.StatusCode)
		var errResp utils.ErrorResponse
		json.NewDecoder(resp.Body).Decode(&errResp)
		require.Equal(t, utils.ErrCodeConflict, errResp.Code)
		require.Contains(t, errResp.Message, "already exists in this property")
	})
}