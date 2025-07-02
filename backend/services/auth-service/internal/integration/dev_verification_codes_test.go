//go:build dev && integration

package integration

import (
	"testing"

	"github.com/stretchr/testify/require"
)

// Happy-path flows (previously existing tests)
func TestPMVerificationFlow(t *testing.T) {
	h.T = t
	testEmail := "jlmoors001@gmail.com"
	testPhone := "+12567013403"

	t.Run("EmailVerification", func(t *testing.T) {
		h.T = t
		sendPMEmailCode(t, testEmail)
		code := retrieveLatestPMEmailCode(t, testEmail)
		require.NotEmpty(t, code, "PM email verification code should not be empty")
		verifyPMEmailCode(t, testEmail, code)
	})

	t.Run("SMSVerification", func(t *testing.T) {
		h.T = t
		sendPMSMSCode(t, testPhone)
		code := retrieveLatestPMSMSCode(t, testPhone)
		require.NotEmpty(t, code, "PM SMS verification code should not be empty")
		verifyPMSMSCode(t, testPhone, code)
	})
}

func TestWorkerVerificationFlow(t *testing.T) {
	h.T = t
	testEmail := "jlmoors001@gmail.com"
	testPhone := "+12567013403"

	t.Run("EmailVerification", func(t *testing.T) {
		h.T = t
		sendWorkerEmailCode(t, testEmail)
		code := retrieveLatestWorkerEmailCode(t, testEmail)
		require.NotEmpty(t, code, "Worker email verification code should not be empty")
		verifyWorkerEmailCode(t, testEmail, code)
	})

	t.Run("SMSVerification", func(t *testing.T) {
		h.T = t
		sendWorkerSMSCode(t, testPhone)
		code := retrieveLatestWorkerSMSCode(t, testPhone)
		require.NotEmpty(t, code, "Worker SMS verification code should not be empty")
		verifyWorkerSMSCode(t, testPhone, code)
	})
}

// -----------------------------------------------------------------------------
// NEW NEGATIVE-PATH TESTS
// -----------------------------------------------------------------------------

func TestInvalidEmailAndPhoneRequests(t *testing.T) {
	h.T = t
	invalidEmails := []string{
		"",
		"plainaddress",
		"@nouser.com",
		"user@domain..com",
		"user@invalid.",
		"user@.invalid.com",
	}
	invalidPhones := []string{
		"",
		"123",
		"+12abc4567",
		"+",
		"555-555-555",
	}

	// ------------- Email endpoints -------------
	t.Run("PM Email – Invalid Payloads", func(t *testing.T) {
		h.T = t
		for _, email := range invalidEmails {
			sendPMEmailCodeExpectFailure(t, email)
		}
	})
	t.Run("Worker Email – Invalid Payloads", func(t *testing.T) {
		h.T = t
		for _, email := range invalidEmails {
			sendWorkerEmailCodeExpectFailure(t, email)
		}
	})

	// ------------- SMS endpoints -------------
	t.Run("PM SMS – Invalid Payloads", func(t *testing.T) {
		h.T = t
		for _, ph := range invalidPhones {
			sendPMSMSCodeExpectFailure(t, ph)
		}
	})
	t.Run("Worker SMS – Invalid Payloads", func(t *testing.T) {
		h.T = t
		for _, ph := range invalidPhones {
			sendWorkerSMSCodeExpectFailure(t, ph)
		}
	})
}
