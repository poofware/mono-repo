// meta-service/services/auth-service/internal/integration/auth_ratelimit_test.go
//go:build (dev_test || staging_test) && integration

package integration

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"github.com/poofware/auth-service/internal/dtos"
	"github.com/poofware/go-utils"
	"github.com/stretchr/testify/require"
)

// TestVerificationCodeRateLimiting verifies that the multi-layered rate limits
// for sending verification codes (SMS and email) are enforced correctly.
// Note: These tests rely on the low, hardcoded limits in config for the test env.
func TestVerificationCodeRateLimiting(t *testing.T) {
	h.T = t
	ctx := context.Background()

	// Cleanup before AND after to ensure total isolation.
	cleanupRateLimitKeys := func() {
		_, _ = h.DB.Exec(context.Background(), `DELETE FROM rate_limit_attempts WHERE key LIKE 'sms:%' OR key LIKE 'email:%'`)
	}
	cleanupRateLimitKeys()
	t.Cleanup(cleanupRateLimitKeys)

	ipForTests := "127.0.0.1" // A consistent fake IP for most tests

	// --- SMS Rate Limiting Tests ---
	t.Run("SMSRateLimiting", func(t *testing.T) {
		h.T = t
		// --- Test Per-Number Limit ---
		phoneForNumberLimit := fmt.Sprintf("%s1111111", utils.TestPhoneNumberBase) // A specific, constant number
		t.Logf("Testing per-number SMS limit (should be %d)", cfg.SMSLimitPerNumberPerHour)
		for range cfg.SMSLimitPerNumberPerHour {
			sendPMSMSCodeWithExpectation(t, phoneForNumberLimit, ipForTests, http.StatusOK)
		}
		// This one should fail
		sendPMSMSCodeWithExpectation(t, phoneForNumberLimit, ipForTests, http.StatusTooManyRequests)

		// --- Test Per-IP Limit ---
		t.Logf("Testing per-IP SMS limit (should be %d)", cfg.SMSLimitPerIPPerHour)
		// We've already used some attempts on this IP from the test above.
		// We can find the current count to see how many more we can make.
		var attemptsOnIP int
		key := fmt.Sprintf("sms:ip:%s", ipForTests)
		_ = h.DB.QueryRow(ctx, `SELECT attempt_count FROM rate_limit_attempts WHERE key=$1`, key).Scan(&attemptsOnIP)
		remainingAttempts := cfg.SMSLimitPerIPPerHour - attemptsOnIP
		require.GreaterOrEqual(t, remainingAttempts, 1, "Should have at least one IP attempt remaining")

		for i := range remainingAttempts {
			// Use different phone numbers for each request to isolate the per-IP limit
			phone := fmt.Sprintf("%s2222%d", utils.TestPhoneNumberBase, i)
			sendPMSMSCodeWithExpectation(t, phone, ipForTests, http.StatusOK)
		}
		// This one should fail
		sendPMSMSCodeWithExpectation(t, fmt.Sprintf("%s3333333", utils.TestPhoneNumberBase), ipForTests, http.StatusTooManyRequests)
	})

	// --- Email Rate Limiting Tests ---
	t.Run("EmailRateLimiting", func(t *testing.T) {
		h.T = t
		// Clear relevant keys again to isolate email tests
		_, _ = h.DB.Exec(ctx, `DELETE FROM rate_limit_attempts WHERE key LIKE 'email:%'`)

		// --- Test Per-Email Limit ---
		emailForAddressLimit := "test-ratelimit-email-addr@thepoofapp.com"
		t.Logf("Testing per-email limit (should be %d)", cfg.EmailLimitPerEmailPerHour)
		for range cfg.EmailLimitPerEmailPerHour {
			sendWorkerEmailCodeWithExpectation(t, emailForAddressLimit, ipForTests, http.StatusOK)
		}
		// This one should fail
		sendWorkerEmailCodeWithExpectation(t, emailForAddressLimit, ipForTests, http.StatusTooManyRequests)
	})

	// --- Global Rate Limiting Tests ---
	t.Run("GlobalRateLimiting", func(t *testing.T) {
		h.T = t
		if !cfg.LDFlag_ShortTokenTTL {
			t.Skip("Skipping global rate limit test because short TTLs (and thus low global limits) are not enabled.")
		}

		// --- Test Global SMS Limit ---
		t.Run("GlobalSMSRateLimiting", func(t *testing.T) {
			h.T = t
			// Clear keys to isolate this test
			_, _ = h.DB.Exec(ctx, `DELETE FROM rate_limit_attempts WHERE key LIKE 'sms:%'`)

			t.Logf("Testing global SMS limit (should be %d)", cfg.GlobalSMSLimitPerHour)
			// To isolate the global limit, each request must have a unique IP and a unique phone number.
			for i := range cfg.GlobalSMSLimitPerHour {
				uniquePhone := fmt.Sprintf("%s4444%d", utils.TestPhoneNumberBase, i)
				uniqueIP := fmt.Sprintf("10.0.0.%d", i)
				sendPMSMSCodeWithExpectation(t, uniquePhone, uniqueIP, http.StatusOK)
			}
			// This one should fail due to the global limit.
			sendPMSMSCodeWithExpectation(t, fmt.Sprintf("%s5555555", utils.TestPhoneNumberBase), "10.0.1.1", http.StatusTooManyRequests)
		})

		// --- Test Global Email Limit ---
		t.Run("GlobalEmailRateLimiting", func(t *testing.T) {
			h.T = t
			// Clear keys to isolate this test
			_, _ = h.DB.Exec(ctx, `DELETE FROM rate_limit_attempts WHERE key LIKE 'email:%'`)

			t.Logf("Testing global email limit (should be %d)", cfg.GlobalEmailLimitPerHour)
			// To isolate the global limit, each request must have a unique IP and a unique email.
			for i := range cfg.GlobalEmailLimitPerHour {
				uniqueEmail := fmt.Sprintf("global-limit-test-%d@thepoofapp.com", i)
				uniqueIP := fmt.Sprintf("10.1.0.%d", i)
				sendWorkerEmailCodeWithExpectation(t, uniqueEmail, uniqueIP, http.StatusOK)
			}
			// This one should fail due to the global limit.
			sendWorkerEmailCodeWithExpectation(t, "global-limit-fail@thepoofapp.com", "10.1.1.1", http.StatusTooManyRequests)
		})
	})
}

