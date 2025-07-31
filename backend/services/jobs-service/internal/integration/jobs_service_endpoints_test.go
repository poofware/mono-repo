//go:build (dev_test || staging_test) && integration

package integration

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"sync"
	"testing"
	"time"

	"github.com/bradfitz/latlong"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/poofware/go-models"
	"github.com/poofware/go-testhelpers"
	"github.com/poofware/go-utils"
	"github.com/poofware/jobs-service/internal/constants"
	"github.com/poofware/jobs-service/internal/dtos"
	"github.com/poofware/jobs-service/internal/routes"
	"github.com/poofware/jobs-service/internal/services"
	internal_utils "github.com/poofware/jobs-service/internal/utils"
)

/*
───────────────────────────────────────────────────────────────────
 1. Health Check

───────────────────────────────────────────────────────────────────
*/
func TestHealthCheck(t *testing.T) {
	h.T = t
	u := h.BaseURL + routes.Health
	req := h.BuildAuthRequest("GET", u, "", nil, "android", "health-dev")
	client := h.NewHTTPClient()
	resp := h.DoRequest(req, client)
	defer resp.Body.Close()

	require.Equal(t, 200, resp.StatusCode)
	body, _ := io.ReadAll(resp.Body)
	t.Logf("Health => %s", string(body))
}

/*
───────────────────────────────────────────────────────────────────
 2. Seed property + building + dumpster

───────────────────────────────────────────────────────────────────
*/
func TestSeedPropertyAndBuildings(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	prop := h.CreateTestProperty(ctx, "SeedingTest Property", testPM.ID, 35.9251, -84.0054)
	b1 := h.CreateTestBuilding(ctx, prop.ID, "Bldg A")
	b2 := h.CreateTestBuilding(ctx, prop.ID, "Bldg B")
	d := h.CreateTestDumpster(ctx, prop.ID, "D-1")

	t.Logf("Created property (id=%s) + 2 buildings (ids=%s, %s) + 1 dumpster (id=%s)", prop.ID, b1.ID, b2.ID, d.ID)
}

/*
───────────────────────────────────────────────────────────────────
 3. ListOpenJobs

───────────────────────────────────────────────────────────────────
*/
func TestListOpenJobs(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	earliest, latest := h.TestSameDayTimeWindow()

	// Property 1 (in range of worker in Chicago)
	p1 := h.CreateTestProperty(ctx, "ListJobs Prop1", testPM.ID, 42.0451, -87.6877) // Evanston, IL
	p1.TimeZone = "America/Chicago"                                                 // Match the location
	require.NoError(t, h.PropertyRepo.Update(ctx, p1))

	b1_p1 := h.CreateTestBuilding(ctx, p1.ID, "P1B1")
	d1_p1 := h.CreateTestDumpster(ctx, p1.ID, "P1D1")
	def1 := h.CreateTestJobDefinition(t, ctx, testPM.ID, p1.ID, "ListingJob1",
		[]uuid.UUID{b1_p1.ID}, []uuid.UUID{d1_p1.ID}, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)

	for i := range 3 {
		dt := time.Now().UTC().AddDate(0, 0, i)
		_ = h.CreateTestJobInstance(t, ctx, def1.ID, dt, models.InstanceStatusOpen, nil)
	}

	// Property 2 (out of range)
	p2 := h.CreateTestProperty(ctx, "ListJobs Prop2 OOR", testPM.ID, 40.0, -90.0)
	b1_p2 := h.CreateTestBuilding(ctx, p2.ID, "P2B1")
	d1_p2 := h.CreateTestDumpster(ctx, p2.ID, "P2D1")
	def2 := h.CreateTestJobDefinition(t, ctx, testPM.ID, p2.ID, "ListingJob2 OOR",
		[]uuid.UUID{b1_p2.ID}, []uuid.UUID{d1_p2.ID}, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
	_ = h.CreateTestJobInstance(t, ctx, def2.ID, time.Now().UTC(), models.InstanceStatusOpen, nil)

	// Worker
	w := h.CreateTestWorker(ctx, "listjobs")
	wJWT := h.CreateMobileJWT(w.ID, "listjobs-dev", "FAKE-PLAY")

	// --- Subtest 3.1: Standard Listing and Paging ---
	t.Run("StandardListingAndPaging", func(t *testing.T) {
		h.T = t
		page := "1"
		size := "2"
		// Worker is in Chicago (central time)
		workerLat, workerLng := 41.8781, -87.6298
		listURL := fmt.Sprintf("%s/api/v1/jobs/open?lat=%f&lng=%f&page=%s&size=%s",
			h.BaseURL, workerLat, workerLng, page, size)

		req := h.BuildAuthRequest("GET", listURL, wJWT, nil, "android", "listjobs-dev")
		client := h.NewHTTPClient()
		resp := h.DoRequest(req, client)
		defer resp.Body.Close()
		require.Equal(t, 200, resp.StatusCode)

		var out dtos.ListJobsResponse
		raw, _ := io.ReadAll(resp.Body)
		require.NoError(t, json.Unmarshal(raw, &out))
		require.Equal(t, 3, out.Total)
		require.Len(t, out.Results, 2)

		// In-depth check of the first result
		if len(out.Results) > 0 {
			jobDTO := out.Results[0]
			require.NotEmpty(t, jobDTO.Property.PropertyName)
			require.NotEmpty(t, jobDTO.Property.Address)
			require.Greater(t, jobDTO.Pay, 0.0, "Job pay should be positive")
			require.Greater(t, jobDTO.EstimatedTimeMinutes, 0, "Job estimated time should be positive")

			// --- CORRECTED TEST LOGIC ---
			// This logic now correctly reflects the service's behavior of using the property's local timezone.
			workerTzName := latlong.LookupZoneName(workerLat, workerLng)
			workerLoc, err := time.LoadLocation(workerTzName)
			require.NoError(t, err)

			propLoc, err := time.LoadLocation(p1.TimeZone)
			require.NoError(t, err)

			jobServiceDate, _ := time.Parse("2006-01-02", jobDTO.ServiceDate)

			// Reconstruct the absolute start/end/hint times using the property's timezone, just like the service does.
			earliestStartLocal := time.Date(jobServiceDate.Year(), jobServiceDate.Month(), jobServiceDate.Day(), def1.EarliestStartTime.Hour(), def1.EarliestStartTime.Minute(), 0, 0, propLoc)
			latestStartLocal := time.Date(jobServiceDate.Year(), jobServiceDate.Month(), jobServiceDate.Day(), def1.LatestStartTime.Hour(), def1.LatestStartTime.Minute(), 0, 0, propLoc)
			hintLocal := time.Date(jobServiceDate.Year(), jobServiceDate.Month(), jobServiceDate.Day(), def1.StartTimeHint.Hour(), def1.StartTimeHint.Minute(), 0, 0, propLoc)
			noShowCutoffLocal := latestStartLocal.Add(-constants.NoShowCutoffBeforeLatestStart)

			// Now, format those correct absolute times for each timezone and assert.
			expectedWorkerWindowStart := earliestStartLocal.In(workerLoc).Format("15:04")
			expectedWorkerWindowEnd := noShowCutoffLocal.In(workerLoc).Format("15:04")
			expectedWorkerHint := hintLocal.In(workerLoc).Format("15:04")

			expectedPropertyWindowStart := earliestStartLocal.In(propLoc).Format("15:04")
			expectedPropertyWindowEnd := noShowCutoffLocal.In(propLoc).Format("15:04")
			expectedPropertyHint := hintLocal.In(propLoc).Format("15:04")

			// Assert all 6 time fields
			require.Equal(t, expectedWorkerWindowStart, jobDTO.WorkerServiceWindowStart, "Worker window start mismatch")
			require.Equal(t, expectedWorkerWindowEnd, jobDTO.WorkerServiceWindowEnd, "Worker window end mismatch")
			require.Equal(t, expectedWorkerHint, jobDTO.WorkerStartTimeHint, "Worker hint mismatch")

			require.Equal(t, expectedPropertyWindowStart, jobDTO.PropertyServiceWindowStart, "Property window start mismatch")
			require.Equal(t, expectedPropertyWindowEnd, jobDTO.PropertyServiceWindowEnd, "Property window end mismatch")
			require.Equal(t, expectedPropertyHint, jobDTO.StartTimeHint, "Property hint mismatch")
		}

		listURL2 := fmt.Sprintf("%s/api/v1/jobs/open?lat=%f&lng=%f&page=2&size=%s", h.BaseURL, workerLat, workerLng, size)
		req2 := h.BuildAuthRequest("GET", listURL2, wJWT, nil, "android", "listjobs-dev")
		resp2 := h.DoRequest(req2, client)
		defer resp2.Body.Close()
		require.Equal(t, 200, resp2.StatusCode)

		var out2 dtos.ListJobsResponse
		b2_respBody, _ := io.ReadAll(resp2.Body)
		require.NoError(t, json.Unmarshal(b2_respBody, &out2))
		require.Equal(t, 3, out2.Total)
		require.Len(t, out2.Results, 1)
		if len(out2.Results) > 0 {
			require.NotEmpty(t, out2.Results[0].Property.PropertyName)
		}
	})

	// --- Subtest 3.2: Job past its acceptance cutoff is not listed ---
	t.Run("ListJobPastAcceptanceCutoff_IsNotVisible", func(t *testing.T) {
		h.T = t

		// --- FIX: Create time window relative to the property's timezone ---
		propLoc, err := time.LoadLocation(p1.TimeZone)
		require.NoError(t, err)
		nowInPropLoc := time.Now().In(propLoc)

		// Create a definition where the acceptance cutoff for today's job has already passed.
		// The original logic could fail the `latest > earliest` DB check when run near midnight.
		// This revised logic sets `latest_start` to be `now - 20m`. This means the acceptance
		// cutoff is `now - 60m` (in the past), while keeping the time values on the same calendar day.
		latestStart := nowInPropLoc.Add(-20 * time.Minute)
		earliestStart := latestStart.Add(-100 * time.Minute) // A 100min duration satisfies all constraints.

		unacceptableDef := h.CreateTestJobDefinition(t, ctx, testPM.ID, p1.ID, "UnacceptableJobDef",
			[]uuid.UUID{b1_p1.ID}, []uuid.UUID{d1_p1.ID}, earliestStart, latestStart, models.JobStatusActive, nil, models.JobFreqDaily, nil)

		// Create the instance for today in the property's timezone to be certain about the service date.
		todayInPropTZ := time.Date(nowInPropLoc.Year(), nowInPropLoc.Month(), nowInPropLoc.Day(), 0, 0, 0, 0, propLoc)
		_ = h.CreateTestJobInstance(t, ctx, unacceptableDef.ID, todayInPropTZ, models.InstanceStatusOpen, nil)

		// List jobs again
		listURL := fmt.Sprintf("%s/api/v1/jobs/open?lat=%f&lng=%f&page=1&size=50",
			h.BaseURL, 41.8781, -87.6298)
		req := h.BuildAuthRequest("GET", listURL, wJWT, nil, "android", "listjobs-dev")
		resp := h.DoRequest(req, h.NewHTTPClient())
		defer resp.Body.Close()
		require.Equal(t, http.StatusOK, resp.StatusCode)

		var out dtos.ListJobsResponse
		raw, _ := io.ReadAll(resp.Body)
		require.NoError(t, json.Unmarshal(raw, &out))

		// The total should still be 3 from the first subtest, as the job past its
		// acceptance cutoff should not be included.
		require.Equal(t, 3, out.Total, "Job past its acceptance cutoff should not be counted in the total")
		for _, job := range out.Results {
			require.NotEqual(t, unacceptableDef.ID, job.DefinitionID, "Job past its acceptance cutoff should not be present in the results list")
		}
		t.Logf("Successfully verified that job past its acceptance cutoff time is not listed.")
	})
}

/*
───────────────────────────────────────────────────────────────────

	3.5) ListMyJobs (assigned or in-progress)

───────────────────────────────────────────────────────────────────
*/
func TestListMyJobs(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	earliest, latest := h.TestSameDayTimeWindow()

	w := h.CreateTestWorker(ctx, "myjobs")
	wJWT := h.CreateMobileJWT(w.ID, "myjobs-dev", "FAKE-PLAY")

	p := h.CreateTestProperty(ctx, "ListMyJobs Prop", testPM.ID, 34.99, -84.01)
	bldg := h.CreateTestBuilding(ctx, p.ID, "LMJB1")
	dump := h.CreateTestDumpster(ctx, p.ID, "LMJD1")

	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "ListMyJobsDefn",
		[]uuid.UUID{bldg.ID}, []uuid.UUID{dump.ID}, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)

	assignedInst := h.CreateTestJobInstance(t, ctx, defn.ID, time.Now(), models.InstanceStatusAssigned, &w.ID)
	inProgInst := h.CreateTestJobInstance(t, ctx, defn.ID, time.Now().AddDate(0, 0, 1), models.InstanceStatusInProgress, &w.ID)
	_ = h.CreateTestJobInstance(t, ctx, defn.ID, time.Now().AddDate(0, 0, 2), models.InstanceStatusOpen, nil)

	otherWorker := h.CreateTestWorker(ctx, "myjobs-other")
	_ = h.CreateTestJobInstance(t, ctx, defn.ID, time.Now().AddDate(0, 0, 3), models.InstanceStatusAssigned, &otherWorker.ID)

	listURL := fmt.Sprintf("%s/api/v1/jobs/my?lat=35.0&lng=-84.0&page=1&size=50", h.BaseURL)
	req := h.BuildAuthRequest("GET", listURL, wJWT, nil, "android", "myjobs-dev")
	client := h.NewHTTPClient()
	resp := h.DoRequest(req, client)
	defer resp.Body.Close()
	require.Equal(t, 200, resp.StatusCode)

	var out dtos.ListJobsResponse
	raw, _ := io.ReadAll(resp.Body)
	require.NoError(t, json.Unmarshal(raw, &out))

	require.Equal(t, 2, out.Total)
	require.Len(t, out.Results, 2)

	foundAssigned := false
	foundInProgress := false
	if len(out.Results) == 2 {
		require.NotEmpty(t, out.Results[0].Property.PropertyName)
		require.NotEmpty(t, out.Results[0].Property.Address)
		for _, job := range out.Results {
			if job.InstanceID == assignedInst.ID {
				foundAssigned = true
			}
			if job.InstanceID == inProgInst.ID {
				foundInProgress = true
			}
		}
	}
	require.True(t, foundAssigned)
	require.True(t, foundInProgress)
	t.Logf("ListMyJobs => total=%d, returned=%d", out.Total, len(out.Results))
}

