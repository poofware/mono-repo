// go-models/unit.go
package models

import (
	"time"

	"github.com/google/uuid"
)

// Unit represents a tenant-addressable space inside a specific building
// that lives on a property.
type Unit struct {
	Versioned
	ID          uuid.UUID  `json:"id"`
	PropertyID  uuid.UUID  `json:"property_id"`
	BuildingID  uuid.UUID  `json:"building_id"`
	FloorID     *uuid.UUID `json:"floor_id,omitempty"`
	UnitNumber  string     `json:"unit_number"`
	TenantToken string     `json:"tenant_token"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
	DeletedAt   *time.Time `json:"deleted_at,omitempty"`
}

func (u *Unit) GetID() string { return u.ID.String() }
