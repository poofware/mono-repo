// meta-service/services/account-service/internal/services/worker_stripe_service.go
package services

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"sort"

	"github.com/google/uuid"
	"github.com/poofware/account-service/internal/config"
	"github.com/poofware/account-service/internal/constants"
	"github.com/poofware/account-service/internal/routes"
	"github.com/poofware/go-models"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"

	"github.com/poofware/account-service/internal/dtos"
	stripe "github.com/stripe/stripe-go/v82"
	"github.com/stripe/stripe-go/v82/account"
	"github.com/stripe/stripe-go/v82/accountlink"
	verificationsession "github.com/stripe/stripe-go/v82/identity/verificationsession"
	"github.com/stripe/stripe-go/v82/webhookendpoint"
)

const (
	createStripeWebhookMaxRetries = 3
	kindKey                       = "kind"
	kindPlatform                  = "platform"
	kindConnect                   = "connect"
)

var (
	platformEvents = []string{
		"identity.verification_session.created",
		"identity.verification_session.requires_input",
		"identity.verification_session.verified",
		"identity.verification_session.canceled",
	}
	connectEvents = []string{
		"account.updated",
		"capability.updated",
		"payment_intent.created",
	}
)

// WorkerStripeService orchestrates Stripe Connect & Identity flows
type WorkerStripeService struct {
	Cfg         *config.Config
	repo        repositories.WorkerRepository
	generatedBy string
	webhookPlatformID string
	webhookConnectID  string
	webhookPlatformSecret string
	webhookConnectSecret  string
	mu                sync.Mutex
}

func NewWorkerStripeService(cfg *config.Config, repo repositories.WorkerRepository) *WorkerStripeService {
	stripe.Key = cfg.StripeSecretKey

	generated := fmt.Sprintf("%s-%s-%s", cfg.AppName, cfg.UniqueRunnerID, cfg.UniqueRunNumber)
	return &WorkerStripeService{
		Cfg:         cfg,
		repo:        repo,
		generatedBy: generated,
	}
}

// ----------------------------------------------------------------------
// Dynamic webhook-endpoint management (similar to CheckrService)
// ----------------------------------------------------------------------

func (s *WorkerStripeService) PlatformWebhookSecret() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.webhookPlatformSecret
}

func (s *WorkerStripeService) ConnectWebhookSecret() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.webhookConnectSecret
}

func (s *WorkerStripeService) Start(ctx context.Context) error {
	if !s.Cfg.LDFlag_DynamicStripeWebhookEndpoint {
		s.webhookPlatformSecret = s.Cfg.StripeWebhookSecret
		s.webhookConnectSecret = s.Cfg.StripeWebhookSecret
		return nil
	}
	dest := s.Cfg.AppUrl + routes.AccountStripeWebhook

	pID, pSecret, err := s.ensureStripeEndpoint(ctx, dest, platformEvents, false)
	if err != nil {
		return err
	}
	cID, cSecret, err := s.ensureStripeEndpoint(ctx, dest, connectEvents, true)
	if err != nil {
		return err
	}

	s.mu.Lock()
	s.webhookPlatformID = pID
	s.webhookConnectID = cID
	s.webhookPlatformSecret = pSecret
	s.webhookConnectSecret = cSecret
	s.mu.Unlock()

	return nil
}

func (s *WorkerStripeService) Stop(ctx context.Context) error {
	if !s.Cfg.LDFlag_DynamicStripeWebhookEndpoint {
		return nil
	}
	s.mu.Lock()
	ids := []string{s.webhookPlatformID, s.webhookConnectID}
	s.mu.Unlock()

	for _, id := range ids {
		if id == "" {
			continue
		}
		delParams := &stripe.WebhookEndpointParams{}
		delParams.Params.Context = ctx
		if _, err := webhookendpoint.Del(id, delParams); err != nil {
			utils.Logger.WithError(err).Warnf("Failed to delete Stripe webhook endpoint %s", id)
		} else {
			utils.Logger.Infof("Deleted Stripe webhook endpoint %s", id)
		}
	}
	return nil
}

