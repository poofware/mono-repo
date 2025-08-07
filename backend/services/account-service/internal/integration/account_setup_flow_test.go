//go:build (dev_test || staging_test) && integration

package integration

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/poofware/mono-repo/backend/services/account-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/services/account-service/internal/routes"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
)

var smsRepo repositories.WorkerSMSVerificationRepository // This is specific to this test file

// TestIntegrationStripe simulates Identity => Connect => (optionally) Checkr
func TestIntegrationStripe(t *testing.T) {
	h.T = t // Update testing.T for the current test
	ctx := h.Ctx

	smsRepo = repositories.NewWorkerSMSVerificationRepository(h.DB)

	// 1) Create a new test worker (relies on DB defaults for status)
	worker := &models.Worker{
		ID:          uuid.New(),
		Email:       "1testing@thepoofapp.com",
		PhoneNumber: "+15550001111",
		TOTPSecret:  "test-secret",
		FirstName:   "Integration",
		LastName:    "Tester",
	}
	err := h.WorkerRepo.Create(ctx, worker)
	require.NoError(t, err, "failed to create test worker")

	defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, worker.ID)

	// 2) Make JWT (mobile style)
	accessToken := h.CreateMobileJWT(worker.ID, "test-device-id", "FAKE-PLAY")

	//-----------------------------------------------------------
	// 0) PERSONAL INFO
	//-----------------------------------------------------------
	t.Run("PersonalInfoFlow", func(t *testing.T) {
		h.T = t
		// 1) Assert worker starts in AWAITING_PERSONAL_INFO state.
		w, err := h.WorkerRepo.GetByID(ctx, worker.ID)
		require.NoError(t, err)
		require.Equal(t, models.SetupProgressAwaitingPersonalInfo, w.SetupProgress)

		_, err = h.DB.Exec(ctx, `UPDATE workers SET on_waitlist=false WHERE id=$1`, worker.ID)
		require.NoError(t, err)

		// 2) Post with address and vehicle information.
		postPayload := dtos.SubmitPersonalInfoRequest{
			StreetAddress: "123 Main St",
			City:          "Anytown",
			State:         "CA",
			ZipCode:       "90210",
			VehicleYear:   2022,
			VehicleMake:   "Honda",
			VehicleModel:  "Civic",
		}
		bodyBytes, _ := json.Marshal(postPayload)

		req := h.BuildAuthRequest(http.MethodPost, h.BaseURL+routes.WorkerSubmitPersonalInfo, accessToken, bodyBytes, "android", "test-device-id")
		resp := h.DoRequest(req, http.DefaultClient)
		defer resp.Body.Close()
		require.Equal(t, http.StatusOK, resp.StatusCode)

		// 3) Assert worker is now in ID_VERIFY state.
		wUpdated, err := h.WorkerRepo.GetByID(ctx, worker.ID)
		require.NoError(t, err)
		require.Equal(t, models.SetupProgressIDVerify, wUpdated.SetupProgress, "Worker should transition to ID_VERIFY after submitting personal info")

		t.Logf("Personal info flow completed, worker is now in %s", wUpdated.SetupProgress)
	})

	//-----------------------------------------------------------
	// A) IDENTITY
	//-----------------------------------------------------------
	t.Run("IdentityFlow", func(t *testing.T) {
		h.T = t
		// 1) GET /api/v1/account/worker/stripe/identity-flow => returns identityFlowURL
		req, _ := http.NewRequest(http.MethodGet, h.BaseURL+routes.WorkerStripeIdentityFlowURL, nil)
		req.Header.Set("Authorization", "Bearer "+accessToken)
		req.Header.Set("X-Platform", "android")
		req.Header.Set("X-Device-ID", "test-device-id")
		req.Header.Set("X-Device-Integrity", "FAKE_INTEGRITY_TOKEN")

		resp, err := http.DefaultClient.Do(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		require.Equal(t, http.StatusOK, resp.StatusCode)
		var identResp dtos.StripeIdentityFlowURLResponse
		body, _ := io.ReadAll(resp.Body)
		err = json.Unmarshal(body, &identResp)
		require.NoError(t, err)
		require.NotEmpty(t, identResp.IdentityFlowURL, "Should return an identity flow URL")

		t.Logf("Identity flow URL Received: %s", identResp.IdentityFlowURL)

		// 2) Immediately check /identity-flow-status => expect 200, status=incomplete
		checkFlowReq, _ := http.NewRequest(http.MethodGet, h.BaseURL+routes.WorkerStripeIdentityFlowStatus, nil)
		checkFlowReq.Header.Set("Authorization", "Bearer "+accessToken)
		checkFlowReq.Header.Set("X-Platform", "android")
		checkFlowReq.Header.Set("X-Device-ID", "test-device-id")
		checkFlowReq.Header.Set("X-Device-Integrity", "FAKE_INTEGRITY_TOKEN")

		checkResp, err := http.DefaultClient.Do(checkFlowReq)
		require.NoError(t, err)
		defer checkResp.Body.Close()
		require.Equal(t, http.StatusOK, checkResp.StatusCode)

		var flowStatus dtos.StripeFlowStatusResponse
		checkBody, _ := io.ReadAll(checkResp.Body)
		err = json.Unmarshal(checkBody, &flowStatus)
		require.NoError(t, err)
		require.Equal(t, dtos.StripeFlowStatusIncomplete, flowStatus.Status, "Flow should be incomplete initially")

		// 3) Complete the identity verification session
		webhookURL := h.BaseURL + routes.AccountStripeWebhook
		if h.RunWithUI {
			t.Log("Waiting for user to complete Identity flow in their browser...")
			t.Log("Press Enter to continue once done, or type 's' then Enter to skip:")
			var input string
			fmt.Scanln(&input)
			if strings.ToLower(input) == "s" {
				t.Skip("User chose to skip the Identity flow.")
			}
			t.Log("User completed the Identity flow.")
		} else {
			h.CompleteIdentityVerificationSession(worker.ID, webhookURL)
		}

		// 4) Wait for Worker => ACH_PAYMENT_ACCOUNT_SETUP
		h.WaitForSetupProgress(worker.ID, models.SetupProgressAchPaymentAccountSetup, 5*time.Second)

		// 5) Now check /identity-flow-status => expect complete
		checkResp2, err := http.DefaultClient.Do(checkFlowReq)
		require.NoError(t, err)
		defer checkResp2.Body.Close()
		require.Equal(t, http.StatusOK, checkResp2.StatusCode)

		var flowStatus2 dtos.StripeFlowStatusResponse
		checkBody2, _ := io.ReadAll(checkResp2.Body)
		err = json.Unmarshal(checkBody2, &flowStatus2)
		require.NoError(t, err)
		require.Equal(t, dtos.StripeFlowStatusComplete, flowStatus2.Status)

		t.Logf("Identity flow status: %s", flowStatus2.Status)
	})

	//-----------------------------------------------------------
	// B) CONNECT
	//-----------------------------------------------------------
	t.Run("ConnectFlow", func(t *testing.T) {
		h.T = t
		// 1) GET /api/v1/account/worker/stripe/connect-flow => returns connectFlowURL
		req, _ := http.NewRequest(http.MethodGet, h.BaseURL+routes.WorkerStripeConnectFlowURL, nil)
		req.Header.Set("Authorization", "Bearer "+accessToken)
		req.Header.Set("X-Platform", "android")
		req.Header.Set("X-Device-ID", "test-device-id")
		req.Header.Set("X-Device-Integrity", "FAKE_INTEGRITY_TOKEN")

		resp, err := http.DefaultClient.Do(req)
		require.NoError(t, err)
		defer resp.Body.Close()
		require.Equal(t, http.StatusOK, resp.StatusCode)

		var connectResp dtos.StripeConnectFlowURLResponse
		body, _ := io.ReadAll(resp.Body)
		err = json.Unmarshal(body, &connectResp)
		require.NoError(t, err)
		require.NotEmpty(t, connectResp.ConnectFlowURL)

		t.Logf("Connect flow URL Received: %s", connectResp.ConnectFlowURL)

		// 2) Check we have an acct in DB
		accID := h.FetchWorkerAccountID(worker.ID)
		require.NotEmpty(t, accID, "Expected a Stripe Connect account ID in DB")

		// 3) Check /connect-flow-status => expect incomplete
		checkFlowReq, _ := http.NewRequest(http.MethodGet, h.BaseURL+routes.WorkerStripeConnectFlowStatus, nil)
		checkFlowReq.Header.Set("Authorization", "Bearer "+accessToken)
		checkFlowReq.Header.Set("X-Platform", "android")
		checkFlowReq.Header.Set("X-Device-ID", "test-device-id")
		checkFlowReq.Header.Set("X-Device-Integrity", "FAKE_INTEGRITY_TOKEN")

		confResp, err := http.DefaultClient.Do(checkFlowReq)
		require.NoError(t, err)
		defer confResp.Body.Close()
		require.Equal(t, http.StatusOK, confResp.StatusCode)

		var connectFlowStatus dtos.StripeFlowStatusResponse
		confBody, _ := io.ReadAll(confResp.Body)
		err = json.Unmarshal(confBody, &connectFlowStatus)
		require.NoError(t, err)
		require.Equal(t, dtos.StripeFlowStatusIncomplete, connectFlowStatus.Status)

		// 4) Complete the Express flow
		webhookURL := h.BaseURL + routes.AccountStripeWebhook
		if h.RunWithUI {
			t.Log("Waiting for user to complete the Connect flow in browser...")
			t.Log("Press Enter to continue once done, or type 's' then Enter to skip:")
			var input string
			fmt.Scanln(&input)
			if strings.ToLower(input) == "s" {
				t.Skip("User chose to skip the Connect flow.")
			}
			t.Log("User completed the Connect flow.")
		} else {
			h.CompleteExpressKYC(accID, webhookURL)
		}

		// 5) Wait for DB => SetupProgress=BACKGROUND_CHECK
		h.WaitForSetupProgress(worker.ID, models.SetupProgressBackgroundCheck, 5*time.Second)

		// 6) check /connect-flow-status => now expect complete
		confResp2, err := http.DefaultClient.Do(checkFlowReq)
		require.NoError(t, err)
		defer confResp2.Body.Close()
		require.Equal(t, http.StatusOK, confResp2.StatusCode)

		var connectFlowStatus2 dtos.StripeFlowStatusResponse
		confBody2, _ := io.ReadAll(confResp2.Body)
		err = json.Unmarshal(confBody2, &connectFlowStatus2)
		require.NoError(t, err)
		require.Equal(t, dtos.StripeFlowStatusComplete, connectFlowStatus2.Status)

		t.Logf("Connect flow status: %s", connectFlowStatus2.Status)
	})

	//-----------------------------------------------------------
	// C) CHECKR => final background-check step
	//-----------------------------------------------------------
	t.Run("CheckrFlow", func(t *testing.T) {
		h.T = t
		if h.CheckrAPIKey == "" {
			t.Skip("CHECKR_API_KEY not configured, skipping CheckrFlow test.")
		}

		// 1) POST /api/v1/account/worker/checkr/invitation => returns invitationURL
		req, _ := http.NewRequest(http.MethodPost, h.BaseURL+routes.WorkerCheckrInvitation, nil)
		req.Header.Set("Authorization", "Bearer "+accessToken)
		req.Header.Set("X-Platform", "android")
		req.Header.Set("X-Device-ID", "test-device-id")
		req.Header.Set("X-Device-Integrity", "FAKE_INTEGRITY_TOKEN")
		req.Header.Set("Content-Type", "application/json")

		resp, err := http.DefaultClient.Do(req)
		require.NoError(t, err)
		defer resp.Body.Close()
		require.Equal(t, http.StatusOK, resp.StatusCode)

		var invResp dtos.CheckrInvitationResponse
		body, _ := io.ReadAll(resp.Body)
		err = json.Unmarshal(body, &invResp)
		require.NoError(t, err, "Failed to parse checkr invitation response")

		t.Logf("Checkr Invitation URL Received: %s", invResp.InvitationURL)

		// 2) Re-fetch worker => check checkr_invitation_id + candidate_id
		wNow, err := h.WorkerRepo.GetByID(ctx, worker.ID)
		require.NoError(t, err)
		require.NotNil(t, wNow.CheckrInvitationID, "Expected checkr_invitation_id in worker record")
		require.NotNil(t, wNow.CheckrCandidateID, "Expected checkr_candidate_id in worker record")
		require.Equal(t, models.AccountStatusIncomplete, wNow.AccountStatus)

		// 3) "invitation.completed"
		webhookURL := h.BaseURL + routes.CheckrWebhook
		if h.RunWithUI {
			t.Log("Manual Checkr invitation flow. Press Enter when done, or 's' to skip.")
			var input string
			fmt.Scanln(&input)
			if strings.ToLower(input) == "s" {
				t.Skip("Skipping manual Checkr invitation flow.")
			}
			t.Log("User completed Checkr invitation manually.")
		} else {
			h.CompleteCheckrInvitation(*wNow.CheckrInvitationID, *wNow.CheckrCandidateID, webhookURL)
		}

		// Wait => setupProgress => DONE => then => BACKGROUND_CHECK_PENDING
		h.WaitForSetupProgress(worker.ID, models.SetupProgressDone, 5*time.Second)

		// check if the invitation was cleared
		wNow2, err := h.WorkerRepo.GetByID(ctx, worker.ID)
		require.NoError(t, err)
		require.Nil(t, wNow2.CheckrInvitationID, "Expected checkr_invitation_id to be nil after completion")

		t.Logf("Checkr invitation completed, ID=%s", *wNow.CheckrInvitationID)

		// check invitation ID changes if re-inviting
		resp, err = http.DefaultClient.Do(req)
		require.NoError(t, err)
		defer resp.Body.Close()
		require.Equal(t, http.StatusOK, resp.StatusCode)

		wNow3, err := h.WorkerRepo.GetByID(ctx, worker.ID)
		require.NoError(t, err)
		require.NotNil(t, wNow3.CheckrInvitationID, "Expected checkr_invitation_id to be not nil after second invitation")
		require.NotEqual(t, *wNow.CheckrInvitationID, *wNow3.CheckrInvitationID, "Expected new invitation_id to differ from the old one")

		if !h.RunWithUI {
			etaID := "report_" + uuid.NewString()[:6]
			etaTime := time.Now().Add(48 * time.Hour).UTC().Format(time.RFC3339)
			mockReportCreatedWithETA(t, etaID, *wNow.CheckrCandidateID, etaTime)

			t.Run("CheckrETA", func(t *testing.T) {
				h.T = t
				waitForCheckrETA(t, accessToken, 30*time.Second)
			})
		}

		// 4) "report.completed" => "clear" => account_status => ACTIVE
		newReportID := "report_" + uuid.NewString()[:8]
		if h.RunWithUI {
			t.Log("Manual Checkr report completion. Press Enter when done, or 's' to skip.")
			var input string
			fmt.Scanln(&input)
			if strings.ToLower(input) == "s" {
				t.Skip("Skipping manual Checkr report flow.")
			}
			t.Log("User completed Checkr report manually.")
		} else {
			h.CompleteCheckrReport(newReportID, *wNow.CheckrCandidateID, webhookURL)
		}

		// Wait => accountStatus => ACTIVE
		h.WaitForAccountStatus(worker.ID, models.AccountStatusActive, 5*time.Second)

		// 5) GET /api/v1/account/worker/checkr/status => "complete"
		stReq, _ := http.NewRequest(http.MethodGet, h.BaseURL+routes.WorkerCheckrStatus, nil)
		stReq.Header.Set("Authorization", "Bearer "+accessToken)
		stReq.Header.Set("X-Platform", "android")
		stReq.Header.Set("X-Device-ID", "test-device-id")
		stReq.Header.Set("X-Device-Integrity", "FAKE_INTEGRITY_TOKEN")

		stResp, err := http.DefaultClient.Do(stReq)
		require.NoError(t, err)
		defer stResp.Body.Close()
		require.Equal(t, http.StatusOK, stResp.StatusCode)

		var stBody dtos.CheckrStatusResponse
		stBytes, _ := io.ReadAll(stResp.Body)
		err = json.Unmarshal(stBytes, &stBody)
		require.NoError(t, err)
		require.Equal(t, dtos.CheckrFlowStatusComplete, stBody.Status, "Expected final checkr status=complete")
	})
}

