package services

import (
	"context"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/services/account-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

type PMService struct {
	pmRepo repositories.PropertyManagerRepository
	prop   repositories.PropertyRepository
	bldg   repositories.PropertyBuildingRepository
	floor  repositories.FloorRepository
	unit   repositories.UnitRepository
	dump   repositories.DumpsterRepository
}

func NewPMService(pmRepo repositories.PropertyManagerRepository, prop repositories.PropertyRepository, bldg repositories.PropertyBuildingRepository, floor repositories.FloorRepository, unit repositories.UnitRepository, dump repositories.DumpsterRepository) *PMService {
	return &PMService{pmRepo, prop, bldg, floor, unit, dump}
}

// GetPMByID retrieves the pm from the DB.
func (s *PMService) GetPMByID(ctx context.Context, userID string) (*models.PropertyManager, error) {
	id, err := uuid.Parse(userID)
	if err != nil {
		return nil, err
	}
	pm, wErr := s.pmRepo.GetByID(ctx, id)
	if wErr != nil {
		return nil, wErr
	}
	return pm, nil
}

func (s *PMService) ListProperties(
	ctx context.Context,
	pmID uuid.UUID,
) ([]dtos.Property, error) {
	props, err := s.prop.ListByManagerID(ctx, pmID)
	if err != nil {
		return nil, err
	}

	out := make([]dtos.Property, 0, len(props))

	for _, p := range props {
		// (1) raw data
		buildings, err := s.bldg.ListByPropertyID(ctx, p.ID)
		if err != nil {
			utils.Logger.WithError(err).Error("list buildings")
			return nil, err
		}
		allUnits, err := s.unit.ListByPropertyID(ctx, p.ID)
		if err != nil {
			utils.Logger.WithError(err).Error("list units")
			return nil, err
		}
		dumpsters, err := s.dump.ListByPropertyID(ctx, p.ID)
		if err != nil {
			utils.Logger.WithError(err).Error("list dumpsters")
			return nil, err
		}

		// (2) group units → buildingID
		unitMap := make(map[uuid.UUID][]*models.Unit, len(buildings))
		for _, u := range allUnits {
			if u.BuildingID == uuid.Nil {
				continue // should never happen, but keeps us safe
			}
			unitMap[u.BuildingID] = append(unitMap[u.BuildingID], u)
		}

		// (3) build DTOs
		bldgDTOs := make([]dtos.Building, 0, len(buildings))
		for _, b := range buildings {
			floors, _ := s.floor.ListByBuildingID(ctx, b.ID)
			bldgDTOs = append(bldgDTOs,
				dtos.NewBuildingFromModel(b, floors, unitMap[b.ID]))
		}

		out = append(out,
			dtos.NewPropertyFromModel(p, bldgDTOs, dumpsters))
	}

	return out, nil
}
