// backend/shared/go-utils/errors.go
package utils

import "errors"

// Domain-level errors used by the service layer to provide
// fine-grained failure reasons.
var (
	ErrInvalidEmail              = errors.New("invalid_email")
	ErrInvalidPhone              = errors.New("invalid_phone")
	ErrEmailExists               = errors.New("email_exists")
	ErrPhoneExists               = errors.New("phone_exists")
        ErrPhoneNotVerified          = errors.New("phone_not_verified")
        ErrEmailNotVerified          = errors.New("email_not_verified")
        ErrKeyNotFoundForAssertion = errors.New("key_not_found_for_assertion")
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
