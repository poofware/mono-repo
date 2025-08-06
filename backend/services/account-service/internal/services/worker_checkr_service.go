// meta-service/services/account-service/internal/services/worker_checkr_service.go
package services

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/account-service/internal/config"
	"github.com/poofware/account-service/internal/constants"
	"github.com/poofware/account-service/internal/dtos"
	"github.com/poofware/account-service/internal/utils/checkr"
	"github.com/poofware/go-models"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
	"github.com/sendgrid/sendgrid-go"
	"github.com/sendgrid/sendgrid-go/helpers/mail" // NEW
)

// how long we remember a webhook event to avoid duplicates
const duplicateThreshold = 60 * time.Minute

// how many times to retry creating the dynamic webhook if we hit a capacity limit
const createWebhookMaxRetries = 1

// The Checkr package slug we always use for Poof gig workers.
const defaultWorkerCheckrPackageSlug = "poof_gig_worker"

// Hard-code the country as "US"
const defaultWorkerCountry = "US"

// CheckrService coordinates background-check invitation logic,
// status checks, and webhook handling for the Worker role.
type CheckrService struct {
	cfg            *config.Config
	client         *checkr.CheckrClient
	repo           repositories.WorkerRepository
	sendgridClient *sendgrid.Client // NEW: For sending alerts
	generatedBy    string

	webhookID       string
	mu              sync.Mutex
	processedEvents map[string]time.Time
}

// NewCheckrService constructs a CheckrService with a configured Checkr client.
func NewCheckrService(cfg *config.Config, repo repositories.WorkerRepository, sg *sendgrid.Client) (*CheckrService, error) {
	client, err := checkr.NewCheckrClient(
		cfg.CheckrAPIKey,
		cfg.LDFlag_CheckrStagingMode,
		3, // maxRetries for 429 rate-limits
		1, // initial backoff
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create Checkr client: %w", err)
	}
	generated := fmt.Sprintf("%s-%s-%s", cfg.AppName, cfg.UniqueRunnerID, cfg.UniqueRunNumber)
	return &CheckrService{
		cfg:             cfg,
		client:          client,
		repo:            repo,
		sendgridClient:  sg, // NEW
		generatedBy:     generated,
		webhookID:       "",
		processedEvents: make(map[string]time.Time),
	}, nil
}

// sendWebhookMissAlert sends an internal notification about a potential webhook failure.
func (s *CheckrService) sendWebhookMissAlert(objectType string, objectID string, workerID uuid.UUID) {
	from := mail.NewEmail(s.cfg.OrganizationName, s.cfg.LDFlag_SendgridFromEmail)
	to := mail.NewEmail("Poof Dev Team", "team@thepoofapp.com")
	subject := fmt.Sprintf("[Webhook Resilience] Missed %s Webhook", objectType)
	plainText := fmt.Sprintf("A %s event for ID %s (Worker ID: %s) was not received. The system self-healed by polling the API. Please investigate potential webhook delivery issues.", objectType, objectID, workerID)
	htmlContent := fmt.Sprintf("<p>%s</p>", plainText)

	msg := mail.NewSingleEmail(from, subject, to, plainText, htmlContent)
	if s.cfg.LDFlag_SendgridSandboxMode {
		ms := mail.NewMailSettings()
		ms.SetSandboxMode(mail.NewSetting(true))
		msg.MailSettings = ms
	}

	_, err := s.sendgridClient.Send(msg)
	if err != nil {
		utils.Logger.WithError(err).Errorf("Failed to send webhook miss alert email for %s ID %s", objectType, objectID)
	} else {
		utils.Logger.Infof("Sent webhook miss alert for %s ID %s.", objectType, objectID)
	}
}

// Start registers a dynamic Checkr webhook if the feature flag is enabled.
func (s *CheckrService) Start(ctx context.Context) error {
	if !s.cfg.LDFlag_DynamicCheckrWebhookEndpoint {
		return nil
	}
	utils.Logger.Info("Registering dynamic Checkr webhook...")

	webhookURL := s.cfg.AppUrl + "/api/v1/account/checkr/webhook"
	body := map[string]any{
		"webhook_url":    webhookURL,
		"include_object": true,
	}

	var attempts int
createAttempt:
	attempts++
	wh, err := s.client.CreateWebhook(ctx, body)
	if err == nil {
		s.webhookID = wh.ID
		utils.Logger.Infof("Successfully registered Checkr webhook ID=%s at %s", wh.ID, wh.WebhookURL)
		return nil
	}

	// if we failed, see if it's a known capacity or duplication conflict
	msg := err.Error()
	utils.Logger.WithError(err).Warn("CreateWebhook call failed")

	switch {
	case strings.Contains(msg, "Allowed webhook API limit exceeded"):
		if attempts > createWebhookMaxRetries {
			return fmt.Errorf("could not create Checkr webhook after removing an existing one: %w", err)
		}
		utils.Logger.Warn("Webhook limit exceeded. Removing an existing webhook and retrying...")

		if removeErr := s.removeAnyWebhookToFreeSlot(ctx, webhookURL); removeErr != nil {
			return fmt.Errorf("failed to remove an existing webhook to free slot: %w", removeErr)
		}
		goto createAttempt

	case strings.Contains(msg, "Url has already been taken"):
		utils.Logger.Warnf("Webhook URL conflict => checking if it is the same as our target %s", webhookURL)
		list, listErr := s.client.ListWebhooks(ctx)
		if listErr != nil {
			return fmt.Errorf("webhook conflict and ListWebhooks failed: %w", listErr)
		}
		for _, w := range list {
			if w.WebhookURL == webhookURL {
				utils.Logger.Infof("Found existing webhook with same URL => using existing ID=%s", w.ID)
				s.webhookID = w.ID
				return nil
			}
		}
		return fmt.Errorf("webhook creation conflict: %w", err)

	default:
		return err
	}
}

