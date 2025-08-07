//go:build (dev_test || staging_test) && integration

package integration

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/poofware/mono-repo/backend/services/earnings-service/internal/constants"
	"github.com/poofware/mono-repo/backend/services/earnings-service/internal/dtos"
	internal_models "github.com/poofware/mono-repo/backend/services/earnings-service/internal/models"
	internal_repositories "github.com/poofware/mono-repo/backend/services/earnings-service/internal/repositories"
	"github.com/poofware/mono-repo/backend/services/earnings-service/internal/routes"
	"github.com/poofware/mono-repo/backend/services/earnings-service/internal/services"
	internal_utils "github.com/poofware/mono-repo/backend/services/earnings-service/internal/utils"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/stripe/stripe-go/v82"
)

// Pre-configured Stripe Test Account IDs for various scenarios
const (
	// Success path
	stripeAcctSuccess = "acct_1RZHahCLd3ZjFFWN"
	// This account is incomplete and thus payouts are disabled. Fails synchronously.
	onboardingIncompletePayoutDisabled = "acct_1RZEmOFqsVmP038F"
	// Failure paths. These accounts pass synchronous checks but fail later via webhook.
	stripeAcctNoAccount          = "acct_1RZHmhFoqLsYiZzr" // "no_account"
	stripeAcctClosed             = "acct_1RZHr6FygW9J4bUS" // "account_closed"
	stripeAcctInsufficientFunds  = "acct_1RZHtcFsyFdceR1B" // "insufficient_funds"
	stripeAcctDebitNotAuthorized = "acct_1RZHx2C5ZpWdYHoX" // "debit_not_authorized"

	//** NO NEED TO USE RIGHT NOW **//
	stripeAcctInstantPayoutsUnsupported = "acct_1RZI2AFgR7qvFutE" // "instant_payouts_unsupported"
	stripeAcctInvalidCurrency           = "acct_1RZHzDCTuJsNNvQa" // "invalid_currency"
)

var (
	// mu and workersForStripeAccounts provide a thread-safe way to ensure each
	// special Stripe test account is associated with only one worker record
	// for the entire duration of the test suite, preventing unique constraint errors.
	mu                       sync.Mutex
	workersForStripeAccounts = make(map[string]*models.Worker)
)

// getOrCreateWorkerForStripeAccount ensures that for any given Stripe account ID, we only create
// one worker record in the database throughout the test suite. This prevents unique
// constraint violations ("workers_stripe_connect_account_id_key") when multiple
// tests need to reference the same special Stripe test account, especially when data is pre-seeded.
func getOrCreateWorkerForStripeAccount(t *testing.T, ctx context.Context, emailPrefix, stripeID string) *models.Worker {
	mu.Lock()
	defer mu.Unlock()

	// 1. Check in-memory cache first for subsequent calls within the same test suite.
	if worker, exists := workersForStripeAccounts[stripeID]; exists {
		t.Logf("Reusing worker %s for Stripe account %s from memory cache", worker.ID, stripeID)
		return worker
	}

	// 2. Check database for pre-existing worker (e.g., from the seeder).
	existingWorker, err := h.WorkerRepo.GetByStripeConnectAccountID(ctx, stripeID)
	require.NoError(t, err, "Failed to check for existing worker by Stripe ID")

	if existingWorker != nil {
		t.Logf("Found pre-existing worker %s for Stripe account %s in database", existingWorker.ID, stripeID)
		workersForStripeAccounts[stripeID] = existingWorker // Cache it for subsequent tests
		return existingWorker
	}

	// 3. If not found in cache or DB, create a new one.
	t.Logf("Creating new worker for Stripe account %s", stripeID)
	worker := h.CreateTestWorkerWithConnectID(ctx, emailPrefix, stripeID)
	workersForStripeAccounts[stripeID] = worker
	return worker
}

/*
------------------------------------------------------------------------------

	Test 1: Payout Lifecycle (Aggregation & Processing)

------------------------------------------------------------------------------
This test verifies the core service logic that is called by cron jobs,
ensuring the business logic for creating and processing payouts works as
expected against various real Stripe account states.
*/
func TestPayoutLifecycle(t *testing.T) {
	h.T = t
	ctx := context.Background()
	stripe.Key = cfg.StripeSecretKey
	h.SeedPlatformBalance(t, 20000, "usd") // Instantly fund with $200.00

	payoutRepo := internal_repositories.NewWorkerPayoutRepository(h.DB)
	payoutService := services.NewPayoutService(cfg, h.WorkerRepo, h.JobInstRepo, payoutRepo)
	// This MUST align with the service's internal logic, which always processes the *previous* pay period.
	lastWeek := getPreviousWeekPayPeriodStart()

	// --- Setup: Create workers and jobs for various scenarios ---
	// 1. Worker who ALREADY HAS a paid payout from the seeder for the target week.
	// The service should see this and NOT create a new payout record. This tests idempotency.
	workerWithExistingPayout := getOrCreateWorkerForStripeAccount(t, ctx, "lifecycle-seeded", stripeAcctSuccess)

	// 2. Worker who WILL HAVE a payout created, but it will fail due to no Stripe ID.
	workerFailNoAcct := h.CreateTestWorker(ctx, "lifecycle-no-acct")

	// 3. Worker who WILL HAVE a payout created, which succeeds synchronously but fails asynchronously.
	// This Stripe account is NOT used by the seeder, so it won't have a unique key conflict.
	workerFailAsync := getOrCreateWorkerForStripeAccount(t, ctx, "lifecycle-fail-async", stripeAcctClosed)

	// 4. Worker with earnings below the minimum payout threshold.
	workerLowPay := h.CreateTestWorker(ctx, "lifecycle-low-pay")

	// --- Create Job Definition and Instances ---
	prop := h.CreateTestProperty(ctx, "LifecycleTestProp", testPM.ID, 0, 0)
	earliest, latest := h.TestSameDayTimeWindow()
	def := h.CreateTestJobDefinition(t, ctx, testPM.ID, prop.ID, "LifecycleJobDef", nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)

	// Create jobs within the *exact* pay period the service will aggregate.
	h.CreateTestJobInstance(t, ctx, def.ID, lastWeek.AddDate(0, 0, 1), models.InstanceStatusCompleted, &workerWithExistingPayout.ID, 50.00) // Job will be found, but payout record exists
	h.CreateTestJobInstance(t, ctx, def.ID, lastWeek.AddDate(0, 0, 2), models.InstanceStatusCompleted, &workerFailNoAcct.ID, 60.00)
	h.CreateTestJobInstance(t, ctx, def.ID, lastWeek.AddDate(0, 0, 3), models.InstanceStatusCompleted, &workerFailAsync.ID, 70.00)
	h.CreateTestJobInstance(t, ctx, def.ID, lastWeek.AddDate(0, 0, 4), models.InstanceStatusCompleted, &workerLowPay.ID, 0.45) // Below $0.50 threshold

	var pFailNoAcct, pFailAsync *internal_models.WorkerPayout

	// --- Test 1.1: Aggregation Logic ---
	t.Run("AggregateAndCreatePayouts", func(t *testing.T) {
		h.T = t
		err := payoutService.AggregateAndCreatePayouts(ctx)
		require.NoError(t, err)

		// Verification for the worker who was pre-seeded.
		// The service should have found the existing payout and skipped creating a new one.
		// We assert that the record is still the one from the seeder.
		pExisting, err := payoutRepo.GetByWorkerAndWeek(ctx, workerWithExistingPayout.ID, lastWeek)
		require.NoError(t, err)
		require.NotNil(t, pExisting, "Expected to find the payout record created by the seeder")
		require.Equal(t, int64(5800), pExisting.AmountCents, "Seeded payout amount should not be modified by aggregation logic")
		require.Equal(t, internal_models.PayoutStatusPaid, pExisting.Status, "Seeded payout status should not be modified")

		// Verify new PENDING payouts were created correctly for the other workers.
		pFailNoAcct, _ = payoutRepo.GetByWorkerAndWeek(ctx, workerFailNoAcct.ID, lastWeek)
		require.NotNil(t, pFailNoAcct, "A new payout record should have been created for the worker with no Stripe ID")
		require.Equal(t, int64(6000), pFailNoAcct.AmountCents)
		require.Equal(t, internal_models.PayoutStatusPending, pFailNoAcct.Status)

		pFailAsync, _ = payoutRepo.GetByWorkerAndWeek(ctx, workerFailAsync.ID, lastWeek)
		require.NotNil(t, pFailAsync, "A new payout record should have been created for the async-failing worker")
		require.Equal(t, int64(7000), pFailAsync.AmountCents)
		require.Equal(t, internal_models.PayoutStatusPending, pFailAsync.Status)

		// Verify no payout was created for the low-pay worker
		pLowPay, _ := payoutRepo.GetByWorkerAndWeek(ctx, workerLowPay.ID, lastWeek)
		require.Nil(t, pLowPay, "No payout should be created for earnings below the minimum threshold")
	})

	// --- Test 1.2: Processing Logic & Final Asynchronous Results ---
	t.Run("ProcessPayoutsAndVerifyFinalStates", func(t *testing.T) {
		h.T = t
		err := payoutService.ProcessPendingPayouts(ctx)
		require.NoError(t, err)

		// Note: We don't need to test the pre-seeded worker here, as their payout is already PAID
		// and won't be picked up by `ProcessPendingPayouts`.

		// Payout for worker with no Stripe ID should fail synchronously.
		finalFailNoAcct, _ := payoutRepo.GetByWorkerAndWeek(ctx, workerFailNoAcct.ID, lastWeek)
		require.NotNil(t, finalFailNoAcct)
		require.Equal(t, internal_models.PayoutStatusFailed, finalFailNoAcct.Status)
		require.Equal(t, constants.ReasonMissingStripeID, *finalFailNoAcct.LastFailureReason)

		// Asynchronously failing payout should end up as FAILED.
		finalFailAsync := waitForPayoutStatus(t, ctx, payoutRepo, pFailAsync.ID, internal_models.PayoutStatusFailed, 30*time.Second)
		require.NotNil(t, finalFailAsync)
		require.NotNil(t, finalFailAsync.StripeTransferID, "Payout should have a transfer ID after synchronous processing, even if it fails asynchronously.")
	})
}

