package services

import (
    "github.com/poofware/mono-repo/backend/services/auth-service/internal/config"
    auth_utils "github.com/poofware/mono-repo/backend/services/auth-service/internal/utils"
)

// TOTPService defines methods for TOTP-related functionality.
type TOTPService struct {
    cfg *config.Config
}

// NewTOTPService constructs and returns a new TOTPService with the given config.
func NewTOTPService(cfg *config.Config) *TOTPService {
    return &TOTPService{cfg: cfg}
}

// GenerateTOTPSecretAndQRCode generates a TOTP secret (and corresponding QR code)
// using data from config (e.g., OrganizationName) to build the account name.
func (s *TOTPService) GenerateTOTPSecret() (string, error) {
    appName := s.cfg.OrganizationName
    accountName := appName + " User"

    // 1) Generate TOTP Secret
    secret, err := auth_utils.GenerateTOTPSecret(appName, accountName)
    if err != nil {
        return "",  err
    }


    return secret, nil
}

