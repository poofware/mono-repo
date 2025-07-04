//go:build (dev_test || dev || staging_test) && integration

package integration

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"os"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/poofware/auth-service/internal/config"
	"github.com/poofware/auth-service/internal/dtos"
	internal_utils "github.com/poofware/auth-service/internal/utils"
	"github.com/poofware/go-middleware"
	"github.com/poofware/go-models"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
	"github.com/poofware/go-testhelpers"
	"github.com/stretchr/testify/require"
)

var (
	h   *testhelpers.TestHelper
	cfg *config.Config
)

func TestMain(m *testing.M) {
	if config.AppName == "" {
		log.Fatal("AppName ldflag is missing")
	}
	if config.UniqueRunnerID == "" {
		log.Fatal("UniqueRunnerID ldflag is missing")
	}
	if config.UniqueRunNumber == "" {
		log.Fatal("UniqueRunNumber ldflag is missing")
	}

	t := &testing.T{}
	h = testhelpers.NewTestHelper(t, config.AppName, config.UniqueRunnerID, config.UniqueRunNumber)
	cfg = config.LoadConfig()

	code := m.Run()
	os.Exit(code)
}

// =============================================================================
// SHARED HELPER FUNCTIONS
// =============================================================================
func createTestAdminWithPassword(t *testing.T, ctx context.Context, username, password string) *models.Admin {
		t.Helper()
	
		adminRepo := repositories.NewAdminRepository(h.DB, cfg.DBEncryptionKey)
	
		// Generate a TOTP secret for the admin
		secret, err := internal_utils.GenerateTOTPSecret(utils.OrganizationName, username)
		require.NoError(t, err)
	
		// Create the admin model
		admin := &models.Admin{
			ID:         uuid.New(),
			Username:   username,
			TOTPSecret: secret,
		}
	
		// Hash the provided password
		admin.PasswordHash, err = utils.HashPassword(password)
		require.NoError(t, err)
	
		// Create the admin in the database
		err = adminRepo.Create(ctx, admin)
		require.NoError(t, err)
	
		// Fetch it back to ensure it was created correctly
		createdAdmin, err := adminRepo.GetByID(ctx, admin.ID)
		require.NoError(t, err)
		require.NotNil(t, createdAdmin)
		return createdAdmin
	}
// --- Generic Request Helper ---

func doRequest(t *testing.T, method, url string, body []byte, headers map[string]string) *http.Response {
	req, err := http.NewRequest(method, url, strings.NewReader(string(body)))
	require.NoError(t, err)

	for k, v := range headers {
		req.Header.Set(k, v)
	}

	client := http.Client{}
	resp, err := client.Do(req)
	require.NoError(t, err)
	return resp
}

// --- PM Verification Helpers ---

func sendPMEmailCode(t *testing.T, email string) {
	req := dtos.RequestEmailCodeRequest{Email: email}
	b, _ := json.Marshal(req)

	url := h.BaseURL + "/auth/v1/pm/request_email_code"
	resp, err := http.Post(url, "application/json", strings.NewReader(string(b)))
	require.NoError(t, err)
	defer resp.Body.Close()

	require.Equal(t, http.StatusOK, resp.StatusCode)
}

func verifyPMEmailCode(t *testing.T, email, code string) {
	req := dtos.VerifyEmailCodeRequest{Email: email, Code: code}
	b, _ := json.Marshal(req)

	url := h.BaseURL + "/auth/v1/pm/verify_email_code"
	resp, err := http.Post(url, "application/json", strings.NewReader(string(b)))
	require.NoError(t, err)
	defer resp.Body.Close()

	require.Equal(t, http.StatusOK, resp.StatusCode)
}

func retrieveLatestPMEmailCode(t *testing.T, pmEmail string) string {
	ctx := context.Background()
	rec, err := h.PMEmailRepo.GetCode(ctx, pmEmail)
	require.NoError(t, err)
	require.NotNil(t, rec)
	return rec.VerificationCode
}

func sendPMSMSCode(t *testing.T, phoneNumber string) {
	req := dtos.RequestSMSCodeRequest{PhoneNumber: phoneNumber}
	b, _ := json.Marshal(req)

	url := h.BaseURL + "/auth/v1/pm/request_sms_code"
	resp, err := http.Post(url, "application/json", strings.NewReader(string(b)))
	require.NoError(t, err)
	defer resp.Body.Close()

	require.Equal(t, http.StatusOK, resp.StatusCode)
}

