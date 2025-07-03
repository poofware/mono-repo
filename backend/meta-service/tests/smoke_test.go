//go:build (dev_test || staging_test)
package integration

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/pquerna/otp/totp"
	"github.com/stretchr/testify/require"
)

const (
	emailTestCode = "999999"
	smsTestCode   = "999999"
)

// TestSmokeMobileFlow runs a minimal Worker registration & login flow in "android" mode.
func TestSmokeMobileFlow(t *testing.T) {
	appURL := os.Getenv("APP_URL_FROM_COMPOSE_NETWORK")
	require.NotEmpty(t, appURL, "APP_URL_FROM_COMPOSE_NETWORK environment variable must be set")

	// 1) Generate test-mode email/phone
	testEmail := fmt.Sprintf("%dtesting@thepoofapp.com", rand.Intn(1e9))
	testPhone := fmt.Sprintf("+999%010d", rand.Intn(1e10))
	t.Logf("[INFO] Using testEmail=%s", testEmail)
	t.Logf("[INFO] Using testPhone=%s", testPhone)

	// 2) Fetch TOTP secret
	totpResp, err := fetchTOTPSecret(appURL)
	require.NoError(t, err, "fetchTOTPSecret error")

	totpCode, err := totp.GenerateCode(totpResp.Secret, time.Now())
	require.NoError(t, err, "generate TOTP code error")

	// 3) Check worker phone “valid” endpoint => expect 200 for “not in use”
	notUsed, err := checkWorkerPhoneInUse(appURL, testPhone)
	require.NoError(t, err, "checkWorkerPhoneInUse error")
	require.False(t, notUsed, "Worker phone unexpectedly in use already")

	// 4) Send & verify Email
	require.NoError(t, sendEmailCode(appURL, testEmail), "sendEmailCode")
	require.NoError(t, verifyEmailCode(appURL, testEmail, emailTestCode), "verifyEmailCode")
	t.Log("[INFO] Email verification (test mode) passed.")

	// 5) Send & verify SMS
	require.NoError(t, sendSMSCode(appURL, testPhone), "sendSMSCode")
	require.NoError(t, verifySMSCode(appURL, testPhone, smsTestCode), "verifySMSCode")
	t.Log("[INFO] SMS verification (test mode) passed.")

	// 6) Register the Worker
	require.NoError(t, registerWorker(
		appURL,
		"SmokeTestFirst",
		"SmokeTestLast",
		testEmail,
		testPhone,
		totpResp.Secret,
		totpCode,
	), "registerWorker")
	t.Log("[INFO] Worker registration succeeded.")

	// 7) Now check phone => we expect 409 => means in use
	nowUsed, err := checkWorkerPhoneInUse(appURL, testPhone)
	require.NoError(t, err, "checkWorkerPhoneInUse post-reg")
	require.True(t, nowUsed, "Worker phone does NOT appear as used after registration")
	t.Log("[INFO] Worker phone is now recognized as in-use as expected.")

	// 8) Mobile Login => get Access Token (with a device ID)
	accessToken, err := loginWorkerGetToken(appURL, testPhone, totpCode, "android", "smoke-device-id")
	require.NoError(t, err, "loginWorkerGetToken error")
	require.NotEmpty(t, accessToken, "No access token returned from worker login")

	t.Log("[INFO] Worker login (mobile) success; got access token. Testing account endpoint...")

	// -------------------------------------------------------------------------
	// 9. Protected account-service endpoint: /worker/checkr/outcome
	// -------------------------------------------------------------------------
	require.NoError(t, checkCheckrOutcome(
		appURL,
		accessToken,
		"android",
		"smoke-device-id",
	))
	t.Log("[INFO] /worker/checkr/outcome responded as expected")

	// -------------------------------------------------------------------------
	// 10. Public “well-known” endpoint: /.well-known/assetlinks.json
	// -------------------------------------------------------------------------
	require.NoError(t, checkWellKnownAssetLinks(appURL))
	t.Log("[INFO] /.well-known/assetlinks.json reachable and looks valid")

	// -------------------------------------------------------------------------
	// 11. Jobs-service: list open jobs (GET /api/v1/jobs)
	// -------------------------------------------------------------------------
	require.NoError(t, listOpenJobs(
		appURL,
		accessToken,
		"android",
		"smoke-device-id",
	), "listOpenJobs")
	t.Log("[INFO] /api/v1/jobs responded as expected (Jobs-service healthy)")

	// -------------------------------------------------------------------------
	// 12. Earnings-service: get summary (GET /api/v1/earnings/summary)
	// -------------------------------------------------------------------------
	require.NoError(t, checkEarningsSummary(
		appURL,
		accessToken,
		"android",
		"smoke-device-id",
	), "checkEarningsSummary")
	t.Log("[INFO] /api/v1/earnings/summary responded as expected (Earnings-service healthy)")
}