// ensureStripeEndpoint deletes any existing matching endpoint (URL+kind) or
// endpoints lacking kind metadata, then unconditionally creates a new one.
func (s *WorkerStripeService) ensureStripeEndpoint(
	ctx context.Context,
	url string,
	events []string,
	connect bool,
) (string, string, error) {

	kind := kindPlatform
	if connect {
		kind = kindConnect
	}

	// 1) Remove all endpoints with the same URL and kind (or missing kind)
	if err := s.cleanupStaleEndpoints(ctx, url, kind); err != nil {
		return "", "", err
	}

	// 2) Create a fresh endpoint
	create := &stripe.WebhookEndpointParams{
		URL:           stripe.String(url),
		EnabledEvents: toPtrSlice(events),
		Metadata: map[string]string{
			kindKey: kind,
		},
		APIVersion: stripe.String(stripe.APIVersion),
	}
	create.Params.Context = ctx
	if connect {
		create.Connect = stripe.Bool(true)
	}

	var tries int
createAttempt:
	tries++
	ep, err := webhookendpoint.New(create)
	if err == nil {
		utils.Logger.Infof("Created Stripe webhook endpoint %s (kind=%s)", ep.ID, kind)
		return ep.ID, ep.Secret, nil
	}

	switch {
	case limitErr(err):
		if tries > createStripeWebhookMaxRetries {
			return "", "", fmt.Errorf("endpoint limit reached; retries exhausted: %w", err)
		}
		utils.Logger.Warn("Endpoint limit hit – deleting one endpoint and retrying…")
		if rmErr := s.removeOldestStripeEndpoint(ctx, url); rmErr != nil {
			return "", "", rmErr
		}
		goto createAttempt

	case urlTakenErr(err):
		utils.Logger.Warn("URL already taken – attempting to delete existing matching endpoint and retry…")
		if rmErr := s.cleanupStaleEndpoints(ctx, url, kind); rmErr != nil {
			return "", "", rmErr
		}
		goto createAttempt
	}

	return "", "", err
}

// cleanupStaleEndpoints removes any endpoint that
//   • shares the URL and has no kind metadata, OR
//   • shares the URL and has the same kind metadata.
func (s *WorkerStripeService) cleanupStaleEndpoints(
	ctx context.Context,
	url string,
	wantKind string,
) error {

	lp := &stripe.WebhookEndpointListParams{}
	lp.Limit = stripe.Int64(100)
	lp.Context = ctx
	for it := webhookendpoint.List(lp); it.Next(); {
		ep := it.WebhookEndpoint()
		if ep.URL != url {
			continue
		}

		gotKind := ep.Metadata[kindKey] // empty if missing
		remove := gotKind == "" || gotKind == wantKind

		if remove {
			utils.Logger.Infof("Removing stale Stripe endpoint %s (kind=%s)", ep.ID, gotKind)
			delParams := &stripe.WebhookEndpointParams{}
			delParams.Params.Context = ctx
			if _, err := webhookendpoint.Del(ep.ID, delParams); err != nil {
				return fmt.Errorf("delete stale endpoint %s: %w", ep.ID, err)
			}
		}
	}
	return nil
}

// removeOldestStripeEndpoint deletes an endpoint to free capacity, trying oldest first.
// It will gracefully handle 404s if another service deletes the same endpoint first.
func (s *WorkerStripeService) removeOldestStripeEndpoint(ctx context.Context, targetURL string) error {
	lp := &stripe.WebhookEndpointListParams{}
	lp.Limit = stripe.Int64(100)
	lp.Context = ctx

	// 1. Get all webhooks and filter out the one we are trying to create.
	var removableEndpoints []*stripe.WebhookEndpoint
	for it := webhookendpoint.List(lp); it.Next(); {
		ep := it.WebhookEndpoint()
		if ep.URL != targetURL {
			removableEndpoints = append(removableEndpoints, ep)
		}
	}

	if len(removableEndpoints) == 0 {
		return fmt.Errorf("no removable webhook endpoints found")
	}

	// 2. Sort them from oldest to newest.
	sort.Slice(removableEndpoints, func(i, j int) bool {
		return removableEndpoints[i].Created < removableEndpoints[j].Created
	})

	// 3. Try to delete them one by one until successful.
	for _, ep := range removableEndpoints {
		_, err := webhookendpoint.Del(ep.ID, nil)
		if err == nil {
			utils.Logger.Infof("Removed oldest Stripe webhook endpoint %s to free slot", ep.ID)
			return nil // Success!
		}

		// If it's a 404, another service probably beat us to it. This is not a fatal error.
		if stripeErr, ok := err.(*stripe.Error); ok && stripeErr.Code == stripe.ErrorCodeResourceMissing {
			utils.Logger.Warnf("Attempted to delete webhook %s, but it was already gone (race condition). Trying next oldest.", ep.ID)
			continue // Try the next one
		}

		// Any other error is unexpected and should fail the startup.
		return fmt.Errorf("failed to delete webhook %s to free slot: %w", ep.ID, err)
	}

	// If we get here, it means we looped through all candidates and they all returned 404.
	return fmt.Errorf("could not free a webhook slot; all candidates were deleted by other processes")
}