/*
───────────────────────────────────────────────────────────────────
 4. Create, Pause, Archive definitions

───────────────────────────────────────────────────────────────────
*/
func TestJobDefinitionFlow(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	earliest, latest := h.TestSameDayTimeWindow()

	p := h.CreateTestProperty(ctx, "FlowProp", testPM.ID, 0, 0)
	bID := h.CreateTestBuilding(ctx, p.ID, "Test Building for Flow").ID
	dID := h.CreateTestDumpster(ctx, p.ID, "Test Dumpster for Flow").ID
	pmJWT := h.CreateWebJWT(testPM.ID, "127.0.0.1")

	t.Run("CreateDefinition_WithGlobalEstimates_OK", func(t *testing.T) {
		h.T = t
		reqDTO := dtos.CreateJobDefinitionRequest{
			PropertyID:                 p.ID,
			Title:                      "Trash Global BiWeekly",
			Description:                utils.Ptr("Clean up trash across property using global estimates."),
			AssignedUnitsByBuilding:    []models.AssignedUnitGroup{{BuildingID: bID, UnitIDs: []uuid.UUID{}}},
			DumpsterIDs:                []uuid.UUID{dID},
			Frequency:                  models.JobFreqBiWeekly,
			StartDate:                  time.Now().AddDate(0, 0, 1),
			EarliestStartTime:          earliest,
			LatestStartTime:            latest,
			GlobalBasePay:              utils.Ptr(80.0),
			GlobalEstimatedTimeMinutes: utils.Ptr(75),
		}
		body, _ := json.Marshal(reqDTO)
		ep := h.BaseURL + routes.JobsDefinitionCreate
		req := h.BuildAuthRequest("POST", ep, pmJWT, body, "web", "127.0.0.1")

		client := h.NewHTTPClient()
		resp := h.DoRequest(req, client)
		defer resp.Body.Close()
		require.Equal(t, 201, resp.StatusCode)

		var cResp dtos.CreateJobDefinitionResponse
		data, _ := io.ReadAll(resp.Body)
		json.Unmarshal(data, &cResp)
		require.NotEqual(t, uuid.Nil, cResp.DefinitionID)
		t.Logf("Created definitionID=%s with global estimates", cResp.DefinitionID)

		createdDef, err := h.JobDefRepo.GetByID(ctx, cResp.DefinitionID)
		require.NoError(t, err)
		require.NotNil(t, createdDef)
		require.Len(t, createdDef.DailyPayEstimates, 7, "Should have 7 daily estimates from global init")
		for _, est := range createdDef.DailyPayEstimates {
			require.Equal(t, 80.0, est.BasePay)
			require.Equal(t, 75, est.EstimatedTimeMinutes)
			require.Equal(t, 75, est.InitialEstimatedTimeMinutes)
		}
	})

	t.Run("CreateDefinition_WithDailyEstimates_OK", func(t *testing.T) {
		h.T = t
		customWeekdays := []int16{int16(time.Monday), int16(time.Wednesday), int16(time.Friday)}
		requiredDailyEstimatesForCustom := []dtos.DailyPayEstimateRequest{
			{DayOfWeek: int(time.Monday), BasePay: 70.0, EstimatedTimeMinutes: 65},
			{DayOfWeek: int(time.Wednesday), BasePay: 75.0, EstimatedTimeMinutes: 70},
			{DayOfWeek: int(time.Friday), BasePay: 80.0, EstimatedTimeMinutes: 75},
		}

		reqDTO := dtos.CreateJobDefinitionRequest{
			PropertyID:              p.ID,
			Title:                   "Trash Custom DailyEst",
			AssignedUnitsByBuilding: []models.AssignedUnitGroup{{BuildingID: bID, UnitIDs: []uuid.UUID{}}},
			DumpsterIDs:             []uuid.UUID{dID},
			Frequency:               models.JobFreqCustom,
			Weekdays:                customWeekdays,
			IntervalWeeks:           utils.Ptr(1),
			StartDate:               time.Now().AddDate(0, 0, 1),
			EarliestStartTime:       earliest,
			LatestStartTime:         latest,
			DailyPayEstimates:       requiredDailyEstimatesForCustom,
		}
		body, _ := json.Marshal(reqDTO)
		ep := h.BaseURL + routes.JobsDefinitionCreate
		req := h.BuildAuthRequest("POST", ep, pmJWT, body, "web", "127.0.0.1")

		client := h.NewHTTPClient()
		resp := h.DoRequest(req, client)
		defer resp.Body.Close()
		require.Equal(t, 201, resp.StatusCode)

		var cResp dtos.CreateJobDefinitionResponse
		data, _ := io.ReadAll(resp.Body)
		json.Unmarshal(data, &cResp)
		require.NotEqual(t, uuid.Nil, cResp.DefinitionID)
		t.Logf("Created definitionID=%s with specific daily estimates", cResp.DefinitionID)

		createdDef, err := h.JobDefRepo.GetByID(ctx, cResp.DefinitionID)
		require.NoError(t, err)
		require.NotNil(t, createdDef)
		require.Len(t, createdDef.DailyPayEstimates, len(customWeekdays))

		monEst := createdDef.GetDailyEstimate(time.Monday)
		require.NotNil(t, monEst)
		require.Equal(t, 70.0, monEst.BasePay)
		require.Equal(t, 65, monEst.EstimatedTimeMinutes)

		wedEst := createdDef.GetDailyEstimate(time.Wednesday)
		require.NotNil(t, wedEst)
		require.Equal(t, 75.0, wedEst.BasePay)

		tueEst := createdDef.GetDailyEstimate(time.Tuesday)
		require.Nil(t, tueEst, "Tuesday estimate should not exist for this CUSTOM definition")
	})

	t.Run("CreateDefinition_WithExpiredNoShowTime_SkipsTodaysInstance", func(t *testing.T) {
		h.T = t
		// Create a definition where the no-show time for today is in the past.
		now := time.Now().UTC()
		latestStart := now.Add(-time.Hour)               // 1 hour ago
		earliestStart := latestStart.Add(-2 * time.Hour) // 3 hours ago

		reqDTO := dtos.CreateJobDefinitionRequest{
			PropertyID:                 p.ID,
			Title:                      "ExpiredTodayDef",
			AssignedUnitsByBuilding:    []models.AssignedUnitGroup{{BuildingID: bID, UnitIDs: []uuid.UUID{}}},
			DumpsterIDs:                []uuid.UUID{dID},
			Frequency:                  models.JobFreqDaily,
			StartDate:                  now.AddDate(0, 0, -1), // Started yesterday
			EarliestStartTime:          earliestStart,
			LatestStartTime:            latestStart,
			GlobalBasePay:              utils.Ptr(50.0),
			GlobalEstimatedTimeMinutes: utils.Ptr(60),
		}
		body, _ := json.Marshal(reqDTO)
		ep := h.BaseURL + routes.JobsDefinitionCreate
		req := h.BuildAuthRequest("POST", ep, pmJWT, body, "web", "127.0.0.1")

		client := h.NewHTTPClient()
		resp := h.DoRequest(req, client)
		defer resp.Body.Close()
		require.Equal(t, 201, resp.StatusCode)

		var cResp dtos.CreateJobDefinitionResponse
		data, _ := io.ReadAll(resp.Body)
		json.Unmarshal(data, &cResp)
		require.NotEqual(t, uuid.Nil, cResp.DefinitionID)
		t.Logf("Created definitionID=%s with expired no-show time for today", cResp.DefinitionID)

		// Check the database to ensure no instance was created for today.
		todayUTC := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
		instances, err := h.JobInstRepo.ListInstancesByDateRange(ctx, nil, []models.InstanceStatusType{models.InstanceStatusOpen}, todayUTC, todayUTC)
		require.NoError(t, err)

		var foundTodaysInstance bool
		for _, inst := range instances {
			if inst.DefinitionID == cResp.DefinitionID {
				foundTodaysInstance = true
				break
			}
		}
		require.False(t, foundTodaysInstance, "Job instance for today should NOT have been created for a definition with an expired no-show time.")
	})

	t.Run("CreateDefinition_FailMismatchedDailyEstimates", func(t *testing.T) {
		h.T = t
		mismatchedDailyEstimates := []dtos.DailyPayEstimateRequest{
			{DayOfWeek: int(time.Sunday), BasePay: 60.0, EstimatedTimeMinutes: 50},
		}
		reqDTO := dtos.CreateJobDefinitionRequest{
			PropertyID:              p.ID,
			Title:                   "Fail Mismatch WDays",
			AssignedUnitsByBuilding: []models.AssignedUnitGroup{{BuildingID: bID, UnitIDs: []uuid.UUID{}}},
			DumpsterIDs:             []uuid.UUID{dID},
			Frequency:               models.JobFreqWeekdays,
			StartDate:               time.Now().AddDate(0, 0, 1),
			EarliestStartTime:       earliest,
			LatestStartTime:         latest,
			DailyPayEstimates:       mismatchedDailyEstimates,
		}
		body, _ := json.Marshal(reqDTO)
		ep := h.BaseURL + routes.JobsDefinitionCreate
		req := h.BuildAuthRequest("POST", ep, pmJWT, body, "web", "127.0.0.1")
		client := h.NewHTTPClient()
		resp := h.DoRequest(req, client)
		defer resp.Body.Close()
		require.Equal(t, 400, resp.StatusCode)

		var errResp utils.ErrorResponse
		data, _ := io.ReadAll(resp.Body)
		json.Unmarshal(data, &errResp)
		require.Equal(t, utils.ErrCodeInvalidPayload, errResp.Code)
		require.Contains(t, errResp.Message, internal_utils.ErrMismatchedPayEstimatesFrequency.Error())
		require.Regexp(t, `missing daily_pay_estimate for required day: (Monday|Tuesday|Wednesday|Thursday|Friday)`, errResp.Message)
	})

	t.Run("CreateDefinition_FailMissingPayTimeInput", func(t *testing.T) {
		h.T = t
		reqDTO := dtos.CreateJobDefinitionRequest{
			PropertyID:              p.ID,
			Title:                   "Fail Missing Input",
			AssignedUnitsByBuilding: []models.AssignedUnitGroup{{BuildingID: bID, UnitIDs: []uuid.UUID{}}},
			DumpsterIDs:             []uuid.UUID{dID},
			Frequency:               models.JobFreqDaily,
			StartDate:               time.Now().AddDate(0, 0, 1),
			EarliestStartTime:       earliest,
			LatestStartTime:         latest,
		}
		body, _ := json.Marshal(reqDTO)
		ep := h.BaseURL + routes.JobsDefinitionCreate
		req := h.BuildAuthRequest("POST", ep, pmJWT, body, "web", "127.0.0.1")
		client := h.NewHTTPClient()
		resp := h.DoRequest(req, client)
		defer resp.Body.Close()
		require.Equal(t, 400, resp.StatusCode)
		var errResp utils.ErrorResponse
		data, _ := io.ReadAll(resp.Body)
		json.Unmarshal(data, &errResp)
		require.Equal(t, utils.ErrCodeInvalidPayload, errResp.Code)
		require.Contains(t, errResp.Message, internal_utils.ErrMissingPayEstimateInput.Error())
	})

	t.Run("PauseDefinition_RemovesFuture", func(t *testing.T) {
		h.T = t
		defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "PauseTest",
			[]uuid.UUID{bID}, []uuid.UUID{dID}, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)

		for i := 0; i <= 3; i++ {
			day := time.Now().AddDate(0, 0, i)
			_ = h.CreateTestJobInstance(t, ctx, defn.ID, day, models.InstanceStatusOpen, nil)
		}

		setDTO := dtos.SetDefinitionStatusRequest{
			DefinitionID: defn.ID,
			NewStatus:    "PAUSED",
		}
		body, _ := json.Marshal(setDTO)
		ep := h.BaseURL + routes.JobsDefinitionStatus
		pmJWT2 := h.CreateWebJWT(testPM.ID, "127.0.0.2")
		req := h.BuildAuthRequest("PATCH", ep, pmJWT2, body, "web", "127.0.0.2")
		client := h.NewHTTPClient()
		resp := h.DoRequest(req, client)
		defer resp.Body.Close()
		require.Equal(t, 204, resp.StatusCode)

		startUTC := services.DateOnly(time.Now().AddDate(0, 0, 1))
		endUTC := services.DateOnly(time.Now().AddDate(0, 0, 5))
		future, err := h.JobInstRepo.ListInstancesByDateRange(
			ctx,
			nil,
			[]models.InstanceStatusType{models.InstanceStatusOpen},
			startUTC,
			endUTC,
		)
		require.NoError(t, err)
		for _, inst := range future {
			if inst.DefinitionID == defn.ID {
				t.Errorf("Future instance %s for paused definition %s should have been removed", inst.ID, defn.ID)
			}
		}
	})

	t.Run("ArchiveDefinition_RemovesFuture", func(t *testing.T) {
		h.T = t
		defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "ArchiveTest",
			[]uuid.UUID{bID}, []uuid.UUID{dID}, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)

		for i := 1; i <= 2; i++ {
			day := time.Now().AddDate(0, 0, i)
			_ = h.CreateTestJobInstance(t, ctx, defn.ID, day, models.InstanceStatusOpen, nil)
		}

		setDTO := dtos.SetDefinitionStatusRequest{
			DefinitionID: defn.ID,
			NewStatus:    "ARCHIVED",
		}
		body, _ := json.Marshal(setDTO)
		pmJWT3 := h.CreateWebJWT(testPM.ID, "127.0.0.3")
		ep := h.BaseURL + routes.JobsDefinitionStatus
		req := h.BuildAuthRequest("PATCH", ep, pmJWT3, body, "web", "127.0.0.3")
		c := h.NewHTTPClient()
		resp := h.DoRequest(req, c)
		defer resp.Body.Close()
		require.Equal(t, 204, resp.StatusCode)

		start := services.DateOnly(time.Now().AddDate(0, 0, 1))
		end := services.DateOnly(time.Now().AddDate(0, 0, 2))
		check, err := h.JobInstRepo.ListInstancesByDateRange(
			ctx,
			nil,
			[]models.InstanceStatusType{models.InstanceStatusOpen},
			start,
			end,
		)
		require.NoError(t, err)
		for _, j := range check {
			if j.DefinitionID == defn.ID {
				t.Errorf("Future instance %s for archived definition %s should have been removed", j.ID, defn.ID)
			}
		}
	})
}

