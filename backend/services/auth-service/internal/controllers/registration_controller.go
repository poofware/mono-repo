package controllers

import (
    "net/http"

    "github.com/poofware/mono-repo/backend/services/auth-service/internal/dtos"
    "github.com/poofware/mono-repo/backend/services/auth-service/internal/services"
    "github.com/poofware/mono-repo/backend/shared/go-utils"
)

// RegistrationController handles registration-related endpoints (e.g., TOTP).
type RegistrationController struct {
    totpService *services.TOTPService
}

// NewRegistrationController constructs a RegistrationController,
// injecting the TOTPService to handle TOTP logic.
func NewRegistrationController(totpService *services.TOTPService) *RegistrationController {
    return &RegistrationController{totpService: totpService}
}

// GenerateTOTPSecret is an HTTP handler that returns a newly generated TOTP secret and QR code.
func (c *RegistrationController) GenerateTOTPSecret(w http.ResponseWriter, r *http.Request) {
    // 1) Invoke service to get TOTP secret and QR code
    secret, err := c.totpService.GenerateTOTPSecret()
    if err != nil {
        utils.RespondErrorWithCode(
            w,
            http.StatusInternalServerError,
            utils.ErrCodeInternal,
            "Failed to generate TOTP data",
            err,
        )
        return
    }

    // 2) Construct the response DTO
    resp := dtos.GenerateTOTPSecretResponse{
        Secret: secret,
    }

    // 3) Return JSON response
    utils.RespondWithJSON(w, http.StatusOK, resp)
}