// --- Helper Functions for Rate Limit Tests ---

// sendPMSMSCodeWithExpectation was fixed to correctly use the phoneNumber parameter,
// enabling accurate testing of per-destination rate limits. The unused 'phonePrefix'
// parameter was removed. It now also accepts an IP address to test IP-based limits.
func sendPMSMSCodeWithExpectation(t *testing.T, phoneNumber, ipAddress string, expectedStatus int) {
	t.Helper()

	req := dtos.RequestSMSCodeRequest{PhoneNumber: phoneNumber}
	body, _ := json.Marshal(req)

	headers := map[string]string{
		"Content-Type":    "application/json",
		"X-Forwarded-For": ipAddress,
	}

	url := h.BaseURL + "/auth/v1/pm/request_sms_code"
	resp := doRequest(t, http.MethodPost, url, body, headers)
	defer resp.Body.Close()

	require.Equal(t, expectedStatus, resp.StatusCode, "Request to send PM SMS code returned unexpected status for phone %s and IP %s", phoneNumber, ipAddress)
}

// sendWorkerEmailCodeWithExpectation now accepts an IP address to test IP-based limits.
func sendWorkerEmailCodeWithExpectation(t *testing.T, email, ipAddress string, expectedStatus int) {
	t.Helper()
	req := dtos.RequestEmailCodeRequest{Email: email}
	body, _ := json.Marshal(req)

	headers := map[string]string{
		"Content-Type":       "application/json",
		"X-Platform":         "android",
		"X-Device-ID":        "ratelimit-test-device",
		"X-Device-Integrity": "FAKE_INTEGRITY_TOKEN",
		"X-Forwarded-For":    ipAddress,
	}

	url := h.BaseURL + "/auth/v1/worker/request_email_code"
	resp := doRequest(t, http.MethodPost, url, body, headers)
	defer resp.Body.Close()

	require.Equal(t, expectedStatus, resp.StatusCode, "Request to send Worker email code returned unexpected status for email %s and IP %s", email, ipAddress)
}
