//go:build (dev_test || staging_test) && integration

package integration

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"testing"
	"time"

	"github.com/bradfitz/latlong"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/poofware/go-models"
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

               // Use deterministic evening hours to avoid crossing midnight in any timezone.
               today := time.Now().In(propLoc)
               latestStart := time.Date(today.Year(), today.Month(), today.Day(), 20, 0, 0, 0, propLoc)
               earliestStart := latestStart.Add(-2 * time.Hour)

		unacceptableDef := h.CreateTestJobDefinition(t, ctx, testPM.ID, p1.ID, "UnacceptableJobDef",
			[]uuid.UUID{b1_p1.ID}, []uuid.UUID{d1_p1.ID}, earliestStart, latestStart, models.JobStatusActive, nil, models.JobFreqDaily, nil)

		// Create the instance for today in the property's timezone to be certain about the service date.
               todayInPropTZ := time.Date(today.Year(), today.Month(), today.Day(), 0, 0, 0, 0, propLoc)
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
               // Use a time window anchored to the previous day to avoid crossing
               // midnight which can violate the DB constraint that compares times
               // without dates.
               dayBefore := now.AddDate(0, 0, -1)
               dayStart := time.Date(dayBefore.Year(), dayBefore.Month(), dayBefore.Day(), 0, 0, 0, 0, time.UTC)
               earliestStart := dayStart                                 // 00:00 of previous day
               latestStart := dayStart.Add(2 * time.Hour)                // 02:00 of previous day

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