func verifyPMSMSCode(t *testing.T, phoneNumber, code string) {
	req := dtos.VerifySMSCodeRequest{PhoneNumber: phoneNumber, Code: code}
	b, _ := json.Marshal(req)

	url := h.BaseURL + "/auth/v1/pm/verify_sms_code"
	resp, err := http.Post(url, "application/json", strings.NewReader(string(b)))
	require.NoError(t, err)
	defer resp.Body.Close()

	require.Equal(t, http.StatusOK, resp.StatusCode)
}

func retrieveLatestPMSMSCode(t *testing.T, pmPhone string) string {
	ctx := context.Background()
	rec, err := h.PMSMSRepo.GetCode(ctx, pmPhone)
	require.NoError(t, err)
	require.NotNil(t, rec)
	return rec.VerificationCode
}

// --- Worker Verification Helpers ---

func sendWorkerEmailCode(t *testing.T, email string) {
	req := dtos.RequestEmailCodeRequest{Email: email}
	b, _ := json.Marshal(req)

	url := h.BaseURL + "/auth/v1/worker/request_email_code"
	resp := doRequest(t, "POST", url, b, map[string]string{
		"Content-Type":       "application/json",
		"X-Platform":         "android",
		"X-Device-Integrity": "FAKE_INTEGRITY_TOKEN",
		"X-Device-ID":        "test-dev-id",
	})
	require.Equal(t, http.StatusOK, resp.StatusCode)
	defer resp.Body.Close()
}

func verifyWorkerEmailCode(t *testing.T, email, code string) {
	req := dtos.VerifyEmailCodeRequest{Email: email, Code: code}
	b, _ := json.Marshal(req)

	url := h.BaseURL + "/auth/v1/worker/verify_email_code"
	resp := doRequest(t, "POST", url, b, map[string]string{
		"Content-Type":       "application/json",
		"X-Platform":         "android",
		"X-Device-Integrity": "FAKE_INTEGRITY_TOKEN",
		"X-Device-ID":        "test-dev-id",
	})
	defer resp.Body.Close()

	require.Equal(t, http.StatusOK, resp.StatusCode)
}

func retrieveLatestWorkerEmailCode(t *testing.T, workerEmail string) string {
	ctx := context.Background()
	rec, err := h.WorkerEmailRepo.GetCode(ctx, workerEmail)
	require.NoError(t, err)
	require.NotNil(t, rec)
	return rec.VerificationCode
}

func sendWorkerSMSCode(t *testing.T, phoneNumber string) {
	req := dtos.RequestSMSCodeRequest{PhoneNumber: phoneNumber}
	b, _ := json.Marshal(req)

	url := h.BaseURL + "/auth/v1/worker/request_sms_code"
	resp := doRequest(t, "POST", url, b, map[string]string{
		"Content-Type":       "application/json",
		"X-Platform":         "android",
		"X-Device-Integrity": "FAKE_INTEGRITY_TOKEN",
		"X-Device-ID":        "test-dev-id",
	})
	require.Equal(t, http.StatusOK, resp.StatusCode)
	defer resp.Body.Close()
}

func verifyWorkerSMSCode(t *testing.T, phoneNumber, code string) {
	req := dtos.VerifySMSCodeRequest{PhoneNumber: phoneNumber, Code: code}
	b, _ := json.Marshal(req)

	url := h.BaseURL + "/auth/v1/worker/verify_sms_code"
	resp := doRequest(t, "POST", url, b, map[string]string{
		"Content-Type":       "application/json",
		"X-Platform":         "android",
		"X-Device-Integrity": "FAKE_INTEGRITY_TOKEN",
		"X-Device-ID":        "test-dev-id",
	})
	defer resp.Body.Close()

	require.Equal(t, http.StatusOK, resp.StatusCode)
}

func retrieveLatestWorkerSMSCode(t *testing.T, workerPhone string) string {
	ctx := context.Background()
	rec, err := h.WorkerSMSRepo.GetCode(ctx, workerPhone)
	require.NoError(t, err)
	require.NotNil(t, rec)
	return rec.VerificationCode
}

// --- Registration Helpers ---

