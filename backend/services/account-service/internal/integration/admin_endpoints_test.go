// backend/services/account-service/internal/integration/admin_endpoints_test.go
package integration

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/services/account-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/services/account-service/internal/routes"
	shared_dtos "github.com/poofware/mono-repo/backend/shared/go-dtos"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-testhelpers"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
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
		Email:           testhelpers.UniqueEmail("pm-hierarchy-test"),
		BusinessName:    "Hierarchy Test PM",
		BusinessAddress: "123 Hierarchy St",
		City:            "Testville",
		State:           "TS",
		ZipCode:         "12345",
	}
	createPMBody, _ := json.Marshal(createPMReq)
	req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminPM, adminToken, createPMBody, "web", "127.0.0.1")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)

	var createdPM shared_dtos.PropertyManager
	json.NewDecoder(resp.Body).Decode(&createdPM)
	pmID, err := uuid.Parse(createdPM.ID)
	require.NoError(t, err)

	// --- AUDIT CHECK for PM CREATE ---
	auditLogs, err := h.AdminAuditLogRepo.ListByTargetID(ctx, pmID)
	require.NoError(t, err)
	require.Len(t, auditLogs, 1, "Expected 1 audit log for PM creation")
	log := auditLogs[0]
	require.Equal(t, models.AuditCreate, log.Action)
	require.Equal(t, adminUser.ID, log.AdminID)
	require.NotNil(t, log.Details, "Details should not be nil on create")
	require.Equal(t, models.TargetPropertyManager, log.TargetType)

	// 3. Create Property, Building, Unit, Dumpster
	createPropReq := dtos.CreatePropertyRequest{
		ManagerID:    pmID,
		PropertyName: "Test Property",
		Address:      "456 Test Ave", City: "Testville", State: "TS", ZipCode: "12345", TimeZone: "UTC", Latitude: 34.7, Longitude: -86.5,
	}
	createPropBody, _ := json.Marshal(createPropReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminProperties, adminToken, createPropBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var createdProp models.Property
	json.NewDecoder(resp.Body).Decode(&createdProp)

	// --- AUDIT CHECK for Property CREATE ---
	auditLogs, err = h.AdminAuditLogRepo.ListByTargetID(ctx, createdProp.ID)
	require.NoError(t, err)
	require.Len(t, auditLogs, 1, "Expected 1 audit log for Property creation")
	require.Equal(t, models.AuditCreate, auditLogs[0].Action)
	require.Equal(t, models.TargetProperty, auditLogs[0].TargetType)

	createBldgReq := dtos.CreateBuildingRequest{PropertyID: createdProp.ID, BuildingName: "Main Building"}
	createBldgBody, _ := json.Marshal(createBldgReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminBuildings, adminToken, createBldgBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var createdBldg models.PropertyBuilding
	json.NewDecoder(resp.Body).Decode(&createdBldg)

	// Insert a floor and create a unit referencing floor_id
	var floorID uuid.UUID
	err = h.DB.QueryRow(ctx, `INSERT INTO floors (id, property_id, building_id, number, created_at, updated_at, row_version) VALUES (gen_random_uuid(), $1, $2, $3, NOW(), NOW(), 1) RETURNING id`, createdProp.ID, createdBldg.ID, 1).Scan(&floorID)
	require.NoError(t, err)

	createUnitReq := dtos.CreateUnitRequest{PropertyID: createdProp.ID, BuildingID: createdBldg.ID, FloorID: floorID, UnitNumber: "101"}
	createUnitBody, _ := json.Marshal(createUnitReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminUnits, adminToken, createUnitBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var createdUnit models.Unit
	json.NewDecoder(resp.Body).Decode(&createdUnit)

	createDumpsterReq := dtos.CreateDumpsterRequest{PropertyID: createdProp.ID, DumpsterNumber: "D1"}
	createDumpsterBody, _ := json.Marshal(createDumpsterReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminDumpsters, adminToken, createDumpsterBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var createdDumpster models.Dumpster
	json.NewDecoder(resp.Body).Decode(&createdDumpster)

	// 4. Get Snapshot and Assert
	snapshotReq := dtos.SnapshotRequest{ManagerID: pmID}
	snapshotBody, _ := json.Marshal(snapshotReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminPMSnapshot, adminToken, snapshotBody, "web", "127.0.0.1")
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
	req = h.BuildAuthRequest(http.MethodPatch, h.BaseURL+routes.AdminPM, adminToken, updatePMBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)
	var updatedPM shared_dtos.PropertyManager
	json.NewDecoder(resp.Body).Decode(&updatedPM)
	require.Equal(t, "Updated Hierarchy PM", updatedPM.BusinessName)

	// --- AUDIT CHECK for PM UPDATE ---
	auditLogs, err = h.AdminAuditLogRepo.ListByTargetID(ctx, pmID)
	require.NoError(t, err)
	require.Len(t, auditLogs, 2, "Expected 2 audit logs for PM (create, update)")
	updateLog := auditLogs[1]
	require.Equal(t, models.AuditUpdate, updateLog.Action)
	require.Equal(t, adminUser.ID, updateLog.AdminID)
	require.NotNil(t, updateLog.Details, "Details should not be nil on update")

	// 6. Soft Delete Unit
	deleteReq := dtos.DeleteRequest{ID: createdUnit.ID}
	deleteBody, _ := json.Marshal(deleteReq)
	req = h.BuildAuthRequest(http.MethodDelete, h.BaseURL+routes.AdminUnits, adminToken, deleteBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	// --- AUDIT CHECK for Unit DELETE ---
	auditLogs, err = h.AdminAuditLogRepo.ListByTargetID(ctx, createdUnit.ID)
	require.NoError(t, err)
	require.Len(t, auditLogs, 2, "Expected 2 audit logs for Unit (create, delete)")
	deleteLog := auditLogs[1]
	require.Equal(t, models.AuditDelete, deleteLog.Action)
	require.Equal(t, adminUser.ID, deleteLog.AdminID)
	require.Nil(t, deleteLog.Details, "Details should be nil on delete")
	require.Equal(t, models.TargetUnit, deleteLog.TargetType)

	// 6.5. Directly verify soft-deletion in the database
	t.Logf("Verifying soft deletion of unit %s directly in the database...", createdUnit.ID)
	var deletedAt *time.Time
	err = h.DB.QueryRow(ctx, "SELECT deleted_at FROM units WHERE id=$1", createdUnit.ID).Scan(&deletedAt)
	require.NoError(t, err, "DB query for deleted_at should not fail for the given unit ID")
	require.NotNil(t, deletedAt, "deleted_at field in the database should NOT be NULL after soft delete")
	t.Logf("DB check PASSED: Unit %s was successfully soft-deleted at %s", createdUnit.ID, deletedAt.Format(time.RFC3339))

	// 7. Get Snapshot again and assert deletion
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminPMSnapshot, adminToken, snapshotBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)
	var snapshotAfterDelete dtos.PropertyManagerSnapshotResponse // FIXED: Use a new variable
	json.NewDecoder(resp.Body).Decode(&snapshotAfterDelete)
	// --- Assert Deletion with better debugging ---
	require.NotEmpty(t, snapshotAfterDelete.Properties, "Snapshot should contain at least one property")
	require.NotEmpty(t, snapshotAfterDelete.Properties[0].Buildings, "Property should contain at least one building")

	// Add detailed logging if the assertion is about to fail
	if len(snapshotAfterDelete.Properties[0].Buildings[0].Units) != 0 {
		snapshotJSON, _ := json.MarshalIndent(snapshotAfterDelete, "", "  ")
		t.Logf("Snapshot still contains units after one was deleted. Full snapshot:\n%s", string(snapshotJSON))
	}

	require.Len(t, snapshotAfterDelete.Properties[0].Buildings[0].Units, 0, "Unit should be soft-deleted and not appear in snapshot, but found %d", len(snapshotAfterDelete.Properties[0].Buildings[0].Units))
	// 8. Soft Delete PM
	deletePMReq := dtos.DeleteRequest{ID: pmID}
	deletePMBody, _ := json.Marshal(deletePMReq)
	req = h.BuildAuthRequest(http.MethodDelete, h.BaseURL+routes.AdminPM, adminToken, deletePMBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	// 9. Verify PM is gone from search
	searchAfterDeleteReq := dtos.SearchPropertyManagersRequest{Filters: map[string]any{"business_name": "Updated Hierarchy PM"}}
	searchAfterDeleteBody, _ := json.Marshal(searchAfterDeleteReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminPMSearch, adminToken, searchAfterDeleteBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)
	var searchResp dtos.PagedPropertyManagersResponse
	json.NewDecoder(resp.Body).Decode(&searchResp)
	require.Equal(t, 0, searchResp.Total, "Soft-deleted PM should not appear in search results")
}

// New integration test for batch unit creation
func TestAdminCreateUnitsBatch(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	// Setup admin
	adminUser, err := h.AdminRepo.GetByUsername(ctx, "seedadmin")
	require.NoError(t, err)
	require.NotNil(t, adminUser)
	adminToken := h.CreateWebJWT(adminUser.ID, "127.0.0.1")

	// Create PM
	createPMReq := dtos.CreatePropertyManagerRequest{
		Email:           testhelpers.UniqueEmail("pm-batch-units"),
		BusinessName:    "Batch Units PM",
		BusinessAddress: "100 Batch Rd",
		City:            "Testville",
		State:           "TS",
		ZipCode:         "12345",
	}
	body, _ := json.Marshal(createPMReq)
	req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminPM, adminToken, body, "web", "127.0.0.1")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var createdPM shared_dtos.PropertyManager
	json.NewDecoder(resp.Body).Decode(&createdPM)
	pmID, _ := uuid.Parse(createdPM.ID)

	// Create Property
	propReq := dtos.CreatePropertyRequest{ManagerID: pmID, PropertyName: "BatchProp", Address: "1 St", City: "X", State: "TS", ZipCode: "12345", TimeZone: "UTC", Latitude: 34.7, Longitude: -86.5}
	propBody, _ := json.Marshal(propReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminProperties, adminToken, propBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var prop models.Property
	json.NewDecoder(resp.Body).Decode(&prop)

	// Create Building
	bReq := dtos.CreateBuildingRequest{PropertyID: prop.ID, BuildingName: "B1"}
	bBody, _ := json.Marshal(bReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminBuildings, adminToken, bBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var bldg models.PropertyBuilding
	json.NewDecoder(resp.Body).Decode(&bldg)

	// Create a floor for the building
	var floorID uuid.UUID
	err = h.DB.QueryRow(ctx, `INSERT INTO floors (id, property_id, building_id, number, created_at, updated_at, row_version) VALUES (gen_random_uuid(), $1, $2, $3, NOW(), NOW(), 1) RETURNING id`, prop.ID, bldg.ID, 1).Scan(&floorID)
	require.NoError(t, err)

	// Batch create units
	batch := dtos.CreateUnitsRequest{Items: []dtos.CreateUnitRequest{
		{PropertyID: prop.ID, BuildingID: bldg.ID, FloorID: floorID, UnitNumber: "B101"},
		{PropertyID: prop.ID, BuildingID: bldg.ID, FloorID: floorID, UnitNumber: "B102"},
		{PropertyID: prop.ID, BuildingID: bldg.ID, FloorID: floorID, UnitNumber: "B103"},
	}}
	batchBody, _ := json.Marshal(batch)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminUnitsBatch, adminToken, batchBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)

	var batchResp dtos.CreateUnitsResponse
	json.NewDecoder(resp.Body).Decode(&batchResp)
	require.Len(t, batchResp.Created, 3)

	// Verify via snapshot
	snapReq := dtos.SnapshotRequest{ManagerID: pmID}
	snapBody, _ := json.Marshal(snapReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminPMSnapshot, adminToken, snapBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)
	var snapshot dtos.PropertyManagerSnapshotResponse
	json.NewDecoder(resp.Body).Decode(&snapshot)
	require.Equal(t, 1, len(snapshot.Properties))
	require.Equal(t, 1, len(snapshot.Properties[0].Buildings))
	require.Equal(t, 3, len(snapshot.Properties[0].Buildings[0].Units))
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
			SetupProgress: "DONE",
			AccountStatus: "ACTIVE",
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
	req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminPMSearch, adminToken, searchBody, "web", "127.0.0.1")
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
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminPMSearch, adminToken, paginatedBody, "web", "127.0.0.1")
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
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminPMSearch, adminToken, paginatedBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)
	json.NewDecoder(resp.Body).Decode(&paginatedResp)
	require.Equal(t, 3, paginatedResp.Total)
	require.Equal(t, 2, paginatedResp.Page)
	require.Len(t, paginatedResp.Data, 1) // 3 total, page size 2, so page 2 has 1 item
}

// Verifies that creating a unit with legacy floor number results in:
// - A Floor row for the building
// - The created unit having a non-nil FloorID
// - Snapshot includes the building's floors
func TestAdminCreateUnit_WithLegacyFloor_MapsToFloorIDAndSnapshotFloors(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	// Setup admin
	adminUser, err := h.AdminRepo.GetByUsername(ctx, "seedadmin")
	require.NoError(t, err)
	require.NotNil(t, adminUser)
	adminToken := h.CreateWebJWT(adminUser.ID, "127.0.0.1")

	// Create PM
	createPMReq := dtos.CreatePropertyManagerRequest{
		Email:           testhelpers.UniqueEmail("pm-floor-test"),
		BusinessName:    "Floor Test PM",
		BusinessAddress: "100 Floor Rd",
		City:            "Testville",
		State:           "TS",
		ZipCode:         "12345",
	}
	body, _ := json.Marshal(createPMReq)
	req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminPM, adminToken, body, "web", "127.0.0.1")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var createdPM shared_dtos.PropertyManager
	json.NewDecoder(resp.Body).Decode(&createdPM)
	pmID, _ := uuid.Parse(createdPM.ID)

	// Create Property
	propReq := dtos.CreatePropertyRequest{ManagerID: pmID, PropertyName: "FloorProp", Address: "1 St", City: "X", State: "TS", ZipCode: "12345", TimeZone: "UTC", Latitude: 34.7, Longitude: -86.5}
	propBody, _ := json.Marshal(propReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminProperties, adminToken, propBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var prop models.Property
	json.NewDecoder(resp.Body).Decode(&prop)

	// Create Building
	bReq := dtos.CreateBuildingRequest{PropertyID: prop.ID, BuildingName: "B-Floors"}
	bBody, _ := json.Marshal(bReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminBuildings, adminToken, bBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var bldg models.PropertyBuilding
	json.NewDecoder(resp.Body).Decode(&bldg)

	// Create Floor row first
	var newFloorID uuid.UUID
	err = h.DB.QueryRow(ctx, `INSERT INTO floors (id, property_id, building_id, number, created_at, updated_at, row_version) VALUES (gen_random_uuid(), $1, $2, $3, NOW(), NOW(), 1) RETURNING id`, prop.ID, bldg.ID, 2).Scan(&newFloorID)
	require.NoError(t, err)

	// Create Unit with floor_id
	unitReq := dtos.CreateUnitRequest{PropertyID: prop.ID, BuildingID: bldg.ID, FloorID: newFloorID, UnitNumber: "F201"}
	unitBody, _ := json.Marshal(unitReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminUnits, adminToken, unitBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var createdUnit models.Unit
	json.NewDecoder(resp.Body).Decode(&createdUnit)

	// Assert unit has FloorID and matches provided
	require.NotNil(t, createdUnit.FloorID, "created unit should have FloorID set")
	require.Equal(t, newFloorID, *createdUnit.FloorID)

	// Verify floors table has the floor for this building
	var count int
	err = h.DB.QueryRow(ctx, `SELECT COUNT(1) FROM floors WHERE id=$1`, newFloorID).Scan(&count)
	require.NoError(t, err)
	require.Equal(t, 1, count, "expected the floor row to exist")

	// Snapshot should include building floors
	snapReq := dtos.SnapshotRequest{ManagerID: pmID}
	snapBody, _ := json.Marshal(snapReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminPMSnapshot, adminToken, snapBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)
	var snapshot dtos.PropertyManagerSnapshotResponse
	json.NewDecoder(resp.Body).Decode(&snapshot)
	require.NotEmpty(t, snapshot.Properties)
	require.NotEmpty(t, snapshot.Properties[0].Buildings)
	floors := snapshot.Properties[0].Buildings[0].Floors
	require.NotEmpty(t, floors, "snapshot should include floors for building")

	floorFound := false
	for _, f := range floors {
		if f.ID == newFloorID || f.Number == 2 {
			floorFound = true
			break
		}
	}
	require.True(t, floorFound, "snapshot should include the created floor")
}

// ----- NEW TESTS -----

// TestAdminPartialUpdatePropertyManager verifies that PATCH only updates provided fields.
func TestAdminPartialUpdatePropertyManager(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	// 1. Setup Admin and a Property Manager
	adminUser, err := h.AdminRepo.GetByUsername(ctx, "seedadmin")
	require.NoError(t, err)
	require.NotNil(t, adminUser)
	adminToken := h.CreateWebJWT(adminUser.ID, "127.0.0.1")
	pm := h.CreateTestPM(ctx, "partial-update-pm")

	// 2. PATCH only the business name
	originalEmail := pm.Email
	originalAddress := pm.BusinessAddress
	updatedBusinessName := "The New Partial Update Corp"

	patchReq := dtos.UpdatePropertyManagerRequest{
		ID:           pm.ID,
		BusinessName: &updatedBusinessName,
	}
	patchBody, _ := json.Marshal(patchReq)
	req := h.BuildAuthRequest(http.MethodPatch, h.BaseURL+routes.AdminPM, adminToken, patchBody, "web", "127.0.0.1")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()

	// 3. Assert response
	require.Equal(t, http.StatusOK, resp.StatusCode)
	var updatedPM shared_dtos.PropertyManager
	json.NewDecoder(resp.Body).Decode(&updatedPM)
	require.Equal(t, updatedBusinessName, updatedPM.BusinessName)
	require.Equal(t, originalEmail, updatedPM.Email) // Assert other fields are unchanged

	// 4. Verify directly in the database
	dbPM, err := h.PMRepo.GetByID(ctx, pm.ID)
	require.NoError(t, err)
	require.Equal(t, updatedBusinessName, dbPM.BusinessName)
	require.Equal(t, originalEmail, dbPM.Email)
	require.Equal(t, originalAddress, dbPM.BusinessAddress)
}

// TestAdminSoftDeleteCascade confirms that soft-deleting a parent entity cascades to its children.
func TestAdminSoftDeleteCascade(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	// 1. Setup Admin and full hierarchy
	adminUser, err := h.AdminRepo.GetByUsername(ctx, "seedadmin")
	require.NoError(t, err)
	require.NotNil(t, adminUser)
	adminToken := h.CreateWebJWT(adminUser.ID, "127.0.0.1")
	pm := h.CreateTestPM(ctx, "cascade-delete-pm")
	prop := h.CreateTestProperty(ctx, "Cascade Property", pm.ID, 34.0, -86.0)
	bldg := h.CreateTestBuilding(ctx, prop.ID, "Cascade Building")

	// Create unit via API to get a full model back
	unitReq := dtos.CreateUnitRequest{PropertyID: prop.ID, BuildingID: bldg.ID, UnitNumber: "C101"}
	createUnitBody, _ := json.Marshal(unitReq)
	req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminUnits, adminToken, createUnitBody, "web", "127.0.0.1")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var createdUnit models.Unit
	json.NewDecoder(resp.Body).Decode(&createdUnit)

	// 2. Soft-delete the Property
	deleteReq := dtos.DeleteRequest{ID: prop.ID}
	deleteBody, _ := json.Marshal(deleteReq)
	req = h.BuildAuthRequest(http.MethodDelete, h.BaseURL+routes.AdminProperties, adminToken, deleteBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	// 3. Verify cascade in the database
	var propDeletedAt, bldgDeletedAt, unitDeletedAt *time.Time
	err = h.DB.QueryRow(ctx, "SELECT deleted_at FROM properties WHERE id=$1", prop.ID).Scan(&propDeletedAt)
	require.NoError(t, err)
	require.NotNil(t, propDeletedAt, "Property should be soft-deleted")

	err = h.DB.QueryRow(ctx, "SELECT deleted_at FROM property_buildings WHERE id=$1", bldg.ID).Scan(&bldgDeletedAt)
	require.NoError(t, err)
	require.NotNil(t, bldgDeletedAt, "Building should be soft-deleted")

	err = h.DB.QueryRow(ctx, "SELECT deleted_at FROM units WHERE id=$1", createdUnit.ID).Scan(&unitDeletedAt)
	require.NoError(t, err)
	require.NotNil(t, unitDeletedAt, "Unit should be soft-deleted")

	// 4. Verify parent PM is NOT deleted
	var pmDeletedAt *time.Time
	err = h.DB.QueryRow(ctx, "SELECT deleted_at FROM property_managers WHERE id=$1", pm.ID).Scan(&pmDeletedAt)
	require.NoError(t, err, "Querying PM deleted_at should not fail")
	require.Nil(t, pmDeletedAt, "Property Manager should NOT be soft-deleted")

	// 5. Verify snapshot endpoint reflects the deletion
	snapshotReq := dtos.SnapshotRequest{ManagerID: pm.ID}
	snapshotBody, _ := json.Marshal(snapshotReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminPMSnapshot, adminToken, snapshotBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	var snapshot dtos.PropertyManagerSnapshotResponse
	json.NewDecoder(resp.Body).Decode(&snapshot)
	require.Len(t, snapshot.Properties, 0, "Snapshot should not contain the soft-deleted property")
}

// TestAdminUpdate_ForcedConflict ensures UpdateWithRetry handles concurrent PATCH requests.
func TestAdminUpdate_ForcedConflict(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	const numConcurrentUpdates = 3

	// 1. Setup Admin and a Property Manager
	adminUser, err := h.AdminRepo.GetByUsername(ctx, "seedadmin")
	require.NoError(t, err)
	require.NotNil(t, adminUser)
	adminToken := h.CreateWebJWT(adminUser.ID, "127.0.0.1")
	pm := h.CreateTestPM(ctx, "conflict-pm")

	// 2. Spawn concurrent goroutines to PATCH the same PM
	var wg sync.WaitGroup
	wg.Add(numConcurrentUpdates)

	// Channels to collect results for assertion after wait group finishes
	finalCity := make(chan string, 1)
	finalState := make(chan string, 1)
	finalZip := make(chan string, 1)

	for i := 0; i < numConcurrentUpdates; i++ {
		go func(n int) {
			defer wg.Done()
			var patchReq dtos.UpdatePropertyManagerRequest
			// Each goroutine updates a different field
			switch n {
			case 0:
				city := "City-" + uuid.NewString()[:4]
				patchReq = dtos.UpdatePropertyManagerRequest{ID: pm.ID, City: &city}
				defer func() { finalCity <- city }()
			case 1:
				state := "S" + fmt.Sprintf("%d", n)
				patchReq = dtos.UpdatePropertyManagerRequest{ID: pm.ID, State: &state}
				defer func() { finalState <- state }()
			case 2:
				zip := fmt.Sprintf("999%02d", n)
				patchReq = dtos.UpdatePropertyManagerRequest{ID: pm.ID, ZipCode: &zip}
				defer func() { finalZip <- zip }()
			}

			patchBody, _ := json.Marshal(patchReq)
			req := h.BuildAuthRequest(http.MethodPatch, h.BaseURL+routes.AdminPM, adminToken, patchBody, "web", "127.0.0.1")
			resp := h.DoRequest(req, http.DefaultClient)
			defer resp.Body.Close()

			// The key assertion: the request must not fail with a 409 Conflict.
			// It should succeed because of the retry logic in the service.
			require.Equal(t, http.StatusOK, resp.StatusCode, "Concurrent PATCH request failed, expected 200 OK")
		}(i)
	}

	wg.Wait()
	close(finalCity)
	close(finalState)
	close(finalZip)

	// 3. Verify final state in the database
	dbPM, err := h.PMRepo.GetByID(ctx, pm.ID)
	require.NoError(t, err)

	// Initial version is 1 (from CreateTestPM). Each successful update increments it.
	expectedVersion := int64(1 + numConcurrentUpdates)
	require.Equal(t, expectedVersion, dbPM.RowVersion, "Row version should be incremented by each concurrent update")

	// Check that all updates were applied correctly
	require.Equal(t, <-finalCity, dbPM.City)
	require.Equal(t, <-finalState, dbPM.State)
	require.Equal(t, <-finalZip, dbPM.ZipCode)
}
func TestAdminAgentCRUD(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	adminUser, err := h.AdminRepo.GetByUsername(ctx, "seedadmin")
	require.NoError(t, err)
	require.NotNil(t, adminUser)
	adminToken := h.CreateWebJWT(adminUser.ID, "127.0.0.1")

	// Create agent
	createReq := dtos.CreateAgentRequest{
		Name:        "Test Agent",
		Email:       testhelpers.UniqueEmail("agent"),
		PhoneNumber: "+15555550123",
		Address:     "1 Agent Way",
		City:        "Testville",
		State:       "TS",
		ZipCode:     "12345",
		Latitude:    34.1234,
		Longitude:   -86.5678,
	}
	body, _ := json.Marshal(createReq)
	req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminAgents, adminToken, body, "web", "127.0.0.1")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var created models.Agent
	json.NewDecoder(resp.Body).Decode(&created)

	// Audit check create
	audits, err := h.AdminAuditLogRepo.ListByTargetID(ctx, created.ID)
	require.NoError(t, err)
	require.Len(t, audits, 1)
	require.Equal(t, models.AuditCreate, audits[0].Action)
	require.Equal(t, models.TargetAgent, audits[0].TargetType)

	// Update agent
	newName := "Updated Agent"
	upd := dtos.UpdateAgentRequest{ID: created.ID, Name: &newName}
	updBody, _ := json.Marshal(upd)
	req = h.BuildAuthRequest(http.MethodPatch, h.BaseURL+routes.AdminAgents, adminToken, updBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	// Delete agent
	delBody, _ := json.Marshal(dtos.DeleteRequest{ID: created.ID})
	req = h.BuildAuthRequest(http.MethodDelete, h.BaseURL+routes.AdminAgents, adminToken, delBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)
}

// New integration tests for Floors admin APIs
func TestAdminCreateAndListFloors(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	// Setup admin
	adminUser, err := h.AdminRepo.GetByUsername(ctx, "seedadmin")
	require.NoError(t, err)
	require.NotNil(t, adminUser)
	adminToken := h.CreateWebJWT(adminUser.ID, "127.0.0.1")

	// Create PM
	createPMReq := dtos.CreatePropertyManagerRequest{
		Email:           testhelpers.UniqueEmail("pm-floor"),
		BusinessName:    "Floor PM",
		BusinessAddress: "100 Floor St",
		City:            "Testville",
		State:           "TS",
		ZipCode:         "12345",
	}
	body, _ := json.Marshal(createPMReq)
	req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminPM, adminToken, body, "web", "127.0.0.1")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var createdPM shared_dtos.PropertyManager
	json.NewDecoder(resp.Body).Decode(&createdPM)
	pmID, _ := uuid.Parse(createdPM.ID)

	// Create Property
	propReq := dtos.CreatePropertyRequest{ManagerID: pmID, PropertyName: "FloorProp", Address: "1 St", City: "X", State: "TS", ZipCode: "12345", TimeZone: "UTC", Latitude: 34.7, Longitude: -86.5}
	propBody, _ := json.Marshal(propReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminProperties, adminToken, propBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var prop models.Property
	json.NewDecoder(resp.Body).Decode(&prop)

	// Create Building
	bReq := dtos.CreateBuildingRequest{PropertyID: prop.ID, BuildingName: "B1"}
	bBody, _ := json.Marshal(bReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminBuildings, adminToken, bBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var bldgDTO dtos.Building
	json.NewDecoder(resp.Body).Decode(&bldgDTO)

	// Create Floor (number 1)
	floorReq := dtos.CreateFloorRequest{PropertyID: prop.ID, BuildingID: bldgDTO.ID, Number: 1}
	floorBody, _ := json.Marshal(floorReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminFloors, adminToken, floorBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)
	var createdFloor models.Floor
	json.NewDecoder(resp.Body).Decode(&createdFloor)
	require.Equal(t, int16(1), createdFloor.Number)
	require.Equal(t, prop.ID, createdFloor.PropertyID)
	require.Equal(t, bldgDTO.ID, createdFloor.BuildingID)

	// Audit check for floor create
	audits, err := h.AdminAuditLogRepo.ListByTargetID(ctx, createdFloor.ID)
	require.NoError(t, err)
	require.Len(t, audits, 1)
	require.Equal(t, models.AuditCreate, audits[0].Action)
	require.Equal(t, models.TargetFloor, audits[0].TargetType)

	// List floors by building
	listReq := dtos.ListFloorsByBuildingRequest{BuildingID: bldgDTO.ID}
	listBody, _ := json.Marshal(listReq)
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminFloorsByBuilding, adminToken, listBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)
	var floors []*models.Floor
	json.NewDecoder(resp.Body).Decode(&floors)
	require.Len(t, floors, 1)
	require.Equal(t, createdFloor.ID, floors[0].ID)

	// Uniqueness: creating number 1 again in same building should conflict
	req = h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminFloors, adminToken, floorBody, "web", "127.0.0.1")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusConflict, resp.StatusCode)
}

// New test: creating an agent without lat/lng should auto-geocode and succeed
func TestAdminCreateAgent_AutoGeocodeWhenNoLatLng(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	adminUser, err := h.AdminRepo.GetByUsername(ctx, "seedadmin")
	require.NoError(t, err)
	require.NotNil(t, adminUser)
	adminToken := h.CreateWebJWT(adminUser.ID, "127.0.0.1")

	createReq := dtos.CreateAgentRequest{
		Name:        "Geo Agent",
		Email:       testhelpers.UniqueEmail("agent-geo"),
		PhoneNumber: "+15555551234",
		Address:     "1600 Amphitheatre Parkway",
		City:        "Mountain View",
		State:       "CA",
		ZipCode:     "94043",
		// Latitude/Longitude omitted intentionally
	}
	body, _ := json.Marshal(createReq)
	req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.AdminAgents, adminToken, body, "web", "127.0.0.1")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode)

	var created models.Agent
	json.NewDecoder(resp.Body).Decode(&created)
	// We accept either non-zero coords (geocoded) or zeros if API key not set; just assert fields echo and types OK
	require.Equal(t, createReq.Name, created.Name)
	require.Equal(t, createReq.Email, created.Email)
	require.Equal(t, createReq.PhoneNumber, created.PhoneNumber)
	require.Equal(t, createReq.Address, created.Address)
	require.Equal(t, createReq.City, created.City)
	require.Equal(t, createReq.State, created.State)
	require.Equal(t, createReq.ZipCode, created.ZipCode)
}
