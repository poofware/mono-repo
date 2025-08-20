//go:build (dev_test || dev || staging_test) && integration

package integration

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-testhelpers"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/routes"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestManagerJobEndpoints holds tests for manager-facing job endpoints.
func TestManagerJobEndpoints(t *testing.T) {
	h.T = t
	ctx := context.Background()

	// --- Test Data Setup ---
	// 1. Create a second PM for unauthorized tests
	unauthorizedPM := &models.PropertyManager{
		ID:              uuid.New(),
		Email:           testhelpers.UniqueEmail("unauthorized-pm"),
		BusinessName:    "Unauthorized LLC",
		BusinessAddress: "1 Hacker Way",
		City:            "Nowhere",
		State:           "NA",
		ZipCode:         "00000",
		AccountStatus:   models.AccountStatusActive,
		SetupProgress:   models.SetupProgressDone,
	}
	require.NoError(t, h.PMRepo.Create(ctx, unauthorizedPM))
	defer h.DB.Exec(ctx, `DELETE FROM property_managers WHERE id=$1`, unauthorizedPM.ID)

	// 2. Create property owned by the main testPM from TestMain
	prop := h.CreateTestProperty(ctx, "ManagerJobs Test Prop", testPM.ID, 34.0, -86.0)
	bldg := h.CreateTestBuilding(ctx, prop.ID, "MJ-B1")
	dumpster := h.CreateTestDumpster(ctx, prop.ID, "MJ-D1")

	// 3. Create a job definition and an instance for that property
	earliest, latest := h.TestSameDayTimeWindow()
	def := h.CreateTestJobDefinition(t, ctx, testPM.ID, prop.ID, "ManagerJobsDef",
		[]uuid.UUID{bldg.ID}, []uuid.UUID{dumpster.ID}, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
	inst := h.CreateTestJobInstance(t, ctx, def.ID, time.Now(), models.InstanceStatusOpen, nil)

	// 4. Generate JWTs for both PMs
	correctToken := h.CreateWebJWT(testPM.ID, "127.0.0.1")
	unauthorizedToken := h.CreateWebJWT(unauthorizedPM.ID, "127.0.0.1")
	client := h.NewHTTPClient()

	// --- Test Case 1: Successful Fetch ---
	t.Run("Should successfully fetch jobs for an owned property", func(t *testing.T) {
		h.T = t
		// ARRANGE
		url := h.BaseURL + routes.JobsPMInstances
		reqBody := dtos.ListJobsForPropertyRequest{PropertyID: prop.ID}
		bodyBytes, _ := json.Marshal(reqBody)
		req := h.BuildAuthRequest("POST", url, correctToken, bodyBytes, "web", "127.0.0.1")

		// ACT
		resp := h.DoRequest(req, client)
		defer resp.Body.Close()

		// ASSERT
		assert.Equal(t, http.StatusOK, resp.StatusCode, "Expected a 200 OK status")

		var jobResponse dtos.ListJobsPMResponse
		err := json.NewDecoder(resp.Body).Decode(&jobResponse)
		require.NoError(t, err, "Failed to decode JSON response")

		assert.Greater(t, jobResponse.Total, 0, "Expected to find at least one job instance")
		require.NotEmpty(t, jobResponse.Results, "Results should not be empty")

		found := false
		for _, jobDTO := range jobResponse.Results {
			if jobDTO.InstanceID == inst.ID {
				found = true
				assert.Equal(t, prop.ID, jobDTO.PropertyID, "Job's property ID should match the requested one")
				// Check that the DTO is the restricted PM version by checking for a field that should NOT exist.
				var asMap map[string]interface{}
				jobBytes, _ := json.Marshal(jobDTO)
				json.Unmarshal(jobBytes, &asMap)
				_, hasPay := asMap["pay"]
				assert.False(t, hasPay, "JobInstancePMDTO should not contain 'pay' field")
				_, hasTravelMinutes := asMap["travel_minutes"]
				assert.False(t, hasTravelMinutes, "JobInstancePMDTO should not contain 'travel_minutes' field")
			}
		}
		assert.True(t, found, "Did not find the created test job instance in the response")
	})

	// --- Test Case 2: Forbidden Access ---
	t.Run("Should return forbidden when fetching jobs for a non-owned property", func(t *testing.T) {
		h.T = t
		// ARRANGE
		url := h.BaseURL + routes.JobsPMInstances
		reqBody := dtos.ListJobsForPropertyRequest{PropertyID: prop.ID}
		bodyBytes, _ := json.Marshal(reqBody)
		req := h.BuildAuthRequest("POST", url, unauthorizedToken, bodyBytes, "web", "127.0.0.1") // Use the wrong PM's token

		// ACT
		resp := h.DoRequest(req, client)
		defer resp.Body.Close()

		// ASSERT
		assert.Equal(t, http.StatusForbidden, resp.StatusCode, "Expected a 403 Forbidden status")
	})

	// --- Test Case 3: Invalid Property ID ---
	t.Run("Should return bad request for invalid property ID format", func(t *testing.T) {
		h.T = t
		// ARRANGE
		url := h.BaseURL + routes.JobsPMInstances
		reqBody := `{"property_id": "not-a-uuid"}` // Malformed JSON
		req := h.BuildAuthRequest("POST", url, correctToken, []byte(reqBody), "web", "127.0.0.1")

		// ACT
		resp := h.DoRequest(req, client)
		defer resp.Body.Close()

		// ASSERT
		assert.Equal(t, http.StatusBadRequest, resp.StatusCode, "Expected a 400 Bad Request status for malformed request body")
	})
}