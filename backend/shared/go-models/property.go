package models

import (
    "time"
    "github.com/google/uuid"
)

type Property struct {
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
    IsDemo       bool              `json:"is_demo"`
    CreatedAt    time.Time         `json:"created_at"`
}
