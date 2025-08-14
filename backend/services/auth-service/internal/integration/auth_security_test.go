//go:build (dev_test || staging_test) && integration

package integration

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"
	"errors"
	"crypto/sha256"
	"encoding/base64"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/mono-repo/backend/services/auth-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
	"github.com/stretchr/testify/require"
)

// TestLoginThrottlingAndAccountLockout verifies that repeated failed login attempts
// result in a temporary account lockout for both PMs and Workers.
func TestLoginThrottlingAndAccountLockout(t *testing.T) {
	h.T = t
	ctx := context.Background()

	// Cleanup rate limit keys after this test to prevent interference with others.
	t.Cleanup(func() {
		_, _ = h.DB.Exec(context.Background(), `DELETE FROM rate_limit_attempts WHERE key LIKE 'sms:%' OR key LIKE 'email:%'`)
	})

	// --- Test PM Lockout ---
	t.Run("PMLockoutAfterTenFailedAttempts", func(t *testing.T) {
		h.T = t
		email := "lockout-pm-" + utils.RandomString(6) + "@thepoofapp.com"
		// FIXED: Use the correct test phone number prefix.
		phone := utils.TestPhoneNumberBase + utils.RandomNumericString(7)
		totpData := generateTOTPSecret(t)
		correctTOTP := h.GenerateTOTPCode(totpData.Secret)

		// Pre-verify email before registration
		sendPMEmailCode(t, email)
		emailCode := retrieveLatestPMEmailCode(t, email)
		verifyPMEmailCode(t, email, emailCode)

		// Pre-verify phone before registration
		sendPMSMSCode(t, phone)
		smsCode := retrieveLatestPMSMSCode(t, phone)
		verifyPMSMSCode(t, phone, smsCode)

		// Register a fresh PM for this test
		registerPM(t, email, &phone, totpData.Secret, correctTOTP)
		pm, _ := h.PMRepo.GetByEmail(ctx, email)
		defer h.DB.Exec(ctx, `DELETE FROM property_managers WHERE id=$1`, pm.ID)

		// 1. Perform 10 failed login attempts with a bad TOTP code
		t.Logf("PM Lockout: Performing %d failed login attempts for %s", cfg.MaxLoginAttempts, email)
		for range cfg.MaxLoginAttempts {
			loginPMWithExpectation(t, email, "000000", http.StatusUnauthorized)
		}

		// 2. The 11th attempt should fail due to lockout, even with the correct code
		t.Log("PM Lockout: Verifying account is now locked.")
		resp := loginPMWithExpectation(t, email, h.GenerateTOTPCode(totpData.Secret), http.StatusUnauthorized)

		// Check the error message for "locked"
		var errResp utils.ErrorResponse
		err := json.NewDecoder(resp.Body).Decode(&errResp)
		require.NoError(t, err)
		require.Contains(t, errResp.Message, "locked", "Error message should indicate account is locked")
	})

	// --- Test Worker Lockout ---
	t.Run("WorkerLockoutAfterTenFailedAttempts", func(t *testing.T) {
		h.T = t
		email := "lockout-worker-" + utils.RandomString(6) + "@thepoofapp.com"
		// FIXED: Use the correct test phone number prefix.
		phone := utils.TestPhoneNumberBase + utils.RandomNumericString(7)
		totpData := generateTOTPSecret(t)
		correctTOTP := h.GenerateTOTPCode(totpData.Secret)
		deviceID := "lockout-device"

		// Pre-verify phone number before registration
		sendWorkerSMSCode(t, phone)
		smsCode := retrieveLatestWorkerSMSCode(t, phone)
		verifyWorkerSMSCode(t, phone, smsCode)

		// Register a fresh Worker for this test
		registerWorker(t, email, phone, totpData.Secret, correctTOTP)
		worker, _ := h.WorkerRepo.GetByPhoneNumber(ctx, phone)
		defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, worker.ID)

		// 1. Perform 10 failed login attempts with a bad TOTP code
		t.Logf("Worker Lockout: Performing %d failed login attempts for %s", cfg.MaxLoginAttempts, phone)
		for range cfg.MaxLoginAttempts {
			loginWorkerWithExpectation(t, phone, "000000", deviceID, http.StatusUnauthorized)
		}

		// 2. The 11th attempt should fail due to lockout, even with the correct code
		t.Log("Worker Lockout: Verifying account is now locked.")
		resp := loginWorkerWithExpectation(t, phone, h.GenerateTOTPCode(totpData.Secret), deviceID, http.StatusUnauthorized)

		var errResp utils.ErrorResponse
		err := json.NewDecoder(resp.Body).Decode(&errResp)
		require.NoError(t, err)
		require.Contains(t, errResp.Message, "locked", "Error message should indicate account is locked")
	})
}

