package testhelpers

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/poofware/go-utils"
	"github.com/stretchr/testify/require"
	"github.com/stripe/stripe-go/v82"
	"github.com/stripe/stripe-go/v82/paymentintent"
)
// PostStripeWebhook signs and posts a mock Stripe event to the webhook endpoint.
func (h *TestHelper) PostStripeWebhook(webhookURL, payload string) {
	headerVal := h.SignStripePayload([]byte(payload))
	req, err := http.NewRequest(http.MethodPost, webhookURL, strings.NewReader(payload))
	require.NoError(h.T, err, "failed to create webhook POST request")
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Stripe-Signature", headerVal)

	resp, err := http.DefaultClient.Do(req)
	require.NoError(h.T, err, "failed to POST webhook payload")
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		body := h.ReadBody(resp)
		h.T.Fatalf("Webhook POST failed, status=%d, body=%s", resp.StatusCode, body)
	}
}

// SignStripePayload constructs the "Stripe-Signature" header value.
func (h *TestHelper) SignStripePayload(payload []byte) string {
	require.NotEmpty(h.T, h.StripeWebhookSecret, "StripeWebhookSecret is not configured in TestHelper")
	timestamp := time.Now().Unix()
	mac := hmac.New(sha256.New, []byte(h.StripeWebhookSecret))
	_, _ = mac.Write([]byte(fmt.Sprintf("%d.", timestamp)))
	_, _ = mac.Write(payload)
	signature := mac.Sum(nil)
	return fmt.Sprintf("t=%d,v1=%s", timestamp, hex.EncodeToString(signature))
}

// PostCheckrWebhook signs and posts a mock Checkr event to the webhook endpoint.
func (h *TestHelper) PostCheckrWebhook(webhookURL, payload string) {
	require.NotEmpty(h.T, h.CheckrAPIKey, "CheckrAPIKey is not configured in TestHelper")
	sig := h.SignCheckrPayload([]byte(payload))
	req, err := http.NewRequest(http.MethodPost, webhookURL, strings.NewReader(payload))
	require.NoError(h.T, err, "failed to create Checkr webhook POST request")
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Checkr-Signature", sig)

	resp, err := http.DefaultClient.Do(req)
	require.NoError(h.T, err, "failed to POST Checkr webhook payload")
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		body := h.ReadBody(resp)
		h.T.Fatalf("Checkr Webhook POST failed, status=%d, body=%s", resp.StatusCode, body)
	}
}

// SignCheckrPayload produces the HMAC-SHA256 signature for the "X-Checkr-Signature" header.
func (h *TestHelper) SignCheckrPayload(payload []byte) string {
	mac := hmac.New(sha256.New, []byte(h.CheckrAPIKey))
	_, _ = mac.Write(payload)
	return hex.EncodeToString(mac.Sum(nil))
}

// MockStripeWebhookPayload creates a JSON byte slice for a Stripe webhook event.
func (h *TestHelper) MockStripeWebhookPayload(t *testing.T, eventType string, data map[string]any) []byte {
	t.Helper()

	payload := map[string]any{
		"id":          "evt_test_" + utils.RandomString(10),
		"object":      "event",
		"api_version": stripe.APIVersion,
		"created":     time.Now().Unix(),
		"type":        eventType,
		"data": map[string]any{
			"object": data,
		},
	}

	jsonBytes, err := json.Marshal(payload)
	require.NoError(t, err, "Failed to marshal mock Stripe webhook payload")
	return jsonBytes
}

// TopUpPlatformBalance credits the platform’s **test-mode** balance.
//
// Stripe always creates a top-up with initial status = "pending". In test
// mode it settles to "succeeded" after roughly 1-3 s, but there’s no
// test-helpers endpoint to force-settle it, so we poll until it flips. :contentReference[oaicite:0]{index=0}
func (h *TestHelper) TopUpPlatformBalance(
	t *testing.T,
	amountCents int64,
	currency string, // e.g. "usd"
) *stripe.Topup {
	t.Helper()

	ctx := context.Background()

	// 1 – Create the top-up (initially "pending").
	params := &stripe.TopupCreateParams{
		Amount:   stripe.Int64(amountCents),
		Currency: stripe.String(currency),
		Source:   stripe.String("btok_us_verified"), // happy-path bank-acct token
		Description: stripe.String(fmt.Sprintf(
			"Test top-up for run %s-%s", h.UniqueRunnerID, h.UniqueRunNumber)),
	}
	tp, err := h.StripeClient.V1Topups.Create(ctx, params)
	require.NoError(t, err, "failed to create test top-up")

	t.Logf("Platform balance topped up with %d %s via top-up %s",
		amountCents, currency, tp.ID)

	// Extra cushion for ledger propagation.
	time.Sleep(time.Second)

	return tp
}

// SeedPlatformBalance creates an instant-settling card charge that
// drops straight into the platform’s *available* balance.
// It returns the succeeded PaymentIntent (instead of a Topup object).
func (h *TestHelper) SeedPlatformBalance(
	t *testing.T,
	amountCents int64,
	currency string, // e.g. "usd"
) *stripe.PaymentIntent {
	t.Helper()

	// Calculate the gross amount including Stripe's processing fees
	// Stripe charges 2.9% + $0.30 for card transactions
	// To get the net amount we want, we need to solve: gross - (gross * 0.029 + 30) = desired_net
	// Rearranging: gross * (1 - 0.029) = desired_net + 30
	// Therefore: gross = (desired_net + 30) / (1 - 0.029)
	stripeFeePercent := 0.029
	stripeFixedFeeCents := int64(30) // $0.30 in cents
	
	grossAmountCents := int64(float64(amountCents+stripeFixedFeeCents) / (1.0 - stripeFeePercent))

	t.Logf("Seeding platform balance: desired net %d cents, gross amount %d cents (includes Stripe fees)", 
		amountCents, grossAmountCents)

	// 1 – Create & confirm the PaymentIntent in one call.
	piParams := &stripe.PaymentIntentParams{
		Amount:           stripe.Int64(grossAmountCents),
		Currency:         stripe.String(currency),
		PaymentMethod:    stripe.String("pm_card_bypassPending"), // magic test PM
		PaymentMethodTypes: stripe.StringSlice([]string{"card"}),
		Confirm:          stripe.Bool(true),
		Description: stripe.String(fmt.Sprintf(
			"Instant balance seed for run %s-%s (gross: %d, net: %d)", 
			h.UniqueRunnerID, h.UniqueRunNumber, grossAmountCents, amountCents)),
	}
	pi, err := paymentintent.New(piParams) // uses global API key
	require.NoError(t, err, "failed to create instant-fund PaymentIntent")

	// 2 – (Defensive) Poll until it's succeeded – should be immediate.
	deadline := time.Now().Add(10 * time.Second)
	for pi.Status != stripe.PaymentIntentStatusSucceeded && time.Now().Before(deadline) {
		time.Sleep(200 * time.Millisecond)
		pi, err = paymentintent.Get(pi.ID, nil)
		require.NoError(t, err, "failed to refresh PaymentIntent status")
	}
	require.Equal(t, stripe.PaymentIntentStatusSucceeded, pi.Status,
		"PaymentIntent did not succeed within 10 s")

	t.Logf("Platform balance funded with %d %s via PaymentIntent %s (gross amount including fees)",
		grossAmountCents, currency, pi.ID)

	// Extra cushion for ledger propagation.
	time.Sleep(time.Second)

	return pi
}
