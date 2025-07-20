//go:build (dev_test || staging_test) && integration

package integration

import (
	"io"
	"context"
	"fmt"
	"math/rand"
	"net/http"
	"strings"
	"testing"
	"time"
	"errors"
	"encoding/json"

	"github.com/poofware/auth-service/internal/services"

	"github.com/poofware/auth-service/internal/dtos"
	"github.com/poofware/go-utils"
	"github.com/stretchr/testify/require"
)

type DesktopSession struct {
	Client *http.Client
}

// ------------------------------------------------------------
// (A) PM Flow
// ------------------------------------------------------------
func TestPropertyManagerRegistrationAndLoginFlow(t *testing.T) {
	h.T = t
	t.Cleanup(func() {
		_, _ = h.DB.Exec(context.Background(), `DELETE FROM rate_limit_attempts WHERE key LIKE 'sms:%' OR key LIKE 'email:%'`)
	})

	testEmail := "jlmoors001@gmail.com"
	testPhone := "+12345678900"

	// 1) TOTP
	totpData := generateTOTPSecret(t)
	totpCode := h.GenerateTOTPCode(totpData.Secret)

	// 2) Validate => expect 200
	require.Equal(t, http.StatusOK, validatePMEmailStatus(t, testEmail))
	require.Equal(t, http.StatusOK, validatePMPhoneStatus(t, testPhone))

	// Send + verify for PM
	sendPMEmailCode(t, testEmail)
	verifyPMEmailCode(t, testEmail, retrieveLatestPMEmailCode(t, testEmail))
	sendPMSMSCode(t, testPhone)
	verifyPMSMSCode(t, testPhone, retrieveLatestPMSMSCode(t, testPhone))

	// 3) Register
	registerPM(t, testEmail, &testPhone, totpData.Secret, totpCode)

	// Defer deletion
	ctx := context.Background()
	pm, err := h.PMRepo.GetByEmail(ctx, testEmail)
	require.NoError(t, err)
	require.NotNil(t, pm)

	defer func() {
		h.DB.Exec(ctx, `DELETE FROM property_managers WHERE id=$1`, pm.ID)
	}()

	// Now validate => expect 409
	require.Equal(t, http.StatusConflict, validatePMEmailStatus(t, testEmail))
	require.Equal(t, http.StatusConflict, validatePMPhoneStatus(t, testPhone))

	t.Run("desktopSuccess", func(t *testing.T) {
		h.T = t
		newTOTP := h.GenerateTOTPCode(totpData.Secret)
		pmObj, client := loginPMDesktop(t, testEmail, newTOTP)
		require.NotEmpty(t, pmObj)
		logoutPMDesktopExpectSuccess(t, client)
	})

	t.Run("secondLoginRevokesOldRefresh", func(t *testing.T) {
		h.T = t
		code1 := h.GenerateTOTPCode(totpData.Secret)
		_, c1 := loginPMDesktop(t, testEmail, code1)
		code2 := h.GenerateTOTPCode(totpData.Secret)
		_, c2 := loginPMDesktop(t, testEmail, code2)
		err := refreshPMDesktop(t, c1, false)
		require.Error(t, err)
		require.NoError(t, refreshPMDesktop(t, c2, true))
	})
}