// TestMobileAttestationAndPlatformSecurity verifies platform-specific security rules,
// such as rejecting worker logins from non-mobile platforms and enforcing device attestation headers.
func TestMobileAttestationAndPlatformSecurity(t *testing.T) {
	h.T = t
	ctx := context.Background()

	// Cleanup rate limit keys after this test to prevent interference with others.
	t.Cleanup(func() {
		_, _ = h.DB.Exec(context.Background(), `DELETE FROM rate_limit_attempts WHERE key LIKE 'sms:%' OR key LIKE 'email:%'`)
	})

	// Setup a generic worker for these tests
	email := "platform-sec-" + utils.RandomString(6) + "@thepoofapp.com"
	// FIXED: Use the correct test phone number prefix.
	phone := utils.TestPhoneNumberBase + utils.RandomNumericString(7)
	totpData := generateTOTPSecret(t)

	// Pre-verify phone before registration
	sendWorkerSMSCode(t, phone)
	smsCode := retrieveLatestWorkerSMSCode(t, phone)
	verifyWorkerSMSCode(t, phone, smsCode)
	registerWorker(t, email, phone, totpData.Secret, h.GenerateTOTPCode(totpData.Secret))

	worker, _ := h.WorkerRepo.GetByPhoneNumber(ctx, phone)
	defer h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, worker.ID)

	t.Run("WorkerLoginFailsFromWebPlatform", func(t *testing.T) {
		h.T = t
		// Attempt to log in as a worker, but with X-Platform: web
		reqDTO := dtos.LoginWorkerRequest{PhoneNumber: phone, TOTPCode: "123456"}
		body, _ := json.Marshal(reqDTO)
		url := h.BaseURL + "/auth/v1/worker/login"

		// Use a platform header of "web"
		resp := doRequest(t, http.MethodPost, url, body, map[string]string{
			"Content-Type": "application/json",
			"X-Platform":   "web",
		})
		defer resp.Body.Close()

		require.Equal(t, http.StatusForbidden, resp.StatusCode, "Worker login should be forbidden from web platform")
	})

	t.Run("WorkerLoginFailsWithoutIntegrityToken", func(t *testing.T) {
		h.T = t
		// Attempt to log in from a mobile platform but omit the X-Device-Integrity header
		reqDTO := dtos.LoginWorkerRequest{PhoneNumber: phone, TOTPCode: "123456"}
		body, _ := json.Marshal(reqDTO)
		url := h.BaseURL + "/auth/v1/worker/login"

		resp := doRequest(t, http.MethodPost, url, body, map[string]string{
			"Content-Type": "application/json",
			"X-Platform":   "android",
			"X-Device-ID":  "some-device",
			// No X-Device-Integrity header
		})
		defer resp.Body.Close()

		require.Equal(t, http.StatusBadRequest, resp.StatusCode, "Worker login should fail without integrity token")
	})
}

