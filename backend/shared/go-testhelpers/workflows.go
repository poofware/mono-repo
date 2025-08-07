package testhelpers

import (
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/stretchr/testify/require"
	stripe "github.com/stripe/stripe-go/v82"
)

// WaitForSetupProgress polls the DB until a worker's SetupProgress matches the target.
func (h *TestHelper) WaitForSetupProgress(workerID uuid.UUID, target models.SetupProgressType, maxWait time.Duration) {
	deadline := time.Now().Add(maxWait)
	for time.Now().Before(deadline) {
		w, err := h.WorkerRepo.GetByID(h.Ctx, workerID)
		require.NoError(h.T, err)
		if w.SetupProgress == target {
			return
		}
		time.Sleep(500 * time.Millisecond)
	}
	h.T.Fatalf("Worker %s did not reach SetupProgress=%s within %v", workerID, target, maxWait)
}

// WaitForAccountStatus polls the DB until a worker's AccountStatus matches the target.
func (h *TestHelper) WaitForAccountStatus(workerID uuid.UUID, target models.AccountStatusType, maxWait time.Duration) {
	deadline := time.Now().Add(maxWait)
	for time.Now().Before(deadline) {
		w, err := h.WorkerRepo.GetByID(h.Ctx, workerID)
		require.NoError(h.T, err)
		if w.AccountStatus == target {
			return
		}
		time.Sleep(500 * time.Millisecond)
	}
	h.T.Fatalf("Worker %s did not reach AccountStatus=%s within %v", workerID, target, maxWait)
}

// CompleteIdentityVerificationSession posts a mock "identity.verification_session.verified" event.
func (h *TestHelper) CompleteIdentityVerificationSession(workerID uuid.UUID, webhookURL string) {
	h.T.Log("Running Identity automation => sending identity.verification_session.verified...")
	eventPayload := fmt.Sprintf(`{
      "id": "evt_1FAKEID_VERIFIED_%s",
      "object": "event",
      "created": %d,
      "api_version": "%s",
      "livemode": false,
      "type": "identity.verification_session.verified",
      "data": {
        "object": {
          "id": "vs_1FAKE_%s",
          "object": "identity.verification_session",
          "client_reference_id": "%s",
          "metadata": { "generated_by": "%s-%s-%s", "account_type": "worker" },
          "status": "verified"
        }
      }
    }`, uuid.NewString()[:6], time.Now().Unix(), stripe.APIVersion, uuid.NewString()[:6], workerID, h.AppName, h.UniqueRunnerID, h.UniqueRunNumber)
	h.PostStripeWebhook(webhookURL, eventPayload)
	h.T.Log("Mocked identity.verification_session.verified event posted.")
}

// CompleteExpressKYC posts a mock "account.updated" event to simulate KYC completion.
func (h *TestHelper) CompleteExpressKYC(accountID, webhookURL string) {
	h.T.Log("Running Connect automation => sending account.updated with real account ID...")
	eventPayload := fmt.Sprintf(`{
      "id": "evt_1FAKEACCTUPDATED_%s",
      "object": "event",
      "created": %d,
      "api_version": "%s",
      "livemode": false,
      "type": "account.updated",
      "data": {
        "object": {
          "id": "%s",
          "object": "account",
          "details_submitted": true,
          "charges_enabled": true,
          "metadata": { "generated_by": "%s-%s-%s", "account_type": "worker" }
        }
      }
    }`, uuid.NewString()[:6], time.Now().Unix(), stripe.APIVersion, accountID, h.AppName, h.UniqueRunnerID, h.UniqueRunNumber)
	h.PostStripeWebhook(webhookURL, eventPayload)
	h.T.Log("Mocked account.updated event posted.")
}

// CompleteCheckrInvitation posts a mock "invitation.completed" event.
func (h *TestHelper) CompleteCheckrInvitation(invitationID, candidateID, webhookURL string) {
	h.T.Log("Running Checkr automation => sending invitation.completed...")
	payload := fmt.Sprintf(`{
      "id": "evt_invitation_completed_%s",
      "object": "event",
      "type": "invitation.completed",
      "created_at": "%s",
      "data": { "object": { "id": "%s", "status": "completed", "candidate_id": "%s", "metadata": { "generated_by": "%s-%s-%s" } } }
    }`, uuid.NewString()[:6], time.Now().UTC().Format(time.RFC3339), invitationID, candidateID, h.AppName, h.UniqueRunnerID, h.UniqueRunNumber)
	h.PostCheckrWebhook(webhookURL, payload)
	h.T.Log("Mocked Checkr invitation.completed event posted.")
}

// CompleteCheckrReport posts a mock "report.completed" event with a 'clear' result.
func (h *TestHelper) CompleteCheckrReport(reportID, candidateID, webhookURL string) {
	h.T.Log("Running Checkr automation => sending report.completed => clear...")
	payload := fmt.Sprintf(`{
      "id": "evt_report_completed_%s",
      "object": "event",
      "type": "report.completed",
      "created_at": "%s",
      "data": { "object": { "id": "%s", "status": "complete", "result": "clear", "candidate_id": "%s", "metadata": { "generated_by": "%s-%s-%s" } } }
    }`, uuid.NewString()[:6], time.Now().UTC().Format(time.RFC3339), reportID, candidateID, h.AppName, h.UniqueRunnerID, h.UniqueRunNumber)
	h.PostCheckrWebhook(webhookURL, payload)
	h.T.Log("Mocked Checkr report.completed event posted.")
}