/*
------------------------------------------------------------------------------

	Test 2: Real Webhook Event Handling

------------------------------------------------------------------------------
This test triggers actions that cause Stripe to send real webhooks back to
the service, verifying the service handles these asynchronous events correctly.
This is used for common, triggerable events like payout.paid and payout.failed.
*/
func TestRealWebhookEvents(t *testing.T) {
	h.T = t
	ctx := context.Background()
	stripe.Key = cfg.StripeSecretKey
	h.SeedPlatformBalance(t, 20000, "usd") // Instantly fund with $200.00

	payoutRepo := internal_repositories.NewWorkerPayoutRepository(h.DB)
	payoutService := services.NewPayoutService(cfg, h.WorkerRepo, h.JobInstRepo, payoutRepo)
	// Use a unique week to prevent data conflicts with other tests
	testWeek := getPreviousWeekPayPeriodStart().AddDate(0, 0, -14)

	// --- Test 2.1: Real `payout.paid` ---
	// This test confirms that a successful payout is marked as PAID after the
	// confirmation webhook arrives.
	t.Run("HandleRealPayoutPaid", func(t *testing.T) {
		h.T = t
		worker := getOrCreateWorkerForStripeAccount(t, ctx, "real-webhook-paid", stripeAcctSuccess)
		payout := createTestPayout(t, ctx, payoutRepo, worker.ID, 1234, internal_models.PayoutStatusPending, nil, testWeek, []uuid.UUID{})

		// Process the payout, which should synchronously mark the status as PROCESSING.
		err := payoutService.ProcessPendingPayouts(ctx)
		require.NoError(t, err)

		// Verify the synchronous status is PROCESSING.
		interimPayout, err := payoutRepo.GetByID(ctx, payout.ID)
		require.NoError(t, err)
		require.Equal(t, internal_models.PayoutStatusProcessing, interimPayout.Status, "Payout should be marked as PROCESSING synchronously")

		// Now poll for the final PAID status, which is set by the webhook.
		finalPayout := waitForPayoutStatus(t, ctx, payoutRepo, payout.ID, internal_models.PayoutStatusPaid, 15*time.Second)
		require.NotNil(t, finalPayout.StripeTransferID)
	})

	// --- Test 2.2: Real `payout.failed` from various test accounts ---
	// These accounts pass the synchronous `transfer` API call but trigger an asynchronous
	// `payout.failed` webhook later. This test verifies that flow.
	failureScenarios := []struct {
		name         string
		accountID    string
		reasonCode   stripe.PayoutFailureCode
		payoutAmount int64
	}{
		{name: "NoAccount", accountID: stripeAcctNoAccount, reasonCode: stripe.PayoutFailureCodeNoAccount, payoutAmount: 1001},
		{name: "AccountClosed", accountID: stripeAcctClosed, reasonCode: stripe.PayoutFailureCodeAccountClosed, payoutAmount: 1002},
		{name: "InsufficientFunds", accountID: stripeAcctInsufficientFunds, reasonCode: stripe.PayoutFailureCodeInsufficientFunds, payoutAmount: 1003},
		{name: "DebitNotAuthorized", accountID: stripeAcctDebitNotAuthorized, reasonCode: stripe.PayoutFailureCodeDebitNotAuthorized, payoutAmount: 1004},
	}

	for _, sc := range failureScenarios {
		t.Run("HandleRealPayoutFailed_"+sc.name, func(t *testing.T) {
			h.T = t
			// 1. Setup a unique worker and a new PENDING payout
			worker := getOrCreateWorkerForStripeAccount(t, ctx, "real-wh-fail-"+sc.name, sc.accountID)
			// Use a date unique to this sub-test to avoid conflicts within the loop
			uniqueTestWeek := testWeek.AddDate(0, 0, -7*int(worker.ID.ClockSequence()))
			payout := createTestPayout(t, ctx, payoutRepo, worker.ID, sc.payoutAmount, internal_models.PayoutStatusPending, nil, uniqueTestWeek, []uuid.UUID{})

			// 2. Action: Process pending payouts. Our specific payout will be picked up.
			err := payoutService.ProcessPendingPayouts(ctx)
			require.NoError(t, err)

			// 3. Verify final asynchronous status.
			// The check for the intermediate 'PROCESSING' status is removed because, with the race
			// condition fixed, the 'payout.failed' webhook can arrive so quickly that the status
			// is already 'FAILED' by the time we check it. We now poll directly for the final state.
			t.Logf("Polling for FAILED status for account %s...", sc.accountID)
			finalPayout := waitForPayoutStatus(t, ctx, payoutRepo, payout.ID, internal_models.PayoutStatusFailed, 30*time.Second)
			require.NotNil(t, finalPayout, "Payout did not transition to FAILED status in time")
			require.NotNil(t, finalPayout.LastFailureReason)
			require.Equal(t, string(sc.reasonCode), *finalPayout.LastFailureReason, "Payout failure reason mismatch")
		})
	}
}

