//go:build (dev_test || staging_test) && integration

package integration

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/poofware/account-service/internal/dtos"
	"github.com/poofware/account-service/internal/routes"
	"github.com/poofware/go-models"
	"github.com/poofware/go-utils"
)

var (
	// The four "manual" candidates from your original data:
	//  1) Bud Richman
	//  2) Vito Andolini
	//  3) Alex Taylor
	//  4) Requisition Tester
	manualCandidateFullNames = map[string]struct{}{
		"Bud Richman":        {},
		"Vito Andolini":      {},
		"Alex Taylor":        {},
		"Requisition Tester": {},
	}
)

// checkrTestCandidate covers a single test scenario for determineOutcome
type checkrTestCandidate struct {
	FirstName             string
	LastName              string
	Email                 string
	Scenario              string
	WebhookType           string
	ReportStatus          string
	Adjudication          *string
	Assessment            *string
	Result                *string
	IncludesCanceled      bool
	ExpectedOutcome       models.ReportOutcomeType
	ExpectedAccountStatus models.AccountStatusType
}

func TestCheckrWebhookOutcomes(t *testing.T) {
	if h.CheckrAPIKey == "" {
		t.Skip("CHECKR_API_KEY not configured, skipping Checkr outcome tests.")
	}

	scenarios := []checkrTestCandidate{
		{
			FirstName: "Vito", LastName: "Andolini", Email: "testing@thepoofapp.com",
			Scenario:              "Status=canceled => outcome=CANCELED (manual candidate #2)",
			WebhookType:           "report.canceled",
			ReportStatus:          "canceled",
			ExpectedOutcome:       models.ReportOutcomeCanceled,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Lady", LastName: "Gaga", Email: "testing@thepoofapp.com",
			Scenario:              "Status=dispute => outcome=DISPUTE_PENDING",
			WebhookType:           "report.disputed",
			ReportStatus:          "dispute",
			ExpectedOutcome:       models.ReportOutcomeDisputePending,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Judge", LastName: "Judy", Email: "testing@thepoofapp.com",
			Scenario:              "Status=suspended => outcome=SUSPENDED",
			WebhookType:           "report.suspended",
			ReportStatus:          "suspended",
			ExpectedOutcome:       models.ReportOutcomeSuspended,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Tom", LastName: "Brady", Email: "testing@thepoofapp.com",
			Scenario:              "Adjudication=engaged => outcome=APPROVED => account=ACTIVE",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Adjudication:          utils.Ptr("engaged"),
			ExpectedOutcome:       models.ReportOutcomeApproved,
			ExpectedAccountStatus: models.AccountStatusActive,
		},
		{
			FirstName: "Samuel", LastName: "Adams", Email: "testing@thepoofapp.com",
			Scenario:              "Adjudication=pre_adverse_action => outcome=PRE_ADVERSE_ACTION",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Adjudication:          utils.Ptr("pre_adverse_action"),
			ExpectedOutcome:       models.ReportOutcomePreAdverseAction,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Peter", LastName: "Griffin", Email: "testing@thepoofapp.com",
			Scenario:              "Adjudication=post_adverse_action => outcome=DISQUALIFIED",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Adjudication:          utils.Ptr("post_adverse_action"),
			ExpectedOutcome:       models.ReportOutcomeDisqualified,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Bud", LastName: "Richman", Email: "testing@thepoofapp.com",
			Scenario:              "assessment=eligible => includesCanceled=false => outcome=APPROVED => account=ACTIVE (manual candidate #1)",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Assessment:            utils.Ptr("eligible"),
			Result:                utils.Ptr("clear"),
			IncludesCanceled:      false,
			ExpectedOutcome:       models.ReportOutcomeApproved,
			ExpectedAccountStatus: models.AccountStatusActive,
		},
		{
			FirstName: "Alex", LastName: "Taylor", Email: "testing@thepoofapp.com",
			Scenario:              "assessment=eligible => includesCanceled=true => outcome=REVIEW_CANCELED_SCREENINGS (manual candidate #3)",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Assessment:            utils.Ptr("eligible"),
			Result:                utils.Ptr("clear"),
			IncludesCanceled:      true,
			ExpectedOutcome:       models.ReportOutcomeReviewCanceledScreenings,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Requisition", LastName: "Tester", Email: "testing@thepoofapp.com",
			Scenario:              "assessment=review => includesCanceled => result=nil => => outcome=CANCELED (manual candidate #4)",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Assessment:            utils.Ptr("review"),
			Result:                nil,
			IncludesCanceled:      true,
			ExpectedOutcome:       models.ReportOutcomeCanceled,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Marvin", LastName: "Martian", Email: "testing@thepoofapp.com",
			Scenario:              "assessment=review => includesCanceled => result=clear => outcome=REVIEW_CANCELED_SCREENINGS",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Assessment:            utils.Ptr("review"),
			Result:                utils.Ptr("clear"),
			IncludesCanceled:      true,
			ExpectedOutcome:       models.ReportOutcomeReviewCanceledScreenings,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Lady", LastName: "GaGa", Email: "testing@thepoofapp.com",
			Scenario:              "assessment=review => includesCanceled => result=consider => outcome=REVIEW_CHARGES_AND_CANCELED_SCREENINGS",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Assessment:            utils.Ptr("review"),
			Result:                utils.Ptr("consider"),
			IncludesCanceled:      true,
			ExpectedOutcome:       models.ReportOutcomeReviewChargesAndCanceledScreenings,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Tommy", LastName: "Pickles", Email: "testing@thepoofapp.com",
			Scenario:              "assessment=review => no canceled => outcome=REVIEW_CHARGES",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Assessment:            utils.Ptr("review"),
			Result:                utils.Ptr("consider"),
			IncludesCanceled:      false,
			ExpectedOutcome:       models.ReportOutcomeReviewCharges,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Escalation", LastName: "Tester", Email: "testing@thepoofapp.com",
			Scenario:              "assessment=escalated => includesCanceled=false => outcome=REVIEW_CHARGES",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Assessment:            utils.Ptr("escalated"),
			Result:                utils.Ptr("consider"),
			IncludesCanceled:      false,
			ExpectedOutcome:       models.ReportOutcomeReviewCharges,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Escalation", LastName: "Canceled", Email: "testing@thepoofapp.com",
			Scenario:              "assessment=escalated => includesCanceled + result=clear => outcome=REVIEW_CANCELED_SCREENINGS",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Assessment:            utils.Ptr("escalated"),
			Result:                utils.Ptr("clear"),
			IncludesCanceled:      true,
			ExpectedOutcome:       models.ReportOutcomeReviewCanceledScreenings,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Weird", LastName: "Assessment", Email: "testing@thepoofapp.com",
			Scenario:              "assessment=some_bogus => outcome=UNKNOWN",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Assessment:            utils.Ptr("some_bogus"),
			ExpectedOutcome:       models.ReportOutcomeUnknownStatus,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Clear", LastName: "NoAssessment", Email: "testing@thepoofapp.com",
			Scenario:              "result=clear => includesCanceled=false => outcome=APPROVED => account=ACTIVE",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Result:                utils.Ptr("clear"),
			IncludesCanceled:      false,
			ExpectedOutcome:       models.ReportOutcomeApproved,
			ExpectedAccountStatus: models.AccountStatusActive,
		},
		{
			FirstName: "Clear", LastName: "Canceled", Email: "testing@thepoofapp.com",
			Scenario:              "result=clear => includesCanceled=true => outcome=REVIEW_CANCELED_SCREENINGS",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Result:                utils.Ptr("clear"),
			IncludesCanceled:      true,
			ExpectedOutcome:       models.ReportOutcomeReviewCanceledScreenings,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Consider", LastName: "NoAssessment", Email: "testing@thepoofapp.com",
			Scenario:              "result=consider => includesCanceled=false => outcome=REVIEW_CHARGES",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Result:                utils.Ptr("consider"),
			IncludesCanceled:      false,
			ExpectedOutcome:       models.ReportOutcomeReviewCharges,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Consider", LastName: "PlusCanceled", Email: "testing@thepoofapp.com",
			Scenario:              "result=consider => includesCanceled=true => outcome=REVIEW_CHARGES_AND_CANCELED_SCREENINGS",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Result:                utils.Ptr("consider"),
			IncludesCanceled:      true,
			ExpectedOutcome:       models.ReportOutcomeReviewChargesAndCanceledScreenings,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Unknown", LastName: "ResultVal", Email: "testing@thepoofapp.com",
			Scenario:              "result=some_bogus => outcome=UNKNOWN",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			Result:                utils.Ptr("something_unknown"),
			ExpectedOutcome:       models.ReportOutcomeUnknownStatus,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "Empty", LastName: "NoResult", Email: "testing@thepoofapp.com",
			Scenario:              "No result or assessment => outcome=UNKNOWN",
			WebhookType:           "report.completed",
			ReportStatus:          "complete",
			ExpectedOutcome:       models.ReportOutcomeUnknownStatus,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
		{
			FirstName: "OddStatus", LastName: "Tester", Email: "testing@thepoofapp.com",
			Scenario:              "status=pending => outcome=UNKNOWN (not recognized by switch)",
			WebhookType:           "report.created",
			ReportStatus:          "pending",
			ExpectedOutcome:       models.ReportOutcomeUnknownStatus,
			ExpectedAccountStatus: models.AccountStatusBackgroundCheckPending,
		},
	}

	for _, sc := range scenarios {
		sc := sc
		t.Run(sc.Scenario, func(t *testing.T) {
			testCheckrOutcome(t, sc)
		})
	}
}

func testCheckrOutcome(t *testing.T, c checkrTestCandidate) {
	h.T = t
	ctx := h.Ctx

	// 1) Create a Worker model. The repository's Create method will only insert the core fields.
	worker := &models.Worker{
		ID:            uuid.New(),
		Email:         c.Email,
		PhoneNumber:   "+1555" + utils.RandomNumericString(7),
		TOTPSecret:    "test-secret",
		FirstName:     c.FirstName,
		LastName:      c.LastName,
		StreetAddress: "123 Worker St",
		City:          "Newark",
		State:         "NJ",
		ZipCode:       "07103",
		VehicleYear:   2020,
		VehicleMake:   "Ford",
		VehicleModel:  "F150",
	}

	err := h.WorkerRepo.Create(ctx, worker)
	require.NoError(t, err, "failed to create test worker")
	defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, worker.ID)

	// Generate a JWT for API calls.
	accessToken := h.CreateMobileJWT(worker.ID, "test-device-id", "FAKE-PLAY")

	// 2) The worker starts in AWAITING_PERSONAL_INFO. We must submit this data via the new dedicated endpoint.
	postPayload := dtos.SubmitPersonalInfoRequest{
		StreetAddress: worker.StreetAddress,
		City:          worker.City,
		State:         worker.State,
		ZipCode:       worker.ZipCode,
		VehicleYear:   worker.VehicleYear,
		VehicleMake:   worker.VehicleMake,
		VehicleModel:  worker.VehicleModel,
	}
	bodyBytes, _ := json.Marshal(postPayload)
	req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.WorkerSubmitPersonalInfo, accessToken, bodyBytes, "android", "test-device-id")
	resp := h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode, "Submitting personal info should succeed")

	// 3) Now, for this specific test, we manually advance the worker to the BACKGROUND_CHECK state
	// so that the call to /checkr/invitation is allowed.
	err = h.WorkerRepo.UpdateWithRetry(ctx, worker.ID, func(wToUpdate *models.Worker) error {
		wToUpdate.SetupProgress = models.SetupProgressBackgroundCheck
		return nil
	})
	require.NoError(t, err, "Failed to update worker to BACKGROUND_CHECK progress")

	// 4) POST /api/v1/account/worker/checkr/invitation
	req = h.BuildAuthRequest("POST", h.BaseURL+routes.WorkerCheckrInvitation, accessToken, nil, "android", "test-device-id")
	resp = h.DoRequest(req, http.DefaultClient)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode, "POST /api/v1/account/worker/checkr/invitation should succeed")

	var invResp dtos.CheckrInvitationResponse
	body := h.ReadBody(resp)
	err = json.Unmarshal([]byte(body), &invResp)
	require.NoError(t, err, "failed to parse CheckrInvitationResponse")

	// 5) "invitation.completed"
	wNow, wErr := h.WorkerRepo.GetByID(ctx, worker.ID)
	require.NoError(t, wErr)
	require.NotNil(t, wNow.CheckrInvitationID)
	require.NotNil(t, wNow.CheckrCandidateID)

	invID := *wNow.CheckrInvitationID
	candID := *wNow.CheckrCandidateID

	completeCheckrInvitationCustom(t, c, invID, candID)

	// 6) Wait => Worker => DONE => then => BACKGROUND_CHECK_PENDING
	h.WaitForSetupProgress(worker.ID, models.SetupProgressDone, 5*time.Second)
	h.WaitForAccountStatus(worker.ID, models.AccountStatusBackgroundCheckPending, 5*time.Second)

	// 7) Fire final "report.*" => check outcome
	reportID := "report_" + uuid.NewString()[:8]
	triggerReportEvent(t, c, reportID, candID)

	// 8) Wait for final Worker.CheckrReportOutcome & Worker.AccountStatus
	waitForWorkerOutcomeAndStatus(t, worker.ID, c.ExpectedOutcome, c.ExpectedAccountStatus, 5*time.Second)
	t.Logf("Scenario '%s' => final outcome=%s, accountStatus=%s: PASS", c.Scenario, c.ExpectedOutcome, c.ExpectedAccountStatus)
}