// ------------------------------------------------------------
// (B) Worker Flow
// ------------------------------------------------------------
func TestWorkerRegistrationAndLoginFlow(t *testing.T) {
	h.T = t
	t.Cleanup(func() {
		_, _ = h.DB.Exec(context.Background(), `DELETE FROM rate_limit_attempts WHERE key LIKE 'sms:%' OR key LIKE 'email:%'`)
	})

	testEmail := "jlmoors001@gmail.com"
	testPhone := "+12345678900"

	// 1) Generate TOTP
	totpData := generateTOTPSecret(t)
	totpCode := h.GenerateTOTPCode(totpData.Secret)

	// 2) Validate worker email/phone => expect 200
	require.Equal(t, http.StatusOK, validateWorkerEmailStatus(t, testEmail))
	require.Equal(t, http.StatusOK, validateWorkerPhoneStatus(t, testPhone))

	// Send + verify email code for worker
	sendWorkerEmailCode(t, testEmail)
	verifyWorkerEmailCode(t, testEmail, retrieveLatestWorkerEmailCode(t, testEmail))

	// Send + verify sms code for worker
	sendWorkerSMSCode(t, testPhone)
	verifyWorkerSMSCode(t, testPhone, retrieveLatestWorkerSMSCode(t, testPhone))

	// 3) Register Worker
	registerWorker(t, testEmail, testPhone, totpData.Secret, totpCode)

	// Defer deletion
	ctx := context.Background()
	w, err := h.WorkerRepo.GetByEmail(ctx, testEmail)
	require.NoError(t, err)
	require.NotNil(t, w)

	defer func() {
		h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, w.ID)
	}()

	// 4) Validate again => expect 409
	require.Equal(t, http.StatusConflict, validateWorkerEmailStatus(t, testEmail))
	require.Equal(t, http.StatusConflict, validateWorkerPhoneStatus(t, testPhone))

	t.Run("mobileSuccessWithDeviceID", func(t *testing.T) {
		h.T = t
		newTOTP := h.GenerateTOTPCode(totpData.Secret)
		wkr, access, refresh := loginWorkerWithPlatform(t, testPhone, newTOTP, "android", "worker-device-abc")
		require.NotEmpty(t, wkr)
		require.NotEmpty(t, access)
		require.NotEmpty(t, refresh)

		logoutWorkerExpectSuccessWithHeaders(t, access, refresh, "android", "worker-device-abc")
	})

	t.Run("mobileNoDeviceIDNegative", func(t *testing.T) {
		h.T = t
		newTOTP := h.GenerateTOTPCode(totpData.Secret)
		_, _, _, err := loginWorkerWithPlatformExpectFail(t, testPhone, newTOTP, "android", "")
		require.Error(t, err, "Expected mobile login to fail when missing device ID.")
	})

	t.Run("mobileSecondLoginRevokesOldRefresh", func(t *testing.T) {
		h.T = t
		deviceA := "worker-device-old"
		deviceB := "worker-device-new"

		code1 := h.GenerateTOTPCode(totpData.Secret)
		_, _, firstRefresh := loginWorkerWithPlatform(t, testPhone, code1, "android", deviceA)

		code2 := h.GenerateTOTPCode(totpData.Secret)
		_, _, secondRefresh := loginWorkerWithPlatform(t, testPhone, code2, "android", deviceB)
		require.NotEqual(t, firstRefresh, secondRefresh)

		_, _, err := refreshWorkerTokenWithPlatform(t, firstRefresh, "android", deviceA, false)
		require.Error(t, err)
	})
}

// ------------------------------------------------------------
// (C) Protected Endpoints Token Flow for PM
// ------------------------------------------------------------
func TestPMProtectedEndpointsTokenFlow(t *testing.T) {
	h.T = t
	t.Cleanup(func() {
		_, _ = h.DB.Exec(context.Background(), `DELETE FROM rate_limit_attempts WHERE key LIKE 'sms:%' OR key LIKE 'email:%'`)
	})

	accessTTL, refreshTTL := getTestTTLs(t)

	randomEmail := fmt.Sprintf("%d%s", rand.Intn(1e9), utils.TestEmailSuffix)
	randomPhone := fmt.Sprintf("%s%09d", utils.TestPhoneNumberBase, rand.Intn(1e9))

	totpData := generateTOTPSecret(t)
	totpCode := h.GenerateTOTPCode(totpData.Secret)

	require.Equal(t, http.StatusOK, validatePMEmailStatus(t, randomEmail))
	require.Equal(t, http.StatusOK, validatePMPhoneStatus(t, randomPhone))

	sendPMEmailCode(t, randomEmail)
	verifyPMEmailCode(t, randomEmail, services.TestEmailCode)
	sendPMSMSCode(t, randomPhone)
	verifyPMSMSCode(t, randomPhone, services.TestPhoneCode)

	registerPM(t, randomEmail, &randomPhone, totpData.Secret, totpCode)

	ctx := context.Background()
	pm, err := h.PMRepo.GetByEmail(ctx, randomEmail)
	require.NoError(t, err)
	require.NotNil(t, pm)

	defer func() {
		h.DB.Exec(ctx, `DELETE FROM property_managers WHERE id=$1`, pm.ID)
	}()

	t.Run("desktopSuccess", func(t *testing.T) {
		h.T = t
		pmObj, client := loginPMDesktop(t, randomEmail, h.GenerateTOTPCode(totpData.Secret))
		require.NotEmpty(t, pmObj)
		logoutPMDesktopExpectSuccess(t, client)

		// Refresh should now fail after logout
		err := refreshPMDesktop(t, client, false)
		require.Error(t, err)
	})

	t.Logf("Using ACCESS_TOKEN_TEST_TTL=%d, REFRESH_TOKEN_TEST_TTL=%d", accessTTL, refreshTTL)
}