/*
------------------------------------------------------------------------------

	Test 3: Mocked Webhook Event Handling

------------------------------------------------------------------------------
This test simulates various webhook events from Stripe by mocking and sending
the payloads manually. This is used for edge cases that are difficult to
trigger reliably in a test environment. It verifies that the service correctly
updates the state of the corresponding payout records.
*/
func TestMockedWebhookEventHandling(t *testing.T) {
	h.T = t
	ctx := context.Background()
	payoutRepo := internal_repositories.NewWorkerPayoutRepository(h.DB)
	generatedBy := fmt.Sprintf("%s-%s-%s", cfg.AppName, cfg.UniqueRunnerID, cfg.UniqueRunNumber)
	// Use a unique week to prevent data conflicts with other tests
	testWeek := getPreviousWeekPayPeriodStart().AddDate(0, 0, -21)

	// --- Setup a base worker and payout for testing against ---
	worker := getOrCreateWorkerForStripeAccount(t, ctx, "webhook-worker", stripeAcctSuccess)
	trID := "tr_wh_" + uuid.NewString()[:12]
	// Start in a PROCESSING state, as this is the state before a webhook arrives.
	payout := createTestPayout(t, ctx, payoutRepo, worker.ID, 5000, internal_models.PayoutStatusProcessing, &trID, testWeek, []uuid.UUID{})

	// --- Test 3.1: `payout.paid` ---
	t.Run("HandlePayoutPaidWebhook", func(t *testing.T) {
		h.T = t
		// Reset state to PROCESSING before this test
		err := payoutRepo.UpdateWithRetry(ctx, payout.ID, func(pToUpdate *internal_models.WorkerPayout) error {
			pToUpdate.Status = internal_models.PayoutStatusProcessing
			return nil
		})
		require.NoError(t, err)

		paidPayload := h.MockStripeWebhookPayload(t, "payout.paid", map[string]any{
			"id":     "po_mock_paid_" + uuid.NewString()[:6],
			"object": "payout",
			"status": "paid",
			"metadata": map[string]string{
				constants.WebhookMetadataPayoutIDKey:    payout.ID.String(),
				constants.WebhookMetadataGeneratedByKey: generatedBy,
			},
		})
		h.PostStripeWebhook(h.BaseURL+routes.EarningsStripeWebhook, string(paidPayload))
		time.Sleep(500 * time.Millisecond)

		updatedPayout, _ := payoutRepo.GetByID(ctx, payout.ID)
		require.Equal(t, internal_models.PayoutStatusPaid, updatedPayout.Status)
	})

	// --- Test 3.2: `payout.failed` with various failure codes ---
	failureScenarios := []struct {
		name       string
		failCode   stripe.PayoutFailureCode
		payoutID   string
		transferID string
	}{
		{name: "no_account", failCode: stripe.PayoutFailureCodeNoAccount, payoutID: "po_fail_no_acct", transferID: "tr_fail_no_acct"},
		{name: "insufficient_funds", failCode: stripe.PayoutFailureCodeInsufficientFunds, payoutID: "po_fail_nsf", transferID: "tr_fail_nsf"},
		{name: "debit_not_authorized", failCode: stripe.PayoutFailureCodeDebitNotAuthorized, payoutID: "po_fail_debit", transferID: "tr_fail_debit"},
		{name: "invalid_currency", failCode: stripe.PayoutFailureCodeInvalidCurrency, payoutID: "po_fail_curr", transferID: "tr_fail_curr"},
	}

	for _, sc := range failureScenarios {
		t.Run("HandlePayoutFailedWebhook_"+sc.name, func(t *testing.T) {
			h.T = t
			// Reset state to PROCESSING before this test
			err := payoutRepo.UpdateWithRetry(ctx, payout.ID, func(pToUpdate *internal_models.WorkerPayout) error {
				pToUpdate.Status = internal_models.PayoutStatusProcessing
				return nil
			})
			require.NoError(t, err)

			failedPayload := h.MockStripeWebhookPayload(t, "payout.failed", map[string]any{
				"id":           sc.payoutID,
				"object":       "payout",
				"status":       "failed",
				"failure_code": string(sc.failCode),
				"metadata": map[string]string{
					constants.WebhookMetadataPayoutIDKey:    payout.ID.String(),
					constants.WebhookMetadataGeneratedByKey: generatedBy,
				},
			})

			h.PostStripeWebhook(h.BaseURL+routes.EarningsStripeWebhook, string(failedPayload))

			// Add a small delay to allow webhook processing
			time.Sleep(500 * time.Millisecond)

			updatedPayout, _ := payoutRepo.GetByID(ctx, payout.ID)
			require.Equal(t, internal_models.PayoutStatusFailed, updatedPayout.Status)
			require.Equal(t, string(sc.failCode), *updatedPayout.LastFailureReason)
		})
	}

	// --- Test 3.3: Ignore webhooks with incorrect metadata ---
	t.Run("IgnoreWebhookWithMismatchedMetadata", func(t *testing.T) {
		h.T = t
		// Reset state to PAID
		err := payoutRepo.UpdateWithRetry(ctx, payout.ID, func(pToUpdate *internal_models.WorkerPayout) error {
			pToUpdate.Status = internal_models.PayoutStatusPaid
			return nil
		})
		require.NoError(t, err)

		irrelevantPayload := h.MockStripeWebhookPayload(t, "account.updated", map[string]any{
			"id":       "acct_irrelevant",
			"object":   "account",
			"metadata": map[string]string{constants.WebhookMetadataGeneratedByKey: "some-other-service"},
		})

		h.PostStripeWebhook(h.BaseURL+routes.EarningsStripeWebhook, string(irrelevantPayload))

		// Verify the payout status did NOT change
		payoutAfter, _ := payoutRepo.GetByID(ctx, payout.ID)
		require.Equal(t, internal_models.PayoutStatusPaid, payoutAfter.Status)
	})

	// --- Test 3.4: Handle `transfer.reversed` Webhook ---
	t.Run("HandleTransferReversedWebhook", func(t *testing.T) {
		h.T = t
		// Reset state to PROCESSING and ensure it has a transfer ID
		reversedTrID := "tr_rev_" + uuid.NewString()[:12]
		err := payoutRepo.UpdateWithRetry(ctx, payout.ID, func(pToUpdate *internal_models.WorkerPayout) error {
			pToUpdate.Status = internal_models.PayoutStatusProcessing
			pToUpdate.StripeTransferID = &reversedTrID
			return nil
		})
		require.NoError(t, err)

		// Mock a transfer.reversed event for the transfer associated with our payout
		reversedPayload := h.MockStripeWebhookPayload(t, "transfer.reversed", map[string]any{
			"id":     reversedTrID,
			"object": "transfer",
			"metadata": map[string]string{
				constants.WebhookMetadataPayoutIDKey:    payout.ID.String(),
				constants.WebhookMetadataGeneratedByKey: generatedBy,
			},
		})
		h.PostStripeWebhook(h.BaseURL+routes.EarningsStripeWebhook, string(reversedPayload))
		time.Sleep(500 * time.Millisecond)

		// The core assertion: the status should NOT change. The service should only log a warning.
		updatedPayout, _ := payoutRepo.GetByID(ctx, payout.ID)
		require.Equal(t, internal_models.PayoutStatusProcessing, updatedPayout.Status, "Payout status should not change after a transfer.reversed event")
	})

	// --- Test 3.5: Handle Legacy `payout.paid` Webhook via Transfer Metadata ---
	t.Run("HandleLegacyPayoutPaidWebhook", func(t *testing.T) {
		h.T = t
		// Create a new payout for this test case for isolation
		legacyWorker := getOrCreateWorkerForStripeAccount(t, ctx, "legacy-webhook-worker", stripeAcctSuccess)
		legacyTestWeek := testWeek.AddDate(0, 0, -7)
		legacyTrID := "tr_legacy_" + uuid.NewString()[:12]
		legacyPayout := createTestPayout(t, ctx, payoutRepo, legacyWorker.ID, 4321, internal_models.PayoutStatusProcessing, &legacyTrID, legacyTestWeek, []uuid.UUID{})

		// This payload simulates an event where the payout object itself has no metadata,
		// but the source transfer (nested inside the balance transaction) does.
		legacyPayload := h.MockStripeWebhookPayload(t, "payout.paid", map[string]any{
			"id":     "po_legacy_" + uuid.NewString()[:6],
			"object": "payout",
			"status": "paid",
			// No metadata at the top level
			"balance_transaction": map[string]any{
				"id":     "txn_legacy_" + uuid.NewString()[:6],
				"object": "balance_transaction",
				"source": map[string]any{
					"id":     *legacyPayout.StripeTransferID,
					"object": "transfer",
					"metadata": map[string]string{ // The crucial metadata is on the transfer
						constants.WebhookMetadataPayoutIDKey:    legacyPayout.ID.String(),
						constants.WebhookMetadataGeneratedByKey: generatedBy,
					},
				},
			},
		})

		h.PostStripeWebhook(h.BaseURL+routes.EarningsStripeWebhook, string(legacyPayload))

		// Verify that the fallback logic correctly found the payout and updated its status.
		finalPayout := waitForPayoutStatus(t, ctx, payoutRepo, legacyPayout.ID, internal_models.PayoutStatusPaid, 5*time.Second)
		require.NotNil(t, finalPayout)
	})
}