// Stop removes the dynamically registered Checkr webhook if we created one.
func (s *CheckrService) Stop(ctx context.Context) error {
	if !s.cfg.LDFlag_DynamicCheckrWebhookEndpoint {
		return nil
	}
	if s.webhookID == "" {
		return nil
	}
	utils.Logger.Infof("Removing dynamic Checkr webhook ID=%s", s.webhookID)
	_, err := s.client.DeleteWebhook(ctx, s.webhookID)
	if err != nil {
		utils.Logger.WithError(err).Errorf("Failed to delete Checkr webhook ID=%s", s.webhookID)
		return err
	}
	utils.Logger.Infof("Checkr webhook ID=%s removed", s.webhookID)
	return nil
}

// removeAnyWebhookToFreeSlot picks any existing webhook to remove if we hit the capacity limit.
func (s *CheckrService) removeAnyWebhookToFreeSlot(ctx context.Context, desiredURL string) error {
	webhooks, err := s.client.ListWebhooks(ctx)
	if err != nil {
		return fmt.Errorf("listing existing webhooks: %w", err)
	}
	if len(webhooks) == 0 {
		return errors.New("no existing webhooks found to remove, cannot free slot")
	}

	var webhookToRemove *checkr.Webhook
	for i := range webhooks {
		if webhooks[i].WebhookURL != desiredURL {
			webhookToRemove = &webhooks[i]
			break
		}
	}
	if webhookToRemove == nil {
		webhookToRemove = &webhooks[0]
	}

	utils.Logger.Warnf("Removing webhook ID=%s at %s to free slot", webhookToRemove.ID, webhookToRemove.WebhookURL)
	_, delErr := s.client.DeleteWebhook(ctx, webhookToRemove.ID)
	if delErr != nil {
		return fmt.Errorf("delete webhook ID=%s: %w", webhookToRemove.ID, delErr)
	}
	utils.Logger.Infof("Removed webhook ID=%s to free slot, reattempting creation...", webhookToRemove.ID)
	return nil
}

// VerifyWebhookSignature checks the X-Checkr-Signature header for authenticity.
func (s *CheckrService) VerifyWebhookSignature(body []byte, providedSig string) bool {
	mac := hmac.New(sha256.New, []byte(s.cfg.CheckrAPIKey))
	mac.Write(body)
	expected := mac.Sum(nil)
	decodedSig, err := hex.DecodeString(providedSig)
	if err != nil {
		return false
	}
	return hmac.Equal(expected, decodedSig)
}