// ------------------------------------------------------------
// (D) Protected Endpoints Token Flow for Worker
// ------------------------------------------------------------
func TestWorkerProtectedEndpointsTokenFlow(t *testing.T) {
	h.T = t
	t.Cleanup(func() {
		_, _ = h.DB.Exec(context.Background(), `DELETE FROM rate_limit_attempts WHERE key LIKE 'sms:%' OR key LIKE 'email:%'`)
	})

	accessTTL, refreshTTL := getTestTTLs(t)

	randomEmail := fmt.Sprintf("%d%s", rand.Intn(1e9), utils.TestEmailSuffix)
	randomPhone := fmt.Sprintf("%s%09d", utils.TestPhoneNumberBase, rand.Intn(1e9))
	totpData := generateTOTPSecret(t)
	totpCode := h.GenerateTOTPCode(totpData.Secret)

	require.Equal(t, http.StatusOK, validateWorkerEmailStatus(t, randomEmail))
	require.Equal(t, http.StatusOK, validateWorkerPhoneStatus(t, randomPhone))

	sendWorkerEmailCode(t, randomEmail)
	verifyWorkerEmailCode(t, randomEmail, services.TestEmailCode)

	sendWorkerSMSCode(t, randomPhone)
	verifyWorkerSMSCode(t, randomPhone, services.TestPhoneCode)

	registerWorker(t, randomEmail, randomPhone, totpData.Secret, totpCode)

	ctx := context.Background()
	w, err := h.WorkerRepo.GetByEmail(ctx, randomEmail)
	require.NoError(t, err)
	require.NotNil(t, w)

	defer func() {
		h.DB.Exec(ctx, `DELETE FROM workers WHERE id=$1`, w.ID)
	}()

	t.Run("mobileSuccessWithDeviceID", func(t *testing.T) {
		h.T = t
		wObj, access, refresh := loginWorkerWithPlatform(t, randomPhone, h.GenerateTOTPCode(totpData.Secret), "android", "worker-1234")
		require.NotEmpty(t, wObj)
		require.NotEmpty(t, access)
		require.NotEmpty(t, refresh)

		logoutWorkerExpectSuccessWithHeaders(t, access, refresh, "android", "worker-1234")
		_, _, err := refreshWorkerTokenWithPlatform(t, refresh, "android", "worker-1234", false)
		require.Error(t, err)
	})

	t.Run("mobileNoDeviceIDNegative", func(t *testing.T) {
		h.T = t
		_, _, _, err := loginWorkerWithPlatformExpectFail(t, randomEmail, h.GenerateTOTPCode(totpData.Secret), "android", "")
		require.Error(t, err)
	})

	t.Logf("Using ACCESS_TOKEN_TEST_TTL=%d, REFRESH_TOKEN_TEST_TTL=%d", accessTTL, refreshTTL)
}

// ------------------------------------------------------------
//  Token Expiration (PM = web only, Worker = mobile only)
// ------------------------------------------------------------