/*
------------------------------------------------------------------------------

	Test 4: Webhook-Driven Recovery Flow

------------------------------------------------------------------------------
This test verifies that the service can recover a failed payout after a
worker updates their Stripe account, triggering an `account.updated` webhook.
*/
func TestWebhookDrivenRecovery(t *testing.T) {
	h.T = t
	ctx := context.Background()
	stripe.Key = cfg.StripeSecretKey
	h.SeedPlatformBalance(t, 10000, "usd") // Instantly fund with $100.00

	payoutRepo := internal_repositories.NewWorkerPayoutRepository(h.DB)
	payoutService := services.NewPayoutService(cfg, h.WorkerRepo, h.JobInstRepo, payoutRepo)
	// Use a unique week to prevent data conflicts with other tests
	testWeek := getPreviousWeekPayPeriodStart().AddDate(0, 0, -28)

	// --- 1. Setup: Create a worker with a restricted account and cause a payout to fail ---
	// We use a real test account that fails asynchronously.
	worker := getOrCreateWorkerForStripeAccount(t, ctx, "recovery-worker", stripeAcctClosed)

	payoutToFail := createTestPayout(t, ctx, payoutRepo, worker.ID, 8800, internal_models.PayoutStatusPending, nil, testWeek, []uuid.UUID{})
	err := payoutService.ProcessPendingPayouts(ctx)
	require.NoError(t, err)

	// Verify the payout is now FAILED by waiting for the async webhook.
	payout := waitForPayoutStatus(t, ctx, payoutRepo, payoutToFail.ID, internal_models.PayoutStatusFailed, 30*time.Second)
	require.NotNil(t, payout)
	require.Equal(t, string(stripe.PayoutFailureCodeAccountClosed), *payout.LastFailureReason)

	// --- 2. Action: Simulate the user fixing their account ---
	// In a real scenario, the user's existing account status would change. We simulate this by sending
	// an `account.updated` webhook for their CURRENT Stripe ID (`stripeAcctClosed`), but with
	// payouts now enabled. This mimics Stripe notifying us that the account issues are resolved.
	t.Logf("Simulating user fixing their account details...")
	accountUpdatedPayload := h.MockStripeWebhookPayload(t, "account.updated", map[string]any{
		"id":                *worker.StripeConnectAccountID, // Webhook is for the worker's EXISTING account
		"object":            "account",
		"payouts_enabled":   true, // The key change indicating the account is now healthy
		"details_submitted": true,
	})
	h.PostStripeWebhook(h.BaseURL+routes.EarningsStripeWebhook, string(accountUpdatedPayload))

	// --- 3. Verification: Check if payout was re-queued ---
	// Give the webhook a moment to be processed. The test is complete once we verify
	// that the webhook handler successfully re-queued the failed payout.
	payout = waitForPayoutStatus(t, ctx, payoutRepo, payout.ID, internal_models.PayoutStatusPending, 15*time.Second)
	require.NotNil(t, payout, "Payout was not re-queued to PENDING after account.updated webhook")
	require.NotNil(t, payout.NextAttemptAt, "NextAttemptAt should be set for the retry")
	t.Logf("Successfully verified that payout %s was re-queued to PENDING.", payout.ID)

	// --- 4. Ensure duplicate payout.failed webhooks do not alter the re-queued payout ---
	generatedBy := fmt.Sprintf("%s-%s-%s", cfg.AppName, cfg.UniqueRunnerID, cfg.UniqueRunNumber)
	dupPayload := h.MockStripeWebhookPayload(t, "payout.failed", map[string]any{
		"id":           *payout.StripePayoutID,
		"object":       "payout",
		"status":       "failed",
		"failure_code": string(stripe.PayoutFailureCodeAccountClosed),
		"metadata": map[string]string{
			constants.WebhookMetadataPayoutIDKey:    payout.ID.String(),
			constants.WebhookMetadataGeneratedByKey: generatedBy,
		},
	})
	h.PostStripeWebhook(h.BaseURL+routes.EarningsStripeWebhook, string(dupPayload))
	time.Sleep(500 * time.Millisecond)

	payoutAfterDup, _ := payoutRepo.GetByID(ctx, payout.ID)
	require.Equal(t, internal_models.PayoutStatusPending, payoutAfterDup.Status, "Duplicate webhook should not alter payout status")
}

