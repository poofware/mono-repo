// meta-service/services/account-service/internal/dtos/property_dtos.go
package dtos

import (
	"time"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/shared/go-models"
)

/*──────────────────────────────────────────────────────────
  Building DTO – now nests its units
──────────────────────────────────────────────────────────*/
type Building struct {
	ID           uuid.UUID          `json:"id"`
	BuildingName string             `json:"building_name,omitempty"`
	Address      *string            `json:"address,omitempty"`
	Latitude     float64            `json:"latitude,omitempty"`
	Longitude    float64            `json:"longitude,omitempty"`
	Units        []*models.Unit     `json:"units,omitempty"`
}

// helper
func NewBuildingFromModel(
	b *models.PropertyBuilding,
	u []*models.Unit,
) Building {
	return Building{
		ID:           b.ID,
		BuildingName: b.BuildingName,
		Address:      b.Address,
		Latitude:     b.Latitude,
		Longitude:    b.Longitude,
		Units:        u,
	}
}

/*──────────────────────────────────────────────────────────
  Property DTO – units are now nested inside buildings
──────────────────────────────────────────────────────────*/
type Property struct {
	ID           uuid.UUID `json:"id"`
	PropertyName string    `json:"property_name"`
	Address      string    `json:"address"`
	City         string    `json:"city"`
	State        string    `json:"state"`
	ZipCode      string    `json:"zip_code"`
	Buildings    []Building          `json:"buildings,omitempty"`
	Dumpsters    []*models.Dumpster  `json:"dumpsters,omitempty"`
	CreatedAt    time.Time           `json:"created_at"`
}

func NewPropertyFromModel(
	p *models.Property,
	b []Building,
	d []*models.Dumpster,
) Property {
	return Property{
		ID:           p.ID,
		PropertyName: p.PropertyName,
		Address:      p.Address,
		City:         p.City,
		State:        p.State,
		ZipCode:      p.ZipCode,
		Buildings:    b,
		Dumpsters:    d,
		CreatedAt:    p.CreatedAt,
	}
}

