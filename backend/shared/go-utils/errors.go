// backend/shared/go-utils/errors.go
package utils

import (
	"errors"
	"net/http"
)

// Domain-level errors used by the service layer to provide
// fine-grained failure reasons.
var (
	ErrInvalidEmail              = errors.New("invalid_email")
	ErrInvalidPhone              = errors.New("invalid_phone")
	ErrEmailExists               = errors.New("email_exists")
	ErrPhoneExists               = errors.New("phone_exists")
	ErrPhoneNotVerified          = errors.New("phone_not_verified")
	ErrEmailNotVerified          = errors.New("email_not_verified")
	ErrKeyNotFoundForAssertion   = errors.New("key_not_found_for_assertion")
	ErrInvalidTenantToken        = errors.New("invalid_tenant_token")

	// For concurrency conflicts
	ErrRowVersionConflict = errors.New("row_version_conflict")

	// For rate limiting
	ErrRateLimitExceeded = errors.New("rate_limit_exceeded")

	// NEW: For external service failures (e.g., Twilio, SendGrid)
	ErrExternalServiceFailure = errors.New("external_service_failure")

	// Additional examples
	ErrNoRowsUpdated = errors.New("no_rows_updated")
)

// NEW: AppError for structured error handling from services to controllers.
type AppError struct {
	StatusCode int
	Code       string
	Message    string
	Err        error
}

func (e *AppError) Error() string {
	if e.Err != nil {
		return e.Err.Error()
	}
	return e.Message
}

// NEW: HandleAppError centralizes responding to AppErrors.
func HandleAppError(w http.ResponseWriter, err error) {
	var appErr *AppError
	if errors.As(err, &appErr) {
		RespondErrorWithCode(w, appErr.StatusCode, appErr.Code, appErr.Message, nil, appErr.Err)
	} else {
		// Fallback for unexpected error types
		RespondErrorWithCode(w, http.StatusInternalServerError, ErrCodeInternal, "An unexpected error occurred", nil, err)
	}
}