//go:build (dev_test || staging_test) && integration

package integration

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/account-service/internal/dtos"
	"github.com/poofware/account-service/internal/routes"
	shared_dtos "github.com/poofware/go-dtos"
	"github.com/poofware/go-models"
	"github.com/poofware/go-utils"
	"github.com/stretchr/testify/require"
)

func TestAdminFullHierarchyFlow(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	// 1. Setup: Get the seeded Admin User and create a JWT
	adminUser, err := h.AdminRepo.GetByUsername(ctx, "seedadmin")
	require.NoError(t, err, "Failed to get seeded admin user")
	require.NotNil(t, adminUser, "Seeded admin user 'seedadmin' not found. Ensure DB is seeded.")
	adminToken := h.CreateWebJWT(adminUser.ID, "127.0.0.1")

	// 2. Create Property Manager
	createPMReq := dtos.CreatePropertyManagerRequest{
		Email:           "pm-hierarchy-test@thepoofapp.com",
		BusinessName:    "Hierarchy Test PM",
		BusinessAddress: "123 Hierarchy St",
		City:            "Testville",
		State:           "TS",
		ZipCode:         "12345",
	}
	createPMBody, _ := json.Marshal(createPMReq)
	req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+"/api/v1/account/admin"+routes.AdminPM, adminToken, createPMBody, "web", "127.0.0.1")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)

	var createdPM shared_dtos.PropertyManager
	json.NewDecoder(resp.Body).Decode(&createdPM)
	pmID, err := uuid.Parse(createdPM.ID)
	require.NoError(t, err)

	// 3. Create Property, Building, Unit, Dumpster
	createPropReq := dtos.CreatePropertyRequest{
		ManagerID:    pmID,
		PropertyName: "Test Property",
		Address:      "456 Test Ave", City: "Testville", State: "TS", ZipCode: "12345", TimeZone: "UTC", Latitude: 34.7, Longitude: -86.5,
	}
	createPropBody, _ := json.Marshal(createPropReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+"/api/v1/account/admin"+routes.AdminProperties, adminToken, createPropBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var createdProp models.Property
	json.NewDecoder(resp.Body).Decode(&createdProp)

	createBldgReq := dtos.CreateBuildingRequest{PropertyID: createdProp.ID, BuildingName: "Main Building"}
	createBldgBody, _ := json.Marshal(createBldgReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+"/api/v1/account/admin"+routes.AdminBuildings, adminToken, createBldgBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var createdBldg models.PropertyBuilding
	json.NewDecoder(resp.Body).Decode(&createdBldg)

	createUnitReq := dtos.CreateUnitRequest{PropertyID: createdProp.ID, BuildingID: createdBldg.ID, UnitNumber: "101"}
	createUnitBody, _ := json.Marshal(createUnitReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+"/api/v1/account/admin"+routes.AdminUnits, adminToken, createUnitBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var createdUnit models.Unit
	json.NewDecoder(resp.Body).Decode(&createdUnit)

	createDumpsterReq := dtos.CreateDumpsterRequest{PropertyID: createdProp.ID, DumpsterNumber: "D1"}
	createDumpsterBody, _ := json.Marshal(createDumpsterReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+"/api/v1/account/admin"+routes.AdminDumpsters, adminToken, createDumpsterBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var createdDumpster models.Dumpster
	json.NewDecoder(resp.Body).Decode(&createdDumpster)

	// 4. Get Snapshot and Assert
	snapshotReq := dtos.SnapshotRequest{ManagerID: pmID}
	snapshotBody, _ := json.Marshal(snapshotReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+"/api/v1/account/admin"+routes.AdminPMSnapshot, adminToken, snapshotBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	var snapshot dtos.PropertyManagerSnapshotResponse
	json.NewDecoder(resp.Body).Decode(&snapshot)
	require.Equal(t, createPMReq.BusinessName, snapshot.BusinessName)
	require.Len(t, snapshot.Properties, 1)
	require.Equal(t, createdProp.ID, snapshot.Properties[0].ID)
	require.Len(t, snapshot.Properties[0].Buildings, 1)
	require.Equal(t, createdBldg.ID, snapshot.Properties[0].Buildings[0].ID)
	require.Len(t, snapshot.Properties[0].Buildings[0].Units, 1)
	require.Equal(t, createdUnit.ID, snapshot.Properties[0].Buildings[0].Units[0].ID)
	require.Len(t, snapshot.Properties[0].Dumpsters, 1)
	require.Equal(t, createdDumpster.ID, snapshot.Properties[0].Dumpsters[0].ID)

	// 5. Update PM
	updatePMReq := dtos.UpdatePropertyManagerRequest{ID: pmID, BusinessName: utils.Ptr("Updated Hierarchy PM")}
	updatePMBody, _ := json.Marshal(updatePMReq)
	req = h.BuildAuthRequest(http.MethodPatch, h.BaseURL+"/api/v1/account/admin"+routes.AdminPM, adminToken, updatePMBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)
	var updatedPM shared_dtos.PropertyManager
	json.NewDecoder(resp.Body).Decode(&updatedPM)
	require.Equal(t, "Updated Hierarchy PM", updatedPM.BusinessName)

	// 6. Soft Delete Unit
	deleteReq := dtos.DeleteRequest{ID: createdUnit.ID}
	deleteBody, _ := json.Marshal(deleteReq)
	req = h.BuildAuthRequest(http.MethodDelete, h.BaseURL+"/api/v1/account/admin"+routes.AdminUnits, adminToken, deleteBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	// 7. Get Snapshot again and assert deletion
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+"/api/v1/account/admin"+routes.AdminPMSnapshot, adminToken, snapshotBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)
	json.NewDecoder(resp.Body).Decode(&snapshot)
	// --- Assert Deletion with better debugging ---
	require.NotEmpty(t, snapshot.Properties, "Snapshot should contain at least one property")
	require.NotEmpty(t, snapshot.Properties[0].Buildings, "Property should contain at least one building")

	// Add detailed logging if the assertion is about to fail
	if len(snapshot.Properties[0].Buildings[0].Units) != 0 {
		snapshotJSON, _ := json.MarshalIndent(snapshot, "", "  ")
		t.Logf("Snapshot still contains units after one was deleted. Full snapshot:\n%s", string(snapshotJSON))
	}

	require.Len(t, snapshot.Properties[0].Buildings[0].Units, 0, "Unit should be soft-deleted and not appear in snapshot, but found %d", len(snapshot.Properties[0].Buildings[0].Units))
	// 8. Soft Delete PM
	deletePMReq := dtos.DeleteRequest{ID: pmID}
	deletePMBody, _ := json.Marshal(deletePMReq)
	req = h.BuildAuthRequest(http.MethodDelete, h.BaseURL+"/api/v1/account/admin"+routes.AdminPM, adminToken, deletePMBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	// 9. Verify PM is gone from search
	searchAfterDeleteReq := dtos.SearchPropertyManagersRequest{Filters: map[string]any{"business_name": "Updated Hierarchy PM"}}
	searchAfterDeleteBody, _ := json.Marshal(searchAfterDeleteReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+"/api/v1/account/admin"+routes.AdminPMSearch, adminToken, searchAfterDeleteBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)
	var searchResp dtos.PagedPropertyManagersResponse
	json.NewDecoder(resp.Body).Decode(&searchResp)
	require.Equal(t, 0, searchResp.Total, "Soft-deleted PM should not appear in search results")
}

func TestAdminSearchAndPagination(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	// 1. Setup: Get the seeded Admin User and create a JWT
	adminUser, err := h.AdminRepo.GetByUsername(ctx, "seedadmin")
	require.NoError(t, err, "Failed to get seeded admin user")
	require.NotNil(t, adminUser, "Seeded admin user 'seedadmin' not found. Ensure DB is seeded.")
	adminToken := h.CreateWebJWT(adminUser.ID, "127.0.0.1")

	// 2. Create multiple PMs
	pmNames := []string{"Search PM A", "Search PM B", "Another Corp", "Search PM C"}
	for _, name := range pmNames {
		pm := &models.PropertyManager{
			ID:              uuid.New(),
			Email:           fmt.Sprintf("%s@test.com", strings.ReplaceAll(strings.ToLower(name), " ", "-")),
			BusinessName:    name,
			BusinessAddress: "1 Main St", City: "Test", State: "TS", ZipCode: "12345",
		}
		require.NoError(t, h.PMRepo.Create(ctx, pm), "Failed to create test PM for search test")
		// Defer cleanup
		defer h.DB.Exec(ctx, `DELETE FROM property_managers WHERE id=$1`, pm.ID)
	}
	// Give a moment for data to be consistent if needed
	time.Sleep(100 * time.Millisecond)

	// 3. Search with a filter
	searchReq := dtos.SearchPropertyManagersRequest{
		Filters: map[string]any{"business_name": "Search PM"},
	}
	searchBody, _ := json.Marshal(searchReq)
	req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+"/api/v1/account/admin"+routes.AdminPMSearch, adminToken, searchBody, "web", "127.0.0.1")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	var searchResp dtos.PagedPropertyManagersResponse
	json.NewDecoder(resp.Body).Decode(&searchResp)

	require.Equal(t, 3, searchResp.Total, "Should find 3 PMs matching 'Search PM'")
	require.Len(t, searchResp.Data, 3)

	// 4. Search with pagination
	paginatedReq := dtos.SearchPropertyManagersRequest{
		Filters:  map[string]any{"business_name": "Search PM"},
		PageSize: 2,
		Page:     1,
	}
	paginatedBody, _ := json.Marshal(paginatedReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+"/api/v1/account/admin"+routes.AdminPMSearch, adminToken, paginatedBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	var paginatedResp dtos.PagedPropertyManagersResponse
	json.NewDecoder(resp.Body).Decode(&paginatedResp)

	require.Equal(t, 3, paginatedResp.Total)
	require.Equal(t, 1, paginatedResp.Page)
	require.Equal(t, 2, paginatedResp.PageSize)
	require.Len(t, paginatedResp.Data, 2)

	// 5. Test page 2
	paginatedReq.Page = 2
	paginatedBody, _ = json.Marshal(paginatedReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+"/api/v1/account/admin"+routes.AdminPMSearch, adminToken, paginatedBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)
	json.NewDecoder(resp.Body).Decode(&paginatedResp)
	require.Equal(t, 3, paginatedResp.Total)
	require.Equal(t, 2, paginatedResp.Page)
	require.Len(t, paginatedResp.Data, 1) // 3 total, page size 2, so page 2 has 1 item
}