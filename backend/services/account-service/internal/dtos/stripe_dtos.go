package dtos

// StripeConnectFlowURLResponse is returned by ConnectFlowURLHandler
type StripeConnectFlowURLResponse struct {
	ConnectFlowURL string `json:"connect_flow_url"`
}

// StripeIdentityFlowURLResponse is returned by IdentityFlowURLHandler
type StripeIdentityFlowURLResponse struct {
	IdentityFlowURL string `json:"identity_flow_url"`
}

type StripeFlowStatus string

const (
	StripeFlowStatusIncomplete StripeFlowStatus = "incomplete"
	StripeFlowStatusComplete   StripeFlowStatus = "complete"
)

// StripeFlowStatusResponse is returned by ConnectFlowStatusHandler
// and IdentityFlowStatusHandler
type StripeFlowStatusResponse struct {
	Status StripeFlowStatus `json:"status"`
}

// WebhookCheckResponse is returned by WebhookCheckHandler
type WebhookCheckResponse struct {
	Message string `json:"message"`
}
