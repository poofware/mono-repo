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
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/routes"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAdminJobEndpoints(t *testing.T) {
	h.T = t
	ctx := context.Background()

	// --- Setup ---
	adminUser, err := h.AdminRepo.GetByUsername(ctx, "seedadmin")
	require.NoError(t, err, "Failed to get seeded admin user")
	require.NotNil(t, adminUser, "Seeded admin user 'seedadmin' not found. Ensure DB is seeded.")
	adminJWT := h.CreateWebJWT(adminUser.ID, "127.0.0.1")
	client := h.NewHTTPClient()

	pm := h.CreateTestPM(ctx, "pm-for-admin-test")
	prop := h.CreateTestProperty(ctx, "AdminTestProp", pm.ID, 34.0, -86.0)
	bldg := h.CreateTestBuilding(ctx, prop.ID, "Admin-B1")
	dumpster := h.CreateTestDumpster(ctx, prop.ID, "Admin-D1")

	var createdDef *models.JobDefinition
	var url = h.BaseURL + routes.AdminJobDefinitions

	// --- Create ---
	t.Run("create job definition (admin)", func(t *testing.T) {
		req := dtos.AdminCreateJobDefinitionRequest{
			ManagerID:             pm.ID,
			PropertyID:            prop.ID,
			Title:                 "Admin Title",
			AssignedBuildingIDs:   []uuid.UUID{bldg.ID},
			DumpsterIDs:           []uuid.UUID{dumpster.ID},
			Frequency:             models.JobFreqDaily,
			StartDate:             time.Now().UTC().AddDate(0, 0, -1),
			EarliestStartTime:     time.Date(0, 1, 1, 0, 0, 0, 0, time.UTC),
			LatestStartTime:       time.Date(0, 1, 1, 23, 50, 0, 0, time.UTC),
			DailyPayEstimates:     []dtos.DailyPayEstimateRequest{{DayOfWeek: 0, BasePay: 10, EstimatedTimeMinutes: 30}, {DayOfWeek: 1, BasePay: 10, EstimatedTimeMinutes: 30}, {DayOfWeek: 2, BasePay: 10, EstimatedTimeMinutes: 30}, {DayOfWeek: 3, BasePay: 10, EstimatedTimeMinutes: 30}, {DayOfWeek: 4, BasePay: 10, EstimatedTimeMinutes: 30}, {DayOfWeek: 5, BasePay: 10, EstimatedTimeMinutes: 30}, {DayOfWeek: 6, BasePay: 10, EstimatedTimeMinutes: 30}},
		}
		body, _ := json.Marshal(req)
		r := h.BuildAuthRequest("POST", url, adminJWT, body, "web", "127.0.0.1")
		resp := h.DoRequest(r, client)
		defer resp.Body.Close()
		assert.Equal(t, http.StatusCreated, resp.StatusCode, "create should return 201")
		var created models.JobDefinition
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&created))
		createdDef = &created
		fmt.Println("Created def:", createdDef.ID)
	})

	// --- Update ---
	t.Run("update job definition (admin)", func(t *testing.T) {
		req := dtos.AdminUpdateJobDefinitionRequest{DefinitionID: createdDef.ID, Title: utils.Ptr("Updated Title")}
		body, _ := json.Marshal(req)
		r := h.BuildAuthRequest("PATCH", url, adminJWT, body, "web", "127.0.0.1")
		resp := h.DoRequest(r, client)
		defer resp.Body.Close()
		assert.Equal(t, http.StatusOK, resp.StatusCode, "update should return 200")
	})

	// --- Delete ---
	t.Run("delete job definition (admin)", func(t *testing.T) {
		req := dtos.AdminDeleteJobDefinitionRequest{DefinitionID: createdDef.ID}
		body, _ := json.Marshal(req)
		r := h.BuildAuthRequest("DELETE", url, adminJWT, body, "web", "127.0.0.1")
		resp := h.DoRequest(r, client)
		defer resp.Body.Close()
		assert.Equal(t, http.StatusOK, resp.StatusCode, "delete should return 200")
	})
}