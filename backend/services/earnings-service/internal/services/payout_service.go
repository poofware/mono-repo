// meta-service/services/earnings-service/internal/services/payout_service.go

package services

import (
	"context"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/earnings-service/internal/config"
	"github.com/poofware/earnings-service/internal/constants"
	internal_models "github.com/poofware/earnings-service/internal/models"
	internal_repositories "github.com/poofware/earnings-service/internal/repositories"
	"github.com/poofware/earnings-service/internal/routes"
	internal_utils "github.com/poofware/earnings-service/internal/utils"
	"github.com/poofware/go-models"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
	"github.com/sendgrid/sendgrid-go"
	"github.com/sendgrid/sendgrid-go/helpers/mail"
	"github.com/stripe/stripe-go/v82"
	"github.com/stripe/stripe-go/v82/account"
	"github.com/stripe/stripe-go/v82/balancetransaction"
	"github.com/stripe/stripe-go/v82/payout"
	"github.com/stripe/stripe-go/v82/transfer"
	"github.com/stripe/stripe-go/v82/webhookendpoint"
)

const (
	baseRetryDelay                = 1 * time.Hour
	maxRetries                    = 5
	createStripeWebhookMaxRetries = 3
	kindKey                       = "kind"
	kindPlatform                  = "platform"
	kindConnect                   = "connect"
	notSetLog                     = "<not set>"
)

// NEW: HTML templates for professional-looking emails.
const userFacingFailureEmailHTML = `<!DOCTYPE html>
<html>
<head>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol"; line-height: 1.6; color: #333333; background-color: #f4f4f4; margin: 0; padding: 0; }
.container { padding: 20px; max-width: 600px; margin: 20px auto; background-color: #ffffff; border: 1px solid #dddddd; border-radius: 8px; }
.header { font-size: 24px; font-weight: bold; color: #d9534f; margin-bottom: 15px; }
.button-container { text-align: center; margin: 30px 0; }
.button { background-color: #5b3a9d; color: white !important; padding: 12px 25px; text-align: center; text-decoration: none; display: inline-block; border-radius: 5px; font-weight: bold; }
.footer { margin-top: 20px; font-size: 12px; color: #777777; text-align: center; }
p { margin-bottom: 15px; }
</style>
</head>
<body>
<div class="container">
<p class="header">Action Required: Your Payout Failed</p>
<p>Hi %s,</p>
<p>We were unable to process your payout of <strong>$%.2f</strong> for the week of %s. This was due to an issue with your connected bank account.</p>
<p><strong>Reason:</strong> %s</p>
<p>To ensure you receive your earnings, please update your payout information in the Stripe Express Dashboard by clicking the button below.</p>
<div class="button-container">
  <a href="%s" class="button">Update Payout Information</a>
</div>
<p>If you continue to have issues after updating your information, please contact our support team.</p>
<div class="footer">The Poof Team</div>
</div>
</body>
</html>`

const internalFinanceEmailHTML = `<!DOCTYPE html>
<html>
<head>
<style>
body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
.container { padding: 20px; max-width: 600px; margin: auto; border: 1px solid #ddd; border-radius: 5px; }
.header { font-size: 24px; font-weight: bold; color: #d9534f; }
.data-label { font-weight: bold; }
ul { list-style-type: none; padding: 0; }
li { margin-bottom: 10px; }
</style>
</head>
<body>
<div class="container">
<p class="header">URGENT: Platform Payout Failure</p>
<p>A payout failed due to a platform-side issue. Please investigate immediately.</p>
<ul>
  <li><span class="data-label">Worker ID:</span> %s</li>
  <li><span class="data-label">Payout ID:</span> %s</li>
  <li><span class="data-label">Amount:</span> $%.2f</li>
  <li><span class="data-label">Reason:</span> %s</li>
</ul>
</div>
</body>
</html>`

var (
	platformEvents = []string{
		"balance.available",
	}
	connectEvents = []string{
		"payout.paid",
		"payout.failed",
		"account.updated",
		"capability.updated",
		"transfer.reversed",
		"payment_intent.created",
	}
)

type PayoutService struct {
	cfg                   *config.Config
	workerRepo            repositories.WorkerRepository
	jobInstRepo           repositories.JobInstanceRepository
	payoutRepo            internal_repositories.WorkerPayoutRepository
	sendgridClient        *sendgrid.Client
	generatedBy           string
	webhookPlatformID     string
	webhookConnectID      string
	webhookPlatformSecret string
	webhookConnectSecret  string
	mu                    sync.Mutex
	recoveryMu            sync.Mutex
}

func NewPayoutService(cfg *config.Config, workerRepo repositories.WorkerRepository, jobInstRepo repositories.JobInstanceRepository, payoutRepo internal_repositories.WorkerPayoutRepository) *PayoutService {
	stripe.Key = cfg.StripeSecretKey
	generated := fmt.Sprintf("%s-%s-%s", cfg.AppName, cfg.UniqueRunnerID, cfg.UniqueRunNumber)
	return &PayoutService{
		cfg:            cfg,
		workerRepo:     workerRepo,
		jobInstRepo:    jobInstRepo,
		payoutRepo:     payoutRepo,
		sendgridClient: sendgrid.NewSendClient(cfg.SendgridAPIKey),
		generatedBy:    generated,
	}
}

func (s *PayoutService) PlatformWebhookSecret() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.webhookPlatformSecret
}

func (s *PayoutService) ConnectWebhookSecret() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.webhookConnectSecret
}