func registerPM(t *testing.T, email string, phoneNumber *string, totpSecret, totpToken string) {
	reqDTO := dtos.RegisterPMRequest{
		FirstName:       "John",
		LastName:        "Doe",
		Email:           email,
		PhoneNumber:     phoneNumber,
		BusinessName:    "Biz Name",
		BusinessAddress: "123 Main St",
		City:            "FakeCity",
		State:           "FC",
		ZipCode:         "99999",
		TOTPSecret:      totpSecret,
		TOTPToken:       totpToken,
	}
	bodyBytes, err := json.Marshal(reqDTO)
	require.NoError(t, err)

	url := h.BaseURL + "/auth/v1/pm/register"
	resp, err := http.Post(url, "application/json", strings.NewReader(string(bodyBytes)))
	require.NoError(t, err)
	defer resp.Body.Close()

	require.Equal(t, http.StatusCreated, resp.StatusCode,
		fmt.Sprintf("registerPM: expected 201, got %d", resp.StatusCode))
}

func registerWorker(t *testing.T, email, phoneNumber, totpSecret, totpToken string) {
	reqDTO := dtos.RegisterWorkerRequest{
		FirstName:   "Alice",
		LastName:    "Worker",
		Email:       email,
		PhoneNumber: phoneNumber,
		TOTPSecret:  totpSecret,
		TOTPToken:   totpToken,
	}
	bodyBytes, err := json.Marshal(reqDTO)
	require.NoError(t, err)

	url := h.BaseURL + "/auth/v1/worker/register"
	resp := doRequest(t, http.MethodPost, url, bodyBytes, map[string]string{
		"Content-Type":       "application/json",
		"X-Platform":         "android",
		"X-Device-ID":        "test-dev-id",
		"X-Device-Integrity": "FAKE_INTEGRITY_TOKEN",
	})
	defer resp.Body.Close()

	require.Equal(t, http.StatusCreated, resp.StatusCode,
		fmt.Sprintf("registerWorker: expected 201, got %d", resp.StatusCode),
	)
}

// --- Validation Helpers ---

func validatePMEmailStatus(t *testing.T, email string) int {
	reqDTO := dtos.ValidatePMEmailRequest{Email: email}
	bodyBytes, err := json.Marshal(reqDTO)
	require.NoError(t, err)

	url := h.BaseURL + "/auth/v1/pm/email/valid"
	resp := doRequest(t, http.MethodPost, url, bodyBytes, map[string]string{
		"Content-Type": "application/json",
		"X-Platform":   "web",
	})
	defer resp.Body.Close()

	return resp.StatusCode
}

func validatePMPhoneStatus(t *testing.T, phone string) int {
	reqDTO := dtos.ValidatePMPhoneRequest{PhoneNumber: phone}
	bodyBytes, err := json.Marshal(reqDTO)
	require.NoError(t, err)

	url := h.BaseURL + "/auth/v1/pm/phone/valid"
	resp := doRequest(t, http.MethodPost, url, bodyBytes, map[string]string{
		"Content-Type": "application/json",
		"X-Platform":   "web",
	})
	defer resp.Body.Close()

	return resp.StatusCode
}

func validateWorkerEmailStatus(t *testing.T, email string) int {
	reqDTO := dtos.ValidateWorkerEmailRequest{Email: email}
	bodyBytes, err := json.Marshal(reqDTO)
	require.NoError(t, err)

	url := h.BaseURL + "/auth/v1/worker/email/valid"
	resp := doRequest(t, http.MethodPost, url, bodyBytes, map[string]string{
		"Content-Type":       "application/json",
		"X-Platform":         "android",
		"X-Device-Integrity": "FAKE_INTEGRITY_TOKEN",
		"X-Device-ID":        "test-dev-id",
	})
	defer resp.Body.Close()

	return resp.StatusCode
}

func validateWorkerPhoneStatus(t *testing.T, phone string) int {
	reqDTO := dtos.ValidateWorkerPhoneRequest{PhoneNumber: phone}
	bodyBytes, err := json.Marshal(reqDTO)
	require.NoError(t, err)

	url := h.BaseURL + "/auth/v1/worker/phone/valid"
	resp := doRequest(t, http.MethodPost, url, bodyBytes, map[string]string{
		"Content-Type":       "application/json",
		"X-Platform":         "android",
		"X-Device-Integrity": "FAKE_INTEGRITY_TOKEN",
		"X-Device-ID":        "test-dev-id",
	})
	defer resp.Body.Close()

	return resp.StatusCode
}

