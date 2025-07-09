package models

import (
    "time"
    "github.com/google/uuid"
)

type PropertyBuilding struct {
    Versioned
    ID          uuid.UUID         `json:"id"`
    PropertyID  uuid.UUID         `json:"property_id"`
    BuildingName string            `json:"building_name,omitempty"`
    Address     *string            `json:"address"`
    Latitude    float64           `json:"latitude,omitempty"`
    Longitude   float64           `json:"longitude,omitempty"`
    CreatedAt      time.Time `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
    DeletedAt    *time.Time `json:"deleted_at,omitempty"` // NEW
}

func (b *PropertyBuilding) GetID() string { return b.ID.String() }