// CreateCheckrInvitation ensures a candidate exists and then creates or reuses an invitation.
func (s *CheckrService) CreateCheckrInvitation(ctx context.Context, workerID uuid.UUID) (string, error) {
	w, err := s.repo.GetByID(ctx, workerID)
	if err != nil {
		return "", err
	}
	if w == nil {
		return "", fmt.Errorf("worker not found, ID=%s", workerID)
	}

	// Enforce normal flow ordering if not allowed out-of-sequence
	if !s.cfg.LDFlag_AllowOOSSetupFlow {
		if w.SetupProgress != models.SetupProgressBackgroundCheck {
			return "", fmt.Errorf(
				"cannot generate Checkr invitation out-of-sequence. Worker %s is at setup_progress=%s",
				w.ID, w.SetupProgress,
			)
		}
	}

	// 1) If no candidate ID, create one
	if w.CheckrCandidateID == nil || *w.CheckrCandidateID == "" {
		cand := checkr.Candidate{
			FirstName: w.FirstName,
			LastName:  w.LastName,
			Email:     w.Email,
			Metadata: map[string]any{
				constants.WebhookMetadataGeneratedByKey: s.generatedBy,
			},
			CustomID: w.ID.String(),
			WorkLocations: []checkr.WorkLocation{
				{
					Country: defaultWorkerCountry,
					State:   w.State,
				},
			},
		}

		utils.Logger.Debugf("Creating new Checkr candidate for workerID: %s", w.ID)
		created, cErr := s.client.CreateCandidate(ctx, cand)
		if cErr != nil {
			return "", fmt.Errorf("failed to create checkr candidate: %w", cErr)
		}

		// concurrency update for candidateID
		candidateID := created.ID
		if err := s.repo.UpdateWithRetry(ctx, w.ID, func(stored *models.Worker) error {
			stored.CheckrCandidateID = &candidateID
			return nil
		}); err != nil {
			return "", err
		}
	}

	// 2) Reuse existing invitation if it hasn't expired
	w2, err2 := s.repo.GetByID(ctx, workerID)
	if err2 != nil {
		return "", err2
	}
	if w2 == nil {
		return "", fmt.Errorf("worker not found on re-check, ID=%s", workerID)
	}
	if w2.CheckrInvitationID != nil && *w2.CheckrInvitationID != "" {
		utils.Logger.Debugf("Found existing Checkr invitation: %s", *w2.CheckrInvitationID)
		inv, invErr := s.client.GetInvitation(ctx, *w2.CheckrInvitationID)
		if invErr == nil && inv.ExpiresAt != nil {
			if time.Now().Before(*inv.ExpiresAt) {
				utils.Logger.Infof("Reusing Checkr invitation %s", inv.ID)
				return inv.InvitationURL, nil
			}
		}
	}

	// 3) Otherwise, create a new invitation
	newInv := checkr.Invitation{
		CandidateID: *w2.CheckrCandidateID,
		Package:     defaultWorkerCheckrPackageSlug,
		WorkLocations: []checkr.WorkLocation{
			{
				Country: defaultWorkerCountry,
				State:   w2.State,
			},
		},
	}
	utils.Logger.Infof("Creating new Checkr invitation for existing candidateID: %s", *w2.CheckrCandidateID)
	inv, err3 := s.client.CreateInvitation(ctx, newInv)
	if err3 != nil {
		return "", fmt.Errorf("failed to create checkr invitation: %w", err3)
	}

	invID := inv.ID
	if err := s.repo.UpdateWithRetry(ctx, w2.ID, func(stored *models.Worker) error {
		stored.CheckrInvitationID = &invID
		return nil
	}); err != nil {
		return "", err
	}

	utils.Logger.Debugf("Stored new Checkr invitationID=%s for candidateID=%s", inv.ID, *w2.CheckrCandidateID)
	return inv.InvitationURL, nil
}

// HandleWebhook parses the incoming Checkr webhook and delegates to the right handler.
func (s *CheckrService) HandleWebhook(ctx context.Context, rawEvent []byte) error {
	var evt checkr.WebhookEvent
	if err := json.Unmarshal(rawEvent, &evt); err != nil {
		return fmt.Errorf("failed to unmarshal top-level Checkr event: %w", err)
	}

	if s.isDuplicateEvent(evt.ID) {
		utils.Logger.Warnf("Skipping duplicate Checkr event: id=%s type=%s", evt.ID, evt.Type)
		return nil
	}

	switch evt.Type {
	case "candidate.created",
		"candidate.id_required",
		"candidate.driver_license_required",
		"candidate.updated",
		"candidate.pre_adverse_action",
		"candidate.post_adverse_action":
		var candObj checkr.CandidateWebhookObj
		if err := json.Unmarshal(evt.Data.Object, &candObj); err == nil {
			return s.handleCandidateEvent(ctx, evt.Type, candObj)
		}
		utils.Logger.WithError(errors.New("parse error")).
			Errorf("Could not parse candidate.* object from event type=%s", evt.Type)

	case "invitation.created",
		"invitation.completed",
		"invitation.expired",
		"invitation.deleted":
		var invObj checkr.InvitationWebhookObj
		if err := json.Unmarshal(evt.Data.Object, &invObj); err == nil {
			return s.handleInvitationEvent(ctx, evt.Type, invObj)
		}
		utils.Logger.WithError(errors.New("parse error")).
			Errorf("Could not parse invitation.* object from event type=%s", evt.Type)

	case "report.created",
		"report.updated",
		"report.canceled",
		"report.upgraded",
		"report.completed",
		"report.suspended",
		"report.resumed",
		"report.disputed",
		"report.pre_adverse_action",
		"report.post_adverse_action",
		"report.engaged":
		var repObj checkr.ReportWebhookObj
		if err := json.Unmarshal(evt.Data.Object, &repObj); err == nil {
			return s.handleReportEvent(ctx, evt.Type, repObj)
		}
		utils.Logger.WithError(errors.New("parse error")).
			Errorf("Could not parse report.* object from event type=%s", evt.Type)

	case "verification.created",
		"verification.completed",
		"verification.processed":
		var verObj checkr.VerificationWebhookObj
		if err := json.Unmarshal(evt.Data.Object, &verObj); err == nil {
			return s.handleVerificationEvent(ctx, evt.Type, verObj)
		}
		utils.Logger.WithError(errors.New("parse error")).
			Errorf("Could not parse verification.* object from event type=%s", evt.Type)

	default:
		utils.Logger.Infof("Unhandled Checkr event type: %s", evt.Type)
	}
	return nil
}