/*
------------------------------------------------------------------------------

	Test 5: Earnings Summary API Endpoint

------------------------------------------------------------------------------
*/
func TestGetEarningsSummaryEndpoint(t *testing.T) {
	h.T = t
	ctx := context.Background()
	payoutRepo := internal_repositories.NewWorkerPayoutRepository(h.DB)
	loc, _ := time.LoadLocation(constants.BusinessTimezone)

	t.Run("Weekly - ForWorkerWithComplexHistory", func(t *testing.T) {
		h.T = t
		// Temporarily ensure weekly payout mode is active for this test.
		originalPayPeriodFlag := cfg.LDFlag_UseShortPayPeriod
		cfg.LDFlag_UseShortPayPeriod = false
		defer func() { cfg.LDFlag_UseShortPayPeriod = originalPayPeriodFlag }()

		worker := h.CreateTestWorker(ctx, "summary-worker-weekly")
		jwt := h.CreateMobileJWT(worker.ID, "summary-device-weekly", "FAKE-PLAY")
		todayNY := time.Now().In(loc)

		// --- Setup data across multiple weeks, statuses, and a timezone edge case ---
		currentWeekStart := internal_utils.GetPayPeriodStartForDate(todayNY)
		lastWeekStart := currentWeekStart.AddDate(0, 0, -7)
		twoWeeksAgoStart := currentWeekStart.AddDate(0, 0, -14)
		threeWeeksAgoStart := currentWeekStart.AddDate(0, 0, -21)

		prop := h.CreateTestProperty(ctx, "SummaryPropWeekly", testPM.ID, 0, 0)
		earliest, latest := h.TestSameDayTimeWindow()
		def := h.CreateTestJobDefinition(t, ctx, testPM.ID, prop.ID, "SummaryDefWeekly", nil, nil, earliest, latest, models.JobStatusActive, nil, models.JobFreqDaily, nil)

		// SCENARIO 1: PAID week (2 weeks ago). Has a payout record.
		job1 := h.CreateTestJobInstance(t, ctx, def.ID, twoWeeksAgoStart.AddDate(0, 0, 1), models.InstanceStatusCompleted, &worker.ID, 20.50) // Tuesday
		job2 := h.CreateTestJobInstance(t, ctx, def.ID, twoWeeksAgoStart.AddDate(0, 0, 3), models.InstanceStatusCompleted, &worker.ID, 22.00) // Thursday
		createTestPayout(t, ctx, payoutRepo, worker.ID, 4250, internal_models.PayoutStatusPaid, nil, twoWeeksAgoStart, []uuid.UUID{job1.ID, job2.ID})

		// SCENARIO 2: FAILED week (last week). Has a payout record.
		job3 := h.CreateTestJobInstance(t, ctx, def.ID, lastWeekStart.AddDate(0, 0, 2), models.InstanceStatusCompleted, &worker.ID, 35.75) // Wednesday
		failedPayout := createTestPayout(t, ctx, payoutRepo, worker.ID, 3575, internal_models.PayoutStatusFailed, nil, lastWeekStart, []uuid.UUID{job3.ID})
		failureReason := string(stripe.PayoutFailureCodeAccountClosed)
		_, requiresUserAction := services.IsFailureRecoverable(failureReason)
		err := payoutRepo.UpdateWithRetry(ctx, failedPayout.ID, func(p *internal_models.WorkerPayout) error {
			p.LastFailureReason = &failureReason
			return nil
		})
		require.NoError(t, err)

		// SCENARIO 3: PAID week (3 weeks ago). This job is now correctly settled.
		job4 := h.CreateTestJobInstance(t, ctx, def.ID, threeWeeksAgoStart.AddDate(0, 0, 4), models.InstanceStatusCompleted, &worker.ID, 50.00) // Friday
		createTestPayout(t, ctx, payoutRepo, worker.ID, 5000, internal_models.PayoutStatusPaid, nil, threeWeeksAgoStart, []uuid.UUID{job4.ID})

		// SCENARIO 4: CURRENT week job.
		h.CreateTestJobInstance(t, ctx, def.ID, currentWeekStart.AddDate(0, 0, 1), models.InstanceStatusCompleted, &worker.ID, 15.00) // Tuesday

		// SCENARIO 5: UNSETTLED job from a past day that maps to the CURRENT week due to timezone.
		mondayEarlyAM_NY := time.Date(currentWeekStart.Year(), currentWeekStart.Month(), currentWeekStart.Day(), 2, 0, 0, 0, loc)
		h.CreateTestJobInstance(t, ctx, def.ID, mondayEarlyAM_NY.UTC(), models.InstanceStatusCompleted, &worker.ID, 10.00)

		// --- API Call ---
		req := h.BuildAuthRequest("GET", h.BaseURL+routes.EarningsSummary, jwt, nil, "android", "summary-device-weekly")
		resp := h.DoRequest(req, h.NewHTTPClient())
		defer resp.Body.Close()
		bodyStr := h.ReadBody(resp)
		require.Equal(t, http.StatusOK, resp.StatusCode, "Response Body: %s", bodyStr)

		var summary dtos.EarningsSummaryResponse
		err = json.Unmarshal([]byte(bodyStr), &summary)
		require.NoError(t, err, "Failed to decode summary response")

		// --- Verification ---
		// Total includes all jobs, settled and unsettled.
		expectedTotal := 20.50 + 22.00 + 35.75 + 50.00 + 15.00 + 10.00
		require.InDelta(t, expectedTotal, summary.TwoMonthTotal, 0.01)

		expectedNextPayoutDate := internal_utils.GetPayPeriodStartForDate(todayNY).AddDate(0, 0, 8)
		require.Equal(t, expectedNextPayoutDate.Format("2006-01-02"), summary.NextPayoutDate)

		// We now have 3 settled weeks of payouts.
		require.Len(t, summary.PastWeeks, 3, "Should have three past weeks of earnings entries (from payout records)")

		// Past weeks are sorted most recent to oldest.
		failedWeek := summary.PastWeeks[0]
		paidWeekTwo := summary.PastWeeks[1]
		paidWeekThree := summary.PastWeeks[2] // The newly settled week

		// Check FAILED week record (-1)
		require.Equal(t, lastWeekStart.Format("2006-01-02"), failedWeek.WeekStartDate)
		require.InDelta(t, 35.75, failedWeek.WeeklyTotal, 0.01, "WeeklyTotal for a settled payout comes from the record, not the sum of jobs")
		require.Equal(t, 1, failedWeek.JobCount, "Job count should be only the jobs associated with the payout record")
		require.Equal(t, string(internal_models.PayoutStatusFailed), failedWeek.PayoutStatus)
		require.NotNil(t, failedWeek.FailureReason)
		require.Equal(t, failureReason, *failedWeek.FailureReason)
		require.Equal(t, requiresUserAction, failedWeek.RequiresUserAction)
		require.Len(t, failedWeek.DailyBreakdown, 1)

		// Check PAID week (-2)
		require.Equal(t, twoWeeksAgoStart.Format("2006-01-02"), paidWeekTwo.WeekStartDate)
		require.InDelta(t, 42.50, paidWeekTwo.WeeklyTotal, 0.01)
		require.Equal(t, 2, paidWeekTwo.JobCount)
		require.Equal(t, string(internal_models.PayoutStatusPaid), paidWeekTwo.PayoutStatus)

		// Check the newly added PAID week (-3)
		require.Equal(t, threeWeeksAgoStart.Format("2006-01-02"), paidWeekThree.WeekStartDate)
		require.InDelta(t, 50.00, paidWeekThree.WeeklyTotal, 0.01)
		require.Equal(t, 1, paidWeekThree.JobCount)
		require.Equal(t, string(internal_models.PayoutStatusPaid), paidWeekThree.PayoutStatus)

		// Check Current Week.
		// Since the $50.00 job from 3 weeks ago is now correctly associated with a payout,
		// it is no longer considered "unsettled" and will not appear in the current week's total.
		// The total only includes the truly current jobs.
		require.NotNil(t, summary.CurrentWeek)
		require.Equal(t, currentWeekStart.Format("2006-01-02"), summary.CurrentWeek.WeekStartDate)
		// Expected total is $15.00 (current week) + $10.00 (timezone edge case) = $25.00.
		require.InDelta(t, 25.00, summary.CurrentWeek.WeeklyTotal, 0.01)
		require.Equal(t, 2, summary.CurrentWeek.JobCount)
		require.Equal(t, services.PayoutStatusCurrent, summary.CurrentWeek.PayoutStatus)
	})

	t.Run("Weekly - ForWorkerWithNoEarnings", func(t *testing.T) {
		h.T = t
		originalPayPeriodFlag := cfg.LDFlag_UseShortPayPeriod
		cfg.LDFlag_UseShortPayPeriod = false
		defer func() { cfg.LDFlag_UseShortPayPeriod = originalPayPeriodFlag }()

		workerNoPay := h.CreateTestWorker(ctx, "summary-worker-no-pay")
		jwtNoPay := h.CreateMobileJWT(workerNoPay.ID, "no-pay-device", "FAKE-PLAY")

		req := h.BuildAuthRequest("GET", h.BaseURL+routes.EarningsSummary, jwtNoPay, nil, "android", "no-pay-device")
		resp := h.DoRequest(req, h.NewHTTPClient())
		defer resp.Body.Close()
		require.Equal(t, http.StatusOK, resp.StatusCode)

		var summary dtos.EarningsSummaryResponse
		err := json.NewDecoder(resp.Body).Decode(&summary)
		require.NoError(t, err)

		require.InDelta(t, 0.00, summary.TwoMonthTotal, 0.01)
		require.Empty(t, summary.PastWeeks)
		require.NotNil(t, summary.CurrentWeek, "CurrentWeek should always be present")
		require.Equal(t, float64(0), summary.CurrentWeek.WeeklyTotal)
		require.Empty(t, summary.CurrentWeek.DailyBreakdown, "CurrentWeek daily breakdown should be empty")
	})
}

