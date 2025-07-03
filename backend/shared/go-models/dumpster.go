package models

import "github.com/google/uuid"

type Dumpster struct {
    ID         uuid.UUID `json:"id"`
    DumpsterNumber string    `json:"dumpster_number"`
    PropertyID uuid.UUID `json:"property_id"`
    Latitude   float64   `json:"latitude"`
    Longitude  float64   `json:"longitude"`
}
