//go:build (dev_test || staging_test) && integration

package integration

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/poofware/go-models"
	"github.com/poofware/jobs-service/internal/dtos"
	"github.com/poofware/jobs-service/internal/routes"
	"github.com/poofware/jobs-service/internal/services"
)

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

	unit := &models.Unit{ID: uuid.New(), PropertyID: p.ID, BuildingID: bID, UnitNumber: "101", TenantToken: uuid.NewString()}
	require.NoError(t, h.UnitRepo.Create(ctx, unit))
	require.NoError(t, h.JobDefRepo.UpdateWithRetry(ctx, defn.ID, func(j *models.JobDefinition) error {
		j.AssignedUnitsByBuilding[0].UnitIDs = []uuid.UUID{unit.ID}
		return nil
	}))

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

		// Verify the unit via API
		var buf bytes.Buffer
		writer := multipart.NewWriter(&buf)
		writer.WriteField("instance_id", inst.ID.String())
		writer.WriteField("unit_id", unit.ID.String())
		writer.WriteField("lat", "0.0")
		writer.WriteField("lng", "0.0")
		writer.WriteField("accuracy", "5.0")
		writer.WriteField("timestamp", fmt.Sprintf("%d", time.Now().UnixMilli()))
		writer.WriteField("is_mock", "false")
		part, _ := writer.CreateFormFile("photo", "ema.jpg")
		_, _ = part.Write([]byte("fake photo data"))
		writer.Close()

		verifyReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsVerifyUnitPhoto, workerJWT, buf.Bytes(), "android", "ema-test-device")
		verifyReq.Header.Set("Content-Type", writer.FormDataContentType())
		verifyResp := h.DoRequest(verifyReq, h.NewHTTPClient())
		defer verifyResp.Body.Close()
		require.Equal(t, 200, verifyResp.StatusCode)

		payload := dtos.JobLocationActionRequest{
			InstanceID: inst.ID,
			Lat:        0.0,
			Lng:        0.0,
			Accuracy:   5.0,
			Timestamp:  time.Now().UnixMilli(),
			IsMock:     false,
		}
		body, _ := json.Marshal(payload)
		dumpReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsDumpBags, workerJWT, body, "android", "ema-test-device")
		dumpResp := h.DoRequest(dumpReq, h.NewHTTPClient())
		defer dumpResp.Body.Close()

		if dumpResp.StatusCode != 200 {
			bodyBytes, _ := io.ReadAll(dumpResp.Body)
			t.Logf("DumpBags failed unexpectedly. Status: %d, Body: %s. Instance ServiceDate: %v",
				dumpResp.StatusCode, string(bodyBytes), currentServiceDate)
		}
		require.Equal(t, 200, dumpResp.StatusCode, "Dump bags should succeed for instance %s", inst.ID)

		var out dtos.JobInstanceActionResponse
		cData, _ := io.ReadAll(dumpResp.Body)
		require.NoError(t, json.Unmarshal(cData, &out), "Failed to unmarshal dump response for instance %s", inst.ID)
		require.Equal(t, "COMPLETED", out.Updated.Status)
		require.NotEmpty(t, out.Updated.UnitVerifications)
		require.Equal(t, int16(0), out.Updated.UnitVerifications[0].AttemptCount)

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

/*
───────────────────────────────────────────────────────────────────
18. Location Validation on Verify Photo & Dump Bags
───────────────────────────────────────────────────────────────────
*/
func TestLocationValidation(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	earliest, latest := h.TestSameDayTimeWindow()

	w := h.CreateTestWorker(ctx, "loc-validate")
	p := h.CreateTestProperty(ctx, "LocValProp", testPM.ID, 0.0, 0.0)
	b := h.CreateTestBuilding(ctx, p.ID, "LocValBldg")
	d := h.CreateTestDumpster(ctx, p.ID, "LocValDump")
	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "LocValJob",
		[]uuid.UUID{b.ID}, []uuid.UUID{d.ID}, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
	unit := &models.Unit{ID: uuid.New(), PropertyID: p.ID, BuildingID: b.ID, UnitNumber: "100", TenantToken: uuid.NewString()}
	require.NoError(t, h.UnitRepo.Create(ctx, unit))
	require.NoError(t, h.JobDefRepo.UpdateWithRetry(ctx, defn.ID, func(j *models.JobDefinition) error {
		j.AssignedUnitsByBuilding[0].UnitIDs = []uuid.UUID{unit.ID}
		return nil
	}))
	inst := h.CreateTestJobInstance(t, ctx, defn.ID, time.Now(), models.InstanceStatusOpen, nil)
	jwt := h.CreateMobileJWT(w.ID, "locval-dev", "FAKE-PLAY")

	loc := dtos.JobLocationActionRequest{InstanceID: inst.ID, Lat: 0, Lng: 0, Accuracy: 5, Timestamp: time.Now().UnixMilli(), IsMock: false}
	body, _ := json.Marshal(loc)
	acceptReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsAccept, jwt, body, "android", "locval-dev")
	acceptResp := h.DoRequest(acceptReq, h.NewHTTPClient())
	defer acceptResp.Body.Close()
	require.Equal(t, http.StatusOK, acceptResp.StatusCode)

	startReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsStart, jwt, body, "android", "locval-dev")
	startResp := h.DoRequest(startReq, h.NewHTTPClient())
	defer startResp.Body.Close()
	require.Equal(t, http.StatusOK, startResp.StatusCode)

	t.Run("VerifyPhoto_Inaccurate", func(t *testing.T) {
		h.T = t
		var buf bytes.Buffer
		writer := multipart.NewWriter(&buf)
		writer.WriteField("instance_id", inst.ID.String())
		writer.WriteField("unit_id", unit.ID.String())
		writer.WriteField("lat", "0")
		writer.WriteField("lng", "0")
		writer.WriteField("accuracy", "50")
		writer.WriteField("timestamp", fmt.Sprintf("%d", time.Now().UnixMilli()))
		writer.WriteField("is_mock", "false")
		part, _ := writer.CreateFormFile("photo", "bad.jpg")
		part.Write([]byte("dummy"))
		writer.Close()

		req := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsVerifyUnitPhoto, jwt, buf.Bytes(), "android", "locval-dev")
		req.Header.Set("Content-Type", writer.FormDataContentType())
		resp := h.DoRequest(req, h.NewHTTPClient())
		defer resp.Body.Close()
		require.Equal(t, http.StatusBadRequest, resp.StatusCode)
	})

	t.Run("DumpBags_Inaccurate", func(t *testing.T) {
		h.T = t
		badLoc := dtos.JobLocationActionRequest{InstanceID: inst.ID, Lat: 0, Lng: 0, Accuracy: 50, Timestamp: time.Now().UnixMilli(), IsMock: false}
		b, _ := json.Marshal(badLoc)
		req := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsDumpBags, jwt, b, "android", "locval-dev")
		resp := h.DoRequest(req, h.NewHTTPClient())
		defer resp.Body.Close()
		require.Equal(t, http.StatusBadRequest, resp.StatusCode)
	})
}