// PM: web token-expiration
func TestPMTokenExpirationBehavior(t *testing.T) {
	h.T = t
	t.Cleanup(func() {
		_, _ = h.DB.Exec(context.Background(), `DELETE FROM rate_limit_attempts WHERE key LIKE 'sms:%' OR key LIKE 'email:%'`)
	})

	if testing.Short() {
		t.Skip("Skipping token-expiration tests in short mode.")
	}

	accessTTL, refreshTTL := getTestTTLs(t)

	// 1 ) Fresh PM registration
	email := fmt.Sprintf("%d%s", rand.Intn(1e9), utils.TestEmailSuffix)
	phone := fmt.Sprintf("%s%09d", utils.TestPhoneNumberBase, rand.Intn(1e9))

	totpData := generateTOTPSecret(t)
	totpCode := h.GenerateTOTPCode(totpData.Secret)

	sendPMEmailCode(t, email)
	verifyPMEmailCode(t, email, services.TestEmailCode)
	sendPMSMSCode(t, phone)
	verifyPMSMSCode(t, phone, services.TestPhoneCode)
	registerPM(t, email, &phone, totpData.Secret, totpCode)

	ctx := context.Background()
	pm, _ := h.PMRepo.GetByEmail(ctx, email)
	require.NotNil(t, pm)
	defer h.DB.Exec(ctx, `DELETE FROM property_managers WHERE id=$1`, pm.ID)

	// 2 ) Login → desktop cookies
	_, client := loginPMDesktop(t, email, h.GenerateTOTPCode(totpData.Secret))

	// 3 ) Let ACCESS token expire
	time.Sleep(time.Duration(accessTTL+1) * time.Second)

	// logout must fail w/ 401
	logoutStatus := func() int {
		url := h.BaseURL + "/auth/v1/pm/logout"
		resp := doRequestWithClient(t, client, http.MethodPost, url, []byte("{}"),
			map[string]string{"X-Platform": "web"})
		defer resp.Body.Close()
		return resp.StatusCode
	}()
	require.Equal(t, http.StatusUnauthorized, logoutStatus)

	// 4 ) Refresh cookie
	require.NoError(t, refreshPMDesktop(t, client, true))

	// 5 ) Let REFRESH expire
	time.Sleep(time.Duration(refreshTTL+1) * time.Second)
	require.Error(t, refreshPMDesktop(t, client, true))
}

// Worker: keep only mobile variant
func TestWorkerTokenExpirationBehavior_Mobile(t *testing.T) {
	h.T = t
	t.Cleanup(func() {
		_, _ = h.DB.Exec(context.Background(), `DELETE FROM rate_limit_attempts WHERE key LIKE 'sms:%' OR key LIKE 'email:%'`)
	})

	if testing.Short() {
		t.Skip("Skipping mobile expiration test in short mode.")
	}

	accessTTL, refreshTTL := getTestTTLs(t)
	email := fmt.Sprintf("%d%s", rand.Intn(1e9), utils.TestEmailSuffix)
	phone := fmt.Sprintf("%s%09d", utils.TestPhoneNumberBase, rand.Intn(1e9))
	deviceID := "worker-exp-device"

	totpData := generateTOTPSecret(t)
	totpCode := h.GenerateTOTPCode(totpData.Secret)

	sendWorkerEmailCode(t, email)
	verifyWorkerEmailCode(t, email, services.TestEmailCode)
	sendWorkerSMSCode(t, phone)
	verifyWorkerSMSCode(t, phone, services.TestPhoneCode)
	registerWorker(t, email, phone, totpData.Secret, totpCode)

	ctx := context.Background()
	w, _ := h.WorkerRepo.GetByEmail(ctx, email)
	defer h.DB.Exec(ctx, "DELETE FROM workers WHERE id=$1", w.ID)

	_, access, refresh := loginWorkerWithPlatform(t, phone, h.GenerateTOTPCode(totpData.Secret), "android", deviceID)

	// check logout with the old access
	dummyRefresh := strings.Repeat("1", 64)
	status := doWorkerProtectedLogoutCheckCode(t, access, dummyRefresh, "android", deviceID)
	require.NotEqual(t, http.StatusUnauthorized, status)

	// Access expires
	time.Sleep(time.Duration(accessTTL+1) * time.Second)
	status = doWorkerProtectedLogoutCheckCode(t, access, dummyRefresh, "android", deviceID)
	require.Equal(t, http.StatusUnauthorized, status)

	newAccess, newRefresh, err := refreshWorkerTokenWithPlatform(t, refresh, "android", deviceID, true)
	require.NoError(t, err)

	status = doWorkerProtectedLogoutCheckCode(t, newAccess, dummyRefresh, "android", deviceID)
	require.NotEqual(t, http.StatusUnauthorized, status)

	time.Sleep(time.Duration(refreshTTL+1) * time.Second)
	_, _, err = refreshWorkerTokenWithPlatform(t, newRefresh, "android", deviceID, true)
	require.Error(t, err)
}

