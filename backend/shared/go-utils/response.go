// backend/shared/go-utils/response.go
package utils

import (
	"encoding/json"
	"net/http"

	"github.com/sirupsen/logrus"
)

const (
	ErrCodeInvalidPayload            = "invalid_payload"
	ErrCodeValidation                = "validation_error"
	ErrCodeUnauthorized              = "unauthorized"
	ErrCodeTokenExpired              = "token_expired"
	ErrCodeInvalidCredentials        = "invalid_credentials"
	ErrCodeInvalidTotp               = "invalid_totp"
	ErrCodeLockedAccount             = "locked_account"
	ErrCodeIPMismatch                = "ip_mismatch"
	ErrCodeInternal                  = "internal_server_error"
	ErrCodeNotFound                  = "not_found"
	ErrCodeConflict                  = "conflict"
	ErrCodePhoneNotVerified          = "phone_not_verified"
        ErrCodeEmailNotVerified          = "email_not_verified"
        ErrCodeRowVersionConflict        = "row_version_conflict"
        ErrCodeRateLimitExceeded         = "rate_limit_exceeded"
        ErrCodeLocationInaccurate        = "location_inaccurate"
        ErrCodeKeyNotFoundForAssertion = "key_not_found_for_assertion"
        ErrCodeInvalidTenantToken        = "invalid_tenant_token"
        ErrCodeExternalServiceFailure    = "external_service_failure" // NEW
)

// ErrorResponse is now extended with an optional `Details` field
// to carry additional info (like the updated job instance).
type ErrorResponse struct {
	Code    string      `json:"code"`
	Message string      `json:"message"`
	Details any         `json:"details,omitempty"`
}

// RespondErrorWithCode builds a JSON error response with a standard
// code and message. The optional `details` is included if non-nil.
func RespondErrorWithCode(
	w http.ResponseWriter,
	status int,
	errorCode string,
	publicMessage string,
	details any,
	devErrs ...error,
) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)

	errBody := ErrorResponse{
		Code:    errorCode,
		Message: publicMessage,
	}
	if details != nil {
		errBody.Details = details
	}
	_ = json.NewEncoder(w).Encode(errBody)

	// devErr is optional; only handle if provided
	if len(devErrs) > 0 && devErrs[0] != nil {
		Logger.WithFields(logrus.Fields{
			"status": status,
			"error":  devErrs[0].Error(),
		}).Error(publicMessage)
	} else {
		Logger.WithFields(logrus.Fields{
			"status": status,
		}).Error(publicMessage)
	}
}

// RespondWithJSON for successful cases
func RespondWithJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