func mockReportCreatedWithETA(t *testing.T, reportID, candidateID, etaISO string) {
	h.T = t
	t.Logf("Mocking report.created with ETA=%s", etaISO)
	payload := fmt.Sprintf(`{
		"id": "evt_report_created_eta",
		"object": "event",
		"type": "report.created",
		"created_at": "2025-04-20T17:00:00Z",
		"data": { "object": { "id": "%s", "status": "pending", "candidate_id": "%s", "estimated_completion_time": "%s", "metadata": { "generated_by": "%s-%s-%s" } } }
	}`, reportID, candidateID, etaISO, h.AppName, h.UniqueRunnerID, h.UniqueRunNumber)
	h.PostCheckrWebhook(h.BaseURL+routes.CheckrWebhook, payload)
}

func waitForCheckrETA(t *testing.T, accessToken string, maxWait time.Duration) {
	h.T = t
	deadline := time.Now().Add(maxWait)
	for time.Now().Before(deadline) {
		url := fmt.Sprintf("%s%s?time_zone=America/Los_Angeles", h.BaseURL, routes.WorkerCheckrReportETA)
		req := h.BuildAuthRequest(http.MethodGet, url, accessToken, nil, "android", "test-device-id")

		resp := h.DoRequest(req, http.DefaultClient)
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			time.Sleep(time.Second)
			continue
		}

		var etaRes dtos.CheckrETAResponse
		data := h.ReadBody(resp)
		if err := json.Unmarshal([]byte(data), &etaRes); err != nil {
			time.Sleep(time.Second)
			continue
		}
		if etaRes.ReportETA != nil {
			t.Logf("Checkr ETA is now: %s", *etaRes.ReportETA)
			return
		}
		time.Sleep(time.Second)
	}
	t.Fatalf("Report ETA never appeared within %v", maxWait)
}
