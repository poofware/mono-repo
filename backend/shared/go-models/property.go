package models

import (
    "time"
    "github.com/google/uuid"
)

type Property struct {
    Versioned
    ID           uuid.UUID         `json:"id"`
    ManagerID    uuid.UUID         `json:"manager_id"`
    PropertyName string            `json:"property_name"`
    Address      string            `json:"address"`
    City         string            `json:"city"`
    State        string            `json:"state"`
    ZipCode      string            `json:"zip_code"`
    TimeZone      string            `json:"timezone"`
    Latitude     float64          `json:"latitude"`
    Longitude    float64          `json:"longitude"`
    CreatedAt    time.Time         `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
    DeletedAt    *time.Time `json:"deleted_at,omitempty"`
}

func (p *Property) GetID() string { return p.ID.String() }