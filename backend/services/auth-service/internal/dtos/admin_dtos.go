// meta-service/services/auth-service/internal/dtos/admin_dtos.go
package dtos

import (
	shared_dtos "github.com/poofware/mono-repo/backend/shared/go-dtos"
)

// LoginAdminRequest is the request body for the admin login endpoint.
type LoginAdminRequest struct {
	Username string `json:"username" validate:"required"`
	Password string `json:"password" validate:"required"`
	TOTPCode string `json:"totp_code" validate:"required,len=6,numeric"`
}

// LoginAdminResponse is the response body for a successful admin login.
// Tokens are handled via cookies, so this only returns the user object.
type LoginAdminResponse struct {
	Admin shared_dtos.Admin `json:"admin"`
}