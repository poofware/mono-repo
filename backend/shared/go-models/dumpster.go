package models

import (
  "time"
  "github.com/google/uuid"
)

type Dumpster struct {
    Versioned
    ID         uuid.UUID `json:"id"`
    DumpsterNumber string    `json:"dumpster_number"`
    PropertyID uuid.UUID `json:"property_id"`
    Latitude   float64   `json:"latitude"`
    Longitude  float64   `json:"longitude"`
    CreatedAt      time.Time `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
	DeletedAt      *time.Time `json:"deleted_at,omitempty"` // NEW
}

func (d *Dumpster) GetID() string { return d.ID.String() }