// ----------------------------------------------------------------------
// Create or retrieve a Connect account, then return the onboarding link
// ----------------------------------------------------------------------
func (s *WorkerStripeService) GetExpressOnboardingURL(ctx context.Context, workerID uuid.UUID) (string, error) {
	worker, err := s.repo.GetByID(ctx, workerID)
	if err != nil {
		utils.Logger.WithError(err).Error("Failed to retrieve worker for GetExpressOnboardingURL")
		return "", fmt.Errorf("could not retrieve worker: %w", err)
	}
	if worker == nil {
		return "", fmt.Errorf("worker not found (ID=%s)", workerID)
	}

	if !s.Cfg.LDFlag_AllowOOSSetupFlow {
		// Return error if this is being called and the worker is not in ACH_PAYMENT_ACCOUNT_SETUP
		if worker.SetupProgress != models.SetupProgressAchPaymentAccountSetup {
			utils.Logger.WithError(err).Errorf(`Worker is not in ACH_PAYMENT_ACCOUNT_SETUP state, instead in %s.`, worker.SetupProgress)
			return "", fmt.Errorf("Onboarding URL can not be generated outside of normal flow. Worker %s is in %s state", worker.ID, worker.SetupProgress)
		}
	}

	var acctID string
	if worker.StripeConnectAccountID == nil || *worker.StripeConnectAccountID == "" {
		acctID, err = s.initializeStripeConnectExpressAccount(ctx, worker)
		if err != nil {
			utils.Logger.WithError(err).Error("Failed to create Stripe Connect account")
			return "", fmt.Errorf("could not create Stripe Connect account: %w", err)
		}
	} else {
		acctID = *worker.StripeConnectAccountID
	}

	linkParams := &stripe.AccountLinkParams{
		Account:    stripe.String(acctID),
		ReturnURL:  stripe.String(s.Cfg.AppUrl + routes.WorkerStripeConnectFlowReturn),
		RefreshURL: stripe.String(s.Cfg.AppUrl + routes.WorkerStripeConnectFlowRefresh),
		Type:       stripe.String(string(stripe.AccountLinkTypeAccountOnboarding)),
		CollectionOptions: &stripe.AccountLinkCollectionOptionsParams{
			Fields: stripe.String(stripe.AccountLinkCollectEventuallyDue),
		},
	}
	acctLink, err := accountlink.New(linkParams)
	if err != nil {
		utils.Logger.WithError(err).Error("Failed to create Stripe AccountLink")
		return "", fmt.Errorf("could not create AccountLink: %w", err)
	}
	return acctLink.URL, nil
}