// isDuplicateEvent returns true if we have seen this event ID recently.
func (s *CheckrService) isDuplicateEvent(eventID string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	if t, exists := s.processedEvents[eventID]; exists {
		if now.Sub(t) < duplicateThreshold {
			return true
		}
	}
	s.processedEvents[eventID] = now

	// cleanup old entries
	for id, at := range s.processedEvents {
		if now.Sub(at) > 2*duplicateThreshold {
			delete(s.processedEvents, id)
		}
	}
	return false
}

// handleCandidateEvent processes candidate.* events. We only do special logic for candidate.post_adverse_action.
func (s *CheckrService) handleCandidateEvent(ctx context.Context, eventType string, cand checkr.CandidateWebhookObj) error {
	gby := cand.Metadata[constants.WebhookMetadataGeneratedByKey]
	if gby != s.generatedBy {
		utils.Logger.Infof("Skipping candidate event %s; metadata.generated_by=%q != %q", eventType, gby, s.generatedBy)
		return nil
	}

	utils.Logger.Infof("Candidate event %s => candidateID=%s, adjudication=%s", eventType, cand.ID, cand.Adjudication)

	if eventType == "candidate.post_adverse_action" {
		w, err := s.repo.GetByCheckrCandidateID(ctx, cand.ID)
		if err != nil {
			return err
		}
		if w == nil {
			utils.Logger.Warnf("No worker found for candidateID=%s (candidate.post_adverse_action)", cand.ID)
			return nil
		}

		if err := s.repo.UpdateWithRetry(ctx, w.ID, func(stored *models.Worker) error {
			stored.CheckrReportOutcome = models.ReportOutcomeDisqualified
			return nil
		}); err != nil {
			return err
		}
		utils.Logger.Infof("Worker %s => candidate.post_adverse_action => outcome=DISQUALIFIED", w.ID)
	}
	return nil
}

// handleInvitationEvent handles invitation.* events. We only do special logic for "completed" and "expired".
func (s *CheckrService) handleInvitationEvent(ctx context.Context, eventType string, inv checkr.InvitationWebhookObj) error {
	if inv.CandidateID == "" {
		utils.Logger.Warnf("Invitation event %s missing candidate_id, skipping", eventType)
		return nil
	}

	// Ensure it was generated by us
	cand, err := s.client.GetCandidate(ctx, inv.CandidateID)
	if err != nil {
		utils.Logger.WithError(err).
			Warnf("Failed to fetch candidate for invitation %s event => ignoring", eventType)
		return nil
	}
	gby, _ := cand.Metadata[constants.WebhookMetadataGeneratedByKey]
	if gby != s.generatedBy {
		utils.Logger.Infof("Skipping invitation event %s; unrecognized metadata.generated_by=%q", eventType, gby)
		return nil
	}

	utils.Logger.Infof("Invitation event %s => ID=%s, status=%s", eventType, inv.ID, inv.Status)

	switch eventType {
	case "invitation.completed":
		return s.handleInvitationCompleted(ctx, inv.ID)
	case "invitation.expired":
		return s.handleInvitationExpired(ctx, inv.ID)
	case "invitation.deleted":
		return s.handleInvitationDeleted(ctx, inv.ID)
	default:
		utils.Logger.Infof("Invitation event %s => no additional logic", eventType)
	}
	return nil
}

// handleInvitationDeleted clears the invitation ID from the worker.
func (s *CheckrService) handleInvitationDeleted(ctx context.Context, invitationID string) error {
	if invitationID == "" {
		utils.Logger.Warn("invitation.deleted with blank ID")
		return nil
	}
	w, err := s.repo.GetByCheckrInvitationID(ctx, invitationID)
	if err != nil {
		return err
	}
	if w == nil {
		utils.Logger.Warnf("No worker found with invitationID=%s for invitation.deleted", invitationID)
		return nil
	}

	if err := s.repo.UpdateWithRetry(ctx, w.ID, func(stored *models.Worker) error {
		stored.CheckrInvitationID = nil
		return nil
	}); err != nil {
		return err
	}
	utils.Logger.Infof("Worker %s => invitation.deleted => cleared invitation ID", w.ID)
	return nil
}

