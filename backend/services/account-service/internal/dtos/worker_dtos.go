package dtos

// SubmitPersonalInfoRequest is the DTO for the dedicated endpoint to submit
// a worker's personal and vehicle information during onboarding.
// All fields are required except for apt_suite.
type SubmitPersonalInfoRequest struct {
	StreetAddress string  `json:"street_address" validate:"required,min=3,max=255"`
	AptSuite      *string `json:"apt_suite,omitempty" validate:"omitempty,max=50"`
	City          string  `json:"city" validate:"required,min=2,max=100"`
	State         string  `json:"state" validate:"required,min=2,max=14"`
	ZipCode       string  `json:"zip_code" validate:"required,min=5,max=10"`
	VehicleYear   int     `json:"vehicle_year" validate:"required,min=1960"`
	VehicleMake   string  `json:"vehicle_make" validate:"required,min=2,max=100"`
	VehicleModel  string  `json:"vehicle_model" validate:"required,min=1,max=100"`
}