// TestVerificationCodeLifecycle checks that codes expire correctly and cannot be reused.
func TestVerificationCodeLifecycle(t *testing.T) {
	h.T = t

	// Cleanup rate limit keys after this test to prevent interference with others.
	t.Cleanup(func() {
		_, _ = h.DB.Exec(context.Background(), `DELETE FROM rate_limit_attempts WHERE key LIKE 'sms:%' OR key LIKE 'email:%'`)
	})

	if !cfg.LDFlag_ShortTokenTTL {
		t.Skip("Skipping verification code lifecycle test because short TTLs are not enabled.")
	}
	email := "lifecycle-" + utils.RandomString(6) + "@thepoofapp.com"

	t.Run("ExpiredVerificationCodeFails", func(t *testing.T) {
		h.T = t
		sendWorkerEmailCode(t, email)
		code := retrieveLatestWorkerEmailCode(t, email)

		// Wait for the code to expire using the fast, configured value
		expiryDuration := cfg.VerificationCodeExpiry
		t.Logf("Waiting for verification code to expire (duration: %v)...", expiryDuration)
		time.Sleep(expiryDuration + 1*time.Second)

		// Attempt to verify with the now-expired code
		req := dtos.VerifyEmailCodeRequest{Email: email, Code: code}
		body, _ := json.Marshal(req)
		url := h.BaseURL + "/auth/v1/worker/verify_email_code"
		resp := doRequest(t, http.MethodPost, url, body, map[string]string{
			"Content-Type":       "application/json",
			"X-Platform":         "android",
			"X-Device-ID":        "test-dev-id",
			"X-Device-Integrity": "FAKE_INTEGRITY_TOKEN",
		})
		defer resp.Body.Close()

		require.Equal(t, http.StatusUnauthorized, resp.StatusCode, "Verification with an expired code should fail")
	})

	t.Run("VerificationCodeCannotBeReused", func(t *testing.T) {
		h.T = t
		sendWorkerEmailCode(t, email)
		code := retrieveLatestWorkerEmailCode(t, email)

		// 1. Verify successfully once
		verifyWorkerEmailCode(t, email, code)

		// 2. Attempt to verify with the same code again. The service should have marked the
		// code as used, so this must fail.
		req := dtos.VerifyEmailCodeRequest{Email: email, Code: code}
		body, _ := json.Marshal(req)
		url := h.BaseURL + "/auth/v1/worker/verify_email_code"
		resp := doRequest(t, http.MethodPost, url, body, map[string]string{
			"Content-Type":       "application/json",
			"X-Platform":         "android",
			"X-Device-ID":        "test-dev-id",
			"X-Device-Integrity": "FAKE_INTEGRITY_TOKEN",
		})
		defer resp.Body.Close()

		// The code should have been used, so this attempt will be unauthorized.
		require.Equal(t, http.StatusUnauthorized, resp.StatusCode, "Reusing a verification code should fail")
	})
}

// TestAttestationChallengeRepository validates the full lifecycle of challenge records
// in the database, including creation, consumption, expiration, and cleanup.
func TestAttestationChallengeRepository(t *testing.T) {
	h.T = t
	ctx := context.Background()
	challengeRepo := repositories.NewAttestationChallengeRepository(h.DB)
	require.NotNil(t, challengeRepo, "Failed to create attestation challenge repository")

	// --- Test Case 1: Successful Create and Consume ---
	t.Run("CreateAndConsume_Success", func(t *testing.T) {
		h.T = t
		challenge := &models.AttestationChallenge{
			ID:           uuid.New(),
			RawChallenge: []byte("test_challenge_data_1"),
			Platform:     "android",
			ExpiresAt:    time.Now().Add(5 * time.Minute),
		}

		// Create
		err := challengeRepo.Create(ctx, challenge)
		require.NoError(t, err, "Failed to create challenge")

		// Consume
		raw, platform, err := challengeRepo.Consume(ctx, challenge.ID)
		require.NoError(t, err, "Consuming a valid challenge should not produce an error")
		require.Equal(t, challenge.RawChallenge, raw, "Consumed raw challenge data does not match")
		require.Equal(t, "android", platform, "Consumed platform does not match")

		// Consume Again (should fail as it's single-use)
		raw2, platform2, err2 := challengeRepo.Consume(ctx, challenge.ID)
		require.NoError(t, err2, "Consuming an already-used challenge should not error")
		require.Nil(t, raw2, "Re-consuming should yield nil data")
		require.Empty(t, platform2, "Re-consuming should yield an empty platform string")
	})

	// --- Test Case 2: Consume Expired Challenge ---
	t.Run("Consume_ExpiredChallenge_Fails", func(t *testing.T) {
		h.T = t
		expiredChallenge := &models.AttestationChallenge{
			ID:           uuid.New(),
			RawChallenge: []byte("expired_challenge_data"),
			Platform:     "ios",
			ExpiresAt:    time.Now().Add(-5 * time.Minute), // Expired
		}

		err := challengeRepo.Create(ctx, expiredChallenge)
		require.NoError(t, err)

		raw, platform, err := challengeRepo.Consume(ctx, expiredChallenge.ID)
		require.NoError(t, err, "Consuming an expired challenge should not error")
		require.Nil(t, raw, "Consuming an expired challenge should yield nil data")
		require.Empty(t, platform, "Consuming an expired challenge should yield an empty platform string")
	})

	// --- Test Case 3: Consume Non-Existent Challenge ---
	t.Run("Consume_NonExistentChallenge_Fails", func(t *testing.T) {
		h.T = t
		nonExistentID := uuid.New()
		raw, platform, err := challengeRepo.Consume(ctx, nonExistentID)
		require.NoError(t, err, "Consuming a non-existent challenge should not error")
		require.Nil(t, raw, "Consuming a non-existent challenge should yield nil data")
		require.Empty(t, platform, "Consuming a non-existent challenge should yield an empty platform string")
	})

	// --- Test Case 4: Cleanup Expired Challenges ---
	t.Run("CleanupExpired", func(t *testing.T) {
		h.T = t
		// Create one valid and one expired challenge
		validChallenge := &models.AttestationChallenge{
			ID:           uuid.New(),
			RawChallenge: []byte("valid_cleanup_test"),
			Platform:     "android",
			ExpiresAt:    time.Now().Add(10 * time.Minute),
		}
		expiredChallenge := &models.AttestationChallenge{
			ID:           uuid.New(),
			RawChallenge: []byte("expired_cleanup_test"),
			Platform:     "ios",
			ExpiresAt:    time.Now().Add(-1 * time.Minute),
		}
		require.NoError(t, challengeRepo.Create(ctx, validChallenge))
		require.NoError(t, challengeRepo.Create(ctx, expiredChallenge))

		// Run cleanup
		err := challengeRepo.CleanupExpired(ctx)
		require.NoError(t, err, "CleanupExpired should not return an error")

		// Verify expired is gone
		rawExpired, _, _ := challengeRepo.Consume(ctx, expiredChallenge.ID)
		require.Nil(t, rawExpired, "Expired challenge should have been deleted by cleanup")

		// Verify valid is still present
		rawValid, _, _ := challengeRepo.Consume(ctx, validChallenge.ID)
		require.NotNil(t, rawValid, "Valid challenge should not have been deleted by cleanup")
	})
}