/*
------------------------------------------------------------------------------

	Test 6: Payout Failure Scenarios & Idempotency

------------------------------------------------------------------------------
This test verifies specific failure modes based on Connect account states and
platform balance, and also ensures that payout processing is idempotent.
*/
func TestPayoutFailureScenariosAndIdempotency(t *testing.T) {
	h.T = t
	ctx := context.Background()
	stripe.Key = cfg.StripeSecretKey
	h.SeedPlatformBalance(t, 10000, "usd") // Instantly fund with $100.00

	payoutRepo := internal_repositories.NewWorkerPayoutRepository(h.DB)
	payoutService := services.NewPayoutService(cfg, h.WorkerRepo, h.JobInstRepo, payoutRepo)
	// Use a unique week to prevent data conflicts with other tests
	testWeek := getPreviousWeekPayPeriodStart().AddDate(0, 0, -35)

	// --- Test 6.1: Transfer to an account that is restricted (fails async) ---
	t.Run("ProcessPayoutForAccountWithRestrictions", func(t *testing.T) {
		h.T = t
		worker := getOrCreateWorkerForStripeAccount(t, ctx, "fail-restricted", stripeAcctClosed)
		payout := createTestPayout(t, ctx, payoutRepo, worker.ID, 7500, internal_models.PayoutStatusPending, nil, testWeek, []uuid.UUID{})

		// Process
		err := payoutService.ProcessPendingPayouts(ctx)
		require.NoError(t, err)

		// The payout will be initiated and should eventually fail asynchronously.
		// We now wait directly for the 'FAILED' status instead of the brittle 'PROCESSING' state.
		updatedPayout := waitForPayoutStatus(t, ctx, payoutRepo, payout.ID, internal_models.PayoutStatusFailed, 15*time.Second)
		require.NotNil(t, updatedPayout)
	})

	// --- Test 6.2: Payout To Account With Payouts Disabled (fails sync) ---
	t.Run("ProcessPayoutForAccountWithPayoutsDisabled", func(t *testing.T) {
		h.T = t
		// Use a unique week for this test
		payoutsDisabledWeek := testWeek.AddDate(0, 0, -7)
		worker := getOrCreateWorkerForStripeAccount(t, ctx, "fail-payouts-disabled", onboardingIncompletePayoutDisabled)
		payout := createTestPayout(t, ctx, payoutRepo, worker.ID, 8500, internal_models.PayoutStatusPending, nil, payoutsDisabledWeek, []uuid.UUID{})

		// Process. Unlike other failures, this should fail synchronously before a transfer is made.
		err := payoutService.ProcessPendingPayouts(ctx)
		// ProcessPendingPayouts continues on most errors, so we don't expect an error here.
		require.NoError(t, err, "ProcessPendingPayouts should not return an error for this type of individual payout failure")

		// Verify the payout failed synchronously
		updatedPayout, err := payoutRepo.GetByID(ctx, payout.ID)
		require.NoError(t, err)
		require.NotNil(t, updatedPayout)
		require.Equal(t, internal_models.PayoutStatusFailed, updatedPayout.Status)
		require.NotNil(t, updatedPayout.LastFailureReason)
		require.Equal(t, constants.ReasonAccountPayoutsDisabled, *updatedPayout.LastFailureReason)
		require.Nil(t, updatedPayout.StripeTransferID, "No Stripe transfer should be created for a synchronously failed payout")
	})

	// --- Test 6.3: Ensure payout processing is idempotent ---
	t.Run("ProcessPendingPayoutsIsIdempotent", func(t *testing.T) {
		h.T = t
		worker := getOrCreateWorkerForStripeAccount(t, ctx, "idempotent", stripeAcctSuccess) // A valid account
		// Use a different week for full isolation
		idempotencyWeek := testWeek.AddDate(0, 0, -14)
		payout := createTestPayout(t, ctx, payoutRepo, worker.ID, 9900, internal_models.PayoutStatusPending, nil, idempotencyWeek, []uuid.UUID{})

		// Process the first time
		t.Log("First payout attempt...")
		err := payoutService.ProcessPendingPayouts(ctx)
		require.NoError(t, err)

		// Verify it was successful and get the transfer ID. We no longer assert the 'PROCESSING' status
		// as it might already be 'PAID'. We just need to know it was initiated.
		payout1, err := payoutRepo.GetByID(ctx, payout.ID)
		require.NoError(t, err)
		require.NotNil(t, payout1)
		require.NotEqual(t, internal_models.PayoutStatusPending, payout1.Status, "Payout status should have changed from PENDING")
		require.NotNil(t, payout1.StripeTransferID)
		firstTransferID := *payout1.StripeTransferID
		t.Logf("First payout attempt initiated with transfer ID: %s", firstTransferID)

		// Now, simulate a retry scenario where the API call succeeded but the DB write failed.
		// The cron job would pick up the PENDING job again.
		err = payoutRepo.UpdateWithRetry(ctx, payout1.ID, func(pToUpdate *internal_models.WorkerPayout) error {
			pToUpdate.Status = internal_models.PayoutStatusPending
			pToUpdate.StripeTransferID = nil // Pretend the transfer ID was never saved
			return nil
		})
		require.NoError(t, err)

		t.Log("Second payout attempt (idempotency check)...")
		err = payoutService.ProcessPendingPayouts(ctx)
		require.NoError(t, err)

		// Verify the final state
		payout2, err := payoutRepo.GetByID(ctx, payout.ID)
		require.NoError(t, err)
		require.NotNil(t, payout2)
		require.NotEqual(t, internal_models.PayoutStatusPending, payout2.Status)
		require.NotNil(t, payout2.StripeTransferID)
		t.Logf("Second payout attempt resulted in transfer ID: %s", *payout2.StripeTransferID)

		// CRUCIAL: The transfer ID should be the SAME as the first one, proving a new transfer wasn't created.
		require.Equal(t, firstTransferID, *payout2.StripeTransferID, "Idempotency failed: a new transfer was created on the second attempt")
	})
}