// --- TOTP, TTL and Session Helpers ---

func generateTOTPSecret(t *testing.T) dtos.GenerateTOTPSecretResponse {
	url := h.BaseURL + "/auth/v1/register/totp_secret"
	resp, err := http.Post(url, "application/json", strings.NewReader("{}"))
	require.NoError(t, err)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	body, err := io.ReadAll(resp.Body)
	require.NoError(t, err)

	var data dtos.GenerateTOTPSecretResponse
	require.NoError(t, json.Unmarshal(body, &data))
	return data
}

func getTestTTLs(_ *testing.T) (int, int) {
	defaultAccessTTL := int(config.TestShortTokenExpiry.Seconds())
	defaultRefreshTTL := int(config.TestShortRefreshTokenExpiry.Seconds())
	return defaultAccessTTL, defaultRefreshTTL
}

func doRequestWithClient(t *testing.T, client *http.Client, method, urlStr string, body []byte, headers map[string]string) *http.Response {
	if client == nil {
		client = &http.Client{}
	}
	req, err := http.NewRequest(method, urlStr, strings.NewReader(string(body)))
	require.NoError(t, err)
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := client.Do(req)
	require.NoError(t, err)
	return resp
}

func newBrowserClient(t *testing.T) *http.Client {
	jar, err := cookiejar.New(nil)
	require.NoError(t, err)
	return &http.Client{Jar: jar}
}

// --- Login/Logout/Refresh Helpers ---

func loginPMDesktop(t *testing.T, email, totpCode string) (any, *http.Client) {
	client := newBrowserClient(t)
	reqDTO := dtos.LoginPMRequest{Email: email, TOTPCode: totpCode}
	body, _ := json.Marshal(reqDTO)
	urlStr := h.BaseURL + "/auth/v1/pm/login"
	headers := map[string]string{
		"Content-Type": "application/json",
		"X-Platform":   "web",
	}

	resp := doRequestWithClient(t, client, http.MethodPost, urlStr, body, headers)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	data, _ := io.ReadAll(resp.Body)
	var loginResp dtos.LoginPMResponse
	_ = json.Unmarshal(data, &loginResp)
	require.Empty(t, loginResp.AccessToken)
	require.Empty(t, loginResp.RefreshToken)

	cookiesPresent(t, client, "/auth/v1/pm/refresh_token")
	return loginResp.PM, client
}

func logoutPMDesktopExpectSuccess(t *testing.T, client *http.Client) {
	urlStr := h.BaseURL + "/auth/v1/pm/logout"
	headers := map[string]string{"X-Platform": "web"}
	resp := doRequestWithClient(t, client, http.MethodPost, urlStr, []byte("{}"), headers)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)
}

func refreshPMDesktop(t *testing.T, client *http.Client, expectSuccess bool) error {
	url := h.BaseURL + "/auth/v1/pm/refresh_token"
	headers := map[string]string{
		"Content-Type": "application/json",
		"X-Platform":   "web",
	}
	resp := doRequestWithClient(t, client, http.MethodPost, url, nil, headers)
	defer resp.Body.Close()

	if expectSuccess {
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("refreshPMDesktop expected 200, got %d", resp.StatusCode)
		}
		return nil
	}

	if resp.StatusCode == http.StatusOK {
		return fmt.Errorf("refreshPMDesktop unexpectedly succeeded")
	}
	return fmt.Errorf("refreshPMDesktop failed as expected with code %d", resp.StatusCode)
}

func cookiesPresent(t *testing.T, client *http.Client, refreshPath string) {
	require.NotNil(t, client, "nil http.Client passed to cookiesPresent")

	rootURL, err := url.Parse(h.BaseURL)
	require.NoError(t, err)
	all := client.Jar.Cookies(rootURL)

	if refreshPath != "" && refreshPath[0] != '/' {
		refreshPath = "/" + refreshPath
	}
	if refreshPath != "" {
		refreshURL, err := url.Parse(h.BaseURL + refreshPath)
		require.NoError(t, err)
		all = append(all, client.Jar.Cookies(refreshURL)...)
	}

	hasAccess, hasRefresh := false, false
	for _, c := range all {
		switch c.Name {
		case middleware.AccessTokenCookieName:
			hasAccess = true
		case middleware.RefreshTokenCookieName:
			hasRefresh = true
		}
	}
	require.True(t, hasAccess, "access token cookie missing")
	require.True(t, hasRefresh, "refresh token cookie missing")
}