// ------------------------------------------------------------
// (E) Admin Flow
// ------------------------------------------------------------
// meta-service/services/auth-service/internal/integration/auth_flow_test.go


func TestAdminLoginFlow(t *testing.T) {
	h.T = t
	ctx := context.Background()

	// --- Create a dedicated admin user for this test flow ---
	const testAdminPassword = "aSecurePassword123!"
	testAdmin := createTestAdminWithPassword(t, ctx, "flow-admin-"+utils.RandomString(6)+"@poof.io", testAdminPassword)
	defer h.DB.Exec(ctx, `DELETE FROM admins WHERE id=$1`, testAdmin.ID)

	// --- Use the credentials from the admin we just created ---
	testAdminUsername := testAdmin.Username
	testAdminTOTPSecret := testAdmin.TOTPSecret

	t.Run("AdminLoginAndLogoutSuccess", func(t *testing.T) {
		h.T = t
		// Generate a valid TOTP code from the secret
		totpCode := h.GenerateTOTPCode(testAdminTOTPSecret)
		_, client := loginAdminDesktop(t, testAdminUsername, testAdminPassword, totpCode)

		// Successfully log out.
		logoutAdminDesktopExpectSuccess(t, client)

		// Refresh should now fail after logout.
		err := refreshAdminDesktop(t, client, false)
		require.Error(t, err, "Refresh should fail after logout")
	})

	t.Run("AdminSecondLoginRevokesOldRefresh", func(t *testing.T) {
		h.T = t
		// Login first time
		code1 := h.GenerateTOTPCode(testAdminTOTPSecret)
		_, c1 := loginAdminDesktop(t, testAdminUsername, testAdminPassword, code1)

		// Login second time
		code2 := h.GenerateTOTPCode(testAdminTOTPSecret)
		_, c2 := loginAdminDesktop(t, testAdminUsername, testAdminPassword, code2)

		// The first client's refresh token should now be invalid.
		err := refreshAdminDesktop(t, c1, false)
		require.Error(t, err, "First refresh token should be revoked by the second login")

		// The second client's refresh token should be valid.
		err = refreshAdminDesktop(t, c2, true)
		require.NoError(t, err, "Second refresh token should still be valid")
	})
}

// (The rest of the file remains unchanged)
	func loginAdminDesktop(t *testing.T, username, password, totpCode string) (any, *http.Client) {
		client := newBrowserClient(t)
		reqDTO := dtos.LoginAdminRequest{Username: username, Password: password, TOTPCode: totpCode}
		body, _ := json.Marshal(reqDTO)
		urlStr := h.BaseURL + "/auth/v1/admin/login"
		resp := doRequestWithClient(t, client, http.MethodPost, urlStr, body, map[string]string{"Content-Type": "application/json", "X-Platform": "web"})
		require.Equal(t, http.StatusOK, resp.StatusCode, "Admin login failed unexpectedly")
		defer resp.Body.Close()
		return nil, client
	}
	
	func logoutAdminDesktopExpectSuccess(t *testing.T, client *http.Client) {
		urlStr := h.BaseURL + "/auth/v1/admin/logout"
		resp := doRequestWithClient(t, client, http.MethodPost, urlStr, nil, map[string]string{"X-Platform": "web"})
		require.Equal(t, http.StatusOK, resp.StatusCode)
		defer resp.Body.Close()
	}
	
	func refreshAdminDesktop(t *testing.T, client *http.Client, expectSuccess bool) error {
		urlStr := h.BaseURL + "/auth/v1/admin/refresh_token"
		resp := doRequestWithClient(t, client, http.MethodPost, urlStr, nil, map[string]string{"X-Platform": "web"})
		defer resp.Body.Close()
		if expectSuccess {
			if resp.StatusCode != http.StatusOK {
				body, _ := io.ReadAll(resp.Body)
				return fmt.Errorf("expected 200 OK for admin refresh, got %d. Body: %s", resp.StatusCode, string(body))
			}
			return nil
		}
		if resp.StatusCode == http.StatusOK {
			return errors.New("expected admin refresh to fail, but it succeeded")
		}
		return fmt.Errorf("refresh failed as expected with status %d", resp.StatusCode)
	}
