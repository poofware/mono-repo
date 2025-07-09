// backend/services/account-service/internal/dtos/admin_req_resp_dtos.go
package dtos

import (
	"github.com/google/uuid"
	"github.com/poofware/go-models"
	shared_dtos "github.com/poofware/go-dtos"
)

// Generic request for soft-deleting an entity.
type DeleteRequest struct {
	ID uuid.UUID `json:"id" validate:"required"`
}

// Generic confirmation response.
type ConfirmationResponse struct {
	Message string `json:"message"`
	ID      string `json:"id"`
}

// ----- Property Manager DTOs -----
type CreatePropertyManagerRequest struct {
	Email           string  `json:"email" validate:"required,email"`
	PhoneNumber     *string `json:"phone_number,omitempty" validate:"omitempty,e164"`
	BusinessName    string  `json:"business_name" validate:"required,min=2"`
	BusinessAddress string  `json:"business_address" validate:"required,min=5"`
	City            string  `json:"city" validate:"required,min=2"`
	State           string  `json:"state" validate:"required,len=2"`
	ZipCode         string  `json:"zip_code" validate:"required,min=5,max=10"`
}

type UpdatePropertyManagerRequest struct {
	ID              uuid.UUID                 `json:"id" validate:"required"`
	Email           *string                   `json:"email,omitempty" validate:"omitempty,email"`
	PhoneNumber     *string                   `json:"phone_number,omitempty" validate:"omitempty,e164"`
	BusinessName    *string                   `json:"business_name,omitempty" validate:"omitempty,min=2"`
	BusinessAddress *string                   `json:"business_address,omitempty" validate:"omitempty,min=5"`
	City            *string                   `json:"city,omitempty" validate:"omitempty,min=2"`
	State           *string                   `json:"state,omitempty" validate:"omitempty,len=2"`
	ZipCode         *string                   `json:"zip_code,omitempty" validate:"omitempty,min=5,max=10"`
	AccountStatus   *models.AccountStatusType `json:"account_status,omitempty"`
	SetupProgress   *models.SetupProgressType `json:"setup_progress,omitempty"`
}

type SearchPropertyManagersRequest struct {
	Filters  map[string]any `json:"filters"`
	Page     int            `json:"page"`
	PageSize int            `json:"page_size"`
}

type PagedPropertyManagersResponse struct {
	Data     []shared_dtos.PropertyManager `json:"data"`
	Total    int                           `json:"total"`
	Page     int                           `json:"page"`
	PageSize int                           `json:"page_size"`
}

// ----- Property DTOs -----

type CreatePropertyRequest struct {
	ManagerID    uuid.UUID `json:"manager_id" validate:"required"`
	PropertyName string    `json:"property_name" validate:"required,min=2"`
	Address      string    `json:"address" validate:"required,min=5"`
	City         string    `json:"city" validate:"required,min=2"`
	State        string    `json:"state" validate:"required,len=2"`
	ZipCode      string    `json:"zip_code" validate:"required,min=5,max=10"`
	TimeZone     string    `json:"time_zone" validate:"required"`
	Latitude     float64   `json:"latitude" validate:"required,latitude"`
	Longitude    float64   `json:"longitude" validate:"required,longitude"`
}

type UpdatePropertyRequest struct {
	ID           uuid.UUID `json:"id" validate:"required"`
	PropertyName *string   `json:"property_name,omitempty" validate:"omitempty,min=2"`
	Address      *string   `json:"address,omitempty" validate:"omitempty,min=5"`
	City         *string   `json:"city,omitempty" validate:"omitempty,min=2"`
	State        *string   `json:"state,omitempty" validate:"omitempty,len=2"`
	ZipCode      *string   `json:"zip_code,omitempty" validate:"omitempty,min=5,max=10"`
	TimeZone     *string   `json:"time_zone,omitempty" validate:"omitempty"`
	Latitude     *float64  `json:"latitude,omitempty" validate:"omitempty,latitude"`
	Longitude    *float64  `json:"longitude,omitempty" validate:"omitempty,longitude"`
}

// ----- Building DTOs -----

type CreateBuildingRequest struct {
	PropertyID   uuid.UUID `json:"property_id" validate:"required"`
	BuildingName string    `json:"building_name,omitempty"`
	Address      *string   `json:"address,omitempty"`
	Latitude     float64   `json:"latitude,omitempty"`
	Longitude    float64   `json:"longitude,omitempty"`
}

type UpdateBuildingRequest struct {
	ID           uuid.UUID `json:"id" validate:"required"`
	BuildingName *string   `json:"building_name,omitempty" validate:"omitempty"`
	Address      *string   `json:"address,omitempty"`
	Latitude     *float64  `json:"latitude,omitempty" validate:"omitempty,latitude"`
	Longitude    *float64  `json:"longitude,omitempty" validate:"omitempty,longitude"`
}

// ----- Unit DTOs -----

type CreateUnitRequest struct {
	PropertyID uuid.UUID `json:"property_id" validate:"required"`
	BuildingID uuid.UUID `json:"building_id" validate:"required"`
	UnitNumber string    `json:"unit_number" validate:"required"`
}

type UpdateUnitRequest struct {
	ID         uuid.UUID `json:"id" validate:"required"`
	UnitNumber *string   `json:"unit_number,omitempty" validate:"omitempty,min=1"`
}

// ----- Dumpster DTOs -----

type CreateDumpsterRequest struct {
	PropertyID     uuid.UUID `json:"property_id" validate:"required"`
	DumpsterNumber string    `json:"dumpster_number" validate:"required"`
	Latitude       float64   `json:"latitude,omitempty"`
	Longitude      float64   `json:"longitude,omitempty"`
}

type UpdateDumpsterRequest struct {
	ID             uuid.UUID `json:"id" validate:"required"`
	DumpsterNumber *string   `json:"dumpster_number,omitempty" validate:"omitempty,min=1"`
	Latitude       *float64  `json:"latitude,omitempty" validate:"omitempty,latitude"`
	Longitude      *float64  `json:"longitude,omitempty" validate:"omitempty,longitude"`
}

// ----- Snapshot DTOs -----

type SnapshotRequest struct {
	ManagerID uuid.UUID `json:"manager_id" validate:"required"`
}

type PropertyManagerSnapshotResponse struct {
	shared_dtos.PropertyManager
	Properties []PropertySnapshot `json:"properties"`
}

type PropertySnapshot struct {
	Property
	JobDefinitions []*models.JobDefinition `json:"job_definitions"`
}