func (s *CheckrService) handleInvitationCompleted(ctx context.Context, invitationID string) error {
	if invitationID == "" {
		utils.Logger.Warn("invitation.completed with blank ID")
		return nil
	}
	w, err := s.repo.GetByCheckrInvitationID(ctx, invitationID)
	if err != nil {
		return err
	}
	if w == nil {
		utils.Logger.Warnf("No worker found with invitationID=%s for invitation.completed", invitationID)
		return nil
	}

	// If the worker is in or beyond BACKGROUND_CHECK stage, we can mark them done
	if s.cfg.LDFlag_AllowOOSSetupFlow ||
		(!s.cfg.LDFlag_AllowOOSSetupFlow && w.SetupProgress == models.SetupProgressBackgroundCheck) {

		if err := s.repo.UpdateWithRetry(ctx, w.ID, func(stored *models.Worker) error {
			stored.SetupProgress = models.SetupProgressDone
			stored.AccountStatus = models.AccountStatusBackgroundCheckPending
			stored.CheckrInvitationID = nil
			return nil
		}); err != nil {
			return err
		}

		utils.Logger.Infof("Worker %s => invitation.completed => setup_progress=DONE, account_status=BACKGROUND_CHECK_PENDING, cleared invitation ID", w.ID)
	}
	return nil
}

func (s *CheckrService) handleInvitationExpired(ctx context.Context, invitationID string) error {
	if invitationID == "" {
		utils.Logger.Warn("invitation.expired with blank ID")
		return nil
	}
	w, err := s.repo.GetByCheckrInvitationID(ctx, invitationID)
	if err != nil {
		return err
	}
	if w == nil {
		utils.Logger.Warnf("No worker found with invitationID=%s for invitation.expired", invitationID)
		return nil
	}

	if err := s.repo.UpdateWithRetry(ctx, w.ID, func(stored *models.Worker) error {
		stored.CheckrInvitationID = nil
		return nil
	}); err != nil {
		return err
	}
	utils.Logger.Infof("Worker %s => invitation.expired => cleared invitation ID", w.ID)
	return nil
}

// handleReportEvent processes report.* events. We store the reportID if not already set and update outcome.
func (s *CheckrService) handleReportEvent(ctx context.Context, eventType string, rep checkr.ReportWebhookObj) error {
	if rep.CandidateID == "" {
		utils.Logger.Warnf("Report event %s missing candidate_id => skipping", eventType)
		return nil
	}

	cand, err := s.client.GetCandidate(ctx, rep.CandidateID)
	if err != nil {
		utils.Logger.WithError(err).Warnf("Failed to fetch candidate => ignoring report %s event", eventType)
		return nil
	}
	gby, _ := cand.Metadata[constants.WebhookMetadataGeneratedByKey]
	if gby != s.generatedBy {
		utils.Logger.Infof("Skipping report event %s => unrecognized metadata", eventType)
		return nil
	}

	utils.Logger.Infof("Report event %s => reportID=%s, candidateID=%s, status=%s", eventType, rep.ID, rep.CandidateID, rep.Status)

	w, wErr := s.repo.GetByCheckrCandidateID(ctx, rep.CandidateID)
	if wErr != nil {
		return wErr
	}
	if w == nil {
		utils.Logger.Warnf("No worker found with candidate_id=%s for event %s", rep.CandidateID, eventType)
		return nil
	}

	var engage bool
	if err := s.repo.UpdateWithRetry(ctx, w.ID, func(stored *models.Worker) error {
		// If the worker doesn't already have this reportID, store it
		if stored.CheckrReportID == nil || *stored.CheckrReportID == "" {
			rid := rep.ID
			stored.CheckrReportID = &rid
		}

		// Check if ETA is present; store it
		if rep.EstimatedCompletionTime != nil {
			stored.CheckrReportETA = rep.EstimatedCompletionTime
		}

		switch eventType {
		case "report.created":
			// Just storing the ID if needed

		case "report.completed":
			outcome := s.determineOutcome(&rep)
			stored.CheckrReportOutcome = outcome
			if outcome == models.ReportOutcomeApproved &&
				stored.AccountStatus == models.AccountStatusBackgroundCheckPending {
				stored.AccountStatus = models.AccountStatusActive
				utils.Logger.Infof("report.completed => worker %s => account status set to ACTIVE", stored.ID)
				if rep.Adjudication == nil || *rep.Adjudication != checkr.ReportAdjudicationEngaged {
					engage = true
				}
			}

		case "report.engaged":
			stored.CheckrReportOutcome = models.ReportOutcomeApproved
			if stored.AccountStatus == models.AccountStatusBackgroundCheckPending {
				stored.AccountStatus = models.AccountStatusActive
				utils.Logger.Infof("report.engaged => worker %s => account status set to ACTIVE", stored.ID)
			}

		case "report.canceled":
			stored.CheckrReportOutcome = models.ReportOutcomeCanceled

		case "report.disputed":
			stored.CheckrReportOutcome = models.ReportOutcomeDisputePending

		case "report.pre_adverse_action":
			stored.CheckrReportOutcome = models.ReportOutcomePreAdverseAction

		case "report.post_adverse_action":
			stored.CheckrReportOutcome = models.ReportOutcomeDisqualified

		case "report.suspended":
			stored.CheckrReportOutcome = models.ReportOutcomeSuspended

		case "report.resumed":
			stored.CheckrReportOutcome = models.ReportOutcomeUnsuspended

		default:
			// no extra outcome logic
		}
		return nil
	}); err != nil {
		return err
	}

	if engage {
		_, err := s.client.UpdateReport(ctx, rep.ID, map[string]any{"adjudication": checkr.ReportAdjudicationEngaged})
		if err != nil {
			utils.Logger.WithError(err).Warnf("Failed to engage Checkr report %s", rep.ID)
		} else {
			utils.Logger.Infof("Automatically engaged Checkr report %s", rep.ID)
		}
	}

	return nil
}

