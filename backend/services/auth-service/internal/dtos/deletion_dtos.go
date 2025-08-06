package dtos

// InitiateDeletionRequest represents the request body for initiating deletion.
type InitiateDeletionRequest struct {
	Email string `json:"email" validate:"required,email"`
}

// InitiateDeletionResponse contains the pending token returned to the client.
type InitiateDeletionResponse struct {
	PendingToken string `json:"pending_token"`
}

// ConfirmDeletionRequest represents the body for confirming a deletion request.
type ConfirmDeletionRequest struct {
	PendingToken string  `json:"pending_token" validate:"required"`
	TOTPCode     *string `json:"totp_code,omitempty"`
	EmailCode    *string `json:"email_code,omitempty"`
	SMSCode      *string `json:"sms_code,omitempty"`
}

// ConfirmDeletionResponse is returned after successful confirmation.
type ConfirmDeletionResponse struct {
	Message string `json:"message"`
}
