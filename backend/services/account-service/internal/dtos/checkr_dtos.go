package dtos

// ------------------------------------------------------------------
// Invitation
// ------------------------------------------------------------------
type CheckrInvitationResponse struct {
	Message       string `json:"message"`
	InvitationURL string `json:"invitation_url"`
}

// ------------------------------------------------------------------
// Flow status (complete / incomplete)
// ------------------------------------------------------------------
type CheckrFlowStatus string

const (
	CheckrFlowStatusIncomplete CheckrFlowStatus = "incomplete"
	CheckrFlowStatusComplete   CheckrFlowStatus = "complete"
)

type CheckrStatusResponse struct {
	Status CheckrFlowStatus `json:"status"`
}

// ------------------------------------------------------------------
// Report ETA  (timezone via query‑param, no request DTO required)
// ------------------------------------------------------------------
type CheckrETAResponse struct {
	ReportETA *string `json:"report_eta"`
}

// ------------------------------------------------------------------
// NEW: Session Token for Web SDK Embed
// ------------------------------------------------------------------
type CheckrSessionTokenResponse struct {
	Token string `json:"token"`
}