// handleVerificationEvent processes verification.* events. Currently logs only.
func (s *CheckrService) handleVerificationEvent(_ context.Context, eventType string, ver checkr.VerificationWebhookObj) error {
	utils.Logger.Infof("Verification event %s => verificationID=%s, reportID=%s", eventType, ver.ID, ver.ReportID)
	return nil
}

// determineOutcome fetches the final Report from Checkr and maps to local outcome, per new fields & logic.
func (s *CheckrService) determineOutcome(rep *checkr.ReportWebhookObj) models.ReportOutcomeType {
	// 1) If the status or includesCanceled forces an immediate outcome
	switch rep.Status {
	case checkr.ReportStatusCanceled:
		return models.ReportOutcomeCanceled
	case checkr.ReportStatusDispute:
		return models.ReportOutcomeDisputePending
	case checkr.ReportStatusSuspended:
		return models.ReportOutcomeSuspended
	case checkr.ReportStatusComplete:
		// Adjudication takes precedence over assessment/result
		if rep.Adjudication != nil && *rep.Adjudication == checkr.ReportAdjudicationPostAdverseAction {
			return models.ReportOutcomeDisqualified
		}
		if rep.Adjudication != nil && *rep.Adjudication == checkr.ReportAdjudicationPreAdverseAction {
			return models.ReportOutcomePreAdverseAction
		}
		if rep.Adjudication != nil && *rep.Adjudication == checkr.ReportAdjudicationEngaged {
			return models.ReportOutcomeApproved
		}

		// Assessment takes next precedence
		if rep.Assessment != nil {
			if *rep.Assessment == checkr.ReportAssessmentEligible {
				if rep.IncludesCanceled {
					return models.ReportOutcomeReviewCanceledScreenings
				} else {
					return models.ReportOutcomeApproved
				}
			} else if *rep.Assessment == checkr.ReportAssessmentReview || *rep.Assessment == checkr.ReportAssessmentEscalated {
				if *rep.Assessment == checkr.ReportAssessmentEscalated {
					utils.Logger.Warn("Report assessment=escalated...this is an Assess Premium feature only, we should not be seeing this, trying to" +
						"handle it as review.")
				}

				if rep.IncludesCanceled {
					if rep.Result == nil {
						// Report was partially completed with no completed reportable screenings
						return models.ReportOutcomeCanceled
					} else if *rep.Result == checkr.ReportResultClear {
						return models.ReportOutcomeReviewCanceledScreenings
					} else if *rep.Result == checkr.ReportResultConsider {
						return models.ReportOutcomeReviewChargesAndCanceledScreenings
					}
				} else {
					return models.ReportOutcomeReviewCharges
				}
			} else {
				utils.Logger.Warnf("Report assessment=%s => unknown value, cannot determine outcome", *rep.Assessment)
				return models.ReportOutcomeUnknownStatus
			}
		}

		// Result takes last precedence
		if rep.Result != nil {
			if *rep.Result == checkr.ReportResultClear {
				if rep.IncludesCanceled {
					return models.ReportOutcomeReviewCanceledScreenings
				} else {
					return models.ReportOutcomeApproved
				}
			} else if *rep.Result == checkr.ReportResultConsider {
				if rep.IncludesCanceled {
					return models.ReportOutcomeReviewChargesAndCanceledScreenings
				} else {
					return models.ReportOutcomeReviewCharges
				}
			} else {
				utils.Logger.Warnf("Report result=%s => unknown value, cannot determine outcome", *rep.Result)
				return models.ReportOutcomeUnknownStatus
			}
		} else {
			utils.Logger.Warn("Report result and assessment are both nil, cannot determine outcome, not sure why we received" +
				" a completed report with no result or assessment...setting report outcome UNKNOWN")
			return models.ReportOutcomeUnknownStatus
		}

	default:
		return models.ReportOutcomeUnknownStatus
	}
}