// ----------------------------------------------------------------------
// Create a Stripe Identity VerificationSession
// ----------------------------------------------------------------------
func (s *WorkerStripeService) GetIdentityVerificationURL(ctx context.Context, workerID uuid.UUID) (string, error) {
	worker, err := s.repo.GetByID(ctx, workerID)
	if err != nil {
		utils.Logger.WithError(err).Error("Failed to retrieve worker for GetIdentityVerificationURL")
		return "", fmt.Errorf("could not retrieve worker: %w", err)
	}
	if worker == nil {
		return "", fmt.Errorf("worker not found (ID=%s)", workerID)
	}

	if !s.Cfg.LDFlag_AllowOOSSetupFlow {
		if worker.SetupProgress != models.SetupProgressIDVerify {
			utils.Logger.WithError(err).Errorf(`Worker is not in ID_VERIFY state, instead in %s.`, worker.SetupProgress)
			return "", fmt.Errorf("Idv URL can not be generated outside of normal flow. Worker %s is in %s state", worker.ID, worker.SetupProgress)
		}
	}

	// Check for an existing verification session ID stored with the worker
	if worker.CurrentStripeIdvSessionID != nil && *worker.CurrentStripeIdvSessionID != "" {
		existingVs, getErr := verificationsession.Get(*worker.CurrentStripeIdvSessionID, nil)
		if getErr != nil {
			utils.Logger.WithError(getErr).Warn("Failed to retrieve existing VerificationSession; will create a new one")
		} else {
			if existingVs.Status != stripe.IdentityVerificationSessionStatusVerified {
				redactParams := &stripe.IdentityVerificationSessionRedactParams{}
				_, redactErr := verificationsession.Redact(*worker.CurrentStripeIdvSessionID, redactParams)
				if redactErr != nil {
					utils.Logger.WithError(redactErr).Warn("Failed to redact existing VerificationSession; proceeding to create new session")
				} else {
					utils.Logger.Infof("Redacted unverified VerificationSession: %s", *worker.CurrentStripeIdvSessionID)
				}
			} else {
				utils.Logger.Infof("Existing VerificationSession %s is already verified; skipping redaction", *worker.CurrentStripeIdvSessionID)
			}
		}
	}

	// Create a new VerificationSession
	params := &stripe.IdentityVerificationSessionParams{
		Type: stripe.String("document"),
		Options: &stripe.IdentityVerificationSessionOptionsParams{
			Document: &stripe.IdentityVerificationSessionOptionsDocumentParams{
				RequireMatchingSelfie: stripe.Bool(true),
			},
		},
		ReturnURL:         stripe.String(s.Cfg.AppUrl + routes.WorkerStripeIdentityFlowReturn),
		ClientReferenceID: stripe.String(worker.ID.String()),
		Metadata: map[string]string{
			constants.WebhookMetadataGeneratedByKey: s.generatedBy,
			constants.WebhookMetadataAccountTypeKey: utils.WorkerAccountType,
		},
	}

	newVs, vsErr := verificationsession.New(params)
	if vsErr != nil {
		utils.Logger.WithError(vsErr).Error("Failed to create new VerificationSession")
		return "", fmt.Errorf("could not create VerificationSession: %w", vsErr)
	}

	// concurrency approach: store the new session ID
	vsID := newVs.ID
	if err := s.repo.UpdateWithRetry(ctx, worker.ID, func(stored *models.Worker) error {
		stored.CurrentStripeIdvSessionID = &vsID
		return nil
	}); err != nil {
		utils.Logger.WithError(err).Error("Failed to update worker with new VerificationSession ID")
		return "", fmt.Errorf("could not update worker: %w", err)
	}

	return newVs.URL, nil
}