func (s *PayoutService) Start(ctx context.Context) error {
	if !s.cfg.LDFlag_DynamicStripeWebhookEndpoint {
		s.webhookPlatformSecret = s.cfg.StripeWebhookSecret
		s.webhookConnectSecret = s.cfg.StripeWebhookSecret
		return nil
	}
	dest := s.cfg.AppUrl + routes.EarningsStripeWebhook

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

func (s *PayoutService) Stop(ctx context.Context) error {
	if !s.cfg.LDFlag_DynamicStripeWebhookEndpoint {
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

func (s *PayoutService) ensureStripeEndpoint(
	ctx context.Context,
	url string,
	events []string,
	connect bool,
) (string, string, error) {
	kind := kindPlatform
	if connect {
		kind = kindConnect
	}

	if err := s.cleanupStaleEndpoints(ctx, url, kind); err != nil {
		return "", "", err
	}

	create := &stripe.WebhookEndpointParams{
		URL:           stripe.String(url),
		EnabledEvents: toPtrSlice(events),
		Metadata:      map[string]string{kindKey: kind},
		APIVersion:    stripe.String(stripe.APIVersion),
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

	if limitErr(err) {
		if tries > createStripeWebhookMaxRetries {
			return "", "", fmt.Errorf("endpoint limit reached; retries exhausted: %w", err)
		}
		utils.Logger.Warn("Endpoint limit hit – deleting one endpoint and retrying…")
		if rmErr := s.removeOldestStripeEndpoint(ctx, url); rmErr != nil {
			return "", "", rmErr
		}
		goto createAttempt
	} else if urlTakenErr(err) {
		utils.Logger.Warn("URL already taken – attempting to delete existing matching endpoint and retry…")
		if rmErr := s.cleanupStaleEndpoints(ctx, url, kind); rmErr != nil {
			return "", "", rmErr
		}
		goto createAttempt
	}

	return "", "", err
}

func (s *PayoutService) cleanupStaleEndpoints(ctx context.Context, url, wantKind string) error {
	lp := &stripe.WebhookEndpointListParams{}
	lp.Limit = stripe.Int64(100)
	lp.Context = ctx
	for it := webhookendpoint.List(lp); it.Next(); {
		ep := it.WebhookEndpoint()
		if ep.URL != url {
			continue
		}
		gotKind := ep.Metadata[kindKey]
		if gotKind == "" || gotKind == wantKind {
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

func (s *PayoutService) removeOldestStripeEndpoint(ctx context.Context, targetURL string) error {
	lp := &stripe.WebhookEndpointListParams{}
	lp.Limit = stripe.Int64(100)
	lp.Context = ctx

	// 1. Get all webhooks and filter out the one we are trying to create.
	var removableEndpoints []*stripe.WebhookEndpoint
	for it := webhookendpoint.List(lp); it.Next(); {
		ep := it.WebhookEndpoint()
		// Only consider endpoints that do not point to our target URL for deletion.
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

func (s *PayoutService) AggregateAndCreatePayouts(ctx context.Context) error {
	var payPeriodStart, payPeriodEnd, weekStartDate, weekEndDate time.Time
	loc, _ := time.LoadLocation(constants.BusinessTimezone)

	if s.cfg.LDFlag_UseShortPayPeriod {
		utils.Logger.Info("Using short pay period (1 day) for payout aggregation.")
		nowInLoc := time.Now().In(loc)
		todayStart := time.Date(nowInLoc.Year(), nowInLoc.Month(), nowInLoc.Day(), 0, 0, 0, 0, loc)
		payPeriodStart = todayStart.AddDate(0, 0, -1) // Yesterday
		payPeriodEnd = todayStart                     // Range is [start, end)

		weekStartDate = payPeriodStart.UTC()
		weekEndDate = weekStartDate // For daily payouts, start and end are the same.
	} else {
		now := time.Now().In(loc)

		// Determine the exact pay period to aggregate.
		// This is always the one *before* the period the current time falls into.
		thisWeekPayPeriodStart := internal_utils.GetPayPeriodStartForDate(now)
		prevWeekPayPeriodStart := thisWeekPayPeriodStart.AddDate(0, 0, -constants.DaysInWeek)

		// The period to query runs from Monday 4AM to the following Monday 4AM.
		payPeriodStart = time.Date(prevWeekPayPeriodStart.Year(), prevWeekPayPeriodStart.Month(), prevWeekPayPeriodStart.Day(), constants.PayPeriodStartHourEST, 0, 0, 0, loc)
		payPeriodEnd = payPeriodStart.AddDate(0, 0, constants.DaysInWeek)

		// The database key is the Monday date that starts the pay period.
		weekStartDate = prevWeekPayPeriodStart
		weekEndDate = weekStartDate.AddDate(0, 0, 6)
	}

	utils.Logger.Infof("Aggregating payouts for pay period: %s to %s", payPeriodStart.Format(time.RFC3339), payPeriodEnd.Format(time.RFC3339))

	statuses := []models.InstanceStatusType{models.InstanceStatusCompleted}
	jobs, err := s.jobInstRepo.ListInstancesByDateRange(ctx, nil, statuses, payPeriodStart, payPeriodEnd)
	if err != nil {
		return fmt.Errorf("could not fetch jobs for payout aggregation: %w", err)
	}

	type workerEarnings struct {
		amountCents int64
		jobIDs      []uuid.UUID
	}
	earningsByWorker := make(map[uuid.UUID]workerEarnings)

	for _, job := range jobs {
		if job.AssignedWorkerID != nil {
			workerID := *job.AssignedWorkerID
			current := earningsByWorker[workerID]
			current.amountCents += int64(job.EffectivePay * 100)
			current.jobIDs = append(current.jobIDs, job.ID)
			earningsByWorker[workerID] = current
		}
	}

	for workerID, earnings := range earningsByWorker {
		if earnings.amountCents <= constants.MinimumPayoutAmountCents {
			continue
		}

		existing, err := s.payoutRepo.GetByWorkerAndWeek(ctx, workerID, weekStartDate)
		if err != nil {
			utils.Logger.WithError(err).Warnf("Could not check for existing payout for worker %s", workerID)
			continue
		}
		if existing != nil {
			continue
		}

		payout := &internal_models.WorkerPayout{
			ID:             uuid.New(),
			WorkerID:       workerID,
			WeekStartDate:  weekStartDate,
			WeekEndDate:    weekEndDate,
			AmountCents:    earnings.amountCents,
			Status:         internal_models.PayoutStatusPending,
			JobInstanceIDs: earnings.jobIDs,
		}
		if err := s.payoutRepo.Create(ctx, payout); err != nil {
			utils.Logger.WithError(err).Errorf("Failed to create payout record for worker %s", workerID)
		} else {
			utils.Logger.Infof("Created PENDING payout of %d cents for worker %s for period starting %s", earnings.amountCents, workerID, weekStartDate.Format(time.RFC3339))
		}
	}
	return nil
}

func (s *PayoutService) ProcessPendingPayouts(ctx context.Context) error {
	utils.Logger.Info("Starting payout processing for pending payouts...")

	payouts, err := s.payoutRepo.FindReadyForPayout(ctx)
	if err != nil {
		return fmt.Errorf("failed to find payouts ready for processing: %w", err)
	}

	if len(payouts) > 0 {
		utils.Logger.Infof("Found %d payouts to process", len(payouts))
	}

	var encounteredInsufficentBalance bool

	for _, p := range payouts {
		utils.Logger.Debugf("Processing payout %s for worker %s (amount: $%.2f)", p.ID, p.WorkerID, float64(p.AmountCents)/100.0)

		err := s.payoutRepo.UpdateWithRetry(ctx, p.ID, func(payoutToUpdate *internal_models.WorkerPayout) error {
			payoutToUpdate.Status = internal_models.PayoutStatusProcessing
			payoutToUpdate.LastAttemptAt = utils.Ptr(time.Now().UTC())
			return nil
		})

		if err != nil {
			utils.Logger.WithError(err).Errorf("Failed to update payout %s to PROCESSING", p.ID)
			continue
		}

		payoutErr := s.processPayout(ctx, p)
		if errors.Is(payoutErr, internal_utils.ErrBalanceInsufficient) {
			utils.Logger.WithError(payoutErr).Warnf("Encountered insufficient balance for payout %s. Will continue processing other payouts.", p.ID)
			encounteredInsufficentBalance = true
			continue // Continue to the next payout.
		}
	}

	if encounteredInsufficentBalance {
		utils.Logger.Warn("Finished payout processing run, but at least one payout failed due to insufficient platform balance.")
		return internal_utils.ErrBalanceInsufficient
	}

	return nil
}

func (s *PayoutService) processPayout(ctx context.Context, p *internal_models.WorkerPayout) error {
	worker, err := s.workerRepo.GetByID(ctx, p.WorkerID)
	if err != nil || worker == nil {
		s.handleFailure(ctx, p, constants.ReasonWorkerNotFound, nil)
		return err
	}

	if worker.StripeConnectAccountID == nil || *worker.StripeConnectAccountID == "" {
		s.handleFailure(ctx, p, constants.ReasonMissingStripeID, nil)
		return errors.New(constants.ReasonMissingStripeID)
	}

	acct, err := account.GetByID(*worker.StripeConnectAccountID, nil)
	if err != nil {
		if stripeErr, ok := err.(*stripe.Error); ok {
			s.handleFailure(ctx, p, string(stripeErr.Code), nil)
		} else {
			s.handleFailure(ctx, p, constants.ReasonUnknownStripeAccountError, nil)
		}
		return err
	}

	utils.Logger.Debugf("Processing payout amount $%.2f for worker %s (Stripe Account: %s)",
		float64(p.AmountCents)/100.0, worker.ID, *worker.StripeConnectAccountID)

	if !acct.PayoutsEnabled {
		s.handleFailure(ctx, p, constants.ReasonAccountPayoutsDisabled, nil)
		return errors.New(constants.ReasonAccountPayoutsDisabled)
	}

	// --- Step 1: Transfer funds from Platform Balance to Connected Account Balance ---
	transferParams := &stripe.TransferParams{
		Amount:      stripe.Int64(p.AmountCents),
		Currency:    stripe.String(string(stripe.CurrencyUSD)),
		Destination: stripe.String(*worker.StripeConnectAccountID),
		Metadata: map[string]string{
			constants.WebhookMetadataPayoutIDKey:    p.ID.String(),
			"worker_id":                             p.WorkerID.String(),
			constants.WebhookMetadataGeneratedByKey: s.generatedBy,
		},
	}
	transferParams.SetIdempotencyKey(fmt.Sprintf("%s-transfer-%d", p.ID.String(), p.RetryCount))

	t, transferErr := transfer.New(transferParams)
	if transferErr != nil {
		if stripeErr, ok := transferErr.(*stripe.Error); ok {
			if stripeErr.Code == stripe.ErrorCodeBalanceInsufficient {
				s.handleFailure(ctx, p, string(stripeErr.Code), nil)
				return internal_utils.ErrBalanceInsufficient
			}
			s.handleFailure(ctx, p, string(stripeErr.Code), nil)
		} else {
			s.handleFailure(ctx, p, constants.ReasonUnknownStripeTransferError, nil)
		}
		return transferErr
	}

	utils.Logger.Infof("Successfully created Stripe Transfer %s for payout %s", t.ID, p.ID)

	// --- Step 2: Create a Payout from the Connected Account Balance to their bank ---
	payoutParams := &stripe.PayoutParams{
		Amount:   stripe.Int64(p.AmountCents),
		Currency: stripe.String(string(stripe.CurrencyUSD)),
		Metadata: map[string]string{
			constants.WebhookMetadataPayoutIDKey:    p.ID.String(),
			constants.WebhookMetadataGeneratedByKey: s.generatedBy,
		},
	}
	payoutParams.SetStripeAccount(*worker.StripeConnectAccountID)
	payoutParams.SetIdempotencyKey(fmt.Sprintf("%s-payout-%d", p.ID.String(), p.RetryCount))

	po, payoutErr := payout.New(payoutParams)
	if payoutErr != nil {
		// The transfer succeeded, but the payout failed synchronously.
		// This is a critical state. We log it and mark the payout as failed.
		// A reversal of the transfer might be needed in a more advanced implementation.
		utils.Logger.WithError(payoutErr).Errorf("CRITICAL: Stripe Transfer %s succeeded but Payout initiation failed for payout %s.", t.ID, p.ID)
		reason := constants.ReasonPayoutInitiationFailed
		if stripeErr, ok := payoutErr.(*stripe.Error); ok {
			reason = string(stripeErr.Code)
		}
		s.handleFailure(ctx, p, reason, &t.ID)
		return payoutErr
	}

	utils.Logger.Infof("Successfully initiated Stripe Payout %s for payout %s", po.ID, p.ID)

	// --- Step 3: Update internal record with Stripe IDs.
	// The final PAID/FAILED status will be set by a webhook.
	err = s.payoutRepo.UpdateWithRetry(ctx, p.ID, func(payoutToUpdate *internal_models.WorkerPayout) error {
		// Persist the Stripe IDs from the successful API calls.
		payoutToUpdate.StripeTransferID = &t.ID
		payoutToUpdate.StripePayoutID = &po.ID

		// CRITICAL: Only clear failure reasons if the status has NOT been changed
		// by a concurrent webhook. If a webhook already marked this as FAILED,
		// we must not overwrite that final state.
		if payoutToUpdate.Status == internal_models.PayoutStatusProcessing {
			// The status is as we left it. We can safely clear any old failure reasons
			// from previous attempts, as this attempt successfully initiated.
			payoutToUpdate.LastFailureReason = nil
			payoutToUpdate.NextAttemptAt = nil
		}
		// If status is already FAILED or PAID, we do nothing to it.
		// The Stripe IDs will still be saved by the update, but the authoritative
		// final status from the webhook is preserved.
		return nil
	})

	if err != nil {
		utils.Logger.WithError(err).Errorf("CRITICAL: Stripe Transfer %s and Payout %s succeeded but failed to update internal payout %s with IDs", t.ID, po.ID, p.ID)
	} else {
		utils.Logger.Infof("Successfully initiated payout %s (Stripe Transfer: %s, Stripe Payout: %s). Awaiting webhook for final status.", p.ID, t.ID, po.ID)
	}
	return nil
}

func (s *PayoutService) handleFailure(ctx context.Context, p *internal_models.WorkerPayout, reason string, transferID *string) {
	err := s.payoutRepo.UpdateWithRetry(ctx, p.ID, func(payoutToUpdate *internal_models.WorkerPayout) error {
		utils.Logger.Warnf("Payout %s for worker %s failed. Reason: %s", payoutToUpdate.ID, payoutToUpdate.WorkerID, reason)
		payoutToUpdate.Status = internal_models.PayoutStatusFailed
		payoutToUpdate.LastFailureReason = &reason

		if transferID != nil {
			payoutToUpdate.StripeTransferID = transferID
		}

		if reason == string(stripe.ErrorCodeBalanceInsufficient) {
			payoutToUpdate.NextAttemptAt = nil
			payoutToUpdate.RetryCount++
			utils.Logger.Warnf("Payout %s failed due to insufficient balance. It will be retried upon 'balance.available' event.", payoutToUpdate.ID)
			s.sendFailureNotification(ctx, payoutToUpdate, false)
			return nil
		}

		payoutToUpdate.RetryCount++
		isRecoverable, requiresUserAction := IsFailureRecoverable(reason)

		if !isRecoverable || payoutToUpdate.RetryCount >= maxRetries {
			payoutToUpdate.NextAttemptAt = nil
			utils.Logger.Errorf("Payout %s for worker %s has failed and will not be retried automatically. Reason: %s", payoutToUpdate.ID, payoutToUpdate.WorkerID, reason)
			if requiresUserAction {
				s.sendFailureNotification(ctx, payoutToUpdate, true)
			} else {
				s.sendFailureNotification(ctx, payoutToUpdate, false)
			}
		} else {
			delay := baseRetryDelay * time.Duration(math.Pow(2, float64(payoutToUpdate.RetryCount-1)))
			nextAttempt := time.Now().UTC().Add(delay)
			payoutToUpdate.NextAttemptAt = &nextAttempt
			utils.Logger.Warnf("Scheduling retry #%d for payout %s at %s", payoutToUpdate.RetryCount, payoutToUpdate.ID, nextAttempt)
		}
		return nil
	})

	if err != nil {
		utils.Logger.WithError(err).Errorf("Failed to update payout %s after failure", p.ID)
	}
}

func (s *PayoutService) sendFailureNotification(ctx context.Context, p *internal_models.WorkerPayout, isUserFault bool) {
	worker, err := s.workerRepo.GetByID(ctx, p.WorkerID)
	if err != nil {
		utils.Logger.WithError(err).Error("Failed to fetch worker for failure notification")
		return
	}

	from := mail.NewEmail(s.cfg.OrganizationName, s.cfg.LDFlag_SendgridFromEmail)
	var subject, plainTextContent, htmlContent string
	var to *mail.Email

	// UPDATED: Use HTML templates
	if isUserFault {
		to = mail.NewEmail(worker.FirstName+" "+worker.LastName, worker.Email)
		subject = constants.EmailSubjectPayoutFailureActionRequired

		plainTextContent = fmt.Sprintf(
			"Hi %s,\n\nYour payout of $%.2f for the week of %s could not be processed due to an issue with your connected bank account. Reason: %s\n\nPlease update your payout information in the Stripe Express Dashboard to ensure you receive your earnings.\n\nLink to Stripe: %s\n\nIf you continue to have issues, please contact support.\n\n- The Poof Team",
			worker.FirstName,
			float64(p.AmountCents)/100.0,
			p.WeekStartDate.Format("January 2, 2006"),
			*p.LastFailureReason,
			constants.StripeExpressDashboardURL,
		)

		htmlContent = fmt.Sprintf(
			userFacingFailureEmailHTML,
			worker.FirstName,
			float64(p.AmountCents)/100.0,
			p.WeekStartDate.Format("January 2, 2006"),
			*p.LastFailureReason,
			constants.StripeExpressDashboardURL,
		)

	} else {
		to = mail.NewEmail(constants.FinanceTeamName, constants.FinanceTeamEmail)
		subject = fmt.Sprintf(constants.EmailSubjectPayoutFailurePlatformIssue, worker.ID)

		plainTextContent = fmt.Sprintf(
			"A payout of $%.2f for worker %s (Payout ID: %s) failed due to a platform-side issue. Reason: %s\n\nPlease investigate immediately.",
			float64(p.AmountCents)/100.0,
			worker.ID.String(),
			p.ID.String(),
			*p.LastFailureReason,
		)

		htmlContent = fmt.Sprintf(
			internalFinanceEmailHTML,
			worker.ID.String(),
			p.ID.String(),
			float64(p.AmountCents)/100.0,
			*p.LastFailureReason,
		)
	}

	msg := mail.NewSingleEmail(from, subject, to, plainTextContent, htmlContent)
	if s.cfg.LDFlag_SendgridSandboxMode {
		ms := mail.NewMailSettings()
		ms.SetSandboxMode(mail.NewSetting(true))
		msg.MailSettings = ms
	}
	if _, err := s.sendgridClient.Send(msg); err != nil {
		utils.Logger.WithError(err).Error("Failed to send payout failure notification")
	}
}

func (s *PayoutService) HandlePayoutEvent(ctx context.Context, payout *stripe.Payout) error {
	// Check if the event was generated by a known source via direct metadata on the Payout object.
	if generator, ok := payout.Metadata[constants.WebhookMetadataGeneratedByKey]; ok {
		if generator != s.generatedBy {
			utils.Logger.Infof("Ignoring payout event %s for Payout %s generated by another instance: %s", payout.Status, payout.ID, generator)
			return nil
		}

		// If it was generated by us, it MUST have the payout ID.
		payoutIDStr, ok := payout.Metadata[constants.WebhookMetadataPayoutIDKey]
		if !ok {
			utils.Logger.Warnf("Payout event %s for Payout %s has matching 'generated_by' but is missing 'payout_id' in metadata. Ignoring.", payout.Status, payout.ID)
			return nil
		}

		// --- Proceed with modern event handling ---
		parsedID, err := uuid.Parse(payoutIDStr)
		if err != nil {
			utils.Logger.WithError(err).Errorf("Invalid UUID in payout metadata: %s", payoutIDStr)
			return nil
		}

		p, err := s.payoutRepo.GetByID(ctx, parsedID)
		if err != nil || p == nil {
			utils.Logger.WithError(err).Errorf("Could not find internal payout record for ID: %s", parsedID)
			return nil
		}

		if payout.Status == stripe.PayoutStatusFailed {
			s.handleFailure(ctx, p, string(payout.FailureCode), p.StripeTransferID)
		} else if payout.Status == stripe.PayoutStatusPaid {
			// This is the final confirmation.
			utils.Logger.Infof("Webhook confirmation: Payout %s for worker %s is now PAID. (Stripe Payout ID: %s)", p.ID, p.WorkerID, payout.ID)
			err := s.payoutRepo.UpdateWithRetry(ctx, p.ID, func(payoutToUpdate *internal_models.WorkerPayout) error {
				// Only update if it's in a transitional state. This makes the handler idempotent.
				if payoutToUpdate.Status == internal_models.PayoutStatusProcessing {
					payoutToUpdate.Status = internal_models.PayoutStatusPaid
				}
				return nil
			})
			if err != nil {
				utils.Logger.WithError(err).Errorf("Failed to update internal payout %s to PAID after webhook confirmation.", p.ID)
			}
		}
		return nil
	}

	// If no 'generated_by' metadata on the payout, it might be an older one.
	// Fallback to checking the source transfer object's metadata.
	return s.handleLegacyPayoutEvent(ctx, payout)
}

func (s *PayoutService) handleLegacyPayoutEvent(ctx context.Context, payout *stripe.Payout) error {
	var transfer *stripe.Transfer
	if payout.BalanceTransaction != nil && payout.BalanceTransaction.Source != nil && payout.BalanceTransaction.Source.Transfer != nil {
		transfer = payout.BalanceTransaction.Source.Transfer
	} else if payout.BalanceTransaction != nil {
		bt, err := balancetransaction.Get(payout.BalanceTransaction.ID, &stripe.BalanceTransactionParams{
			Params: stripe.Params{Expand: []*string{stripe.String("source")}},
		})
		if err != nil || bt == nil || bt.Source == nil || bt.Source.Transfer == nil {
			utils.Logger.WithError(err).Warnf("Could not get balance_transaction or its source transfer for payout: %s", payout.ID)
			return nil
		}
		transfer = bt.Source.Transfer
	} else {
		utils.Logger.Warnf("Payout event %s for Payout %s missing balance_transaction, cannot trace source. Ignoring.", payout.Status, payout.ID)
		return nil
	}

	// Check if the source transfer was generated by this service instance.
	if generator, ok := transfer.Metadata[constants.WebhookMetadataGeneratedByKey]; !ok || generator != s.generatedBy {
		var g string
		if !ok {
			g = notSetLog
		} else {
			g = generator
		}
		utils.Logger.Infof("Ignoring legacy payout event %s for Payout %s because its source transfer's 'generated_by' is '%s' (does not match current instance).", payout.Status, payout.ID, g)
		return nil
	}

	payoutIDStr, ok := transfer.Metadata[constants.WebhookMetadataPayoutIDKey]
	if !ok {
		utils.Logger.Warnf("Stripe Transfer %s (from Payout %s) missing payout_id in metadata. Ignoring.", transfer.ID, payout.ID)
		return nil
	}

	parsedID, err := uuid.Parse(payoutIDStr)
	if err != nil {
		utils.Logger.WithError(err).Errorf("Invalid UUID in transfer metadata: %s", payoutIDStr)
		return nil
	}

	p, err := s.payoutRepo.GetByID(ctx, parsedID)
	if err != nil || p == nil {
		utils.Logger.WithError(err).Errorf("Could not find internal payout record for ID: %s", parsedID)
		return nil
	}

	if payout.Status == stripe.PayoutStatusFailed {
		s.handleFailure(ctx, p, string(payout.FailureCode), &transfer.ID)
	} else if payout.Status == stripe.PayoutStatusPaid {
		// This is the final confirmation.
		utils.Logger.Infof("Webhook confirmation: Payout %s for worker %s is now PAID. (Stripe Payout ID: %s)", p.ID, p.WorkerID, payout.ID)
		err := s.payoutRepo.UpdateWithRetry(ctx, p.ID, func(payoutToUpdate *internal_models.WorkerPayout) error {
			// Only update if it's in a transitional state. This makes the handler idempotent.
			if payoutToUpdate.Status == internal_models.PayoutStatusProcessing {
				payoutToUpdate.Status = internal_models.PayoutStatusPaid
			}
			return nil
		})
		if err != nil {
			utils.Logger.WithError(err).Errorf("Failed to update internal payout %s to PAID after legacy webhook confirmation.", p.ID)
		}
	}
	return nil
}

func (s *PayoutService) HandleAccountUpdatedEvent(ctx context.Context, acct *stripe.Account) error {
	worker, err := s.workerRepo.GetByStripeConnectAccountID(ctx, acct.ID)
	if err != nil {
		utils.Logger.WithError(err).Errorf("Error finding worker by Stripe account ID %s", acct.ID)
		return err
	}
	if worker == nil {
		return nil
	}

	if acct.PayoutsEnabled {
		failedPayouts, err := s.payoutRepo.FindFailedPayoutsForWorkerByAccountError(ctx, worker.ID)
		if err != nil {
			utils.Logger.WithError(err).Errorf("Error finding failed payouts for worker %s", worker.ID)
			return err
		}

		for _, p := range failedPayouts {
			err := s.payoutRepo.UpdateWithRetry(ctx, p.ID, func(payoutToUpdate *internal_models.WorkerPayout) error {
				utils.Logger.Infof("Worker %s updated their account. Re-queueing failed payout %s.", worker.ID, payoutToUpdate.ID)
				payoutToUpdate.Status = internal_models.PayoutStatusPending
				payoutToUpdate.RetryCount = 0
				payoutToUpdate.NextAttemptAt = utils.Ptr(time.Now().UTC())
				return nil
			})
			if err != nil {
				utils.Logger.WithError(err).Errorf("Failed to re-queue payout %s", p.ID)
			}
		}
	}

	return nil
}

func (s *PayoutService) HandleCapabilityUpdatedEvent(ctx context.Context, cap *stripe.Capability) error {
	if cap.Account == nil {
		return nil
	}
	utils.Logger.Infof("Received capability.updated for account %s: capability %s is now %s",
		cap.Account.ID, cap.ID, cap.Status)

	if cap.ID == constants.StripeCapabilityTransfers && cap.Status == stripe.CapabilityStatusActive {
		worker, err := s.workerRepo.GetByStripeConnectAccountID(ctx, cap.Account.ID)
		if err != nil || worker == nil {
			utils.Logger.WithError(err).Errorf("Could not find worker for Connect account %s", cap.Account.ID)
			return nil
		}

		failedPayouts, err := s.payoutRepo.FindFailedPayoutsForWorkerByAccountError(ctx, worker.ID)
		if err != nil {
			utils.Logger.WithError(err).Errorf("Error finding failed payouts for worker %s", worker.ID)
			return err
		}
		for _, p := range failedPayouts {
			err := s.payoutRepo.UpdateWithRetry(ctx, p.ID, func(payoutToUpdate *internal_models.WorkerPayout) error {
				utils.Logger.Infof("Worker %s transfers capability became active. Re-queueing failed payout %s.", worker.ID, payoutToUpdate.ID)
				payoutToUpdate.Status = internal_models.PayoutStatusPending
				payoutToUpdate.RetryCount = 0
				payoutToUpdate.NextAttemptAt = utils.Ptr(time.Now().UTC())
				return nil
			})
			if err != nil {
				utils.Logger.WithError(err).Errorf("Failed to re-queue payout %s", p.ID)
			}
		}

	} else if cap.ID == constants.StripeCapabilityTransfers && cap.Status == stripe.CapabilityStatusInactive {
		utils.Logger.Warnf("CRITICAL: Transfers capability for account %s has become inactive. Notifying worker and finance.", cap.Account.ID)
		worker, err := s.workerRepo.GetByStripeConnectAccountID(ctx, cap.Account.ID)
		if err != nil || worker == nil {
			utils.Logger.WithError(err).Errorf("Could not find worker for Connect account %s", cap.Account.ID)
			return nil
		}

		// FIX: Only send notification if the worker is fully onboarded and active.
		if worker.AccountStatus != models.AccountStatusActive || worker.SetupProgress != models.SetupProgressDone {
			utils.Logger.Infof("Ignoring capability.updated event for inactive/onboarding worker %s. This is expected.", worker.ID)
			return nil
		}

		dummyPayout := &internal_models.WorkerPayout{
			WorkerID:          worker.ID,
			LastFailureReason: utils.Ptr(fmt.Sprintf("Your account's ability to receive transfers was disabled by Stripe. Please visit the Stripe Express dashboard to resolve any outstanding issues.")),
		}
		s.sendFailureNotification(ctx, dummyPayout, true)
	}
	return nil
}

func (s *PayoutService) HandleTransferEvent(ctx context.Context, t *stripe.Transfer) error {
	if generator, ok := t.Metadata[constants.WebhookMetadataGeneratedByKey]; !ok || generator != s.generatedBy {
		var g string
		if !ok {
			g = notSetLog
		} else {
			g = generator
		}
		utils.Logger.Infof("Ignoring transfer.reversed event for Transfer %s because its 'generated_by' is '%s' (does not match current instance).", t.ID, g)
		return nil
	}

	payoutIDStr, ok := t.Metadata[constants.WebhookMetadataPayoutIDKey]
	if !ok {
		// This should not happen if 'generated_by' is present, but it is a good safeguard.
		utils.Logger.Warnf("transfer.reversed event for Transfer %s has matching 'generated_by' but is missing 'payout_id' in metadata. Ignoring.", t.ID)
		return nil
	}

	payoutID, err := uuid.Parse(payoutIDStr)
	if err != nil {
		utils.Logger.WithError(err).Errorf("Invalid UUID in transfer metadata for transfer %s: %s", t.ID, payoutIDStr)
		return nil
	}

	p, err := s.payoutRepo.GetByID(ctx, payoutID)
	if err != nil || p == nil {
		// It's possible the payout was resolved manually, so this is not a critical error.
		// A warning is sufficient.
		utils.Logger.WithError(err).Warnf("Received 'transfer.reversed' for Transfer %s but could not find associated internal Payout %s. Please investigate if this was unexpected.", t.ID, payoutID)
		return nil
	}

	// As per new requirements, a transfer reversal is a rare, manual operation.
	// We will log it for visibility but will not automatically fail the associated payout,
	// as the resolution will likely be a manual process or handled in a subsequent pay run.
	utils.Logger.Warnf("Received 'transfer.reversed' event for Transfer %s (associated with internal Payout %s for Worker %s). This is a manual operation and does not automatically fail the payout. Please investigate.", t.ID, p.ID, p.WorkerID)
	return nil
}

func (s *PayoutService) HandleBalanceAvailableEvent(ctx context.Context, b *stripe.Balance) error {
	// Use TryLock to ensure that only one recovery process can run at a time,
	// preventing race conditions from multiple concurrent `balance.available` webhooks.
	if !s.recoveryMu.TryLock() {
		utils.Logger.Info("Balance recovery process is already running. Skipping this event.")
		return nil
	}
	utils.Logger.Debug("Acquired balance recovery lock.")

	// This function now releases the lock on all exit paths using defer.
	defer func() {
		s.recoveryMu.Unlock()
		utils.Logger.Debug("Released balance recovery lock.")
	}()

	utils.Logger.Info("Received balance.available event. Checking for payouts that failed due to insufficient funds.")

	failedPayouts, err := s.payoutRepo.FindFailedByReason(ctx, string(stripe.ErrorCodeBalanceInsufficient))
	if err != nil {
		utils.Logger.WithError(err).Error("Failed to find payouts that failed due to insufficient balance")
		return err
	}

	if len(failedPayouts) == 0 {
		utils.Logger.Info("No payouts found that failed due to insufficient balance. Nothing to do.")
		return nil
	}

	utils.Logger.Infof("Found %d payouts to re-queue for processing.", len(failedPayouts))
	for _, p := range failedPayouts {
		err := s.payoutRepo.UpdateWithRetry(ctx, p.ID, func(payoutToUpdate *internal_models.WorkerPayout) error {
			utils.Logger.Infof("Re-queueing payout %s for worker %s.", payoutToUpdate.ID, payoutToUpdate.WorkerID)
			payoutToUpdate.Status = internal_models.PayoutStatusPending
			payoutToUpdate.NextAttemptAt = utils.Ptr(time.Now().UTC())
			return nil
		})
		if err != nil {
			utils.Logger.WithError(err).Errorf("Failed to re-queue payout %s", p.ID)
		}
	}

	// Trigger processing in a goroutine to not block the webhook response.
	// We pass a new, detached context to the goroutine.
	go func() {
		// This goroutine now manages its own lifecycle without holding the lock.
		bgCtx, cancel := context.WithTimeout(context.Background(), constants.BalanceRecoveryProcessTimeout)
		defer cancel()

		// Start with an initial delay to give Stripe's systems a moment to sync.
		utils.Logger.Debugf("Balance recovery goroutine started. Waiting for initial delay.")
		time.Sleep(constants.BalanceRecoveryInitialDelay)

		const maxRetries = 5
		var backoff = constants.BalanceRecoveryInitialBackoff

		for i := range maxRetries {
			utils.Logger.Infof("Attempt %d/%d: Triggering payout processing after 'balance.available' event.", i+1, maxRetries)
			err := s.ProcessPendingPayouts(bgCtx)

			if err == nil {
				utils.Logger.Info("Successfully processed payouts after 'balance.available' event.")
				return // Success!
			}

			// If it's not the specific insufficient balance error, fail fast.
			if !errors.Is(err, internal_utils.ErrBalanceInsufficient) {
				utils.Logger.WithError(err).Error("Failed to process pending payouts with a non-recoverable error after balance top-up.")
				return
			}

			// If it was `errBalanceInsufficient` and we have retries left, re-queue and try again.
			if i < maxRetries-1 {
				utils.Logger.Warnf("Payout processing still failed with insufficient balance. Re-queueing for another attempt in %v...", backoff)

				// The previous attempt marked the payout as FAILED. We must find it and put it back
				// into the PENDING state so the next iteration of this loop can pick it up.
				payoutsToRequeue, findErr := s.payoutRepo.FindFailedByReason(bgCtx, string(stripe.ErrorCodeBalanceInsufficient))
				if findErr != nil {
					utils.Logger.WithError(findErr).Error("Could not re-query for failed payouts during recovery retry loop.")
					return // Cannot continue if we can't query the database.
				}

				if len(payoutsToRequeue) == 0 {
					utils.Logger.Warn("A balance insufficient error was reported, but no payouts are in the corresponding failed state. Assuming process is complete.")
					return
				}

				for _, p := range payoutsToRequeue {
					updateErr := s.payoutRepo.UpdateWithRetry(bgCtx, p.ID, func(payoutToUpdate *internal_models.WorkerPayout) error {
						payoutToUpdate.Status = internal_models.PayoutStatusPending
						return nil
					})
					if updateErr != nil {
						utils.Logger.WithError(updateErr).Errorf("Failed to re-queue payout %s during recovery retry loop", p.ID)
					}
				}

				time.Sleep(backoff)
				backoff *= 2
			}
		}
		utils.Logger.Error("Gave up processing payouts after multiple retries due to persistent 'balance_insufficient' error.")
	}()

	return nil
}

// IsFailureRecoverable determines if a failure is transient and can be retried automatically,
// and whether the failure requires action from the worker. It is now exported.
func IsFailureRecoverable(reason string) (isSystemRecoverable bool, requiresUserAction bool) {
	switch reason {
	// --- Failures requiring USER ACTION (not system-recoverable) ---
	case string(stripe.PayoutFailureCodeAccountClosed),
		string(stripe.PayoutFailureCodeBankAccountRestricted),
		string(stripe.PayoutFailureCodeInvalidAccountNumber),
		string(stripe.ErrorCodePayoutsNotAllowed),
		constants.ReasonMissingStripeID,
		constants.ReasonAccountPayoutsDisabled,
		constants.StripeFailureCodeAccountRestricted,
		string(stripe.PayoutFailureCodeNoAccount),
		string(stripe.PayoutFailureCodeDebitNotAuthorized),
		string(stripe.PayoutFailureCodeInvalidCurrency),
		string(stripe.PayoutFailureCodeAccountFrozen),
		string(stripe.PayoutFailureCodeBankOwnershipChanged),
		string(stripe.PayoutFailureCodeDeclined),
		string(stripe.PayoutFailureCodeIncorrectAccountHolderName),
		string(stripe.PayoutFailureCodeIncorrectAccountHolderTaxID):
		return false, true

	// --- Failures that are SYSTEM-RECOVERABLE (transient or platform-side) ---
	case string(stripe.ErrorCodeBalanceInsufficient),
		string(stripe.PayoutFailureCodeCouldNotProcess),
		constants.ReasonUnknownStripeAccountError,
		constants.ReasonUnknownStripeTransferError,
		constants.ReasonPayoutInitiationFailed:
		return true, false

	// --- FINAL failures (not system-recoverable, not user's fault) ---
	case string(stripe.PayoutFailureCodeInsufficientFunds): // This is the Connect Account's balance, not the platform's.
		return false, false

	// Default: Treat unknown errors as final and not user-actionable.
	default:
		return false, false
	}
}

func toPtrSlice(events []string) []*string {
	out := make([]*string, len(events))
	for i, s := range events {
		out[i] = stripe.String(s)
	}
	return out
}

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
