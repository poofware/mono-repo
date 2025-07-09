package models

import (
    "time"
    "github.com/google/uuid"
)

type PropertyBuilding struct {
    ID          uuid.UUID         `json:"id"`
    PropertyID  uuid.UUID         `json:"property_id"`
    BuildingName string            `json:"building_name,omitempty"`
    Address     *string            `json:"address"`
    Latitude    float64           `json:"latitude,omitempty"`
    Longitude   float64           `json:"longitude,omitempty"`
    DeletedAt    *time.Time `json:"deleted_at,omitempty"` // NEW
}