func loginWorkerWithPlatformExpectFail(t *testing.T, phoneNumber, totpCode, platform, deviceID string) (any, string, string, error) {
	reqDTO := dtos.LoginWorkerRequest{
		PhoneNumber: phoneNumber,
		TOTPCode:    totpCode,
	}
	bodyBytes, err := json.Marshal(reqDTO)
	require.NoError(t, err)

	url := h.BaseURL + "/auth/v1/worker/login"
	headers := map[string]string{
		"Content-Type": "application/json",
		"X-Platform":   platform,
	}
	if deviceID != "" {
		headers["X-Device-ID"] = deviceID
	}
	if platform != "web" {
		headers["X-Device-Integrity"] = "FAKE_INTEGRITY_TOKEN"
	}

	resp := doRequest(t, http.MethodPost, url, bodyBytes, headers)
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		return nil, "", "", fmt.Errorf("login Worker expected fail but got 200 OK")
	}
	return nil, "", "", fmt.Errorf("login Worker failed as expected with code %d", resp.StatusCode)
}

func loginWorkerWithPlatform(t *testing.T, phoneNumber, totpCode, platform, deviceID string) (any, string, string) {
	reqDTO := dtos.LoginWorkerRequest{
		PhoneNumber: phoneNumber,
		TOTPCode:    totpCode,
	}
	bodyBytes, err := json.Marshal(reqDTO)
	require.NoError(t, err)

	url := h.BaseURL + "/auth/v1/worker/login"
	headers := map[string]string{
		"Content-Type": "application/json",
		"X-Platform":   platform,
	}
	if deviceID != "" {
		headers["X-Device-ID"] = deviceID
	}
	if platform != "web" {
		headers["X-Device-Integrity"] = "FAKE_INTEGRITY_TOKEN"
	}

	resp := doRequest(t, http.MethodPost, url, bodyBytes, headers)
	defer resp.Body.Close()

	require.Equal(t, http.StatusOK, resp.StatusCode)

	data, err := io.ReadAll(resp.Body)
	require.NoError(t, err)

	var loginResp dtos.LoginWorkerResponse
	require.NoError(t, json.Unmarshal(data, &loginResp))

	return loginResp.Worker, loginResp.AccessToken, loginResp.RefreshToken
}

func logoutWorkerExpectSuccessWithHeaders(t *testing.T, accessToken, refreshToken, platform, deviceID string) {
	url := h.BaseURL + "/auth/v1/worker/logout"
	reqBody := dtos.LogoutRequest{RefreshToken: refreshToken}
	bodyBytes, _ := json.Marshal(reqBody)

	headers := map[string]string{
		"Authorization": "Bearer " + accessToken,
		"Content-Type":  "application/json",
		"X-Platform":    platform,
	}
	if deviceID != "" {
		headers["X-Device-ID"] = deviceID
	}
	if platform != "web" {
		headers["X-Device-Integrity"] = "FAKE_INTEGRITY_TOKEN"
	}

	resp := doRequest(t, http.MethodPost, url, bodyBytes, headers)
	defer resp.Body.Close()

	require.Equal(t, http.StatusOK, resp.StatusCode)
}

func refreshWorkerTokenWithPlatform(t *testing.T, oldRefreshToken, platform, deviceID string, expectSuccess bool) (string, string, error) {
	refreshURL := h.BaseURL + "/auth/v1/worker/refresh_token"
	reqDTO := dtos.RefreshTokenRequest{RefreshToken: oldRefreshToken}
	bodyBytes, _ := json.Marshal(reqDTO)

	headers := map[string]string{
		"Content-Type": "application/json",
		"X-Platform":   platform,
	}
	if deviceID != "" {
		headers["X-Device-ID"] = deviceID
	}
	if platform != "web" {
		headers["X-Device-Integrity"] = "FAKE_INTEGRITY_TOKEN"
	}

	resp := doRequest(t, http.MethodPost, refreshURL, bodyBytes, headers)
	defer resp.Body.Close()

	if expectSuccess {
		if resp.StatusCode != http.StatusOK {
			return "", "", fmt.Errorf("refreshWorkerToken: expected 200 but got %d", resp.StatusCode)
		}
		var refreshResp dtos.RefreshTokenResponse
		data, _ := io.ReadAll(resp.Body)
		if err := json.Unmarshal(data, &refreshResp); err != nil {
			return "", "", err
		}
		return refreshResp.AccessToken, refreshResp.RefreshToken, nil
	} else {
		if resp.StatusCode == http.StatusOK {
			return "", "", fmt.Errorf("refreshWorkerToken: expected fail but got 200")
		}
		return "", "", fmt.Errorf("refreshWorkerToken failed as expected with code %d", resp.StatusCode)
	}
}