/*
───────────────────────────────────────────────────────────────────
 5. Full Worker Flow: Accept -> Start -> Complete

───────────────────────────────────────────────────────────────────
*/
func TestFullWorkerFlow(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	earliest, latest := h.TestSameDayTimeWindow()

	w := h.CreateTestWorker(ctx, "workerflow")
	p := h.CreateTestProperty(ctx, "FullFlowProp", testPM.ID, 0.0, 0.0)
	bldg := h.CreateTestBuilding(ctx, p.ID, "Test Building for Full Flow")
	dumpster := h.CreateTestDumpster(ctx, p.ID, "Test Dumpster for Full Flow")

	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "FullFlowJob",
		[]uuid.UUID{bldg.ID}, []uuid.UUID{dumpster.ID}, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
	inst := h.CreateTestJobInstance(t, ctx, defn.ID, time.Now(), models.InstanceStatusOpen, nil)

	workerJWT := h.CreateMobileJWT(w.ID, "flow-device-123", "FAKE-PLAY")

	t.Run("AcceptJob", func(t *testing.T) {
		h.T = t
		acceptPayload := dtos.JobLocationActionRequest{
			InstanceID: inst.ID, Lat: 0.0, Lng: 0.0, Accuracy: 5.0, Timestamp: time.Now().UnixMilli(), IsMock: false,
		}
		body, _ := json.Marshal(acceptPayload)
		ep := h.BaseURL + routes.JobsAccept
		req := h.BuildAuthRequest("POST", ep, workerJWT, body, "android", "flow-device-123")
		c := h.NewHTTPClient()
		resp := h.DoRequest(req, c)
		defer resp.Body.Close()
		require.Equal(t, 200, resp.StatusCode)

		var ar dtos.JobInstanceActionResponse
		b, _ := io.ReadAll(resp.Body)
		json.Unmarshal(b, &ar)
		require.Equal(t, "ASSIGNED", ar.Updated.Status)
		require.NotEmpty(t, ar.Updated.Property.PropertyName)
		require.Equal(t, p.ID, ar.Updated.Property.PropertyID)
	})

	t.Run("StartJob", func(t *testing.T) {
		h.T = t
		startPayload := dtos.JobLocationActionRequest{
			InstanceID: inst.ID, Lat: 0.0, Lng: 0.0, Accuracy: 5.0, Timestamp: time.Now().UnixMilli(), IsMock: false,
		}
		body, _ := json.Marshal(startPayload)
		ep := h.BaseURL + routes.JobsStart
		req := h.BuildAuthRequest("POST", ep, workerJWT, body, "android", "flow-device-123")
		c := h.NewHTTPClient()
		resp := h.DoRequest(req, c)
		defer resp.Body.Close()
		require.Equal(t, 200, resp.StatusCode)

		var r dtos.JobInstanceActionResponse
		data, _ := io.ReadAll(resp.Body)
		json.Unmarshal(data, &r)
		require.Equal(t, "IN_PROGRESS", r.Updated.Status)
	})

	t.Run("CompleteJob", func(t *testing.T) {
		h.T = t
		var buf bytes.Buffer
		writer := multipart.NewWriter(&buf)
		writer.WriteField("instance_id", inst.ID.String())
		writer.WriteField("lat", "0.0")
		writer.WriteField("lng", "0.0")
		writer.WriteField("accuracy", "3.7")
		writer.WriteField("timestamp", fmt.Sprintf("%d", time.Now().UnixMilli()))
		writer.WriteField("is_mock", "false")
		part, err := writer.CreateFormFile("photos[]", "test.jpg")
		require.NoError(t, err)
		_, _ = part.Write([]byte("fake image bytes"))
		writer.Close()

		ep := h.BaseURL + routes.JobsComplete
		// Use the test helper's BuildAuthRequest and DoRequest pattern
		req := h.BuildAuthRequest("POST", ep, workerJWT, buf.Bytes(), "android", "flow-device-123")
		req.Header.Set("Content-Type", writer.FormDataContentType())

		c := h.NewHTTPClient()
		resp := h.DoRequest(req, c)
		defer resp.Body.Close()
		require.Equal(t, 200, resp.StatusCode)

		var r dtos.JobInstanceActionResponse
		d, _ := io.ReadAll(resp.Body)
		json.Unmarshal(d, &r)
		require.Equal(t, "COMPLETED", r.Updated.Status)
	})
}

