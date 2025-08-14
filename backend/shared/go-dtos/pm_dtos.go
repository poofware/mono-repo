package dtos

import (
	"github.com/poofware/mono-repo/backend/shared/go-models"
)

type PropertyManager struct {
	Email         string            `json:"email"`
	PhoneNumber   *string           `json:"phone_number,omitempty"`
	BusinessName  string            `json:"business_name"`
	BusinessAddress string          `json:"business_address"`
	City          string            `json:"city"`
	State         string            `json:"state"`
	ZipCode       string            `json:"zip_code"`
	AccountStatus models.AccountStatusType `json:"account_status"`
	SetupProgress models.SetupProgressType `json:"setup_progress"`
}

func NewPMFromModel(worker models.PropertyManager) PropertyManager {
	return PropertyManager{
		Email:         worker.Email,
		PhoneNumber:   worker.PhoneNumber,
		BusinessName:  worker.BusinessName,
		BusinessAddress: worker.BusinessAddress,
		City:          worker.City,
		State:         worker.State,
		ZipCode:       worker.ZipCode,
		AccountStatus: worker.AccountStatus,
		SetupProgress: worker.SetupProgress,
	}
}