// ----------------------------------------------------------------------
// GetConnectFlowStatus checks if the worker has advanced to
//   ACH_PAYMENT_ACCOUNT_SETUP => BACKGROUND_CHECK
// If Stripe account is fully set up, we move them forward.
// Otherwise we simply return a flow status (complete or incomplete)
// ----------------------------------------------------------------------
func (s *WorkerStripeService) GetConnectFlowStatus(ctx context.Context, userID string) (dtos.StripeFlowStatus, error) {
	// Attempt to parse worker ID
	wID, parseErr := uuid.Parse(userID)
	if parseErr != nil {
		// This is a real input error => we do want to bubble it up as an error
		return dtos.StripeFlowStatusIncomplete, parseErr
	}

	// Fetch worker record
	worker, err := s.repo.GetByID(ctx, wID)
	if err != nil {
		// DB/system error
		return dtos.StripeFlowStatusIncomplete, err
	}
	if worker == nil {
		// Not found => logically incomplete
		return dtos.StripeFlowStatusIncomplete, nil
	}

	// If they're already beyond ACH_PAYMENT_ACCOUNT_SETUP, consider connect flow "complete"
	if worker.SetupProgress == models.SetupProgressBackgroundCheck || worker.SetupProgress == models.SetupProgressDone {
		return dtos.StripeFlowStatusComplete, nil
	}

	// If they're exactly in the required state for connect, let's see if Stripe says they've completed it
	if worker.SetupProgress == models.SetupProgressAchPaymentAccountSetup {
		// Check Stripe details
		if worker.StripeConnectAccountID == nil {
			// No account => definitely incomplete
			return dtos.StripeFlowStatusIncomplete, nil
		}

		acctID := *worker.StripeConnectAccountID
		acct, accErr := account.GetByID(acctID, nil)
		if accErr != nil {
			return dtos.StripeFlowStatusIncomplete, accErr
		}

		if acct.DetailsSubmitted && acct.ChargesEnabled {
			// concurrency approach: set setup_progress => BACKGROUND_CHECK
			if err := s.repo.UpdateWithRetry(ctx, worker.ID, func(stored *models.Worker) error {
				stored.SetupProgress = models.SetupProgressBackgroundCheck
				return nil
			}); err != nil {
				return dtos.StripeFlowStatusIncomplete, err
			}
			// Now it's complete from the perspective of connect flow
			return dtos.StripeFlowStatusComplete, nil
		}
		// Otherwise still incomplete
		return dtos.StripeFlowStatusIncomplete, nil
	}

	// If they're in ID_VERIFY or some other earlier stage, connect flow is incomplete
	return dtos.StripeFlowStatusIncomplete, nil
}

// ----------------------------------------------------------------------
// CheckIdentityFlowStatus verifies if the worker has completed ID_VERIFY
// If so, they should be advanced to ACH_PAYMENT_ACCOUNT_SETUP
// Otherwise respond with "complete" or "incomplete" accordingly
// ----------------------------------------------------------------------
func (s *WorkerStripeService) CheckIdentityFlowStatus(ctx context.Context, userID string) (dtos.StripeFlowStatus, error) {
	wID, parseErr := uuid.Parse(userID)
	if parseErr != nil {
		return dtos.StripeFlowStatusIncomplete, parseErr
	}

	worker, err := s.repo.GetByID(ctx, wID)
	if err != nil {
		return dtos.StripeFlowStatusIncomplete, err
	}
	if worker == nil {
		return dtos.StripeFlowStatusIncomplete, nil
	}

	// If worker is already beyond ID_VERIFY, that means ID flow is effectively "complete"
	switch worker.SetupProgress {
	case models.SetupProgressAchPaymentAccountSetup, models.SetupProgressBackgroundCheck, models.SetupProgressDone:
		return dtos.StripeFlowStatusComplete, nil
	}

	// If still in ID_VERIFY, that means incomplete
	return dtos.StripeFlowStatusIncomplete, nil
}

// ----------------------------------------------------------------------
// Webhook handlers for Stripe events
// ----------------------------------------------------------------------

func (s *WorkerStripeService) HandleAccountUpdated(acct *stripe.Account) error {
	if acct.Metadata[constants.WebhookMetadataGeneratedByKey] != s.generatedBy {
		utils.Logger.Infof("Skipping account.updated for %s; metadata=%q != %q",
			acct.ID, acct.Metadata[constants.WebhookMetadataGeneratedByKey], s.generatedBy)
		return nil
	}
	utils.Logger.Infof("account.updated: acctID=%s, details_submitted=%v", acct.ID, acct.DetailsSubmitted)

	ctx := context.Background()
	worker, err := s.repo.GetByStripeConnectAccountID(ctx, acct.ID)
	if err != nil {
		utils.Logger.WithError(err).Errorf("Could not find worker by connect account %s", acct.ID)
		return err
	}
	if worker == nil {
		utils.Logger.Warnf("No worker found for connect account %s", acct.ID)
		return nil
	}

	// If the account is set up and the worker is still in ACH_PAYMENT_ACCOUNT_SETUP, advance them
	if acct.DetailsSubmitted && acct.ChargesEnabled {
		if s.Cfg.LDFlag_AllowOOSSetupFlow ||
			(!s.Cfg.LDFlag_AllowOOSSetupFlow && worker.SetupProgress == models.SetupProgressAchPaymentAccountSetup) {

			if updErr := s.repo.UpdateWithRetry(ctx, worker.ID, func(stored *models.Worker) error {
				stored.SetupProgress = models.SetupProgressBackgroundCheck
				return nil
			}); updErr != nil {
				utils.Logger.WithError(updErr).Error("Failed to update worker after Express onboarding")
				return updErr
			}
			utils.Logger.Infof("Worker %s advanced to BACKGROUND_CHECK (still INCOMPLETE)", worker.ID)
		}
	}
	return nil
}

