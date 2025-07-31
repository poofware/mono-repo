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

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/poofware/go-models"
	"github.com/poofware/go-testhelpers"
	"github.com/poofware/go-utils"
	"github.com/poofware/jobs-service/internal/constants"
	"github.com/poofware/jobs-service/internal/dtos"
	"github.com/poofware/jobs-service/internal/routes"
	internal_utils "github.com/poofware/jobs-service/internal/utils"
)

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

	// Create a unit and assign it to the job definition
       unit := &models.Unit{
               ID:         uuid.New(),
               PropertyID: p.ID,
               BuildingID: bldg.ID,
               UnitNumber: "101",
               TenantToken: uuid.NewString(),
       }
	require.NoError(t, h.UnitRepo.Create(ctx, unit))

	require.NoError(t, h.JobDefRepo.UpdateWithRetry(ctx, defn.ID, func(j *models.JobDefinition) error {
		j.AssignedUnitsByBuilding[0].UnitIDs = []uuid.UUID{unit.ID}
		return nil
	}))

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

	t.Run("VerifyUnitPhoto", func(t *testing.T) {
		h.T = t
		var buf bytes.Buffer
		writer := multipart.NewWriter(&buf)
		writer.WriteField("instance_id", inst.ID.String())
		writer.WriteField("unit_id", unit.ID.String())
		writer.WriteField("lat", "0.0")
		writer.WriteField("lng", "0.0")
		writer.WriteField("accuracy", "3.7")
		writer.WriteField("timestamp", fmt.Sprintf("%d", time.Now().UnixMilli()))
		writer.WriteField("is_mock", "false")
		part, err := writer.CreateFormFile("photo", "test.jpg")
		require.NoError(t, err)
		_, _ = part.Write([]byte("fake image bytes"))
		writer.Close()

		ep := h.BaseURL + routes.JobsVerifyUnitPhoto
		req := h.BuildAuthRequest("POST", ep, workerJWT, buf.Bytes(), "android", "flow-device-123")
		req.Header.Set("Content-Type", writer.FormDataContentType())

		c := h.NewHTTPClient()
		resp := h.DoRequest(req, c)
		defer resp.Body.Close()
		require.Equal(t, 200, resp.StatusCode)

		var r dtos.JobInstanceActionResponse
		data, _ := io.ReadAll(resp.Body)
		json.Unmarshal(data, &r)
		require.Equal(t, "IN_PROGRESS", r.Updated.Status)
		require.Len(t, r.Updated.UnitVerifications, 1)
		require.Equal(t, "VERIFIED", r.Updated.UnitVerifications[0].Status)
	})

	t.Run("DumpBags", func(t *testing.T) {
		h.T = t
		payload := dtos.JobLocationActionRequest{
			InstanceID: inst.ID,
			Lat:        0.0,
			Lng:        0.0,
			Accuracy:   3.7,
			Timestamp:  time.Now().UnixMilli(),
			IsMock:     false,
		}
		body, _ := json.Marshal(payload)
		ep := h.BaseURL + routes.JobsDumpBags
		req := h.BuildAuthRequest("POST", ep, workerJWT, body, "android", "flow-device-123")
		c := h.NewHTTPClient()
		resp := h.DoRequest(req, c)
		defer resp.Body.Close()
		require.Equal(t, 200, resp.StatusCode)

		var r dtos.JobInstanceActionResponse
		data, _ := io.ReadAll(resp.Body)
		json.Unmarshal(data, &r)
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
	b := h.CreateTestBuilding(ctx, p.ID, "Conc Bldg")
	d := h.CreateTestDumpster(ctx, p.ID, "Conc Dump")
	defn := h.CreateTestJobDefinition(t, ctx, testPM.ID, p.ID, "ConcurrencyCompleteTest",
		[]uuid.UUID{b.ID}, []uuid.UUID{d.ID}, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)

       unit := &models.Unit{ID: uuid.New(), PropertyID: p.ID, BuildingID: b.ID, UnitNumber: "101", TenantToken: uuid.NewString()}
	require.NoError(t, h.UnitRepo.Create(ctx, unit))
	require.NoError(t, h.JobDefRepo.UpdateWithRetry(ctx, defn.ID, func(j *models.JobDefinition) error {
		j.AssignedUnitsByBuilding[0].UnitIDs = []uuid.UUID{unit.ID}
		return nil
	}))

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

	// Verify the unit first
	{
		var buf bytes.Buffer
		writer := multipart.NewWriter(&buf)
		writer.WriteField("instance_id", inst.ID.String())
		writer.WriteField("unit_id", unit.ID.String())
		writer.WriteField("lat", "0.0")
		writer.WriteField("lng", "0.0")
		writer.WriteField("accuracy", "2.5")
		writer.WriteField("timestamp", fmt.Sprintf("%d", time.Now().UnixMilli()))
		writer.WriteField("is_mock", "false")
		part, _ := writer.CreateFormFile("photo", "v.jpg")
		part.Write([]byte("dummy"))
		writer.Close()

		req := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsVerifyUnitPhoto, wJWT, buf.Bytes(), "android", "completeConc-dev")
		req.Header.Set("Content-Type", writer.FormDataContentType())
		resp := h.DoRequest(req, h.NewHTTPClient())
		defer resp.Body.Close()
		require.Equal(t, 200, resp.StatusCode)
	}

	doDump := func() int {
		payload := dtos.JobLocationActionRequest{
			InstanceID: inst.ID,
			Lat:        0.0,
			Lng:        0.0,
			Accuracy:   2.5,
			Timestamp:  time.Now().UnixMilli(),
			IsMock:     false,
		}
		body, _ := json.Marshal(payload)
		req := h.BuildAuthRequest("POST", h.BaseURL+routes.JobsDumpBags, wJWT, body, "android", "completeConc-dev")
		resp := h.DoRequest(req, h.NewHTTPClient())
		defer resp.Body.Close()
		return resp.StatusCode
	}

	var results [2]int
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		results[0] = doDump()
	}()
	go func() {
		defer wg.Done()
		results[1] = doDump()
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