// TestIssueChallengeEndpoint validates the /worker/challenge endpoint, ensuring
// it correctly issues and stores challenges for different mobile platforms.
func TestIssueChallengeEndpoint(t *testing.T) {
	h.T = t

	// --- Test Case 1: Android Challenge ---
	t.Run("IssueChallenge_Android_Success", func(t *testing.T) {
		h.T = t
		url := h.BaseURL + "/auth/v1/worker/challenge"
		resp := doRequest(t, http.MethodPost, url, nil, map[string]string{
			"Content-Type": "application/json",
			"X-Platform":   "android", // Platform header is required
		})
		defer resp.Body.Close()
		require.Equal(t, http.StatusOK, resp.StatusCode)

		var challengeResp dtos.ChallengeResponse
		err := json.NewDecoder(resp.Body).Decode(&challengeResp)
		require.NoError(t, err)
		require.NotEmpty(t, challengeResp.ChallengeToken)
		require.NotEmpty(t, challengeResp.Challenge)

		// Verify against DB
		tokenUUID, err := uuid.Parse(challengeResp.ChallengeToken)
		require.NoError(t, err)

		dbChallenge, err := getChallengeByID(context.Background(), tokenUUID) // Using a helper to fetch without consuming
		require.NoError(t, err)
		require.NotNil(t, dbChallenge, "Challenge should exist in the database")
		require.Equal(t, "android", dbChallenge.Platform)

		// Android expects the requestHash, which is base64(sha256(raw_challenge))
		expectedHash := sha256.Sum256(dbChallenge.RawChallenge)
		expectedEncodedHash := base64.RawURLEncoding.EncodeToString(expectedHash[:])
		require.Equal(t, expectedEncodedHash, challengeResp.Challenge)
	})

	// --- Test Case 2: iOS Challenge ---
	t.Run("IssueChallenge_iOS_Success", func(t *testing.T) {
		h.T = t
		url := h.BaseURL + "/auth/v1/worker/challenge"
		resp := doRequest(t, http.MethodPost, url, nil, map[string]string{
			"Content-Type": "application/json",
			"X-Platform":   "ios", // Platform header is required
		})
		defer resp.Body.Close()
		require.Equal(t, http.StatusOK, resp.StatusCode)

		var challengeResp dtos.ChallengeResponse
		err := json.NewDecoder(resp.Body).Decode(&challengeResp)
		require.NoError(t, err)

		// Verify against DB
		tokenUUID, err := uuid.Parse(challengeResp.ChallengeToken)
		require.NoError(t, err)
		dbChallenge, err := getChallengeByID(context.Background(), tokenUUID)
		require.NoError(t, err)
		require.NotNil(t, dbChallenge, "Challenge should exist in the database")
		require.Equal(t, "ios", dbChallenge.Platform)

		// iOS expects the raw challenge, base64-url-encoded
		expectedEncodedChallenge := base64.RawURLEncoding.EncodeToString(dbChallenge.RawChallenge)
		require.Equal(t, expectedEncodedChallenge, challengeResp.Challenge)
	})

	// --- Test Case 3: Invalid Platform in Body ---
	t.Run("IssueChallenge_InvalidPlatform_Fails", func(t *testing.T) {
		h.T = t
		url := h.BaseURL + "/auth/v1/worker/challenge"
		resp := doRequest(t, http.MethodPost, url, nil, map[string]string{
			"Content-Type": "application/json",
			"X-Platform":   "yolo", // Header is valid mobile
		})
		defer resp.Body.Close()
		require.True(t, resp.StatusCode == http.StatusBadRequest || resp.StatusCode == http.StatusForbidden, 
			"Request should fail with 400 or 403 due to invalid platform in header, got %d", resp.StatusCode)

	})

	// --- Test Case 4: Non-Mobile Platform in Header ---
	t.Run("IssueChallenge_WebPlatform_Fails", func(t *testing.T) {
		h.T = t
		url := h.BaseURL + "/auth/v1/worker/challenge"
		resp := doRequest(t, http.MethodPost, url, nil, map[string]string{
			"Content-Type": "application/json",
			"X-Platform":   "web", // Endpoint is mobile-only
		})
		defer resp.Body.Close()
		require.Equal(t, http.StatusForbidden, resp.StatusCode, "Request should be forbidden for web platform")
	})
}