// ----------------------------------------------------------------------------
// TOTP
// ----------------------------------------------------------------------------
type totpSecretResponse struct {
	Secret string `json:"secret"`
	QRCode string `json:"qr_code"` // FIXED: Changed from 'URI' to 'QRCode'
}

func fetchTOTPSecret(baseURL string) (*totpSecretResponse, error) {
	url := baseURL + "/auth/v1/register/totp_secret"
	resp, err := http.Post(url, "application/json", strings.NewReader("{}"))
	if err != nil {
		return nil, fmt.Errorf("POST totp_secret: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("expected 200 from totp_secret, got %d", resp.StatusCode)
	}

	var data totpSecretResponse
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return nil, fmt.Errorf("decode totpSecretResponse: %w", err)
	}
	return &data, nil
}

// ----------------------------------------------------------------------------
// Worker phone “valid” endpoint => returns 200 if not in use, 409 if in use
// ----------------------------------------------------------------------------
func checkWorkerPhoneInUse(baseURL, phone string) (bool, error) {
	// We interpret 200 => not in use => bool=false
	//            409 => in use => bool=true
	// other statuses => error
	reqData := map[string]string{"phone_number": phone}
	bodyBytes, err := json.Marshal(reqData)
	if err != nil {
		return false, fmt.Errorf("marshal: %w", err)
	}

	url := baseURL + "/auth/v1/worker/phone/valid"
	req, err := http.NewRequest("POST", url, bytes.NewReader(bodyBytes))
	if err != nil {
		return false, fmt.Errorf("newRequest: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	// tell the service this is mobile
	req.Header.Set("X-Platform", "android")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return false, fmt.Errorf("doRequest: %w", err)
	}
	defer resp.Body.Close()

	switch resp.StatusCode {
	case http.StatusOK:
		// Means phone not used yet
		return false, nil
	case http.StatusConflict:
		// Means phone in use
		return true, nil
	default:
		bodyBytes, _ := io.ReadAll(resp.Body)
		return false, fmt.Errorf("unexpected status code %d from /worker/phone/valid; body=%s",
			resp.StatusCode, string(bodyBytes))
	}
}

// ----------------------------------------------------------------------------
// Email verification
// ----------------------------------------------------------------------------
func sendEmailCode(baseURL, email string) error {
	reqData := map[string]string{"email": email}
	reqBody, _ := json.Marshal(reqData)

	url := baseURL + "/auth/v1/worker/request_email_code"
	req, err := http.NewRequest("POST", url, bytes.NewReader(reqBody))
	if err != nil {
		return fmt.Errorf("sendEmailCode newRequest: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	// mobile-only
	req.Header.Set("X-Platform", "android")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("sendEmailCode do: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("expected 200 from /request_email_code, got %d", resp.StatusCode)
	}
	return nil
}

func verifyEmailCode(baseURL, email, code string) error {
	reqData := map[string]string{
		"email": email,
		"code":  code,
	}
	reqBody, _ := json.Marshal(reqData)

	url := baseURL + "/auth/v1/worker/verify_email_code"
	req, err := http.NewRequest("POST", url, bytes.NewReader(reqBody))
	if err != nil {
		return fmt.Errorf("verifyEmailCode newRequest: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	// mobile-only
	req.Header.Set("X-Platform", "android")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("verifyEmailCode do: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("expected 200 from /verify_email_code, got %d", resp.StatusCode)
	}
	return nil
}

// ----------------------------------------------------------------------------
// SMS verification
// ----------------------------------------------------------------------------
func sendSMSCode(baseURL, phone string) error {
	reqData := map[string]string{"phone_number": phone}
	reqBody, _ := json.Marshal(reqData)

	url := baseURL + "/auth/v1/worker/request_sms_code"
	req, err := http.NewRequest("POST", url, bytes.NewReader(reqBody))
	if err != nil {
		return fmt.Errorf("sendSMSCode newRequest: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	// mobile-only
	req.Header.Set("X-Platform", "android")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("sendSMSCode do: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("expected 200 from /request_sms_code, got %d", resp.StatusCode)
	}
	return nil
}

func verifySMSCode(baseURL, phone, code string) error {
	reqData := map[string]string{
		"phone_number": phone,
		"code":         code,
	}
	reqBody, _ := json.Marshal(reqData)

	url := baseURL + "/auth/v1/worker/verify_sms_code"
	req, err := http.NewRequest("POST", url, bytes.NewReader(reqBody))
	if err != nil {
		return fmt.Errorf("verifySMSCode newRequest: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	// mobile-only
	req.Header.Set("X-Platform", "android")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("verifySMSCode do: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("expected 200 from /verify_sms_code, got %d", resp.StatusCode)
	}
	return nil
}

// ----------------------------------------------------------------------------
// Worker Registration (mobile flow only)
// ----------------------------------------------------------------------------
func registerWorker(baseURL, first, last, email, phone, totpSecret, totpToken string) error {
	reqData := map[string]any{
		"first_name":     first,
		"last_name":      last,
		"email":          email,
		"phone_number":   phone,
		"street_address": "123 Smoke Rd",
		"city":           "TestCity",
		"state":          "TT",
		"zip_code":       "12345",
		"vehicle_year":   2020,
		"vehicle_make":   "SmokeMobile",
		"vehicle_model":  "TestModel",
		"totp_secret":    totpSecret,
		"totp_token":     totpToken,
	}

	reqBody, err := json.Marshal(reqData)
	if err != nil {
		return fmt.Errorf("registerWorker marshal: %w", err)
	}

	url := baseURL + "/auth/v1/worker/register"
	req, err := http.NewRequest("POST", url, bytes.NewReader(reqBody))
	if err != nil {
		return fmt.Errorf("registerWorker newRequest: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	// mobile-only
	req.Header.Set("X-Platform", "android")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("registerWorker do: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("expected 201 from /worker/register, got %d, body=%s", resp.StatusCode, string(body))
	}
	return nil
}

// ----------------------------------------------------------------------------
// Worker Login => AccessToken (mobile only)
// ----------------------------------------------------------------------------
func loginWorkerGetToken(baseURL, phone, totpCode, platform, deviceID string) (string, error) {
	type loginWorkerRequest struct {
		PhoneNumber string `json:"phone_number"`
		TOTPCode    string `json:"totp_code"`
	}
	reqDTO := loginWorkerRequest{
		PhoneNumber: phone,
		TOTPCode:    totpCode,
	}
	bodyBytes, _ := json.Marshal(reqDTO)

	url := baseURL + "/auth/v1/worker/login"
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(bodyBytes))
	if err != nil {
		return "", fmt.Errorf("loginWorker newRequest: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	// platform for middleware
	req.Header.Set("X-Platform", platform)
	// attach a fake integrity token for the MobileAttestationMiddleware
	req.Header.Set("X-Device-Integrity", "FAKE_INTEGRITY_TOKEN")
	// device ID for binding
	if deviceID != "" {
		req.Header.Set("X-Device-ID", deviceID)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("loginWorker do: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("loginWorker: expected 200, got %d, body=%s", resp.StatusCode, string(body))
	}

	type loginWorkerResponse struct {
		Worker       any    `json:"worker"`
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	var out loginWorkerResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", fmt.Errorf("loginWorker decode: %w", err)
	}
	if out.AccessToken == "" {
		return "", fmt.Errorf("no accessToken in login response")
	}
	return out.AccessToken, nil
}

// =============================================================================
// Account-service smoke checks
// =============================================================================
func checkCheckrOutcome(baseURL, accessToken, platform, deviceID string) error {
	url := baseURL + "/api/v1/account/worker/checkr/outcome"
	req, _ := http.NewRequest(http.MethodGet, url, nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("X-Platform", platform)
	if deviceID != "" {
		req.Header.Set("X-Device-ID", deviceID)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("checkr/outcome: expected 200, got %d – %s", resp.StatusCode, string(body))
	}

	var out struct{ Outcome string `json:"outcome"` }
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return err
	}
	if strings.ToUpper(out.Outcome) != "UNKNOWN" {
		return fmt.Errorf("unexpected outcome %q (want \"UNKNOWN\")", out.Outcome)
	}
	return nil
}

// Public /.well-known/assetlinks.json
func checkWellKnownAssetLinks(baseURL string) error {
	url := baseURL + "/.well-known/assetlinks.json"
	resp, err := http.Get(url)
	if err != nil {
		return fmt.Errorf("GET assetlinks.json: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("assetlinks.json expected 200, got %d", resp.StatusCode)
	}
	body, _ := io.ReadAll(resp.Body)
	if !strings.Contains(string(body), `"package_name"`) {
		return fmt.Errorf("assetlinks.json does not appear valid")
	}
	return nil
}

// =============================================================================
// Jobs-service smoke checks
// =============================================================================
func listOpenJobs(baseURL, accessToken, platform, deviceID string) error {
	// Minimal radius query near 0,0 to satisfy required lat/lng params.
	url := baseURL + "/api/v1/jobs/open?lat=0&lng=0&page=1&size=1"
	req, _ := http.NewRequest(http.MethodGet, url, nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("X-Platform", platform)
	if deviceID != "" {
		req.Header.Set("X-Device-ID", deviceID)
	}
	req.Header.Set("Accept", "application/json") // <-- ensure JSON, avoid Swagger HTML

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("listOpenJobs: expected 200, got %d – %s", resp.StatusCode, string(body))
	}

	// Ensure valid JSON payload with required keys.
	var out struct {
		Results []any `json:"results"`
		Page    int   `json:"page"`
		Size    int   `json:"size"`
		Total   int   `json:"total"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return fmt.Errorf("listOpenJobs decode: %w", err)
	}
	return nil
}

// =============================================================================
// Earnings-service smoke checks
// =============================================================================
func checkEarningsSummary(baseURL, accessToken, platform, deviceID string) error {
	url := baseURL + "/api/v1/earnings/summary"
	req, _ := http.NewRequest(http.MethodGet, url, nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("X-Platform", platform)
	if deviceID != "" {
		req.Header.Set("X-Device-ID", deviceID)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("GET /earnings/summary: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("expected 200 from /earnings/summary, got %d, body=%s", resp.StatusCode, string(body))
	}

	// FIXED: Updated this struct to match the new EarningsSummaryResponse DTO
	var out struct {
		TwoMonthTotal  float64 `json:"two_month_total"`
		CurrentWeek    any     `json:"current_week"`
		PastWeeks      []any   `json:"past_weeks"`
		NextPayoutDate string  `json:"next_payout_date"`
	}

	// Read the body once to check for keys and for decoding
	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response body: %w", err)
	}

	if err := json.Unmarshal(bodyBytes, &out); err != nil {
		return fmt.Errorf("decode EarningsSummaryResponse: %w", err)
	}

	// FIXED: Updated these checks for the new field names
	if !strings.Contains(string(bodyBytes), `"two_month_total"`) {
		return fmt.Errorf("response missing 'two_month_total' field")
	}

	if !strings.Contains(string(bodyBytes), `"current_week"`) {
		return fmt.Errorf("response missing 'current_week' field")
	}

	if !strings.Contains(string(bodyBytes), `"past_weeks"`) {
		return fmt.Errorf("response missing 'past_weeks' field")
	}

	return nil
}