func completeCheckrInvitationCustom(t *testing.T, c checkrTestCandidate, invitationID, candidateID string) {
	h.T = t
	if h.RunWithUI && isManualCandidate(c) {
		t.Logf("[MANUAL MODE] Fill out Checkr invitation for invitationID=%s, candidateID=%s", invitationID, candidateID)
		t.Log("Press Enter when done, or 's' to skip this scenario.")
		var input string
		fmt.Scanln(&input)
		if strings.ToLower(input) == "s" {
			t.Skip("Skipping manual Checkr invitation flow for user input.")
		}
		t.Log("User completed Checkr invitation manually.")
	} else {
		h.CompleteCheckrInvitation(invitationID, candidateID, h.BaseURL+routes.CheckrWebhook)
	}
}

func triggerReportEvent(t *testing.T, c checkrTestCandidate, reportID, candidateID string) {
	h.T = t
	if h.RunWithUI && isManualCandidate(c) {
		t.Logf("[MANUAL MODE] Finalize Checkr report => %s => status=%s => (candidate=%s)", c.WebhookType, c.ReportStatus, candidateID)
		t.Log("Press Enter when done, or 's' to skip this scenario.")
		var input string
		fmt.Scanln(&input)
		if strings.ToLower(input) == "s" {
			t.Skipf("Skipping manual final report event for scenario '%s'", c.Scenario)
		}
		t.Log("User completed the Checkr report manually.")
	} else {
		idSuffix := uuid.NewString()[:6]
		eventMap := map[string]any{
			"id":         fmt.Sprintf("evt_%s_%s", c.WebhookType, idSuffix),
			"object":     "event",
			"type":       c.WebhookType,
			"created_at": "2025-05-01T18:34:00Z",
			"data": map[string]any{
				"object": map[string]any{
					"id":                reportID,
					"object":            "report",
					"status":            c.ReportStatus,
					"candidate_id":      candidateID,
					"includes_canceled": c.IncludesCanceled,
					"metadata": map[string]any{
						"generated_by": h.AppName + "-" + h.UniqueRunnerID + "-" + h.UniqueRunNumber,
					},
				},
			},
		}

		obj := eventMap["data"].(map[string]any)["object"].(map[string]any)
		if c.Adjudication != nil {
			obj["adjudication"] = *c.Adjudication
		}
		if c.Assessment != nil {
			obj["assessment"] = *c.Assessment
		}
		if c.Result != nil {
			obj["result"] = *c.Result
		}

		raw, err := json.MarshalIndent(eventMap, "", "  ")
		require.NoError(t, err, "failed to marshal final report event")

		h.PostCheckrWebhook(h.BaseURL+routes.CheckrWebhook, string(raw))
	}
}

func waitForWorkerOutcomeAndStatus(
	t *testing.T,
	workerID uuid.UUID,
	wantOutcome models.ReportOutcomeType,
	wantStatus models.AccountStatusType,
	maxWait time.Duration,
) {
	h.T = t
	deadline := time.Now().Add(maxWait)
	for time.Now().Before(deadline) {
		w, err := h.WorkerRepo.GetByID(context.Background(), workerID)
		require.NoError(t, err, "failed to retrieve worker in waitForWorkerOutcomeAndStatus")
		if w.CheckrReportOutcome == wantOutcome && w.AccountStatus == wantStatus {
			return
		}
		time.Sleep(time.Second)
	}
	t.Fatalf("Worker %s not at outcome=%s and accountStatus=%s within %v",
		workerID, wantOutcome, wantStatus, maxWait)
}

func isManualCandidate(c checkrTestCandidate) bool {
	fullName := c.FirstName + " " + c.LastName
	_, ok := manualCandidateFullNames[fullName]
	return ok
}