/*
───────────────────────────────────────────────────────────────────

	5.5. Accept Job Account Status & Time Gating

───────────────────────────────────────────────────────────────────
*/
func TestAcceptJobGating(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	// --- Setup: Active Worker, Inactive Worker ---
	activeWorker := h.CreateTestWorker(ctx, "active-acceptor")
	activeWorkerJWT := h.CreateMobileJWT(activeWorker.ID, "active-dev-accept", "FAKE-PLAY")

	inactiveWorker := &models.Worker{
		ID:          uuid.New(),
		Email:       testhelpers.UniqueEmail("inactive-acceptor"),
		PhoneNumber: testhelpers.UniquePhone(),
		FirstName:   "Inactive",
		LastName:    "Worker",
		TOTPSecret:  "worker-totp-" + uuid.NewString()[:8],
	}
	require.NoError(t, h.WorkerRepo.Create(ctx, inactiveWorker))
	inactiveWorkerJWT := h.CreateMobileJWT(inactiveWorker.ID, "inactive-dev-accept", "FAKE-PLAY")

	// --- Common Setup ---
	p := h.CreateTestProperty(ctx, "AcceptGatingProp", testPM.ID, 0, 0)
	ep := h.BaseURL + routes.JobsAccept

	// --- Test Case 1: Inactive worker attempts to accept ---
	t.Run("InactiveWorker_Fails", func(t *testing.T) {
		h.T = t
		earliest, latest := h.TestSameDayTimeWindow()
		defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "AcceptGatingDef_Inactive",
			nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
		inst := h.CreateTestJobInstance(t, ctx, defn.ID, time.Now(), models.InstanceStatusOpen, nil)

		// FIX: Add timestamp to payload to pass controller validation
		acceptPayload := dtos.JobLocationActionRequest{InstanceID: inst.ID, Lat: 0.0, Lng: 0.0, Timestamp: time.Now().UnixMilli()}
		body, _ := json.Marshal(acceptPayload)

		inactiveReq := h.BuildAuthRequest("POST", ep, inactiveWorkerJWT, body, "android", "inactive-dev-accept")
		inactiveResp := h.DoRequest(inactiveReq, h.NewHTTPClient())
		defer inactiveResp.Body.Close()

		require.Equal(t, http.StatusForbidden, inactiveResp.StatusCode, "Inactive worker should be forbidden")
		var errResp utils.ErrorResponse
		data, _ := io.ReadAll(inactiveResp.Body)
		require.NoError(t, json.Unmarshal(data, &errResp), "Failed to unmarshal error response")
		require.Equal(t, internal_utils.ErrWorkerNotActive.Error(), errResp.Code, "Response should have correct error code")
	})

	// --- Test Case 2: Active worker fails to accept job past acceptance cutoff time ---
	t.Run("AcceptJobPastAcceptanceCutoff_Fails", func(t *testing.T) {
		h.T = t
		now := time.Now().UTC()
		// Set latest_start so the acceptance cutoff (latest_start - 40m) has passed.
		latestStart := now.Add(30 * time.Minute)
		earliestStart := latestStart.Add(-100 * time.Minute) // Ensure valid window to avoid DB constraint error

		defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "AcceptGatingDef_Expired",
			nil, nil, earliestStart, latestStart, models.JobStatusActive, nil, models.JobFreqDaily, nil)
		inst := h.CreateTestJobInstance(t, ctx, defn.ID, time.Now(), models.InstanceStatusOpen, nil)

		acceptPayload := dtos.JobLocationActionRequest{InstanceID: inst.ID, Lat: 0.0, Lng: 0.0, Timestamp: time.Now().UnixMilli()}
		body, _ := json.Marshal(acceptPayload)

		activeReq := h.BuildAuthRequest("POST", ep, activeWorkerJWT, body, "android", "active-dev-accept")
		activeResp := h.DoRequest(activeReq, h.NewHTTPClient())
		defer activeResp.Body.Close()

		require.Equal(t, http.StatusBadRequest, activeResp.StatusCode, "Accepting a job past acceptance cutoff should be a bad request")
		var errResp utils.ErrorResponse
		data, _ := io.ReadAll(activeResp.Body)
		require.NoError(t, json.Unmarshal(data, &errResp), "Failed to unmarshal error response")
		require.Equal(t, internal_utils.ErrNotWithinTimeWindow.Error(), errResp.Code, "Response should have correct time window error code")
	})

	// --- Test Case 3: Active worker accepts successfully ---
	t.Run("ActiveWorker_Succeeds", func(t *testing.T) {
		h.T = t
		earliest, latest := h.TestSameDayTimeWindow()
		defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "AcceptGatingDef_Active",
			nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
		inst := h.CreateTestJobInstance(t, ctx, defn.ID, time.Now(), models.InstanceStatusOpen, nil)

		// FIX: Add timestamp to payload to pass controller validation
		acceptPayload := dtos.JobLocationActionRequest{InstanceID: inst.ID, Lat: 0.0, Lng: 0.0, Timestamp: time.Now().UnixMilli()}
		body, _ := json.Marshal(acceptPayload)

		activeReq := h.BuildAuthRequest("POST", ep, activeWorkerJWT, body, "android", "active-dev-accept")
		activeResp := h.DoRequest(activeReq, h.NewHTTPClient())
		defer activeResp.Body.Close()
		require.Equal(t, http.StatusOK, activeResp.StatusCode, "Active worker should be able to accept the job")
	})
}

/*
───────────────────────────────────────────────────────────────────
 6. Tiered Unaccept Penalties (replaces old penalty test)

───────────────────────────────────────────────────────────────────
*/
func TestTieredUnacceptPenalties(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	runUnacceptTest := func(
		t *testing.T,
		testName string,
		earliestStartTime, latestStartTime time.Time,
		expectedPenalty int,
		shouldBeExcluded bool,
	) {
		h.T = t
		if earliestStartTime.Day() != latestStartTime.Day() {
			t.Skipf("Skipping sub-test '%s' because calculated job window crosses a day boundary (test run near midnight)", testName)
			return
		}

		worker := h.CreateTestWorker(ctx, "penalty-worker-"+testName, 100)
		workerJWT := h.CreateMobileJWT(worker.ID, "penalty-dev-"+testName, "FAKE-PLAY")
		initialScore := worker.ReliabilityScore

		p := h.CreateTestProperty(ctx, "PenaltyProp-"+testName, testPM.ID, 0, 0)
		defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "PenaltyDef-"+testName,
			nil, nil, earliestStartTime, latestStartTime, models.JobStatusActive, nil, models.JobFreqDaily, nil)

		inst := h.CreateTestJobInstance(t, ctx, defn.ID, earliestStartTime, models.InstanceStatusOpen, nil)

		// Check if the job is expired before attempting to accept.
		noShowCutoffTime := latestStartTime.Add(-constants.NoShowCutoffBeforeLatestStart)
		acceptanceCutoffTime := noShowCutoffTime.Add(-constants.AcceptanceCutoffBeforeNoShow)
		if time.Now().UTC().After(acceptanceCutoffTime) {
			t.Skipf("Skipping penalty test '%s' because its acceptance cutoff time has already passed", testName)
			return
		}

		acceptPayload := dtos.JobLocationActionRequest{
			InstanceID: inst.ID, Lat: 0.0, Lng: 0.0, Accuracy: 5.0, Timestamp: time.Now().UnixMilli(), IsMock: false,
		}
		acceptBody, _ := json.Marshal(acceptPayload)
		acceptReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsAccept, workerJWT, acceptBody, "android", "penalty-dev-"+testName)
		acceptResp := h.DoRequest(acceptReq, h.NewHTTPClient())
		defer acceptResp.Body.Close()
		require.Equal(t, 200, acceptResp.StatusCode, "%s: Accept should succeed", testName)

		unacceptPayload := dtos.JobInstanceActionRequest{InstanceID: inst.ID}
		unacceptBody, _ := json.Marshal(unacceptPayload)
		unacceptReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsUnaccept, workerJWT, unacceptBody, "android", "penalty-dev-"+testName)
		unacceptResp := h.DoRequest(unacceptReq, h.NewHTTPClient())
		defer unacceptResp.Body.Close()
		require.Equal(t, 200, unacceptResp.StatusCode, "%s: Unaccept should succeed", testName)

		updatedWorker, err := h.WorkerRepo.GetByID(ctx, worker.ID)
		require.NoError(t, err)
		require.Equal(t, initialScore+expectedPenalty, updatedWorker.ReliabilityScore,
			"%s: Score should be %d, but was %d", testName, initialScore+expectedPenalty, updatedWorker.ReliabilityScore)
		t.Logf("%s: Worker score updated correctly from %d to %d (penalty: %d)", testName, initialScore, updatedWorker.ReliabilityScore, expectedPenalty)

		updatedInst, err := h.JobInstRepo.GetByID(ctx, inst.ID)
		require.NoError(t, err)

		// NOTE: The logic for Unaccept resulting in a CANCELED job is currently unreachable
		// via the API, as the acceptance window closes before the cancellation window begins.
		// Therefore, we always expect the job to revert to OPEN.
		require.Equal(t, models.InstanceStatusOpen, updatedInst.Status, "%s: Instance should be OPEN again", testName)

		if shouldBeExcluded {
			require.Contains(t, updatedInst.ExcludedWorkerIDs, worker.ID, "%s: Worker should be in exclusion list", testName)
			t.Logf("%s: Worker correctly added to exclusion list.", testName)
		} else {
			require.NotContains(t, updatedInst.ExcludedWorkerIDs, worker.ID, "%s: Worker should NOT be in exclusion list", testName)
			t.Logf("%s: Worker correctly NOT added to exclusion list.", testName)
		}
	}

	now := time.Now().UTC().Truncate(time.Minute)
	const jobWindowDuration = 2 * time.Hour

	t.Run("NoPenalty_AmpleNotice", func(t *testing.T) {
		eStart := now.Add(48 * time.Hour)
		lStart := eStart.Add(jobWindowDuration)
		runUnacceptTest(t, "NoPenalty", eStart, lStart, 0, false)
	})

	t.Run("Penalty24h_Minus1", func(t *testing.T) {
		eStart := now.Add(10 * time.Hour)
		lStart := eStart.Add(jobWindowDuration)
		runUnacceptTest(t, "Penalty24h", eStart, lStart, constants.WorkerPenalty24h, false)
	})

	t.Run("PenaltyExclusion_Minus2", func(t *testing.T) {
		lStart := now.Add(7 * time.Hour)
		eStart := lStart.Add(-jobWindowDuration)
		runUnacceptTest(t, "PenaltyExclusion", eStart, lStart, constants.WorkerPenaltyExclusionWindow, true)
	})

	t.Run("PenaltyEarly_Minus3", func(t *testing.T) {
		lStart := now.Add(5 * time.Hour)
		eStart := lStart.Add(-jobWindowDuration)
		runUnacceptTest(t, "PenaltyEarly", eStart, lStart, constants.WorkerPenaltyEarly, true)
	})

	t.Run("PenaltyMid_Minus6", func(t *testing.T) {
		lStart := now.Add(2*time.Hour + 30*time.Minute)
		eStart := lStart.Add(-jobWindowDuration)
		runUnacceptTest(t, "PenaltyMid", eStart, lStart, constants.WorkerPenaltyMid, true)
	})

	t.Run("PenaltyLate_Minus10", func(t *testing.T) {
		lStart := now.Add(90 * time.Minute)
		eStart := lStart.Add(-jobWindowDuration)
		runUnacceptTest(t, "PenaltyLate", eStart, lStart, constants.WorkerPenaltyLate, true)
	})
}

/*
───────────────────────────────────────────────────────────────────
 7. Concurrency Start

───────────────────────────────────────────────────────────────────
*/
func TestConcurrencyStart(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	earliest, latest := h.TestSameDayTimeWindow()

	p := h.CreateTestProperty(ctx, "ConcStartProp", testPM.ID, 0.0, 0.0)
	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "ConcurrencyStartTest",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
	inst := h.CreateTestJobInstance(t, ctx, defn.ID, time.Now(), models.InstanceStatusOpen, nil)
	w := h.CreateTestWorker(ctx, "startConc")
	jwtW := h.CreateMobileJWT(w.ID, "startC-dev", "FAKE-PLAY")

	acceptLoc := dtos.JobLocationActionRequest{
		InstanceID: inst.ID, Lat: 0.0, Lng: 0.0, Accuracy: 5.0, Timestamp: time.Now().UnixMilli(), IsMock: false,
	}
	acceptBody, _ := json.Marshal(acceptLoc)
	acceptReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsAccept, jwtW, acceptBody, "android", "startC-dev")
	acceptResp := h.DoRequest(acceptReq, h.NewHTTPClient())
	defer acceptResp.Body.Close()
	require.Equal(t, 200, acceptResp.StatusCode, "Accept should succeed")

	doStart := func() int {
		locReq := dtos.JobLocationActionRequest{
			InstanceID: inst.ID, Lat: 0.0, Lng: 0.0, Accuracy: 5.0, Timestamp: time.Now().UnixMilli(), IsMock: false,
		}
		b, _ := json.Marshal(locReq)
		req := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsStart, jwtW, b, "android", "startC-dev")
		c := h.NewHTTPClient()
		resp := h.DoRequest(req, c)
		defer resp.Body.Close()
		return resp.StatusCode
	}

	var codes [2]int
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		codes[0] = doStart()
	}()
	go func() {
		defer wg.Done()
		codes[1] = doStart()
	}()
	wg.Wait()

	successCount := 0
	failCount := 0
	for _, c := range codes {
		if c == 200 {
			successCount++
		} else if c == 409 || c == 400 {
			failCount++
		} else {
			t.Errorf("Unexpected status code: %d", c)
		}
	}
	require.Equal(t, 1, successCount, "Expect exactly 1 successful start")
	require.Equal(t, 1, failCount, "Expect exactly 1 failure (409 or 400) for second call")
}

