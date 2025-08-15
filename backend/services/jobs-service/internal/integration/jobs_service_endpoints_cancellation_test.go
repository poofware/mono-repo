//go:build (dev_test || staging_test) && integration

package integration

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/constants"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/routes"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/services"
	internal_utils "github.com/poofware/mono-repo/backend/services/jobs-service/internal/utils"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

/*
───────────────────────────────────────────────────────────────────
 9. Exclusion

───────────────────────────────────────────────────────────────────
*/
func TestExcludedWorkerCannotAccept(t *testing.T) {
	h.T = t
	ctx := h.Ctx
    earliest, latest, serviceDate := h.WindowActiveNowInTZ("UTC")

	p := h.CreateTestProperty(ctx, "ExclProp", testPM.ID, 0.0, 0.0)
	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "ExclusionTest",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
    inst := h.CreateTestJobInstance(t, ctx, defn.ID, serviceDate, models.InstanceStatusOpen, nil)

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
    earliest, latest, serviceDate := h.WindowActiveNowInTZ("UTC")

	_, err := h.DB.Exec(ctx, `TRUNCATE TABLE job_instances, job_definitions CASCADE`)
	require.NoError(t, err, "failed to truncate job_instances & job_definitions")

	prop := h.CreateTestProperty(ctx, "LargePagingProp_SameDay", testPM.ID, 35.0, -84.0)
	sharedBuilding := h.CreateTestBuilding(ctx, prop.ID, "SharedLargePagingBldg")
	sharedDumpster := h.CreateTestDumpster(ctx, prop.ID, "SharedLargePagingDump")

    for i := range 25 {
		def := h.CreateTestJobDefinition(t, ctx, testPM.ID, prop.ID, fmt.Sprintf("SameDayJob %d", i),
			[]uuid.UUID{sharedBuilding.ID}, []uuid.UUID{sharedDumpster.ID}, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
        _ = h.CreateTestJobInstance(t, ctx, def.ID, serviceDate, models.InstanceStatusOpen, nil)
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
    earliest, latest, serviceDate := h.ActiveAcceptanceWindow()
	initialScore := 100

	w := h.CreateTestWorker(ctx, "cancel-reopen", initialScore)
	workerJWT := h.CreateMobileJWT(w.ID, "cancelReopenDevice", "FAKE-PLAY")
	p := h.CreateTestProperty(ctx, "CancelReopenProp", testPM.ID, 0, 0)
	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "CancelReopenJob",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
	// Use today's date for the instance
    inst := h.CreateTestJobInstance(t, ctx, defn.ID, serviceDate, models.InstanceStatusOpen, nil)

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

// Late unassignment after the acceptance cutoff should reopen the job and penalize the worker
func TestUnaccept_AfterAcceptanceCutoff_Reopens(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	initialScore := 100

    // Setup a job where acceptance cutoff has passed but we are safely before no-show.
    // Choose latest so that no-show (latest-20m) is ~35m from now; acceptance cutoff (no-show-40m) is ~-5m.
    now := time.Now().UTC()
    latest := now.Add(55 * time.Minute)      // no-show ≈ now + 35m
    earliest := latest.Add(-2 * time.Hour)   // 2-hour window
    serviceDate := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)

	w := h.CreateTestWorker(ctx, "unaccept-late", initialScore)
	workerJWT := h.CreateMobileJWT(w.ID, "unacceptLateDevice", "FAKE-PLAY")
	p := h.CreateTestProperty(ctx, "UnacceptLateProp", testPM.ID, 0, 0)
	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "UnacceptLateJob",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
    inst := h.CreateTestJobInstance(t, ctx, defn.ID, serviceDate, models.InstanceStatusOpen, nil)

	// Manually assign the job to the worker to bypass acceptance window checks
	_, err := h.DB.Exec(ctx, `UPDATE job_instances SET status=$1, assigned_worker_id=$2, row_version=row_version+1 WHERE id=$3`,
		models.InstanceStatusAssigned, w.ID, inst.ID)
	require.NoError(t, err)

	unacceptBody, _ := json.Marshal(dtos.JobInstanceActionRequest{InstanceID: inst.ID})
	unacceptReq := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsUnaccept, workerJWT, unacceptBody, "android", "unacceptLateDevice")
	unacceptResp := h.DoRequest(unacceptReq, h.NewHTTPClient())
	defer unacceptResp.Body.Close()
	require.Equal(t, http.StatusOK, unacceptResp.StatusCode)

	var out dtos.JobInstanceActionResponse
	data, _ := io.ReadAll(unacceptResp.Body)
	require.NoError(t, json.Unmarshal(data, &out))
	require.Equal(t, string(models.InstanceStatusOpen), out.Updated.Status, "Job should reopen")

    updatedWorker, err := h.WorkerRepo.GetByID(ctx, w.ID)
    require.NoError(t, err)
    // Compute expected penalty using the same timezone-aware construction as the service
    propLoc, tzErr := time.LoadLocation(p.TimeZone)
    require.NoError(t, tzErr)
    earliestLocal := time.Date(serviceDate.Year(), serviceDate.Month(), serviceDate.Day(), earliest.Hour(), earliest.Minute(), 0, 0, propLoc)
    latestLocal := time.Date(serviceDate.Year(), serviceDate.Month(), serviceDate.Day(), latest.Hour(), latest.Minute(), 0, 0, propLoc)
    noShowTime := latestLocal.Add(-constants.NoShowCutoffBeforeLatestStart)
    expectedPenalty, _ := services.CalculatePenaltyForUnassign(time.Now(), earliestLocal, noShowTime)
    require.Equal(t, initialScore+expectedPenalty, updatedWorker.ReliabilityScore, "Worker should be penalized correctly")

	updatedInst, err := h.JobInstRepo.GetByID(ctx, inst.ID)
	require.NoError(t, err)
	require.Contains(t, updatedInst.ExcludedWorkerIDs, w.ID, "Worker should be excluded")
}

func TestCancelInProgress_BecomesCanceled_AfterLatestStart(t *testing.T) {
	h.T = t
	ctx := h.Ctx
	initialScore := 100

    // FIX: Define a deterministic same-day window (2 hours duration) that avoids midnight crossing
    // and ensures DB CHECK (latest > earliest and >= 90 minutes) always holds.
    now := time.Now().UTC()
    anchor := time.Date(now.Year(), now.Month(), now.Day(), 12, 0, 0, 0, time.UTC) // 12:00 UTC today
    earliest := time.Date(anchor.Year(), anchor.Month(), anchor.Day(), 10, 0, 0, 0, time.UTC) // 10:00
    latest := time.Date(anchor.Year(), anchor.Month(), anchor.Day(), 12, 0, 0, 0, time.UTC)   // 12:00

	w := h.CreateTestWorker(ctx, "cancel-late", initialScore)
	workerJWT := h.CreateMobileJWT(w.ID, "cancelLateDevice", "FAKE-PLAY")
	p := h.CreateTestProperty(ctx, "CancelLateProp", testPM.ID, 0, 0)
	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "CancelLateJob",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
    // Use yesterday as service date so that, relative to 'now', we are definitively after the window.
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

	// 2. Cancel the job after its latest start time has already passed.
	//    This request should succeed with a 200 and result in a CANCELED job.
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
    earliest, latest, serviceDate := h.ActiveAcceptanceWindow()

	w := h.CreateTestWorker(ctx, "cancel-neg")
	workerJWT := h.CreateMobileJWT(w.ID, "cancelNegDevice", "FAKE-PLAY")

	pA := h.CreateTestProperty(ctx, "CancelNegPropA", testPM.ID, 0, 0)
	defA := h.CreateTestJobDefinition(t, ctx, testPM.ID, pA.ID, "CancelNegTestA",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
    instWrong := h.CreateTestJobInstance(t, ctx, defA.ID, serviceDate, models.InstanceStatusAssigned, &w.ID)

	pB := h.CreateTestProperty(ctx, "CancelNegPropB", testPM.ID, 0, 0)
	defB := h.CreateTestJobDefinition(t, ctx, testPM.ID, pB.ID, "CancelNegTestB",
		nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)
	otherWorker := h.CreateTestWorker(ctx, "otherCancel")
    instNotAssigned := h.CreateTestJobInstance(t, ctx, defB.ID, serviceDate, models.InstanceStatusInProgress, &otherWorker.ID)

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
    earliestForPast, latestForPast, instPastServiceDate := h.ActiveAcceptanceWindow()

    defIDPast := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "TimeGuardPastDef",
		nil, nil, earliestForPast, latestForPast, models.JobStatusActive, nil, models.JobFreqDaily, nil).ID
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
