package dtos

import (
	"time"

	"github.com/poofware/go-models"
)

// Existing Worker DTO for GET endpoints
type Worker struct {
	ID                  string                   `json:"id"`
	Email               string                   `json:"email"`
	PhoneNumber         string                   `json:"phone_number"`
	FirstName           string                   `json:"first_name"`
	LastName            string                   `json:"last_name"`
	StreetAddress       string                   `json:"street_address"`
	AptSuite            *string                  `json:"apt_suite,omitempty"`
	City                string                   `json:"city"`
	State               string                   `json:"state"`
	ZipCode             string                   `json:"zip_code"`
	VehicleYear         int                      `json:"vehicle_year"`
	VehicleMake         string                   `json:"vehicle_make"`
	VehicleModel        string                   `json:"vehicle_model"`
	AccountStatus       models.AccountStatusType `json:"account_status"`
	SetupProgress       models.SetupProgressType `json:"setup_progress"`
	CheckrCandidateID   *string                  `json:"checkr_candidate_id,omitempty"`
	CheckrReportOutcome models.ReportOutcomeType `json:"checkr_report_outcome,omitempty"`
	CheckrReportETA     *time.Time               `json:"checkr_report_eta,omitempty"`
	OnWaitlist          bool                     `json:"on_waitlist"`
}

func NewWorkerFromModel(worker models.Worker) Worker {
	return Worker{
		ID:                  worker.ID.String(),
		Email:               worker.Email,
		PhoneNumber:         worker.PhoneNumber,
		FirstName:           worker.FirstName,
		LastName:            worker.LastName,
		StreetAddress:       worker.StreetAddress,
		AptSuite:            worker.AptSuite,
		City:                worker.City,
		State:               worker.State,
		ZipCode:             worker.ZipCode,
		VehicleYear:         worker.VehicleYear,
		VehicleMake:         worker.VehicleMake,
		VehicleModel:        worker.VehicleModel,
		AccountStatus:       worker.AccountStatus,
		SetupProgress:       worker.SetupProgress,
		CheckrCandidateID:   worker.CheckrCandidateID,
		CheckrReportOutcome: worker.CheckrReportOutcome,
		CheckrReportETA:     worker.CheckrReportETA,
		OnWaitlist:          worker.OnWaitlist,
	}
}

// ----------------------------------------------------------------------
// WorkerPatchRequest
//   - All fields as pointers, so that "null" or omission => no update
//
// ----------------------------------------------------------------------
type WorkerPatchRequest struct {
	Email         *string `json:"email,omitempty"`
	PhoneNumber   *string `json:"phone_number,omitempty"`
	FirstName     *string `json:"first_name,omitempty"`
	LastName      *string `json:"last_name,omitempty"`
	StreetAddress *string `json:"street_address,omitempty"`
	AptSuite      *string `json:"apt_suite,omitempty"`
	City          *string `json:"city,omitempty"`
	State         *string `json:"state,omitempty"`
	ZipCode       *string `json:"zip_code,omitempty"`
	VehicleYear   *int    `json:"vehicle_year,omitempty"`
	VehicleMake   *string `json:"vehicle_make,omitempty"`
	VehicleModel  *string `json:"vehicle_model,omitempty"`
}