/*
───────────────────────────────────────────────────────────────────
 8. Concurrency Complete

───────────────────────────────────────────────────────────────────
*/
func TestConcurrencyComplete(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	earliest, latest := h.TestSameDayTimeWindow()

	p := h.CreateTestProperty(ctx, "ConcCompProp", testPM.ID, 0.0, 0.0)
	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "ConcurrencyCompleteTest",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
	inst := h.CreateTestJobInstance(t, ctx, defn.ID, time.Now(), models.InstanceStatusOpen, nil)
	w := h.CreateTestWorker(ctx, "completeConc")
	wJWT := h.CreateMobileJWT(w.ID, "completeConc-dev", "FAKE-PLAY")

	aLoc := dtos.JobLocationActionRequest{
		InstanceID: inst.ID, Lat: 0.0, Lng: 0.0, Accuracy: 5.0, Timestamp: time.Now().UnixMilli(), IsMock: false,
	}
	aBody, _ := json.Marshal(aLoc)
	aReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsAccept, wJWT, aBody, "android", "completeConc-dev")
	aResp := h.DoRequest(aReq, h.NewHTTPClient())
	defer aResp.Body.Close()
	require.Equal(t, 200, aResp.StatusCode)

	sLoc := dtos.JobLocationActionRequest{
		InstanceID: inst.ID, Lat: 0.0, Lng: 0.0, Accuracy: 5.0, Timestamp: time.Now().UnixMilli(), IsMock: false,
	}
	sBody, _ := json.Marshal(sLoc)
	sReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsStart, wJWT, sBody, "android", "completeConc-dev")
	sResp := h.DoRequest(sReq, h.NewHTTPClient())
	defer sResp.Body.Close()
	require.Equal(t, 200, sResp.StatusCode)

	doComplete := func() int {
		var buf bytes.Buffer
		writer := multipart.NewWriter(&buf)
		writer.WriteField("instance_id", inst.ID.String())
		writer.WriteField("lat", "0.0")
		writer.WriteField("lng", "0.0")
		writer.WriteField("accuracy", "2.5")
		writer.WriteField("timestamp", fmt.Sprintf("%d", time.Now().UnixMilli()))
		writer.WriteField("is_mock", "false")
		part, _ := writer.CreateFormFile("photos[]", "c.jpg")
		part.Write([]byte("dummy"))
		writer.Close()

		req := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsComplete, wJWT, buf.Bytes(), "android", "completeConc-dev")
		req.Header.Set("Content-Type", writer.FormDataContentType())

		c := h.NewHTTPClient()
		resp := h.DoRequest(req, c)
		defer resp.Body.Close()
		return resp.StatusCode
	}

	var results [2]int
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		results[0] = doComplete()
	}()
	go func() {
		defer wg.Done()
		results[1] = doComplete()
	}()
	wg.Wait()

	success := 0
	conflict := 0
	for _, r := range results {
		if r == 200 {
			success++
		} else if r == 409 || r == 400 {
			conflict++
		}
	}
	require.Equal(t, 1, success, "One call should succeed")
	require.Equal(t, 1, conflict, "Second call => concurrency conflict or wrong status")
}

/*
───────────────────────────────────────────────────────────────────
 9. Exclusion

───────────────────────────────────────────────────────────────────
*/
func TestExcludedWorkerCannotAccept(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	earliest, latest := h.TestSameDayTimeWindow()

	p := h.CreateTestProperty(ctx, "ExclProp", testPM.ID, 0.0, 0.0)
	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "ExclusionTest",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
	inst := h.CreateTestJobInstance(t, ctx, defn.ID, time.Now(), models.InstanceStatusOpen, nil)

	exW := h.CreateTestWorker(ctx, "excl1")
	require.NoError(t, h.JobInstRepo.AddExcludedWorker(ctx, inst.ID, exW.ID))

	okW := h.CreateTestWorker(ctx, "excl2")

	exJWT := h.CreateMobileJWT(exW.ID, "excluded-dev-1", "FAKE-PLAY")
	locReq := dtos.JobLocationActionRequest{
		InstanceID: inst.ID, Lat: 0.0, Lng: 0.0, Accuracy: 5.0, Timestamp: time.Now().UnixMilli(), IsMock: false,
	}
	body, _ := json.Marshal(locReq)
	ep := h.BaseURL + routes.JobsAccept
	req := h.BuildAuthRequest("POST", ep, exJWT, body, "android", "excluded-dev-1")
	resp := h.DoRequest(req, h.NewHTTPClient())
	defer resp.Body.Close()
	require.Equal(t, 400, resp.StatusCode, "excluded => got=%d", resp.StatusCode)

	okJWT := h.CreateMobileJWT(okW.ID, "excl-ok-dev-2", "FAKE-PLAY")
	req2 := h.BuildAuthRequest("POST", ep, okJWT, body, "android", "excl-ok-dev-2")
	resp2 := h.DoRequest(req2, h.NewHTTPClient())
	defer resp2.Body.Close()
	require.Equal(t, 200, resp2.StatusCode)
}

/*
───────────────────────────────────────────────────────────────────
 10. TestListOpenJobsLargePaging

───────────────────────────────────────────────────────────────────
*/
func TestListOpenJobsLargePaging_SameDay(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	earliest, latest := h.TestSameDayTimeWindow()

	_, err := h.DB.Exec(ctx, `TRUNCATE TABLE job_instances, job_definitions CASCADE`)
	require.NoError(t, err, "failed to truncate job_instances & job_definitions")

	prop := h.CreateTestProperty(ctx, "LargePagingProp_SameDay", testPM.ID, 35.0, -84.0)
	sharedBuilding := h.CreateTestBuilding(ctx, prop.ID, "SharedLargePagingBldg")
	sharedDumpster := h.CreateTestDumpster(ctx, prop.ID, "SharedLargePagingDump")

	for i := range 25 {
		def := h.CreateTestJobDefinition(t, ctx, testPM.ID, prop.ID, fmt.Sprintf("SameDayJob %d", i),
			[]uuid.UUID{sharedBuilding.ID}, []uuid.UUID{sharedDumpster.ID}, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
		_ = h.CreateTestJobInstance(t, ctx, def.ID, time.Now().UTC(), models.InstanceStatusOpen, nil)
	}

	w := h.CreateTestWorker(ctx, "same-day-paging")
	wJWT := h.CreateMobileJWT(w.ID, "same-day-dev", "FAKE-PLAY")

	doList := func(page, size int) (dtos.ListJobsResponse, int, error) {
		listURL := fmt.Sprintf(
			"%s/api/v1/jobs/open?lat=35.0&lng=-84.0&page=%d&size=%d",
			h.BaseURL, page, size,
		)
		req := h.BuildAuthRequest(http.MethodGet, listURL, wJWT, nil, "android", "same-day-dev")
		client := h.NewHTTPClient()
		resp, err := client.Do(req)
		if err != nil {
			return dtos.ListJobsResponse{}, 0, err
		}
		defer resp.Body.Close()

		status := resp.StatusCode
		raw, readErr := io.ReadAll(resp.Body)
		if readErr != nil {
			return dtos.ListJobsResponse{}, status, readErr
		}
		if status != http.StatusOK {
			return dtos.ListJobsResponse{}, status, fmt.Errorf("non-200: %s", string(raw))
		}
		var out dtos.ListJobsResponse
		if jerr := json.Unmarshal(raw, &out); jerr != nil {
			return dtos.ListJobsResponse{}, status, jerr
		}
		return out, status, nil
	}

	t.Run("pagesOf10", func(t *testing.T) {
		h.T = t
		r1, code1, err1 := doList(1, 10)
		require.NoError(t, err1)
		require.Equal(t, 200, code1)
		require.Equal(t, 25, r1.Total)
		require.Len(t, r1.Results, 10)
		if len(r1.Results) > 0 {
			require.NotEmpty(t, r1.Results[0].Property.PropertyName)
		}

		r2, code2, err2 := doList(2, 10)
		require.NoError(t, err2)
		require.Equal(t, 200, code2)
		require.Equal(t, 25, r2.Total)
		require.Len(t, r2.Results, 10)

		r3, code3, err3 := doList(3, 10)
		require.NoError(t, err3)
		require.Equal(t, 200, code3)
		require.Equal(t, 25, r3.Total)
		require.Len(t, r3.Results, 5)

		r4, code4, err4 := doList(4, 10)
		require.NoError(t, err4)
		require.Equal(t, 200, code4)
		require.Equal(t, 25, r4.Total)
		require.Len(t, r4.Results, 0)
	})

	t.Run("pageSize1", func(t *testing.T) {
		h.T = t
		r1, code1, err1 := doList(1, 1)
		require.NoError(t, err1)
		require.Equal(t, 200, code1)
		require.Equal(t, 25, r1.Total)
		require.Len(t, r1.Results, 1)

		r25, code25, err25 := doList(25, 1)
		require.NoError(t, err25)
		require.Equal(t, 200, code25)
		require.Equal(t, 25, r25.Total)
		require.Len(t, r25.Results, 1)

		r26, code26, err26 := doList(26, 1)
		require.NoError(t, err26)
		require.Equal(t, 200, code26)
		require.Equal(t, 25, r26.Total)
		require.Len(t, r26.Results, 0)
	})

	t.Run("pageSizeBig", func(t *testing.T) {
		h.T = t
		rLarge, codeLarge, errLarge := doList(1, 200)
		require.NoError(t, errLarge)
		require.Equal(t, 200, codeLarge)
		require.Equal(t, 25, rLarge.Total)
		require.Len(t, rLarge.Results, 25)
	})
}

func TestCancelInProgress_RevertsToOpen_WithPenalty(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	// FIX: Use a time window that is currently active so the job can be started.
	earliest, latest := h.TestSameDayTimeWindow()
	initialScore := 100

	w := h.CreateTestWorker(ctx, "cancel-reopen", initialScore)
	workerJWT := h.CreateMobileJWT(w.ID, "cancelReopenDevice", "FAKE-PLAY")
	p := h.CreateTestProperty(ctx, "CancelReopenProp", testPM.ID, 0, 0)
	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "CancelReopenJob",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
	// Use today's date for the instance
	inst := h.CreateTestJobInstance(t, ctx, defn.ID, time.Now().UTC(), models.InstanceStatusOpen, nil)

	// 1. Accept and Start
	acceptPayload := dtos.JobLocationActionRequest{InstanceID: inst.ID, Lat: 0, Lng: 0, Accuracy: 5, Timestamp: time.Now().UnixMilli()}
	acceptBody, _ := json.Marshal(acceptPayload)
	acceptReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsAccept, workerJWT, acceptBody, "android", "cancelReopenDevice")
	acceptResp := h.DoRequest(acceptReq, h.NewHTTPClient())
	require.Equal(t, http.StatusOK, acceptResp.StatusCode, "Accept should succeed for job within a valid window")
	acceptResp.Body.Close()

	startPayload := dtos.JobLocationActionRequest{InstanceID: inst.ID, Lat: 0, Lng: 0, Accuracy: 5, Timestamp: time.Now().UnixMilli()}
	startBody, _ := json.Marshal(startPayload)
	startReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsStart, workerJWT, startBody, "android", "cancelReopenDevice")
	startResp := h.DoRequest(startReq, h.NewHTTPClient())
	require.Equal(t, http.StatusOK, startResp.StatusCode, "Start should succeed for job within a valid window")
	startResp.Body.Close()

	// 2. Cancel the job (this happens well before any cutoffs)
	cancelPayload := dtos.JobInstanceActionRequest{InstanceID: inst.ID}
	cancelBody, _ := json.Marshal(cancelPayload)
	cancelReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsCancel, workerJWT, cancelBody, "android", "cancelReopenDevice")
	cancelResp := h.DoRequest(cancelReq, h.NewHTTPClient())
	defer cancelResp.Body.Close()
	require.Equal(t, http.StatusOK, cancelResp.StatusCode)

	// 3. Assertions
	var out dtos.JobInstanceActionResponse
	cData, _ := io.ReadAll(cancelResp.Body)
	require.NoError(t, json.Unmarshal(cData, &out))

	// Because it was canceled with ample notice (> 7 hours before no-show), it reverts to OPEN
	require.Equal(t, string(models.InstanceStatusOpen), out.Updated.Status, "Job should revert to OPEN when canceled early")
	require.Nil(t, out.Updated.CheckInAt, "CheckInAt should be cleared")

	// Verify penalty and exclusion. For a same-day cancellation, there should be a penalty and exclusion.
	updatedWorker, err := h.WorkerRepo.GetByID(ctx, w.ID)
	require.NoError(t, err)

	// Determine expected penalty based on the time window
	noShowTime := latest.Add(-constants.NoShowCutoffBeforeLatestStart)
	expectedPenalty, shouldBeExcluded := services.CalculatePenaltyForUnassign(time.Now().UTC(), earliest, noShowTime)

	require.Equal(t, initialScore+expectedPenalty, updatedWorker.ReliabilityScore, "Worker should receive the correct penalty")

	updatedInst, err := h.JobInstRepo.GetByID(ctx, inst.ID)
	require.NoError(t, err)

	if shouldBeExcluded {
		require.Contains(t, updatedInst.ExcludedWorkerIDs, w.ID, "Worker should be excluded for this cancellation")
	} else {
		require.NotContains(t, updatedInst.ExcludedWorkerIDs, w.ID, "Worker should not be excluded for this cancellation")
	}
}

