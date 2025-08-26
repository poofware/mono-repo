package dtos

import (
	"time"

	"github.com/poofware/mono-repo/backend/shared/go-models"
)

type PropertyManager struct {
	ID              string                     `json:"id"` // NEW
	Email           string                     `json:"email"`
	PhoneNumber     *string                    `json:"phone_number,omitempty"`
	BusinessName    string                     `json:"business_name"`
	BusinessAddress string                     `json:"business_address"`
	City            string                     `json:"city"`
	State           string                     `json:"state"`
	ZipCode         string                     `json:"zip_code"`
	AccountStatus   models.PMAccountStatusType `json:"account_status"`
	SetupProgress   models.SetupProgressType   `json:"setup_progress"`
	CreatedAt       time.Time                  `json:"created_at"`
	UpdatedAt       time.Time                  `json:"updated_at"`
}

func NewPMFromModel(pm models.PropertyManager) PropertyManager {
	return PropertyManager{
		ID:              pm.ID.String(), // NEW
		Email:           pm.Email,
		PhoneNumber:     pm.PhoneNumber,
		BusinessName:    pm.BusinessName,
		BusinessAddress: pm.BusinessAddress,
		City:            pm.City,
		State:           pm.State,
		ZipCode:         pm.ZipCode,
		AccountStatus:   pm.AccountStatus,
		SetupProgress:   pm.SetupProgress,
		CreatedAt:       pm.CreatedAt,
		UpdatedAt:       pm.UpdatedAt,
	}
}