// GetCheckrStatus returns "complete" if the worker’s SetupProgress==DONE, else "incomplete".
// It now includes a fallback to poll the Checkr API directly if the worker seems stuck.
func (s *CheckrService) GetCheckrStatus(ctx context.Context, workerID uuid.UUID) (dtos.CheckrFlowStatus, error) {
	w, err := s.repo.GetByID(ctx, workerID)
	if err != nil {
		return dtos.CheckrFlowStatusIncomplete, err
	}
	if w == nil {
		return dtos.CheckrFlowStatusIncomplete, nil
	}

	// If worker is already done, no need to check anything else.
	if w.SetupProgress == models.SetupProgressDone && w.AccountStatus != models.AccountStatusBackgroundCheckPending {
		return dtos.CheckrFlowStatusComplete, nil
	}

	// --- Robust Fallback Polling ---

	// 1. Poll INVITATION status if worker is stuck at BACKGROUND_CHECK.
	if w.SetupProgress == models.SetupProgressBackgroundCheck && w.CheckrInvitationID != nil && *w.CheckrInvitationID != "" {
		utils.Logger.Debugf("Polling Checkr API for invitation status for worker %s (invitation ID: %s) due to incomplete state.", w.ID, *w.CheckrInvitationID)
		utils.Logger.Infof("Worker %s is in BACKGROUND_CHECK. Polling invitation %s status from Checkr API.", w.ID, *w.CheckrInvitationID)
		inv, invErr := s.client.GetInvitation(ctx, *w.CheckrInvitationID)
		if invErr != nil {
			utils.Logger.WithError(invErr).Warnf("Failed to poll Checkr invitation status for ID %s", *w.CheckrInvitationID)
		} else if inv.Status == "completed" {
			utils.Logger.Infof("Polling found Checkr invitation %s is 'completed'. Triggering self-healing.", inv.ID)
			if err := s.handleInvitationCompleted(ctx, inv.ID); err != nil {
				utils.Logger.WithError(err).Error("Self-healing failed for completed invitation.")
				return dtos.CheckrFlowStatusIncomplete, nil
			}
			s.sendWebhookMissAlert("Checkr Invitation", inv.ID, w.ID)
			// After successful self-healing, the worker's state is now advanced.
			return dtos.CheckrFlowStatusComplete, nil
		}
	}

	// 2. Poll REPORT status if worker is stuck at BACKGROUND_CHECK_PENDING.
	if w.AccountStatus == models.AccountStatusBackgroundCheckPending && w.CheckrReportID != nil && *w.CheckrReportID != "" {
		utils.Logger.Infof("Worker %s is in BACKGROUND_CHECK_PENDING. Polling report %s status from Checkr API.", w.ID, *w.CheckrReportID)
		report, reportErr := s.client.GetReport(ctx, *w.CheckrReportID)
		if reportErr != nil {
			utils.Logger.WithError(reportErr).Warnf("Failed to poll Checkr report status for ID %s", *w.CheckrReportID)
		} else if report.Status == checkr.ReportStatusComplete {
			utils.Logger.Infof("Polling found Checkr report %s is 'complete'. Triggering self-healing.", report.ID)

			reportWebhookObj := checkr.ReportWebhookObj{
				ID:                      report.ID,
				Object:                  report.Object,
				URI:                     report.URI,
				Status:                  report.Status,
				Result:                  report.Result,
				Adjudication:            report.Adjudication,
				Assessment:              report.Assessment,
				Package:                 report.Package,
				CandidateID:             report.CandidateID,
				IncludesCanceled:        report.IncludesCanceled,
				EstimatedCompletionTime: report.EstimatedTime,
				CreatedAt:               *report.CreatedAt, // Dereference pointer
			}

			if err := s.handleReportEvent(ctx, "report.completed", reportWebhookObj); err != nil {
				utils.Logger.WithError(err).Error("Self-healing failed for completed report.")
				return dtos.CheckrFlowStatusIncomplete, nil
			}
			s.sendWebhookMissAlert("Checkr Report", report.ID, w.ID)

			// The worker's state should now be updated.
			return dtos.CheckrFlowStatusComplete, nil
		}
	}

	// If none of the above conditions were met, the flow is still incomplete.
	return dtos.CheckrFlowStatusIncomplete, nil
}

// GetWorkerCheckrETA returns the worker's CheckrReportETA (if any).
func (s *CheckrService) GetWorkerCheckrETA(ctx context.Context, workerID uuid.UUID) (*time.Time, error) {
	w, err := s.repo.GetByID(ctx, workerID)
	if err != nil {
		return nil, err
	}
	if w == nil {
		return nil, fmt.Errorf("worker not found, ID=%s", workerID)
	}
	return w.CheckrReportETA, nil
}