func TestCancelInProgress_BecomesCanceled_AfterCutoff(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	initialScore := 100

	// FIX: Create a job where the time window has already passed its no-show cutoff.
	// This isolates the test to the logic within the CancelJobInstance service method
	// for jobs that are canceled late.
	now := time.Now().UTC()
	// Set latest start time to 10 minutes in the past.
	latest := now.Add(-10 * time.Minute)
	// Set earliest to 100 mins before that, matching the original duration.
	earliest := latest.Add(-100 * time.Minute)

	w := h.CreateTestWorker(ctx, "cancel-late", initialScore)
	workerJWT := h.CreateMobileJWT(w.ID, "cancelLateDevice", "FAKE-PLAY")
	p := h.CreateTestProperty(ctx, "CancelLateProp", testPM.ID, 0, 0)
	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "CancelLateJob",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
	inst := h.CreateTestJobInstance(t, ctx, defn.ID, now.AddDate(0, 0, -1), models.InstanceStatusOpen, nil)

	// FIX: Manually set the job to IN_PROGRESS in the database to bypass the now-invalid
	// time window checks in the Accept and Start handlers. This ensures we are testing
	// the desired state for the Cancel handler.
	updateQuery := `
        UPDATE job_instances
        SET status = $1, assigned_worker_id = $2, check_in_at = $3, row_version = row_version + 1
        WHERE id = $4`
	// Set check_in_at to a realistic time before the no-show cutoff would have passed.
	checkinTime := now.Add(-45 * time.Minute)
	_, err := h.DB.Exec(ctx, updateQuery, models.InstanceStatusInProgress, w.ID, checkinTime, inst.ID)
	require.NoError(t, err, "Failed to manually set instance to IN_PROGRESS")

	// 2. The no-show cutoff is now guaranteed to be in the past.
	//    no-show cutoff = latest_start_time - 20m = (now - 10m) - 20m = now - 30m.

	// 3. Cancel the job. This request should now succeed with a 200.
	cancelPayload := dtos.JobInstanceActionRequest{InstanceID: inst.ID}
	cancelBody, _ := json.Marshal(cancelPayload)
	cancelReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsCancel, workerJWT, cancelBody, "android", "cancelLateDevice")
	cancelResp := h.DoRequest(cancelReq, h.NewHTTPClient())
	defer cancelResp.Body.Close()
	// The original failure was here. With the state correctly set, it should now pass.
	require.Equal(t, http.StatusOK, cancelResp.StatusCode)

	// 4. Assertions
	var out dtos.JobInstanceActionResponse
	cData, _ := io.ReadAll(cancelResp.Body)
	require.NoError(t, json.Unmarshal(cData, &out))

	// Because it was canceled after the no-show cutoff, it is fully CANCELED.
	require.Equal(t, string(models.InstanceStatusCanceled), out.Updated.Status, "Job should be CANCELED when worker cancels after no-show time")

	// Verify the severe no-show penalty and exclusion.
	updatedWorker, err := h.WorkerRepo.GetByID(ctx, w.ID)
	require.NoError(t, err)
	require.Equal(t, initialScore+constants.WorkerPenaltyNoShow, updatedWorker.ReliabilityScore, "Worker should receive the full no-show penalty")

	updatedInst, err := h.JobInstRepo.GetByID(ctx, inst.ID)
	require.NoError(t, err)
	require.Contains(t, updatedInst.ExcludedWorkerIDs, w.ID, "Worker should be excluded for a late cancellation")
}

/*
───────────────────────────────────────────────────────────────────
 12. CancelJob Negative: Wrong Status or Not Assigned

───────────────────────────────────────────────────────────────────
*/
func TestCancelJob_NegativeCases(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	earliest, latest := h.TestSameDayTimeWindow()

	w := h.CreateTestWorker(ctx, "cancel-neg")
	workerJWT := h.CreateMobileJWT(w.ID, "cancelNegDevice", "FAKE-PLAY")

	pA := h.CreateTestProperty(ctx, "CancelNegPropA", testPM.ID, 0, 0)
	defA := h.CreateTestJobDefinition(t, ctx, testPM.ID, pA.ID, "CancelNegTestA",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
	instWrong := h.CreateTestJobInstance(t, ctx, defA.ID, time.Now().UTC(), models.InstanceStatusAssigned, &w.ID)

	pB := h.CreateTestProperty(ctx, "CancelNegPropB", testPM.ID, 0, 0)
	defB := h.CreateTestJobDefinition(t, ctx, testPM.ID, pB.ID, "CancelNegTestB",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
	otherWorker := h.CreateTestWorker(ctx, "otherCancel")
	instNotAssigned := h.CreateTestJobInstance(t, ctx, defB.ID, time.Now().UTC(), models.InstanceStatusInProgress, &otherWorker.ID)

	body1, _ := json.Marshal(dtos.JobInstanceActionRequest{InstanceID: instWrong.ID})
	req1 := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsCancel, workerJWT, body1, "android", "cancelNegDevice")
	resp1 := h.DoRequest(req1, h.NewHTTPClient())
	defer resp1.Body.Close()
	require.Equal(t, 400, resp1.StatusCode, "Cancel on job in ASSIGNED => 400")

	body2, _ := json.Marshal(dtos.JobInstanceActionRequest{InstanceID: instNotAssigned.ID})
	req2 := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsCancel, workerJWT, body2, "android", "cancelNegDevice")
	resp2 := h.DoRequest(req2, h.NewHTTPClient())
	defer resp2.Body.Close()
	require.Equal(t, 400, resp2.StatusCode, "Cancel on job assigned to different worker => 400")
}

/*
───────────────────────────────────────────────────────────────────
 13. Additional time-window checks => Start job

───────────────────────────────────────────────────────────────────
*/
func TestStartJobTimeGuards(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	w := h.CreateTestWorker(ctx, "time-guard")
	workerJWT := h.CreateMobileJWT(w.ID, "timeguard-dev", "FAKE-PLAY")
	p := h.CreateTestProperty(ctx, "TimeGuardProp", testPM.ID, 0, 0)

	// --- Test Case 1: Start too early ---
	now := time.Now().UTC()
	defEarliestFuture := now.Add(30 * time.Minute)
	defLatestFuture := defEarliestFuture.Add(2 * time.Hour)
	if defLatestFuture.Day() != defEarliestFuture.Day() {
		// The window crossed midnight. To make the test robust, push the entire window
		// to a safe time on the next calendar day.
		// The date of `defLatestFuture` is guaranteed to be on the next day in this scenario.
		tomorrowDateOnly := time.Date(defLatestFuture.Year(), defLatestFuture.Month(), defLatestFuture.Day(), 0, 0, 0, 0, time.UTC)
		defEarliestFuture = tomorrowDateOnly.Add(10 * time.Hour)
		defLatestFuture = tomorrowDateOnly.Add(12 * time.Hour)
	}

	defIDFuture := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "TimeGuardFutureDef",
		nil, nil, defEarliestFuture, defLatestFuture, models.JobStatusActive, nil, models.JobFreqDaily, nil).ID

	instFutureServiceDate := time.Date(defEarliestFuture.Year(), defEarliestFuture.Month(), defEarliestFuture.Day(), 0, 0, 0, 0, time.UTC)
	instFuture := h.CreateTestJobInstance(t, ctx, defIDFuture, instFutureServiceDate, models.InstanceStatusOpen, nil)

	locA := dtos.JobLocationActionRequest{
		InstanceID: instFuture.ID, Lat: 0.0, Lng: 0.0, Accuracy: 5.0, Timestamp: time.Now().UnixMilli(), IsMock: false,
	}
	bodyAccA, _ := json.Marshal(locA)
	accReqA := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsAccept, workerJWT, bodyAccA, "android", "timeguard-dev")
	accRespA := h.DoRequest(accReqA, h.NewHTTPClient())
	defer accRespA.Body.Close()
	require.Equal(t, 200, accRespA.StatusCode, "Accept job should succeed. Def Earliest: %v, Now: %v", defEarliestFuture, now)

	startReqA := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsStart, workerJWT, bodyAccA, "android", "timeguard-dev")
	startRespA := h.DoRequest(startReqA, h.NewHTTPClient())
	defer startRespA.Body.Close()

	require.Equal(t, 400, startRespA.StatusCode, "Starting before definition's earliest time (defEarliest: %v, now: %v) => 400", defEarliestFuture, time.Now().UTC())
	rawErrA, _ := io.ReadAll(startRespA.Body)
	t.Logf("Start job too early => status=%d, body=%s. Def Earliest: %v, Def Latest: %v, Instance Service Date: %v",
		startRespA.StatusCode, string(rawErrA), defEarliestFuture.Format(time.RFC3339), defLatestFuture.Format(time.RFC3339), instFutureServiceDate.Format("2006-01-02"))
	var errRespA utils.ErrorResponse
	require.NoError(t, json.Unmarshal(rawErrA, &errRespA))
	require.Equal(t, internal_utils.ErrNotWithinTimeWindow.Error(), errRespA.Code)

	// --- Test Case 2: Start within window (should succeed) ---
	nowForTestCase2 := time.Now().UTC()
	earliestForPast, latestForPast := h.TestSameDayTimeWindow()

	defIDPast := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "TimeGuardPastDef",
		nil, nil, earliestForPast, latestForPast, models.JobStatusActive, nil, models.JobFreqDaily, nil).ID
	instPastServiceDate := time.Date(nowForTestCase2.Year(), nowForTestCase2.Month(), nowForTestCase2.Day(), 0, 0, 0, 0, time.UTC)
	instPast := h.CreateTestJobInstance(t, ctx, defIDPast, instPastServiceDate, models.InstanceStatusOpen, nil)

	locB := dtos.JobLocationActionRequest{
		InstanceID: instPast.ID, Lat: 0.0, Lng: 0.0, Accuracy: 2.0, Timestamp: time.Now().UnixMilli(), IsMock: false,
	}
	bodyAccB, _ := json.Marshal(locB)
	accReqB := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsAccept, workerJWT, bodyAccB, "android", "timeguard-dev")
	accRespB := h.DoRequest(accReqB, h.NewHTTPClient())
	defer accRespB.Body.Close()
	require.Equal(t, 200, accRespB.StatusCode, "Accept job must succeed for current-window job")

	startReqB := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsStart, workerJWT, bodyAccB, "android", "timeguard-dev")
	startRespB := h.DoRequest(startReqB, h.NewHTTPClient())
	defer startRespB.Body.Close()
	require.Equal(t, 200, startRespB.StatusCode, "Starting within time window (earliest %v, latest %v, now %v) => 200 OK", earliestForPast.Format(time.RFC3339), latestForPast.Format(time.RFC3339), time.Now().UTC().Format(time.RFC3339))
	rawRespB, _ := io.ReadAll(startRespB.Body)
	t.Logf("Start job within earliest-latest => status=%d, resp=%s. Def Earliest: %v, Def Latest: %v, Instance Service Date: %v",
		startRespB.StatusCode, string(rawRespB), earliestForPast.Format(time.RFC3339), latestForPast.Format(time.RFC3339), instPastServiceDate.Format("2006-01-02"))
	var actionResp dtos.JobInstanceActionResponse
	err := json.Unmarshal(rawRespB, &actionResp)
	require.NoError(t, err, "Failed to unmarshal response body: %s", string(rawRespB))
	require.Equal(t, "IN_PROGRESS", actionResp.Updated.Status)
}