func (s *WorkerStripeService) HandleCapabilityUpdated(capObj *stripe.Capability) error {
	acc, err := account.GetByID(capObj.Account.ID, nil)
	if err != nil {
		utils.Logger.WithError(err).Errorf("Failed to fetch account %s for capability.updated", capObj.Account.ID)
		return err
	}
	if acc.Metadata[constants.WebhookMetadataGeneratedByKey] != s.generatedBy {
		utils.Logger.Infof("Skipping capability.updated for %s; metadata=%q != %q",
			acc.ID, acc.Metadata[constants.WebhookMetadataGeneratedByKey], s.generatedBy)
		return nil
	}
	utils.Logger.Infof("capability.updated: acctID=%s, capability=%s, status=%s",
		capObj.Account.ID, capObj.ID, capObj.Status)
	return nil
}

func (s *WorkerStripeService) HandleVerificationSessionCreated(session *stripe.IdentityVerificationSession) error {
	if session.Metadata[constants.WebhookMetadataGeneratedByKey] != s.generatedBy {
		utils.Logger.Infof("Skipping verification_session.created for %s; metadata=%q != %q",
			session.ID, session.Metadata[constants.WebhookMetadataGeneratedByKey], s.generatedBy)
		return nil
	}
	utils.Logger.Infof("verification_session.created: %s", session.ID)
	return nil
}

func (s *WorkerStripeService) HandleVerificationSessionRequiresInput(session *stripe.IdentityVerificationSession) error {
	if session.Metadata[constants.WebhookMetadataGeneratedByKey] != s.generatedBy {
		utils.Logger.Infof("Skipping verification_session.requires_input for %s; metadata=%q != %q",
			session.ID, session.Metadata[constants.WebhookMetadataGeneratedByKey], s.generatedBy)
		return nil
	}
	utils.Logger.Warnf("verification_session.requires_input: %s, reason=%v", session.ID, session.LastError)
	return nil
}

func (s *WorkerStripeService) HandleVerificationSessionVerified(session *stripe.IdentityVerificationSession) error {
	if session.Metadata[constants.WebhookMetadataGeneratedByKey] != s.generatedBy {
		utils.Logger.Infof("Skipping verification_session.verified for %s; metadata=%q != %q",
			session.ID, session.Metadata[constants.WebhookMetadataGeneratedByKey], s.generatedBy)
		return nil
	}
	utils.Logger.Infof("verification_session.verified: %s, clientRef=%s", session.ID, session.ClientReferenceID)

	ctx := context.Background()
	workerID, wErr := uuid.Parse(session.ClientReferenceID)
	if wErr != nil {
		utils.Logger.WithError(wErr).Warnf("Invalid worker UUID: %s", session.ClientReferenceID)
		return wErr
	}

	worker, err := s.repo.GetByID(ctx, workerID)
	if err != nil {
		utils.Logger.WithError(err).Error("Failed to retrieve worker for ID verification")
		return err
	}
	if worker == nil {
		utils.Logger.Warnf("No worker found for ID=%s", workerID)
		return nil
	}

	if s.Cfg.LDFlag_AllowOOSSetupFlow ||
		(!s.Cfg.LDFlag_AllowOOSSetupFlow && worker.SetupProgress == models.SetupProgressIDVerify) {

		if updErr := s.repo.UpdateWithRetry(ctx, worker.ID, func(stored *models.Worker) error {
			stored.SetupProgress = models.SetupProgressAchPaymentAccountSetup
			return nil
		}); updErr != nil {
			utils.Logger.WithError(updErr).Error("Failed to update worker after ID verification")
			return updErr
		}
		utils.Logger.Infof("Worker %s advanced to ACH_PAYMENT_ACCOUNT_SETUP (still INCOMPLETE)", worker.ID)
	}

	return nil
}

