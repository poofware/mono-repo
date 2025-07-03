// go-models/unit.go
package models

import (
	"time"

	"github.com/google/uuid"
)

// Unit represents a tenant-addressable space inside a specific building
// that lives on a property.
type Unit struct {
	ID          uuid.UUID  `json:"id"`
	PropertyID  uuid.UUID  `json:"property_id"`
	BuildingID  uuid.UUID  `json:"building_id"`
	UnitNumber  string     `json:"unit_number"`
	TenantToken string    `json:"tenant_token"`
	CreatedAt   time.Time  `json:"created_at"`
}