/*
───────────────────────────────────────────────────────────────────
 14. Job Estimated Time EMA Flow

───────────────────────────────────────────────────────────────────
*/
func TestJobEstimatedTimeEmaFlow(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	earliest, latest := h.TestSameDayTimeWindow()

	w := h.CreateTestWorker(ctx, "ema-test")
	workerJWT := h.CreateMobileJWT(w.ID, "ema-test-device", "FAKE-PLAY")
	p := h.CreateTestProperty(ctx, "EmaProperty", testPM.ID, 0, 0)
	bID := h.CreateTestBuilding(ctx, p.ID, "Test Building for EMA Flow").ID
	dID := h.CreateTestDumpster(ctx, p.ID, "Test Dumpster for EMA Flow").ID

	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "EmaTestDef",
		[]uuid.UUID{bID}, []uuid.UUID{dID}, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)

	initialServiceDate := time.Now().UTC().Truncate(24 * time.Hour)
	weekdayForTest := initialServiceDate.Weekday()

	completeJobCycleAndGetNewEstimate := func(currentServiceDate time.Time, actualMinsSimulated int) int {
		inst := h.CreateTestJobInstance(t, ctx, defn.ID, currentServiceDate, models.InstanceStatusOpen, nil)

		checkinTime := time.Now().UTC().Add(-time.Duration(actualMinsSimulated) * time.Minute)
		updateQuery := `
            UPDATE job_instances
            SET status = $1, assigned_worker_id = $2, check_in_at = $3, row_version = row_version + 1
            WHERE id = $4`
		_, dbErr := h.DB.Exec(ctx, updateQuery, models.InstanceStatusInProgress, w.ID, checkinTime, inst.ID)
		require.NoError(t, dbErr, "Failed to manually set instance to IN_PROGRESS with check_in_at for instance %s", inst.ID)

		var buf bytes.Buffer
		writer := multipart.NewWriter(&buf)
		writer.WriteField("instance_id", inst.ID.String())
		writer.WriteField("lat", "0.0")
		writer.WriteField("lng", "0.0")
		writer.WriteField("accuracy", "5.0")
		writer.WriteField("timestamp", fmt.Sprintf("%d", time.Now().UnixMilli()))
		writer.WriteField("is_mock", "false")
		part, _ := writer.CreateFormFile("photos[]", "ema.jpg")
		_, _ = part.Write([]byte("fake photo data"))
		writer.Close()

		compReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsComplete, workerJWT, buf.Bytes(), "android", "ema-test-device")
		compReq.Header.Set("Content-Type", writer.FormDataContentType())

		respComp := h.DoRequest(compReq, h.NewHTTPClient())
		defer respComp.Body.Close()

		if respComp.StatusCode != 200 {
			bodyBytes, _ := io.ReadAll(respComp.Body)
			t.Logf("CompleteJob failed unexpectedly. Status: %d, Body: %s. Instance ServiceDate: %v",
				respComp.StatusCode, string(bodyBytes), currentServiceDate)
		}
		require.Equal(t, 200, respComp.StatusCode, "Complete job should succeed for instance %s", inst.ID)

		var out dtos.JobInstanceActionResponse
		cData, _ := io.ReadAll(respComp.Body)
		require.NoError(t, json.Unmarshal(cData, &out), "Failed to unmarshal complete response for instance %s", inst.ID)
		require.Equal(t, "COMPLETED", out.Updated.Status)

		defAfter, errGet := h.JobDefRepo.GetByID(ctx, defn.ID)
		require.NoError(t, errGet)
		dailyEst := defAfter.GetDailyEstimate(currentServiceDate.Weekday())
		require.NotNil(t, dailyEst, "Daily estimate for weekday %s should exist", currentServiceDate.Weekday())
		return dailyEst.EstimatedTimeMinutes
	}

	newEst1 := completeJobCycleAndGetNewEstimate(initialServiceDate, 30)
	require.Equal(t, 54, newEst1, "EMA after 1st completion (actual 30min)")
	t.Logf("EMA for %s after 1st cycle (actual 30min) => %d", weekdayForTest, newEst1)

	newEst2 := completeJobCycleAndGetNewEstimate(initialServiceDate.AddDate(0, 0, 7), 70)
	require.Equal(t, 57, newEst2, "EMA after 2nd completion (actual 70min)")
	t.Logf("EMA for %s after 2nd cycle (actual 70min) => %d", weekdayForTest, newEst2)

	newEst3 := completeJobCycleAndGetNewEstimate(initialServiceDate.AddDate(0, 0, 14), 55)
	require.Equal(t, 57, newEst3, "EMA after 3rd completion (actual 55min)")
	t.Logf("EMA for %s after 3rd cycle (actual 55min) => %d", weekdayForTest, newEst3)

	var differentWeekday time.Weekday
	if weekdayForTest == time.Saturday {
		differentWeekday = time.Sunday
	} else {
		differentWeekday = weekdayForTest + 1
	}

	defFinal, err := h.JobDefRepo.GetByID(ctx, defn.ID)
	require.NoError(t, err)
	estForDifferentDay := defFinal.GetDailyEstimate(differentWeekday)
	require.NotNil(t, estForDifferentDay, "Estimate for different weekday %s should exist", differentWeekday)
	require.Equal(t, 60, estForDifferentDay.EstimatedTimeMinutes,
		"Estimate for %s should remain at its initial value of 60 after updates to %s", differentWeekday, weekdayForTest)
	t.Logf("EMA for %s (different day) remains %d, showing independence from updates to %s",
		differentWeekday, estForDifferentDay.EstimatedTimeMinutes, weekdayForTest)
}