/*
------------------------------------------------------------------------------

	Test 7: Insufficient Balance and Recovery

------------------------------------------------------------------------------
This test verifies the complete flow of a payout failing due to insufficient
platform funds, and then being automatically retried and succeeding after the
balance is replenished via a `balance.available` webhook.
*/
func TestInsufficientBalanceAndRecovery(t *testing.T) {
	h.T = t
	ctx := context.Background()
	stripe.Key = cfg.StripeSecretKey

	t.Log("IF FAILURE OCCURS, make sure that the account balance first and foremost is BELOW 500k.00 USD")

	// Start with a known, low balance to guarantee the first payout fails.
	h.SeedPlatformBalance(t, 5000, "usd") // $50.00

	payoutRepo := internal_repositories.NewWorkerPayoutRepository(h.DB)
	payoutService := services.NewPayoutService(cfg, h.WorkerRepo, h.JobInstRepo, payoutRepo)
	testWeek := getPreviousWeekPayPeriodStart().AddDate(0, 0, -56)

	// --- 1. Setup ---
	// Create two workers. One will have a payout larger than the balance,
	// the other a smaller one to check that processing continues.
	workerFail := getOrCreateWorkerForStripeAccount(t, ctx, "fail-funds-recov", stripeAcctSuccess)
	workerSucceedsEarly := getOrCreateWorkerForStripeAccount(t, ctx, "succeed-funds-recov", stripeAcctSuccess) // Using a success account for the small payout

	// Create PENDING payouts. The first is for a large amount ($500,000.00) that will fail.
	// The second is smaller ($10.00) and should be processed immediately.
	payoutFail := createTestPayout(t, ctx, payoutRepo, workerFail.ID, 50000000, internal_models.PayoutStatusPending, nil, testWeek, []uuid.UUID{})                            // $500,000.00
	payoutSucceeds := createTestPayout(t, ctx, payoutRepo, workerSucceedsEarly.ID, 1000, internal_models.PayoutStatusPending, nil, testWeek.AddDate(0, 0, -7), []uuid.UUID{}) // $10.00

	t.Logf("Created payouts of $500,000.00 for %s and $10.00 for %s", workerFail.ID, workerSucceedsEarly.ID)

	// --- 2. Attempt to process ---
	// This will process the $10 payout successfully, fail on the $500k payout,
	// and return an error because at least one failure occurred.
	err := payoutService.ProcessPendingPayouts(ctx)
	require.Error(t, err, "ProcessPendingPayouts should return an error when balance is insufficient")
	require.ErrorIs(t, err, internal_utils.ErrBalanceInsufficient, "Error message should be errBalanceInsufficient")

	// --- 3. Verify initial state ---
	// The large payout should have failed due to insufficient funds. Its status should be FAILED,
	// but the recovery mechanism triggered by the balance webhook could already be running.
	// We only need to verify that the smaller payout was processed and is on its way to being PAID.
	finalPayoutSucceeds := waitForPayoutStatus(t, ctx, payoutRepo, payoutSucceeds.ID, internal_models.PayoutStatusPaid, 15*time.Second)
	require.NotNil(t, finalPayoutSucceeds, "The smaller payout should have succeeded as processing continues on insufficient_balance errors")

	// --- 4. Simulate Balance Top-up and Webhook ---
	// Add enough funds to cover the large failed payout. This will trigger the 'balance.available' webhook.
	t.Log("Seeding platform balance to cover the large payout...")
	h.SeedPlatformBalance(t, 50010000, "usd") // $500,100.00, enough for the large payout and some buffer

	// --- 5. Verify Final State after Recovery ---
	// The `balance.available` webhook will trigger the recovery logic.
	// We just need to wait for the final status of the large payout.
	// The timeout must be long enough to account for the service's internal retry delay.
	t.Log("Waiting for the large payout to be re-processed after recovery...")
	finalPayoutFail := waitForPayoutStatus(t, ctx, payoutRepo, payoutFail.ID, internal_models.PayoutStatusPaid, 90*time.Second)

	// Final assertions
	require.NotNil(t, finalPayoutFail, "The large payout did not recover and become PAID in time")
	require.NotNil(t, finalPayoutFail.StripeTransferID)
	t.Logf("Successfully recovered and paid out %s", finalPayoutFail.ID)
}

/*
------------------------------------------------------------------------------

	Test 8: Advanced Recovery and Retry Scenarios

------------------------------------------------------------------------------
This test suite verifies more nuanced recovery and retry flows that are
critical for service resilience but not covered in the main lifecycle tests.
*/
func TestAdvancedRecoveryAndRetryScenarios(t *testing.T) {
	h.T = t
	ctx := context.Background()
	stripe.Key = cfg.StripeSecretKey
	h.SeedPlatformBalance(t, 10000, "usd")

	payoutRepo := internal_repositories.NewWorkerPayoutRepository(h.DB)
	payoutService := services.NewPayoutService(cfg, h.WorkerRepo, h.JobInstRepo, payoutRepo)

	// --- Test 8.1: Recovery from `capability.updated` Webhook ---
	t.Run("CapabilityUpdatedRecovery", func(t *testing.T) {
		h.T = t
		// Use a unique week for this test
		testWeek := getPreviousWeekPayPeriodStart().AddDate(0, 0, -42)
		// We use an account that will fail asynchronously due to restrictions.
		worker := getOrCreateWorkerForStripeAccount(t, ctx, "capability-recovery", stripeAcctClosed)

		// 1. Create and process a payout that will fail
		payoutToFail := createTestPayout(t, ctx, payoutRepo, worker.ID, 1234, internal_models.PayoutStatusPending, nil, testWeek, []uuid.UUID{})
		err := payoutService.ProcessPendingPayouts(ctx)
		require.NoError(t, err)

		// 2. Wait for the payout to enter the FAILED state from the async webhook
		payout := waitForPayoutStatus(t, ctx, payoutRepo, payoutToFail.ID, internal_models.PayoutStatusFailed, 30*time.Second)
		require.NotNil(t, payout)
		require.Equal(t, string(stripe.PayoutFailureCodeAccountClosed), *payout.LastFailureReason)

		// 3. Simulate the capability becoming active by sending a mock webhook
		t.Logf("Simulating 'transfers' capability becoming active for account %s...", *worker.StripeConnectAccountID)
		capabilityPayload := h.MockStripeWebhookPayload(t, "capability.updated", map[string]any{
			"id":     "transfers",
			"object": "capability",
			"status": "active",
			"account": map[string]string{ // The account the capability belongs to
				"id": *worker.StripeConnectAccountID,
			},
		})
		h.PostStripeWebhook(h.BaseURL+routes.EarningsStripeWebhook, string(capabilityPayload))

		// 4. Verify the payout was re-queued to PENDING
		payout = waitForPayoutStatus(t, ctx, payoutRepo, payout.ID, internal_models.PayoutStatusPending, 15*time.Second)
		require.NotNil(t, payout, "Payout was not re-queued to PENDING after capability.updated webhook")
		require.NotNil(t, payout.NextAttemptAt, "NextAttemptAt should be set for the retry")
		require.Zero(t, payout.RetryCount, "RetryCount should be reset to 0 for a user-driven recovery")
		t.Logf("Successfully verified that payout %s was re-queued after capability update.", payout.ID)
	})

	// --- Test 8.2: Execution of a Scheduled System-Error Retry ---
	t.Run("SystemErrorRetryExecution", func(t *testing.T) {
		h.T = t
		// Use a unique week for this test
		testWeek := getPreviousWeekPayPeriodStart().AddDate(0, 0, -49)
		// This worker must have a valid account so the retry attempt can succeed.
		worker := getOrCreateWorkerForStripeAccount(t, ctx, "system-retry-worker", stripeAcctSuccess)
		payout := createTestPayout(t, ctx, payoutRepo, worker.ID, 4567, internal_models.PayoutStatusPending, nil, testWeek, []uuid.UUID{})

		// 1. Manually put the payout into a FAILED state with a scheduled retry time in the past.
		// This simulates a transient system error that happened previously.
		t.Log("Manually setting payout to a retryable FAILED state...")
		retryTime := time.Now().UTC().Add(-1 * time.Minute)
		systemFailureReason := "test_system_error_transient"
		err := payoutRepo.UpdateWithRetry(ctx, payout.ID, func(pToUpdate *internal_models.WorkerPayout) error {
			pToUpdate.Status = internal_models.PayoutStatusFailed
			pToUpdate.LastFailureReason = &systemFailureReason
			pToUpdate.RetryCount = 1
			pToUpdate.NextAttemptAt = &retryTime
			return nil
		})
		require.NoError(t, err, "Failed to manually update payout for retry test")

		// 2. Trigger the payout processing job.
		t.Log("Processing pending payouts, expecting the failed job to be picked up for retry...")
		err = payoutService.ProcessPendingPayouts(ctx)
		require.NoError(t, err)

		// 3. Verify the payout was successfully processed and is now PAID.
		// This proves that the `FindReadyForPayout` query correctly found the failed-but-retryable
		// payout and that the subsequent processing was successful.
		finalPayout := waitForPayoutStatus(t, ctx, payoutRepo, payout.ID, internal_models.PayoutStatusPaid, 15*time.Second)
		require.NotNil(t, finalPayout, "Payout did not successfully retry and transition to PAID")
		require.NotNil(t, finalPayout.StripeTransferID)
		t.Logf("Successfully verified that scheduled retry for payout %s was executed.", payout.ID)
	})

	// --- Test 8.3: Ignored Recovery from `capability.updated` (inactive) Webhook ---
	t.Run("CapabilityUpdatedToInactiveIsIgnored", func(t *testing.T) {
		h.T = t
		testWeek := getPreviousWeekPayPeriodStart().AddDate(0, 0, -63)
		worker := getOrCreateWorkerForStripeAccount(t, ctx, "capability-inactive", stripeAcctSuccess) // account needs to exist
		payout := createTestPayout(t, ctx, payoutRepo, worker.ID, 1111, internal_models.PayoutStatusFailed, nil, testWeek, []uuid.UUID{})

		// Simulate the capability becoming inactive by sending a mock webhook
		t.Logf("Simulating 'transfers' capability becoming inactive for account %s...", *worker.StripeConnectAccountID)
		capabilityPayload := h.MockStripeWebhookPayload(t, "capability.updated", map[string]any{
			"id":      "transfers",
			"object":  "capability",
			"status":  "inactive", // The key part of this test
			"account": *worker.StripeConnectAccountID,
		})
		h.PostStripeWebhook(h.BaseURL+routes.EarningsStripeWebhook, string(capabilityPayload))

		// Wait a moment for webhook processing
		time.Sleep(2 * time.Second)

		// Verify the payout status DID NOT change from FAILED
		finalPayout, err := payoutRepo.GetByID(ctx, payout.ID)
		require.NoError(t, err)
		require.Equal(t, internal_models.PayoutStatusFailed, finalPayout.Status, "Payout status should not change after capability becomes inactive")
		t.Logf("Successfully verified that payout %s was not re-queued.", payout.ID)
	})
}