// getChallengeByID is a test helper to fetch a challenge by ID without consuming it.
// It's a standalone function, not a method, to avoid package visibility issues.
func getChallengeByID(ctx context.Context, id uuid.UUID) (*models.AttestationChallenge, error) {
	q := `SELECT id, raw_challenge, platform, expires_at FROM attestation_challenges WHERE id = $1`
	row := h.DB.QueryRow(ctx, q, id) // 'h' is the global test helper with DB connection
	var c models.AttestationChallenge
	err := row.Scan(&c.ID, &c.RawChallenge, &c.Platform, &c.ExpiresAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil // Not found is not an error for a 'Get' function.
		}
		return nil, err
	}
	return &c, nil
}

// --- Helper Functions for Security Tests ---

// loginPMWithExpectation is a helper to perform a PM login and check the status code.
// It returns the full http.Response for further inspection.
func loginPMWithExpectation(t *testing.T, email, totpCode string, expectedStatus int) *http.Response {
	reqDTO := dtos.LoginPMRequest{Email: email, TOTPCode: totpCode}
	body, _ := json.Marshal(reqDTO)
	url := h.BaseURL + "/auth/v1/pm/login"

	resp := doRequest(t, http.MethodPost, url, body, map[string]string{
		"Content-Type": "application/json",
		"X-Platform":   "web",
	})

	require.Equal(t, expectedStatus, resp.StatusCode, "PM login returned unexpected status code")
	return resp
}

// loginWorkerWithExpectation is a helper to perform a Worker login and check the status code.
// It returns the full http.Response for further inspection.
func loginWorkerWithExpectation(t *testing.T, phone, totpCode, deviceID string, expectedStatus int) *http.Response {
	reqDTO := dtos.LoginWorkerRequest{PhoneNumber: phone, TOTPCode: totpCode}
	body, _ := json.Marshal(reqDTO)
	url := h.BaseURL + "/auth/v1/worker/login"

	resp := doRequest(t, http.MethodPost, url, body, map[string]string{
		"Content-Type":       "application/json",
		"X-Platform":         "android",
		"X-Device-ID":        deviceID,
		"X-Device-Integrity": "FAKE_INTEGRITY_TOKEN",
	})

	require.Equal(t, expectedStatus, resp.StatusCode, "Worker login returned unexpected status code")
	return resp
}
