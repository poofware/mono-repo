// backend/services/account-service/internal/dtos/property_dtos.go

package dtos

import (
	"time"

	"github.com/google/uuid"
	"github.com/poofware/go-models"
)

/*──────────────────────────────────────────────────────────
  Building DTO – now nests its units
──────────────────────────────────────────────────────────*/
type Building struct {
	ID           uuid.UUID          `json:"id"`
	PropertyID   uuid.UUID      `json:"property_id"`
	BuildingName string             `json:"building_name,omitempty"`
	Address      *string            `json:"address,omitempty"`
	Latitude     float64            `json:"latitude,omitempty"`
	Longitude    float64            `json:"longitude,omitempty"`
	Units        []*models.Unit     `json:"units,omitempty"`
	CreatedAt    time.Time      `json:"created_at"`   
	UpdatedAt    time.Time      `json:"updated_at"`
}

// helper
func NewBuildingFromModel(
	b *models.PropertyBuilding,
	u []*models.Unit,
) Building {
	return Building{
		ID:           b.ID,
		PropertyID:   b.PropertyID,
		BuildingName: b.BuildingName,
		Address:      b.Address,
		Latitude:     b.Latitude,
		Longitude:    b.Longitude,
		Units:        u,
		CreatedAt:    b.CreatedAt, 
		UpdatedAt:    b.UpdatedAt,
	}
}

/*──────────────────────────────────────────────────────────
  Property DTO – units are now nested inside buildings
──────────────────────────────────────────────────────────*/
type Property struct {
	ID           uuid.UUID `json:"id"`
	ManagerID    uuid.UUID `json:"manager_id"`
	PropertyName string    `json:"property_name"`
	Address      string    `json:"address"`
	City         string    `json:"city"`
	State        string    `json:"state"`
	ZipCode      string    `json:"zip_code"`
	TimeZone     string    `json:"timezone"`
	Latitude     float64   `json:"latitude"`  
	Longitude    float64   `json:"longitude"`
	Buildings    []Building          `json:"buildings,omitempty"`
	Dumpsters    []*models.Dumpster  `json:"dumpsters,omitempty"`
	CreatedAt    time.Time           `json:"created_at"`
	UpdatedAt    time.Time          `json:"updated_at"`
}

func NewPropertyFromModel(
	p *models.Property,
	b []Building,
	d []*models.Dumpster,
) Property {
	return Property{
		ID:           p.ID,
		ManagerID:    p.ManagerID,
		PropertyName: p.PropertyName,
		Address:      p.Address,
		City:         p.City,
		State:        p.State,
		ZipCode:      p.ZipCode,
		TimeZone:     p.TimeZone, 
		Latitude:     p.Latitude, 
		Longitude:    p.Longitude,
		Buildings:    b,
		Dumpsters:    d,
		CreatedAt:    p.CreatedAt,
		UpdatedAt:    p.UpdatedAt,
	}
}