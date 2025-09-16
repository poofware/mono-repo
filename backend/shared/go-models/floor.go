package models

import (
	"time"

	"github.com/google/uuid"
)

// Floor represents a level within a specific building on a property.
type Floor struct {
	Versioned
	ID         uuid.UUID  `json:"id"`
	PropertyID uuid.UUID  `json:"property_id"`
	BuildingID uuid.UUID  `json:"building_id"`
	Number     int16      `json:"number"`
	CreatedAt  time.Time  `json:"created_at"`
	UpdatedAt  time.Time  `json:"updated_at"`
	DeletedAt  *time.Time `json:"deleted_at,omitempty"`
}

func (f *Floor) GetID() string { return f.ID.String() }
