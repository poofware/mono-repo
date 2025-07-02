package dtos

// If you have a request body for TOTP generation, define it here. 
// Currently, your endpoint does not require a request body, so you could keep it empty or omit it entirely.

type GenerateTOTPSecretRequest struct {
    // e.g. custom fields if needed
}

type GenerateTOTPSecretResponse struct {
    Secret string `json:"secret"`
}

