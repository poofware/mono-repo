package dtos

import "github.com/poofware/go-models"

// AdminDTO is the data transfer object for an admin user,
// omitting sensitive fields like TOTP secrets and password hashes.
type Admin struct {
	ID            string                  `json:"id"`
	Username      string                  `json:"username"`
	AccountStatus models.AccountStatusType `json:"account_status"`
	SetupProgress models.SetupProgressType `json:"setup_progress"`
}

// NewAdminFromModel creates an AdminDTO from a models.Admin.
func NewAdminFromModel(admin models.Admin) Admin {
	return Admin{
		ID:            admin.ID.String(),
		Username:      admin.Username,
		AccountStatus: admin.AccountStatus,
		SetupProgress: admin.SetupProgress,
	}
}