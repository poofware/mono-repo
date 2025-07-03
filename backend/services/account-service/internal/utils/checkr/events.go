package checkr

import (
	"time"
	"encoding/json"
)

// WebhookEvent is the top-level event shape for all Checkr webhooks.
type WebhookEvent struct {
	ID         string    `json:"id"`
	Object     string    `json:"object"`
	Type       string    `json:"type"`
	CreatedAt  time.Time `json:"created_at"`
	WebhookURL string    `json:"webhook_url"`
	Data       struct {
		Object json.RawMessage `json:"object"`
	} `json:"data"`
	AccountID string `json:"account_id"`
}

// CandidateWebhookObj is the payload in event.Data.Object for candidate.* events.
type CandidateWebhookObj struct {
	ID                   string    `json:"id"`
	Object               string    `json:"object"`
	URI                  string    `json:"uri"`
	CreatedAt            time.Time `json:"created_at"`
	FirstName            string    `json:"first_name"`
	LastName             string    `json:"last_name"`
	MiddleName           string    `json:"middle_name"`
	Email                string    `json:"email"`
	Dob                  string    `json:"dob"`
	SSN                  string    `json:"ssn"`
	Zipcode              string    `json:"zipcode"`
	Phone                string    `json:"phone"`
	Adjudication         string    `json:"adjudication"`
	ReportIDs            []string  `json:"report_ids"`
	Metadata             map[string]any `json:"metadata"`
	// ... other fields as needed
}

// InvitationWebhookObj is the payload in event.Data.Object for invitation.* events.
type InvitationWebhookObj struct {
	ID            string            `json:"id"`
	Status        string            `json:"status"`
	URI           string            `json:"uri"`
	InvitationURL string            `json:"invitation_url"`
	CompletedAt   *time.Time        `json:"completed_at"`
	DeletedAt     *time.Time        `json:"deleted_at"`
	ExpiresAt     *time.Time        `json:"expires_at"`
	Package       string            `json:"package"`
	Object        string            `json:"object"`
	CreatedAt     time.Time         `json:"created_at"`
	CandidateID   string            `json:"candidate_id"`
	ReportID      *string           `json:"report_id"`
	Metadata map[string]any `json:"metadata,omitempty"`
}

// ReportWebhookObj is the payload in event.Data.Object for report.* events.
type ReportWebhookObj struct {
	ID          string     `json:"id"`
	Object      string     `json:"object"`
	URI         string     `json:"uri"`
	CreatedAt   time.Time  `json:"created_at"`
	ReceivedAt  *time.Time `json:"received_at"`
	Status      ReportStatus     `json:"status"`
	Result      *ReportResult     `json:"result"`
	Package     string     `json:"package"`
	CandidateID string     `json:"candidate_id"`
	IncludesCanceled  bool 		       `json:"includes_canceled"`
	Assessment        *ReportAssessment `json:"assessment"`
	Adjudication      *ReportAdjudication `json:"adjudication"`
	EstimatedCompletionTime *time.Time `json:"estimated_completion_time,omitempty"`
	// fields for different search IDs omitted for brevity
	Metadata map[string]any `json:"metadata,omitempty"`
}

// VerificationWebhookObj is the payload in event.Data.Object for verification.* events (not used much here).
type VerificationWebhookObj struct {
	ID               string     `json:"id"`
	Object           string     `json:"object"`
	URI              string     `json:"uri"`
	CreatedAt        time.Time  `json:"created_at"`
	CompletedAt      *time.Time `json:"completed_at"`
	ProcessedAt      *time.Time `json:"processed_at"`
	VerificationType string     `json:"verification_type"`
	ReportID         string     `json:"report_id"`
	Metadata        map[string]any `json:"metadata,omitempty"`
}

