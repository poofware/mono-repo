package dtos

type HealthCheckResponse struct {
	Status string `json:"status"`
}

// NEW: For webhook check endpoint
type WebhookCheckResponse struct {
	Message string `json:"message"`
}
