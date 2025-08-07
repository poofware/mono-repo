//go:build dev && integration

package integration

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/dtos"
)

// TestListOpenJobs_TravelInfo verifies that DistanceMiles and TravelMinutes are correctly
// populated. It also attempts to infer if the actual Google Maps Routes API was used
// for routes where a simple distance heuristic would differ significantly from real driving time.
func TestListOpenJobs_TravelInfo(t *testing.T) {
	h.T = t
	ctx := context.Background()
	earliest, latest := h.TestSameDayTimeWindow()

	worker := h.CreateTestWorker(ctx, "gmapstester")
	const deviceID = "gmapstest-device-session1" // Consistent device ID
	workerJWT := h.CreateMobileJWT(worker.ID, deviceID, "FAKE-PLAY")
	httpClient := h.NewHTTPClient()

	// --- Test Case 1: Palo Alto (query) to San Jose (property) ---
	propLatSJ, propLngSJ := 37.3382, -121.8863      // San Jose, CA
	workerQueryLatPA, workerQueryLngPA := 37.4419, -122.1430 // Palo Alto, CA

	propSJ := h.CreateTestProperty(ctx, "GMapsPropSJ", testPM.ID, propLatSJ, propLngSJ)
	buildingSJ := h.CreateTestBuilding(ctx, propSJ.ID, "GMapsBuildingSJ")
	dumpsterSJ := h.CreateTestDumpster(ctx, propSJ.ID, "GMapsDumpsterSJ")
	defSJ := h.CreateTestJobDefinition(t, ctx, testPM.ID, propSJ.ID, "GMapsJobSJ",
		[]uuid.UUID{buildingSJ.ID}, []uuid.UUID{dumpsterSJ.ID}, earliest, latest,
		models.JobStatusActive, nil, models.JobFreqDaily, nil)
	// MODIFIED: Create instance for tomorrow to ensure it's always within the acceptance window.
	_ = h.CreateTestJobInstance(t, ctx, defSJ.ID, time.Now().UTC().AddDate(0, 0, 1), models.InstanceStatusOpen, nil)

	listURLPA := fmt.Sprintf("%s/api/v1/jobs/open?lat=%f&lng=%f&page=1&size=10",
		h.BaseURL, workerQueryLatPA, workerQueryLngPA)
	reqPA := h.BuildAuthRequest("GET", listURLPA, workerJWT, nil, "android", deviceID)
	respPA := h.DoRequest(reqPA, httpClient)
	defer respPA.Body.Close()
	require.Equal(t, http.StatusOK, respPA.StatusCode, "Failed to list jobs from Palo Alto. Body: %s", h.ReadBody(respPA))

	var outPA dtos.ListJobsResponse
	rawPA, _ := io.ReadAll(respPA.Body)
	require.NoError(t, json.Unmarshal(rawPA, &outPA), "Failed to unmarshal Palo Alto response. Raw: %s", string(rawPA))
	require.GreaterOrEqual(t, outPA.Total, 1)
	require.NotEmpty(t, outPA.Results)

	var jobDTOPA dtos.JobInstanceDTO
	foundJobPA := false
	for _, j := range outPA.Results {
		if j.PropertyID == propSJ.ID {
			jobDTOPA = j
			foundJobPA = true
			break
		}
	}
	require.True(t, foundJobPA, "Expected to find San Jose job from Palo Alto query. Results: %+v", outPA.Results)

	// --- Distance Assertions for PA to SJ ---
	expectedHaversineDistPAtoSJ := utils.DistanceMiles(workerQueryLatPA, workerQueryLngPA, propLatSJ, propLngSJ)
	actualDrivingDistPAtoSJ := jobDTOPA.DistanceMiles
	t.Logf("Palo Alto to San Jose: Expected Haversine Distance=%.2f, API Reported Driving Distance=%.2f", expectedHaversineDistPAtoSJ, actualDrivingDistPAtoSJ)

	require.Greater(t, actualDrivingDistPAtoSJ, 0.0, "API Driving Distance (PA-SJ) should be positive")
	require.GreaterOrEqualf(t, actualDrivingDistPAtoSJ, expectedHaversineDistPAtoSJ-0.1,
		"API Driving Distance (%.2f) (PA-SJ) should generally be >= Haversine distance (%.2f)", actualDrivingDistPAtoSJ, expectedHaversineDistPAtoSJ)
	maxExpectedDrivingDistRatio := 1.75
	require.LessOrEqualf(t, actualDrivingDistPAtoSJ, expectedHaversineDistPAtoSJ*maxExpectedDrivingDistRatio,
		"API Driving Distance (%.2f) (PA-SJ) is unexpectedly large ( > %.2fx Haversine of %.2f). Max allowed: %.2f",
		actualDrivingDistPAtoSJ, maxExpectedDrivingDistRatio, expectedHaversineDistPAtoSJ, expectedHaversineDistPAtoSJ*maxExpectedDrivingDistRatio)

	// --- TravelMinutes Assertions for PA to SJ ---
	require.NotNil(t, jobDTOPA.TravelMinutes, "TravelMinutes (PA-SJ) should be populated")
	if jobDTOPA.TravelMinutes != nil {
		require.Greater(t, *jobDTOPA.TravelMinutes, 0, "TravelMinutes (PA-SJ) should be positive. Got: %d", *jobDTOPA.TravelMinutes)
		t.Logf("Palo Alto to San Jose: API Reported TravelMinutes=%d", *jobDTOPA.TravelMinutes)
		minExpectedTravelTime := int(actualDrivingDistPAtoSJ * 1.0) // ~60 mph avg
		maxExpectedTravelTime := int(actualDrivingDistPAtoSJ * 3.0) // ~20 mph avg (allow more variance)
		require.GreaterOrEqualf(t, float64(*jobDTOPA.TravelMinutes), float64(minExpectedTravelTime), "TravelMinutes for PA-SJ (%d) seems too low for distance %.2f miles (min expected: %d)", *jobDTOPA.TravelMinutes, actualDrivingDistPAtoSJ, minExpectedTravelTime)
		require.LessOrEqualf(t, float64(*jobDTOPA.TravelMinutes), float64(maxExpectedTravelTime), "TravelMinutes for PA-SJ (%d) seems too high for distance %.2f miles (max expected: %d)", *jobDTOPA.TravelMinutes, actualDrivingDistPAtoSJ, maxExpectedTravelTime)
	}

	// --- Test Case 2: Oakland (query) to San Francisco (property) - Tests routing over a bridge ---
	propLatSF, propLngSF := 37.7749, -122.4194      // San Francisco, CA
	workerQueryLatOK, workerQueryLngOK := 37.8044, -122.2712 // Oakland, CA

	propSF := h.CreateTestProperty(ctx, "GMapsPropSF", testPM.ID, propLatSF, propLngSF)
	buildingSF := h.CreateTestBuilding(ctx, propSF.ID, "GMapsBuildingSF")
	dumpsterSF := h.CreateTestDumpster(ctx, propSF.ID, "GMapsDumpsterSF")
	serviceDateSF := time.Now().UTC().AddDate(0, 0, 1)
	defSF := h.CreateTestJobDefinition(t, ctx, testPM.ID, propSF.ID, "GMapsJobSF",
		[]uuid.UUID{buildingSF.ID}, []uuid.UUID{dumpsterSF.ID}, earliest, latest,
		models.JobStatusActive, nil, models.JobFreqDaily, nil)
	_ = h.CreateTestJobInstance(t, ctx, defSF.ID, serviceDateSF, models.InstanceStatusOpen, nil)

	listURLSF := fmt.Sprintf("%s/api/v1/jobs/open?lat=%f&lng=%f&page=1&size=10",
		h.BaseURL, workerQueryLatOK, workerQueryLngOK)
	reqSF := h.BuildAuthRequest("GET", listURLSF, workerJWT, nil, "android", deviceID)
	respSF := h.DoRequest(reqSF, httpClient)
	defer respSF.Body.Close()
	require.Equal(t, http.StatusOK, respSF.StatusCode, "Failed to list jobs from Oakland. Body: %s", h.ReadBody(respSF))

	var outSF dtos.ListJobsResponse
	rawSF, _ := io.ReadAll(respSF.Body)
	require.NoError(t, json.Unmarshal(rawSF, &outSF), "Failed to unmarshal Oakland response. Raw: %s", string(rawSF))
	require.GreaterOrEqual(t, outSF.Total, 1)
	require.NotEmpty(t, outSF.Results)

	var jobDTOSF dtos.JobInstanceDTO
	foundJobSF := false
	for _, j := range outSF.Results {
		if j.PropertyID == propSF.ID {
			jobDTOSF = j
			foundJobSF = true
			break
		}
	}
	require.True(t, foundJobSF, "Expected to find San Francisco job from Oakland query. Results: %+v", outSF.Results)

	// --- Distance Assertions for OK to SF ---
	expectedHaversineDistOKtoSF := utils.DistanceMiles(workerQueryLatOK, workerQueryLngOK, propLatSF, propLngSF)
	actualDrivingDistOKtoSF := jobDTOSF.DistanceMiles
	t.Logf("Oakland to San Francisco: Expected Haversine Distance=%.2f, API Reported Driving Distance=%.2f", expectedHaversineDistOKtoSF, actualDrivingDistOKtoSF)

	require.Greater(t, actualDrivingDistOKtoSF, 0.0, "API Driving Distance (OK-SF) should be positive")
	require.GreaterOrEqualf(t, actualDrivingDistOKtoSF, expectedHaversineDistOKtoSF-0.1,
		"API Driving Distance (%.2f) (OK-SF) should generally be >= Haversine distance (%.2f)", actualDrivingDistOKtoSF, expectedHaversineDistOKtoSF)
	maxExpectedDrivingDistRatioOKSF := 2.0 // Bay Bridge route can be significantly longer than direct line, increased ratio
	require.LessOrEqualf(t, actualDrivingDistOKtoSF, expectedHaversineDistOKtoSF*maxExpectedDrivingDistRatioOKSF,
		"API Driving Distance (%.2f) (OK-SF) is unexpectedly large ( > %.2fx Haversine of %.2f). Max allowed: %.2f",
		actualDrivingDistOKtoSF, maxExpectedDrivingDistRatioOKSF, expectedHaversineDistOKtoSF, expectedHaversineDistOKtoSF*maxExpectedDrivingDistRatioOKSF)

	// --- TravelMinutes Assertions for OK to SF ---
	require.NotNil(t, jobDTOSF.TravelMinutes, "TravelMinutes (OK-SF) should be populated")
	if jobDTOSF.TravelMinutes != nil {
		require.Greater(t, *jobDTOSF.TravelMinutes, 0, "TravelMinutes (OK-SF) should be positive. Got: %d", *jobDTOSF.TravelMinutes)

		haversineBasedFallbackTimeOKtoSF := int(expectedHaversineDistOKtoSF*utils.CrowFliesDriveTimeMultiplier + 0.5)

		t.Logf("Oakland to San Francisco: API Reported Driving Distance=%.2f, API Reported TravelMinutes=%d, Haversine-based Fallback Time Est: ~%d mins",
			actualDrivingDistOKtoSF,
			*jobDTOSF.TravelMinutes,
			haversineBasedFallbackTimeOKtoSF)

		// Assertion 1: Plausible time for API distance
		minExpectedTravelTimeForAPIDist := int(actualDrivingDistOKtoSF / (70.0 / 60.0)) // Max speed 70mph for the driving distance
		maxExpectedTravelTimeForAPIDist := int(actualDrivingDistOKtoSF / (10.0 / 60.0)) // Min speed 10mph for bridge traffic
		require.GreaterOrEqualf(t, float64(*jobDTOSF.TravelMinutes), float64(minExpectedTravelTimeForAPIDist), "API TravelMinutes for OK-SF (%d) seems too low for API driving distance %.2f miles (min expected for dist: %d)", *jobDTOSF.TravelMinutes, actualDrivingDistOKtoSF, minExpectedTravelTimeForAPIDist)
		require.LessOrEqualf(t, float64(*jobDTOSF.TravelMinutes), float64(maxExpectedTravelTimeForAPIDist), "API TravelMinutes for OK-SF (%d) seems too high for API driving distance %.2f miles (max expected for dist: %d)", *jobDTOSF.TravelMinutes, actualDrivingDistOKtoSF, maxExpectedTravelTimeForAPIDist)

		// Assertion 2: For OK-SF, the API reported travel time should be noticeably different (likely greater)
		// than a simple Haversine-distance-based fallback time, indicating real routing.
		// A 3-minute absolute difference or more should indicate it's not just the fallback.
		timeDifferenceFromHaversineFallback := math.Abs(float64(*jobDTOSF.TravelMinutes - haversineBasedFallbackTimeOKtoSF))
		distanceDifferenceFromHaversine := math.Abs(actualDrivingDistOKtoSF - expectedHaversineDistOKtoSF)

		// If API time is very close to Haversine fallback AND API distance is very close to Haversine distance, it's suspicious.
		// Otherwise, if either time or distance show significant routing intelligence, it's good.
		isDistinctFromSimpleFallback := timeDifferenceFromHaversineFallback > 3.0 || distanceDifferenceFromHaversine > 1.5 // e.g. >3 mins OR >1.5 miles diff

		require.True(t, isDistinctFromSimpleFallback,
			fmt.Sprintf("For OK-SF: API Time (%d min) vs Haversine Fallback Time (%d min) (Diff: %.1f min).\n"+
				"AND API Driving Distance (%.2f mi) vs Haversine Distance (%.2f mi) (Diff: %.2f mi).\n"+
				"Both time and distance are too similar to simple Haversine-based estimates, suggesting GMaps API might not be providing detailed routing for this complex path or is returning values very close to the fallback.",
				*jobDTOSF.TravelMinutes, haversineBasedFallbackTimeOKtoSF, timeDifferenceFromHaversineFallback,
				actualDrivingDistOKtoSF, expectedHaversineDistOKtoSF, distanceDifferenceFromHaversine))

		t.Logf("Oakland-SF: API Time (%d) vs Haversine Fallback Time (%d). API Dist (%.2f) vs Haversine Dist (%.2f). Distinctness checks passed.",
			*jobDTOSF.TravelMinutes, haversineBasedFallbackTimeOKtoSF, actualDrivingDistOKtoSF, expectedHaversineDistOKtoSF)
	}

	// --- Test Case 3: Worker query with (0,0) lat/lng ---
	listURLZero := fmt.Sprintf("%s/api/v1/jobs/open?lat=0&lng=0&page=1&size=10", h.BaseURL)
	reqZero := h.BuildAuthRequest("GET", listURLZero, workerJWT, nil, "android", deviceID)
	respZero := h.DoRequest(reqZero, httpClient)
	defer respZero.Body.Close()
	require.Equal(t, http.StatusOK, respZero.StatusCode, "Failed to list jobs from (0,0). Body: %s", h.ReadBody(respZero))

	var outZero dtos.ListJobsResponse
	rawZero, _ := io.ReadAll(respZero.Body)
	require.NoError(t, json.Unmarshal(rawZero, &outZero), "Failed to unmarshal (0,0) response. Raw: %s", string(rawZero))
	require.GreaterOrEqual(t, outZero.Total, 1)
	require.NotEmpty(t, outZero.Results)

	jobDTOZero := outZero.Results[0]
	require.Equal(t, 0.0, jobDTOZero.DistanceMiles)
	require.Nil(t, jobDTOZero.TravelMinutes)
	t.Logf("Query from (0,0): DistanceMiles=%.2f, TravelMinutes=<nil> (as expected)", jobDTOZero.DistanceMiles)
}