/*
------------------------------------------------------------------------------

	Test 9: Webhook Security

------------------------------------------------------------------------------
This test verifies security aspects of the webhook handler, such as signature
validation.
*/
func TestWebhookSecurity(t *testing.T) {
	h.T = t

	t.Run("RejectRequestWithInvalidSignature", func(t *testing.T) {
		h.T = t
		// 1. Create a valid payload, but an invalid signature
		payload := h.MockStripeWebhookPayload(t, "account.updated", map[string]any{
			"id":     "acct_invalid_sig",
			"object": "account",
		})
		// This signature is intentionally incorrect.
		badSignature := "t=1672531200,v1=0000000000000000000000000000000000000000000000000000000000000000"

		// 2. POST to the webhook endpoint with the bad signature
		req, err := http.NewRequest(http.MethodPost, h.BaseURL+routes.EarningsStripeWebhook, strings.NewReader(string(payload)))
		require.NoError(t, err)
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Stripe-Signature", badSignature)

		resp, err := http.DefaultClient.Do(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		// 3. Assert a 400 Bad Request response
		require.Equal(t, http.StatusBadRequest, resp.StatusCode, "Request with invalid signature should be rejected")
	})
}

// waitForPayoutStatus polls the database for a specific payout status.
func waitForPayoutStatus(t *testing.T, ctx context.Context, repo internal_repositories.WorkerPayoutRepository, payoutID uuid.UUID, targetStatus internal_models.PayoutStatusType, maxWait time.Duration) *internal_models.WorkerPayout {
	t.Helper()
	deadline := time.Now().Add(maxWait)
	var lastStatus internal_models.PayoutStatusType

	for time.Now().Before(deadline) {
		payout, err := repo.GetByID(ctx, payoutID)
		require.NoError(t, err)
		if payout == nil {
			t.Fatalf("payout with ID %s not found in database during polling", payoutID)
			return nil
		}
		lastStatus = payout.Status
		if payout.Status == targetStatus {
			t.Logf("Payout %s reached target status '%s'", payoutID, targetStatus)
			return payout
		}
		time.Sleep(1 * time.Second)
	}

	t.Fatalf("timed out waiting for payout %s to reach status '%s'. Last seen status was '%s'", payoutID, targetStatus, lastStatus)
	return nil
}

// createTestPayout is a local helper because the repo is specific to this service.
func createTestPayout(t *testing.T, ctx context.Context, repo internal_repositories.WorkerPayoutRepository, workerID uuid.UUID, amountCents int64, status internal_models.PayoutStatusType, transferID *string, weekStartDate time.Time, jobIDs []uuid.UUID) *internal_models.WorkerPayout {
	t.Helper()

	// For daily payouts, WeekEndDate is the same as WeekStartDate.
	var weekEndDate time.Time
	if cfg.LDFlag_UseShortPayPeriod {
		weekEndDate = weekStartDate
	} else {
		weekEndDate = weekStartDate.AddDate(0, 0, 6)
	}

	payout := &internal_models.WorkerPayout{
		ID:               uuid.New(),
		WorkerID:         workerID,
		WeekStartDate:    weekStartDate,
		WeekEndDate:      weekEndDate,
		AmountCents:      amountCents,
		Status:           status,
		StripeTransferID: transferID,
		JobInstanceIDs:   jobIDs,
	}
	err := repo.Create(ctx, payout)
	require.NoError(t, err, "payout creation failed. This may be due to a transient error, as the ON CONFLICT rule should handle uniqueness.")

	// Fetch by the unique key (worker + week) to get the record regardless of whether it was
	// just inserted or already existed. This makes the helper robust to the ON CONFLICT clause.
	created, err := repo.GetByWorkerAndWeek(ctx, workerID, weekStartDate)
	require.NoError(t, err)
	require.NotNil(t, created, "payout was not found in DB after creation. The ON CONFLICT rule may have prevented insert and no existing record was found.")

	// If a specific status was requested (e.g. for a test setup), ensure it's set.
	// The ON CONFLICT might have returned an existing record with a different status.
	if created.Status != status || (transferID != nil && (created.StripeTransferID == nil || *created.StripeTransferID != *transferID)) || created.WeekEndDate != weekEndDate {
		err = repo.UpdateWithRetry(ctx, created.ID, func(pToUpdate *internal_models.WorkerPayout) error {
			pToUpdate.Status = status
			pToUpdate.StripeTransferID = transferID
			pToUpdate.StripePayoutID = nil // Reset this for test consistency
			pToUpdate.WeekEndDate = weekEndDate
			pToUpdate.JobInstanceIDs = jobIDs
			return nil
		})
		require.NoError(t, err)
		created, err = repo.GetByID(ctx, created.ID)
		require.NoError(t, err)
	}

	return created
}

// getPreviousWeekPayPeriodStart returns the Monday that started the previous full pay period.
func getPreviousWeekPayPeriodStart() time.Time {
	// This logic must exactly match how the cron job determines its target week.
	loc, _ := time.LoadLocation(constants.BusinessTimezone)
	now := time.Now().In(loc)

	thisWeekPayPeriodStart := internal_utils.GetPayPeriodStartForDate(now)
	return thisWeekPayPeriodStart.AddDate(0, 0, -constants.DaysInWeek)
}