func (s *WorkerStripeService) HandleVerificationSessionCanceled(session *stripe.IdentityVerificationSession) error {
	if session.Metadata[constants.WebhookMetadataGeneratedByKey] != s.generatedBy {
		utils.Logger.Infof("Skipping verification_session.canceled for %s; metadata=%q != %q",
			session.ID, session.Metadata[constants.WebhookMetadataGeneratedByKey], s.generatedBy)
		return nil
	}
	utils.Logger.Warnf("verification_session.canceled: %s", session.ID)
	return nil
}

func (s *WorkerStripeService) initializeStripeConnectExpressAccount(ctx context.Context, worker *models.Worker) (string, error) {
	acctParams := &stripe.AccountParams{
		Type:         stripe.String(string(stripe.AccountTypeExpress)),
		Country:      stripe.String("US"),
		BusinessType: stripe.String(string(stripe.AccountBusinessTypeIndividual)),
		BusinessProfile: &stripe.AccountBusinessProfileParams{
			ProductDescription: stripe.String("Gig Worker for Poof"),
		},
		Capabilities: &stripe.AccountCapabilitiesParams{
			Transfers: &stripe.AccountCapabilitiesTransfersParams{
				Requested: stripe.Bool(true),
			},
		},
		Metadata: map[string]string{
			constants.WebhookMetadataGeneratedByKey: s.generatedBy,
			constants.WebhookMetadataAccountTypeKey: utils.WorkerAccountType,
		},
	}

	if s.Cfg.LDFlag_PrefillStripeExpressKYC {
		acctParams.Individual = &stripe.PersonParams{
			FirstName: stripe.String(worker.FirstName),
			LastName:  stripe.String(worker.LastName),
			DOB: &stripe.PersonDOBParams{
				Day:   stripe.Int64(1),
				Month: stripe.Int64(1),
				Year:  stripe.Int64(1990),
			},
			SSNLast4: stripe.String("1234"),
		}
		acctParams.ExternalAccount = &stripe.AccountExternalAccountParams{
			Token: stripe.String("btok_us_verified"),
		}
	}

	acct, createErr := account.New(acctParams)
	if createErr != nil {
		utils.Logger.WithError(createErr).Error("Failed to create Stripe Connect account")
		return "", fmt.Errorf("could not create Stripe Connect account: %w", createErr)
	}
	acctID := acct.ID

	// concurrency approach: store the new connect account ID
	if err := s.repo.UpdateWithRetry(ctx, worker.ID, func(stored *models.Worker) error {
		stored.StripeConnectAccountID = &acctID
		return nil
	}); err != nil {
		utils.Logger.WithError(err).Error("Failed to update worker with new Connect account ID")
		return "", fmt.Errorf("could not update worker with new connect account ID: %w", err)
	}

	return acctID, nil
}

func toPtrSlice(events []string) []*string {
	out := make([]*string, len(events))
	for i, s := range events {
		out[i] = stripe.String(s)
	}
	return out
}

// Helpers for Stripe error inspection.
func limitErr(err error) bool {
	if se, ok := err.(*stripe.Error); ok && se.Type == stripe.ErrorTypeInvalidRequest {
		return strings.Contains(se.Msg, "Allowed webhook API limit exceeded") ||
			strings.Contains(se.Msg, "16 test webhook endpoints") ||
			strings.Contains(se.Msg, "16 webhook endpoints")
	}
	return false
}

func urlTakenErr(err error) bool {
	if se, ok := err.(*stripe.Error); ok && se.Type == stripe.ErrorTypeInvalidRequest {
		msg := strings.ToLower(se.Msg)
		return strings.Contains(msg, "url has already been taken") ||
			strings.Contains(msg, "url is already in use")
	}
	return false
}