func doWorkerProtectedLogoutCheckCode(t *testing.T, accessToken, refreshToken, platform, deviceID string) int {
	url := h.BaseURL + "/auth/v1/worker/logout"
	reqBody := dtos.LogoutRequest{RefreshToken: refreshToken}
	bodyBytes, _ := json.Marshal(reqBody)

	headers := map[string]string{
		"Authorization": "Bearer " + accessToken,
		"Content-Type":  "application/json",
		"X-Platform":    platform,
	}
	if deviceID != "" {
		headers["X-Device-ID"] = deviceID
	}
	if platform != "web" {
		headers["X-Device-Integrity"] = "FAKE_INTEGRITY_TOKEN"
	}

	resp := doRequest(t, http.MethodPost, url, bodyBytes, headers)
	defer resp.Body.Close()
	return resp.StatusCode
}

// --- Negative Path Verification Helpers ---

func sendPMEmailCodeExpectFailure(t *testing.T, email string) {
	reqDTO := dtos.RequestEmailCodeRequest{Email: email}
	b, err := json.Marshal(reqDTO)
	require.NoError(t, err)

	url := h.BaseURL + "/auth/v1/pm/request_email_code"
	resp, err := http.Post(url, "application/json", strings.NewReader(string(b)))
	require.NoError(t, err)
	defer resp.Body.Close()

	require.True(t,
		resp.StatusCode >= 400 && resp.StatusCode < 500,
		fmt.Sprintf("expected 4xx for email %q, got %d", email, resp.StatusCode),
	)
}

func sendWorkerEmailCodeExpectFailure(t *testing.T, email string) {
	reqDTO := dtos.RequestEmailCodeRequest{Email: email}
	b, err := json.Marshal(reqDTO)
	require.NoError(t, err)

	url := h.BaseURL + "/auth/v1/worker/request_email_code"
	req, err := http.NewRequest(http.MethodPost, url, strings.NewReader(string(b)))
	require.NoError(t, err)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Platform", "android")

	resp, err := http.DefaultClient.Do(req)
	require.NoError(t, err)
	defer resp.Body.Close()

	require.True(t,
		resp.StatusCode >= 400 && resp.StatusCode < 500,
		fmt.Sprintf("expected 4xx for email %q, got %d", email, resp.StatusCode),
	)
}

func sendPMSMSCodeExpectFailure(t *testing.T, phone string) {
	reqDTO := dtos.RequestSMSCodeRequest{PhoneNumber: phone}
	b, err := json.Marshal(reqDTO)
	require.NoError(t, err)

	url := h.BaseURL + "/auth/v1/pm/request_sms_code"
	resp, err := http.Post(url, "application/json", strings.NewReader(string(b)))
	require.NoError(t, err)
	defer resp.Body.Close()

	require.True(t,
		resp.StatusCode >= 400 && resp.StatusCode < 500,
		fmt.Sprintf("expected 4xx for phone %q, got %d", phone, resp.StatusCode),
	)
}

func sendWorkerSMSCodeExpectFailure(t *testing.T, phone string) {
	reqDTO := dtos.RequestSMSCodeRequest{PhoneNumber: phone}
	b, err := json.Marshal(reqDTO)
	require.NoError(t, err)

	url := h.BaseURL + "/auth/v1/worker/request_sms_code"
	req, err := http.NewRequest(http.MethodPost, url, strings.NewReader(string(b)))
	require.NoError(t, err)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Platform", "android")

	resp, err := http.DefaultClient.Do(req)
	require.NoError(t, err)
	defer resp.Body.Close()

	require.True(t,
		resp.StatusCode >= 400 && resp.StatusCode < 500,
		fmt.Sprintf("expected 4xx for phone %q, got %d", phone, resp.StatusCode),
	)
}