/*
───────────────────────────────────────────────────────────────────
 15. Job Release Gating Logic (Tenant & Reliability Score)

───────────────────────────────────────────────────────────────────
*/
func TestJobReleaseGating(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	// --- SOLUTION: Add these lines to ensure a clean slate for this test ---
	_, err := h.DB.Exec(ctx, `TRUNCATE TABLE job_instances, job_definitions CASCADE`)
	require.NoError(t, err, "failed to truncate job_instances & job_definitions")
	// --- End of fix ---

	const propTimeZone = "America/New_York"
	propLoc, err := time.LoadLocation(propTimeZone)
	require.NoError(t, err, "Failed to load property timezone")

	prop := h.CreateTestProperty(ctx, "GatingProp", testPM.ID, 40.7128, -74.0060) // NYC
	prop.TimeZone = propTimeZone
	require.NoError(t, h.PropertyRepo.Update(ctx, prop))

	earliest, latest := h.TestSameDayTimeWindow()
	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, prop.ID, "GatingDef",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)

	nowInPropTZ := time.Now().In(propLoc)
	todayInPropTZ := time.Date(nowInPropTZ.Year(), nowInPropTZ.Month(), nowInPropTZ.Day(), 0, 0, 0, 0, propLoc)

	var allJobDates []time.Time
	// FIX: Create jobs from today forward to avoid having an expired "yesterday" job in the list.
	for i := 0; i <= 7; i++ {
		serviceDate := todayInPropTZ.AddDate(0, 0, i)
		allJobDates = append(allJobDates, serviceDate)
		_ = h.CreateTestJobInstance(t, ctx, defn.ID, serviceDate, models.InstanceStatusOpen, nil)
	}

	// Reference dates are now relative to the new `allJobDates` slice.
	guaranteedVisibleDates := allJobDates[0:6] // today -> today+5
	gatedDay6 := allJobDates[6]                // today+6
	gatedDay7 := allJobDates[7]                // today+7

	listAndCheckJobs := func(
		t *testing.T,
		scenarioName string,
		worker *models.Worker,
		expectedTotal int,
		mustBeVisibleDates []time.Time,
	) {
		h.T = t
		t.Helper()
		deviceID := "gating-device-" + worker.ID.String()[:8]
		wJWT := h.CreateMobileJWT(worker.ID, deviceID, "FAKE-PLAY")

		listURL := fmt.Sprintf("%s/api/v1/jobs/open?lat=%f&lng=%f&page=1&size=50",
			h.BaseURL, prop.Latitude, prop.Longitude)

		req := h.BuildAuthRequest("GET", listURL, wJWT, nil, "android", deviceID)
		client := h.NewHTTPClient()
		resp := h.DoRequest(req, client)
		defer resp.Body.Close()
		require.Equal(t, http.StatusOK, resp.StatusCode, "%s: API call failed with status %d. Body: %s", scenarioName, resp.StatusCode, h.ReadBody(resp))

		var out dtos.ListJobsResponse
		raw, _ := io.ReadAll(resp.Body)
		require.NoError(t, json.Unmarshal(raw, &out), "%s: failed to unmarshal response", scenarioName)

		require.Equal(t, expectedTotal, out.Total, "%s: expected total jobs mismatch", scenarioName)

		returnedDates := make(map[string]bool)
		for _, job := range out.Results {
			returnedDates[job.ServiceDate] = true
		}

		for _, visibleDate := range mustBeVisibleDates {
			dateStr := visibleDate.Format("2006-01-02")
			require.True(t, returnedDates[dateStr], "%s: expected visible date %s was not in response", scenarioName, dateStr)
		}
	}

	t.Run("StandardWorker_Score100", func(t *testing.T) {
		h.T = t
		worker := h.CreateTestWorker(ctx, "gating-standard-100", 100)
		releaseTimeForDay6 := todayInPropTZ

		if time.Now().Before(releaseTimeForDay6) {
			t.Logf("[StandardWorker_Score100] Testing BEFORE release time for Day+6 job. Now: %v, Release: %v", time.Now(), releaseTimeForDay6)
			// FIX: Expected total is 6 (today..today+5)
			listAndCheckJobs(t, "StandardWorker_Score100 (Before Release)", worker, 6, guaranteedVisibleDates)
		} else {
			t.Logf("[StandardWorker_Score100] Testing AFTER release time for Day+6 job. Now: %v, Release: %v", time.Now(), releaseTimeForDay6)
			// FIX: Expected total is 7 (today..today+6)
			listAndCheckJobs(t, "StandardWorker_Score100 (After Release)", worker, 7, append(guaranteedVisibleDates, gatedDay6))
		}
	})

	t.Run("StandardWorker_Score70", func(t *testing.T) {
		h.T = t
		worker := h.CreateTestWorker(ctx, "gating-standard-70", 70)
		releaseTimeForDay6 := todayInPropTZ.Add(36 * time.Minute)

		if time.Now().Before(releaseTimeForDay6) {
			t.Logf("[StandardWorker_Score70] Testing BEFORE release time. Now: %v, Release: %v", time.Now(), releaseTimeForDay6)
			// FIX: Expected total is 6
			listAndCheckJobs(t, "StandardWorker_Score70 (Before Release)", worker, 6, guaranteedVisibleDates)
		} else {
			t.Logf("[StandardWorker_Score70] Testing AFTER release time. Now: %v, Release: %v", time.Now(), releaseTimeForDay6)
			// FIX: Expected total is 7
			listAndCheckJobs(t, "StandardWorker_Score70 (After Release)", worker, 7, append(guaranteedVisibleDates, gatedDay6))
		}
	})

	t.Run("TenantWorker_Score100", func(t *testing.T) {
		h.T = t
		worker := h.CreateTestWorker(ctx, "gating-tenant-100", 100)
		worker = h.MakeWorkerTenant(t, ctx, worker, prop.ID)

		releaseTimeForDay6 := todayInPropTZ.Add(-1 * time.Hour)
		releaseTimeForDay7 := todayInPropTZ.AddDate(0, 0, 1).Add(-1 * time.Hour)

		now := time.Now()
		if now.Before(releaseTimeForDay6) {
			t.Logf("[TenantWorker_Score100] Testing BEFORE Day+6 release. Now: %v, Release6: %v", now, releaseTimeForDay6)
			// FIX: Expected total is 6
			listAndCheckJobs(t, "TenantWorker_Score100 (Before D6)", worker, 6, guaranteedVisibleDates)
		} else if now.Before(releaseTimeForDay7) {
			t.Logf("[TenantWorker_Score100] Testing AFTER Day+6 release, BEFORE Day+7 release. Now: %v, R6: %v, R7: %v", now, releaseTimeForDay6, releaseTimeForDay7)
			// FIX: Expected total is 7
			listAndCheckJobs(t, "TenantWorker_Score100 (After D6, Before D7)", worker, 7, append(guaranteedVisibleDates, gatedDay6))
		} else {
			t.Logf("[TenantWorker_Score100] Testing AFTER Day+7 release. Now: %v, R7: %v", now, releaseTimeForDay7)
			// FIX: Expected total is 8
			listAndCheckJobs(t, "TenantWorker_Score100 (After D7)", worker, 8, append(guaranteedVisibleDates, gatedDay6, gatedDay7))
		}
	})

	t.Run("TenantWorker_Score70", func(t *testing.T) {
		h.T = t
		worker := h.CreateTestWorker(ctx, "gating-tenant-70", 70)
		worker = h.MakeWorkerTenant(t, ctx, worker, prop.ID)

		delay := 36 * time.Minute
		releaseTimeForDay6 := todayInPropTZ.Add(-1 * time.Hour).Add(delay)
		releaseTimeForDay7 := todayInPropTZ.AddDate(0, 0, 1).Add(-1 * time.Hour).Add(delay)

		now := time.Now()
		if now.Before(releaseTimeForDay6) {
			t.Logf("[TenantWorker_Score70] Testing BEFORE Day+6 release. Now: %v, Release6: %v", now, releaseTimeForDay6)
			// FIX: Expected total is 6
			listAndCheckJobs(t, "TenantWorker_Score70 (Before D6)", worker, 6, guaranteedVisibleDates)
		} else if now.Before(releaseTimeForDay7) {
			t.Logf("[TenantWorker_Score70] Testing AFTER Day+6 release, BEFORE Day+7 release. Now: %v, R6: %v, R7: %v", now, releaseTimeForDay6, releaseTimeForDay7)
			// FIX: Expected total is 7
			listAndCheckJobs(t, "TenantWorker_Score70 (After D6, Before D7)", worker, 7, append(guaranteedVisibleDates, gatedDay6))
		} else {
			t.Logf("[TenantWorker_Score70] Testing AFTER Day+7 release. Now: %v, R7: %v", now, releaseTimeForDay7)
			// FIX: Expected total is 8
			listAndCheckJobs(t, "TenantWorker_Score70 (After D7)", worker, 8, append(guaranteedVisibleDates, gatedDay6, gatedDay7))
		}
	})
}

/*
───────────────────────────────────────────────────────────────────
16. Job Scheduler Service: Run Daily Window Maintenance method check (not cron)

───────────────────────────────────────────────────────────────────
*/
func TestJobSchedulerService(t *testing.T) {
	h.T = t
	ctx := h.Ctx

	prop := h.CreateTestProperty(ctx, "SchedulerTestProp", testPM.ID, 40.0, -74.0)
	earliest, latest := h.TestSameDayTimeWindow()
	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, prop.ID, "SchedulerDailyJob",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)

	targetWeekday := time.Now().UTC().AddDate(0, 0, 7).Weekday()
	var expectedPay float64
	for _, est := range defn.DailyPayEstimates {
		if est.DayOfWeek == targetWeekday {
			expectedPay = est.BasePay
			break
		}
	}
	require.Greater(t, expectedPay, 0.0, "Test setup requires a non-zero base pay for the target weekday")

	jobScheduler := services.NewJobSchedulerService(
		nil,
		h.JobDefRepo,
		h.JobInstRepo,
		h.PropertyRepo,
	)
	err := jobScheduler.RunDailyWindowMaintenance(ctx)
	require.NoError(t, err, "RunDailyWindowMaintenance should not return an error")

	dayPlus7 := services.DateOnly(time.Now().UTC().AddDate(0, 0, 7))

	query := `SELECT effective_pay FROM job_instances WHERE definition_id = $1 AND service_date = $2`
	var effectivePay float64
	err = h.DB.QueryRow(ctx, query, defn.ID, dayPlus7).Scan(&effectivePay)

	require.NoError(t, err, "Should find the newly created instance for day+7 in the database")
	require.Equal(t, expectedPay, effectivePay, "The effective_pay of the created instance should match the definition's base_pay")

	t.Logf("JobSchedulerService correctly created an instance for %s with effective_pay=%.2f", dayPlus7.Format("2006-01-02"), effectivePay)
}

/*
───────────────────────────────────────────────────────────────────
17. Multi-Worker Cancel & Re-accept Flow (NEW)
───────────────────────────────────────────────────────────────────
*/
func TestMultiWorkerCancelAndReacceptFlow(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	earliest, latest := h.TestSameDayTimeWindow()

	// 1. Create resources: a property and two active workers.
	prop := h.CreateTestProperty(ctx, "MultiWorkerProp", testPM.ID, 0, 0)
	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, prop.ID, "MultiWorkerJob",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
	inst := h.CreateTestJobInstance(t, ctx, defn.ID, time.Now(), models.InstanceStatusOpen, nil)

	workerA := h.CreateTestWorker(ctx, "worker-a-multi")
	workerB := h.CreateTestWorker(ctx, "worker-b-multi")
	jwtA := h.CreateMobileJWT(workerA.ID, "multi-dev-a", "FAKE-PLAY")
	jwtB := h.CreateMobileJWT(workerB.ID, "multi-dev-b", "FAKE-PLAY")

	// 2. Worker A accepts and starts the job.
	acceptPayload := dtos.JobLocationActionRequest{
		InstanceID: inst.ID, Lat: 0.0, Lng: 0.0, Accuracy: 5.0, Timestamp: time.Now().UnixMilli(), IsMock: false,
	}
	acceptBody, _ := json.Marshal(acceptPayload)
	acceptReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsAccept, jwtA, acceptBody, "android", "multi-dev-a")
	acceptResp := h.DoRequest(acceptReq, h.NewHTTPClient())
	defer acceptResp.Body.Close()
	require.Equal(t, http.StatusOK, acceptResp.StatusCode, "Worker A should accept job")

	startPayload := dtos.JobLocationActionRequest{
		InstanceID: inst.ID, Lat: 0.0, Lng: 0.0, Accuracy: 5.0, Timestamp: time.Now().UnixMilli(), IsMock: false,
	}
	startBody, _ := json.Marshal(startPayload)
	startReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsStart, jwtA, startBody, "android", "multi-dev-a")
	startResp := h.DoRequest(startReq, h.NewHTTPClient())
	defer startResp.Body.Close()
	require.Equal(t, http.StatusOK, startResp.StatusCode, "Worker A should start job")

	// 3. Worker A cancels the job.
	cancelPayload := dtos.JobInstanceActionRequest{InstanceID: inst.ID}
	cancelBody, _ := json.Marshal(cancelPayload)
	cancelReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsCancel, jwtA, cancelBody, "android", "multi-dev-a")
	cancelResp := h.DoRequest(cancelReq, h.NewHTTPClient())
	defer cancelResp.Body.Close()
	require.Equal(t, http.StatusOK, cancelResp.StatusCode, "Worker A should cancel job")

	// 4. Worker B lists open jobs and verifies the canceled job is available again.
	listURL := fmt.Sprintf("%s/api/v1/jobs/open?lat=0&lng=0&page=1&size=50", h.BaseURL)
	listReq := h.BuildAuthRequest("GET", listURL, jwtB, nil, "android", "multi-dev-b")
	listResp := h.DoRequest(listReq, h.NewHTTPClient())
	defer listResp.Body.Close()
	require.Equal(t, http.StatusOK, listResp.StatusCode, "Worker B should be able to list open jobs")

	var openJobsList dtos.ListJobsResponse
	raw, _ := io.ReadAll(listResp.Body)
	require.NoError(t, json.Unmarshal(raw, &openJobsList))

	jobFoundForWorkerB := false
	for _, jobDTO := range openJobsList.Results {
		if jobDTO.InstanceID == inst.ID {
			jobFoundForWorkerB = true
			require.Equal(t, "OPEN", jobDTO.Status, "Job status should be OPEN for Worker B")
			break
		}
	}
	require.True(t, jobFoundForWorkerB, "Canceled job was not found in Worker B's list of open jobs")

	// 5. Worker B accepts the job.
	acceptReqB := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsAccept, jwtB, acceptBody, "android", "multi-dev-b")
	acceptRespB := h.DoRequest(acceptReqB, h.NewHTTPClient())
	defer acceptRespB.Body.Close()
	require.Equal(t, http.StatusOK, acceptRespB.StatusCode, "Worker B should be able to accept the re-opened job")
}