// GetWorkerCheckrOutcome retrieves the worker and ensures the background-check
// outcome is fully up to date. It performs the same "self healing" polling as
// before but now returns the refreshed *Worker object so callers have a
// consistent view of the worker state.
func (s *CheckrService) GetWorkerCheckrOutcome(
	ctx context.Context,
	workerID uuid.UUID,
) (*models.Worker, error) {

	w, err := s.repo.GetByID(ctx, workerID)
	if err != nil {
		return nil, err
	}
	if w == nil {
		return nil, fmt.Errorf("worker not found, ID=%s", workerID)
	}

	// log the statuses
	utils.Logger.Infof("Worker %s => CheckrReportOutcome=%s, AccountStatus=%s", w.ID,
		w.CheckrReportOutcome, w.AccountStatus)

	utils.Logger.Debugf("Worker %s => CheckrReportID=%s", w.ID, utils.Val(w.CheckrReportID))

	// --- Robust Fallback Polling ---
	if w.CheckrReportOutcome == models.ReportOutcomeUnknownStatus &&
		w.AccountStatus == models.AccountStatusBackgroundCheckPending {

		// If we don't have a report ID yet, attempt to fetch it via the candidate
		if (w.CheckrReportID == nil || *w.CheckrReportID == "") &&
			w.CheckrCandidateID != nil && *w.CheckrCandidateID != "" {

			utils.Logger.Infof("Outcome unknown for worker %s with no report ID. Polling candidate %s from Checkr API.", w.ID, *w.CheckrCandidateID)
			cand, candErr := s.client.GetCandidate(ctx, *w.CheckrCandidateID)
			if candErr != nil {
				utils.Logger.WithError(candErr).Warnf("Failed to poll Checkr candidate for ID %s", *w.CheckrCandidateID)
			} else if len(cand.ReportIDs) > 0 {
				// Use the most recent report ID
				rid := cand.ReportIDs[len(cand.ReportIDs)-1]
				if err := s.repo.UpdateWithRetry(ctx, w.ID, func(stored *models.Worker) error {
					stored.CheckrReportID = &rid
					return nil
				}); err == nil {
					w.CheckrReportID = &rid
				}
			}
		}

		if w.CheckrReportID != nil && *w.CheckrReportID != "" {
			utils.Logger.Debugf("Polling Checkr API for report outcome for worker %s (report ID: %s) due to UNKNOWN status.", w.ID, *w.CheckrReportID)
			utils.Logger.Infof("Outcome unknown for worker %s. Polling report %s from Checkr API.", w.ID, *w.CheckrReportID)
			report, reportErr := s.client.GetReport(ctx, *w.CheckrReportID)

			if reportErr != nil {
				utils.Logger.WithError(reportErr).Warnf("Failed to poll Checkr report for ID %s", *w.CheckrReportID)
			} else if report.Status == checkr.ReportStatusComplete {
				utils.Logger.Infof("Polling found Checkr report %s is 'complete'. Triggering self-healing.", report.ID)

				reportWebhookObj := checkr.ReportWebhookObj{
					ID:                      report.ID,
					Object:                  report.Object,
					URI:                     report.URI,
					Status:                  report.Status,
					Result:                  report.Result,
					Adjudication:            report.Adjudication,
					Assessment:              report.Assessment,
					Package:                 report.Package,
					CandidateID:             report.CandidateID,
					IncludesCanceled:        report.IncludesCanceled,
					EstimatedCompletionTime: report.EstimatedTime,
					CreatedAt:               *report.CreatedAt,
				}

				if err := s.handleReportEvent(ctx, "report.completed", reportWebhookObj); err != nil {
					utils.Logger.WithError(err).Error("Self-healing failed for completed report.")
				} else {
					s.sendWebhookMissAlert("Checkr Report", report.ID, w.ID)
				}

				// Reload worker for updated outcome
				w, _ = s.repo.GetByID(ctx, workerID)
			}
		}
	}

	// Return the fully refreshed worker
	return w, nil
}

// NEW: CreateSessionToken generates a short-lived token for the Checkr Web SDK.
func (s *CheckrService) CreateSessionToken(ctx context.Context, workerID uuid.UUID) (string, error) {
	w, err := s.repo.GetByID(ctx, workerID)
	if err != nil {
		return "", err
	}
	if w == nil {
		return "", fmt.Errorf("worker not found, ID=%s", workerID)
	}
	if w.CheckrCandidateID == nil || *w.CheckrCandidateID == "" {
		return "", fmt.Errorf("worker %s has no Checkr Candidate ID", workerID)
	}

	token, err := s.client.CreateSessionToken(ctx, *w.CheckrCandidateID)
	if err != nil {
		return "", fmt.Errorf("failed to create Checkr session token: %w", err)
	}
	return token.Token, nil
}
