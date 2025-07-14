//go:build (dev_test || dev || staging_test) && integration

package integration

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/go-models"
	"github.com/poofware/go-utils"
	"github.com/poofware/jobs-service/internal/dtos"
	"github.com/poofware/jobs-service/internal/routes"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAdminJobEndpoints(t *testing.T) {
	h.T = t
	ctx := context.Background()

	// --- Setup ---

	adminUser, err := h.AdminRepo.GetByUsername(ctx, "seedadmin")
	require.NoError(t, err, "Failed to get seeded admin user")
	adminJWT := h.CreateWebJWT(adminUser.ID, "127.0.0.1")
	client := h.NewHTTPClient()

	pm := h.CreateTestPM(ctx, "pm-for-admin-test")
	prop := h.CreateTestProperty(ctx, "AdminTestProp", pm.ID, 34.0, -86.0)
	bldg := h.CreateTestBuilding(ctx, prop.ID, "Admin-B1")
	dumpster := h.CreateTestDumpster(ctx, prop.ID, "Admin-D1")

	var createdDef *models.JobDefinition
	var url = h.BaseURL + routes.AdminJobDefinitions

	// --- Test Case 1: CREATE JobDefinition ---
	t.Run("AdminCreatesJobDefinition", func(t *testing.T) {
		h.T = t
		// Arrange
		earliest, latest := h.TestSameDayTimeWindow()
		createReq := dtos.AdminCreateJobDefinitionRequest{
			ManagerID:                  pm.ID,
			PropertyID:                 prop.ID,
			Title:                      "Admin Created Job",
			Description:                utils.Ptr("This job was created by an admin."),
			AssignedBuildingIDs:        []uuid.UUID{bldg.ID},
			DumpsterIDs:                []uuid.UUID{dumpster.ID},
			Frequency:                  models.JobFreqDaily,
			StartDate:                  time.Now().UTC().AddDate(0, 0, -1),
			EarliestStartTime:          earliest,
			LatestStartTime:            latest,
			GlobalBasePay:              utils.Ptr(25.50),
			GlobalEstimatedTimeMinutes: utils.Ptr(45),
		}

		bodyBytes, err := json.Marshal(createReq)
		require.NoError(t, err)

		req := h.BuildAuthRequest(http.MethodPost, url, adminJWT, bodyBytes, "web", "127.0.0.1")

		// Act
		resp := h.DoRequest(req, client)
		defer resp.Body.Close()

		// Assert
		require.Equal(t, http.StatusCreated, resp.StatusCode, "Expected 201 Created. Body: %s", h.ReadBody(resp))
		err = json.NewDecoder(resp.Body).Decode(&createdDef)
		require.NoError(t, err, "Failed to decode response body")
		assert.Equal(t, createReq.Title, createdDef.Title)
		assert.Equal(t, createReq.PropertyID, createdDef.PropertyID)
		assert.Equal(t, pm.ID, createdDef.ManagerID) // Verify it's assigned to the correct PM

		// Assert audit log
		auditLogs, err := h.AdminAuditLogRepo.ListByTargetID(ctx, createdDef.ID)
		require.NoError(t, err)
		require.Len(t, auditLogs, 1, "Expected one audit log entry")
		assert.Equal(t, models.AuditCreate, auditLogs[0].Action)
		assert.Equal(t, models.TargetJobDefinition, auditLogs[0].TargetType)
		assert.Equal(t, adminUser.ID, auditLogs[0].AdminID)
	})

	// --- Test Case 2: UPDATE JobDefinition ---
	t.Run("AdminUpdatesJobDefinition", func(t *testing.T) {
		h.T = t
		require.NotNil(t, createdDef, "createdDef should not be nil for update test")

		// Arrange
		newTitle := "Admin Updated Job Title"
		updateReq := dtos.AdminUpdateJobDefinitionRequest{
			DefinitionID: createdDef.ID,
			Title:        &newTitle,
		}
		bodyBytes, err := json.Marshal(updateReq)
		require.NoError(t, err)

		req := h.BuildAuthRequest(http.MethodPatch, url, adminJWT, bodyBytes, "web", "127.0.0.1")

		// Act
		resp := h.DoRequest(req, client)
		defer resp.Body.Close()

		// Assert
		require.Equal(t, http.StatusOK, resp.StatusCode, "Expected 200 OK")
		var updatedDef *models.JobDefinition
		err = json.NewDecoder(resp.Body).Decode(&updatedDef)
		require.NoError(t, err)
		assert.Equal(t, newTitle, updatedDef.Title)
		assert.Greater(t, updatedDef.RowVersion, createdDef.RowVersion, "Row version should have incremented")

		// Assert audit log
		auditLogs, err := h.AdminAuditLogRepo.ListByTargetID(ctx, createdDef.ID)
		require.NoError(t, err)
		require.Len(t, auditLogs, 2, "Expected two audit log entries now")
		assert.Equal(t, models.AuditUpdate, auditLogs[1].Action)
		assert.Equal(t, models.TargetJobDefinition, auditLogs[1].TargetType)
		assert.Equal(t, adminUser.ID, auditLogs[1].AdminID)
	})

	// --- Test Case 3: DELETE JobDefinition (Soft) ---
	t.Run("AdminSoftDeletesJobDefinition", func(t *testing.T) {
		h.T = t
		require.NotNil(t, createdDef, "createdDef should not be nil for delete test")

		// Arrange: Create future instances to verify they get deleted
		var futureInstanceIDs []uuid.UUID
		for i := 1; i <= 3; i++ {
			inst := h.CreateTestJobInstance(t, ctx, createdDef.ID, time.Now().AddDate(0, 0, i), models.InstanceStatusOpen, nil)
			futureInstanceIDs = append(futureInstanceIDs, inst.ID)
		}

		deleteReq := dtos.AdminDeleteJobDefinitionRequest{
			DefinitionID: createdDef.ID,
		}
		bodyBytes, err := json.Marshal(deleteReq)
		require.NoError(t, err)

		req := h.BuildAuthRequest(http.MethodDelete, url, adminJWT, bodyBytes, "web", "127.0.0.1")

		// Act
		resp := h.DoRequest(req, client)
		defer resp.Body.Close()

		// Assert
		require.Equal(t, http.StatusOK, resp.StatusCode, "Expected 200 OK for soft delete")

		// Assert audit log
		auditLogs, err := h.AdminAuditLogRepo.ListByTargetID(ctx, createdDef.ID)
		require.NoError(t, err)
		require.Len(t, auditLogs, 3, "Expected three audit log entries now")
		assert.Equal(t, models.AuditDelete, auditLogs[2].Action)
		assert.Equal(t, models.TargetJobDefinition, auditLogs[2].TargetType)
		assert.Equal(t, adminUser.ID, auditLogs[2].AdminID)

		// Assert definition status is DELETED in the DB
		dbDef, err := h.JobDefRepo.GetByID(ctx, createdDef.ID)
		require.NoError(t, err)
		assert.Equal(t, models.JobStatusDeleted, dbDef.Status)

		// Assert cascade deletion of future open instances
		for _, instID := range futureInstanceIDs {
			_, err := h.JobInstRepo.GetByID(ctx, instID)
			assert.Error(t, err, fmt.Sprintf("Expected error when fetching deleted instance %s", instID))
			assert.ErrorIs(t, err, pgx.ErrNoRows, fmt.Sprintf("Expected ErrNoRows for deleted instance %s", instID))
		}
	})
}