// backend/services/account-service/internal/services/admin_service.go
// NEW FILE
package services

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/account-service/internal/dtos"
	"github.com/poofware/go-dtos"
	"github.com/poofware/go-models"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
)

type AdminService struct {
	pmRepo       repositories.PropertyManagerRepository
	propRepo     repositories.PropertyRepository
	bldgRepo     repositories.PropertyBuildingRepository
	unitRepo     repositories.UnitRepository
	dumpsterRepo repositories.DumpsterRepository
	jobDefRepo   repositories.JobDefinitionRepository
	auditRepo    repositories.AdminAuditLogRepository
}

func NewAdminService(
	pmRepo repositories.PropertyManagerRepository,
	propRepo repositories.PropertyRepository,
	bldgRepo repositories.PropertyBuildingRepository,
	unitRepo repositories.UnitRepository,
	dumpsterRepo repositories.DumpsterRepository,
	jobDefRepo repositories.JobDefinitionRepository,
	auditRepo repositories.AdminAuditLogRepository,
) *AdminService {
	return &AdminService{
		pmRepo:       pmRepo,
		propRepo:     propRepo,
		bldgRepo:     bldgRepo,
		unitRepo:     unitRepo,
		dumpsterRepo: dumpsterRepo,
		jobDefRepo:   jobDefRepo,
		auditRepo:    auditRepo,
	}
}

func (s *AdminService) logAudit(ctx context.Context, adminID, targetID uuid.UUID, action models.AuditAction, targetType models.AuditTargetType, details any) {
	var detailsJSON json.RawMessage
	if details != nil {
		detailsJSON, _ = json.Marshal(details)
	}
	_ = s.auditRepo.Create(ctx, &models.AdminAuditLog{
		ID:         uuid.New(),
		AdminID:    adminID,
		Action:     action,
		TargetID:   targetID,
		TargetType: targetType,
		Details:    detailsJSON,
	})
}

// CreatePropertyManager creates a new property manager.
func (s *AdminService) CreatePropertyManager(ctx context.Context, adminID uuid.UUID, req dtos.CreatePropertyManagerRequest) (*go_dtos.PropertyManager, error) {
	existing, _ := s.pmRepo.GetByEmail(ctx, req.Email)
	if existing != nil {
		return nil, &utils.AppError{StatusCode: http.StatusConflict, Code: utils.ErrCodeConflict, Message: "Email already in use"}
	}

	pm := &models.PropertyManager{
		ID:              uuid.New(),
		Email:           req.Email,
		PhoneNumber:     req.PhoneNumber,
		BusinessName:    req.BusinessName,
		BusinessAddress: req.BusinessAddress,
		City:            req.City,
		State:           req.State,
		ZipCode:         req.ZipCode,
		AccountStatus:   models.AccountStatusIncomplete,
		SetupProgress:   models.SetupProgressDone, // Admins create them as 'Done'
	}

	if err := s.pmRepo.Create(ctx, pm); err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to create property manager", Err: err}
	}

	s.logAudit(ctx, adminID, pm.ID, models.AuditCreate, models.TargetPropertyManager, pm)
	dto := go_dtos.NewPMFromModel(*pm)
	return &dto, nil
}

// UpdatePropertyManager updates an existing property manager.
func (s *AdminService) UpdatePropertyManager(ctx context.Context, adminID uuid.UUID, req dtos.UpdatePropertyManagerRequest) (*go_dtos.PropertyManager, error) {
	var updatedPM *models.PropertyManager
	err := s.pmRepo.UpdateWithRetry(ctx, req.ID, func(pm *models.PropertyManager) error {
		if req.Email != nil {
			pm.Email = *req.Email
		}
		if req.PhoneNumber != nil {
			pm.PhoneNumber = req.PhoneNumber
		}
		if req.BusinessName != nil {
			pm.BusinessName = *req.BusinessName
		}
		if req.BusinessAddress != nil {
			pm.BusinessAddress = *req.BusinessAddress
		}
		if req.City != nil {
			pm.City = *req.City
		}
		if req.State != nil {
			pm.State = *req.State
		}
		if req.ZipCode != nil {
			pm.ZipCode = *req.ZipCode
		}
		if req.AccountStatus != nil {
			pm.AccountStatus = *req.AccountStatus
		}
		if req.SetupProgress != nil {
			pm.SetupProgress = *req.SetupProgress
		}
		updatedPM = pm
		return nil
	})

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Property manager not found"}
		}
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to update property manager", Err: err}
	}

	s.logAudit(ctx, adminID, updatedPM.ID, models.AuditUpdate, models.TargetPropertyManager, updatedPM)
	dto := go_dtos.NewPMFromModel(*updatedPM)
	return &dto, nil
}

// SoftDeletePropertyManager marks a property manager as deleted.
func (s *AdminService) SoftDeletePropertyManager(ctx context.Context, adminID, pmID uuid.UUID) error {
	if err := s.pmRepo.SoftDelete(ctx, pmID); err != nil {
		return &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to delete property manager", Err: err}
	}
	s.logAudit(ctx, adminID, pmID, models.AuditDelete, models.TargetPropertyManager, nil)
	return nil
}

// SearchPropertyManagers searches for property managers with pagination.
func (s *AdminService) SearchPropertyManagers(ctx context.Context, req dtos.SearchPropertyManagersRequest) (*dtos.PagedPropertyManagersResponse, error) {
	if req.Page < 1 {
		req.Page = 1
	}
	if req.PageSize < 1 {
		req.PageSize = 10
	}
	offset := (req.Page - 1) * req.PageSize

	pms, total, err := s.pmRepo.Search(ctx, req.Filters, req.PageSize, offset)
	if err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Search failed", Err: err}
	}

	dtos := make([]go_dtos.PropertyManager, len(pms))
	for i, pm := range pms {
		dtos[i] = go_dtos.NewPMFromModel(*pm)
	}

	return &dtos.PagedPropertyManagersResponse{
		Data:     dtos,
		Total:    total,
		Page:     req.Page,
		PageSize: req.PageSize,
	}, nil
}

// GetPropertyManagerSnapshot retrieves the full hierarchy for a property manager.
func (s *AdminService) GetPropertyManagerSnapshot(ctx context.Context, managerID uuid.UUID) (*dtos.PropertyManagerSnapshotResponse, error) {
	pm, err := s.pmRepo.GetByID(ctx, managerID)
	if err != nil || pm == nil {
		return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Property manager not found"}
	}

	pmDTO := go_dtos.NewPMFromModel(*pm)
	snapshot := &dtos.PropertyManagerSnapshotResponse{PropertyManager: pmDTO}

	props, err := s.propRepo.ListByManagerID(ctx, managerID)
	if err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to list properties"}
	}

	for _, p := range props {
		buildings, _ := s.bldgRepo.ListByPropertyID(ctx, p.ID)
		allUnits, _ := s.unitRepo.ListByPropertyID(ctx, p.ID)
		dumpsters, _ := s.dumpsterRepo.ListByPropertyID(ctx, p.ID)
		jobDefs, _ := s.jobDefRepo.ListByPropertyID(ctx, p.ID)

		unitMap := make(map[uuid.UUID][]*models.Unit)
		for _, u := range allUnits {
			unitMap[u.BuildingID] = append(unitMap[u.BuildingID], u)
		}

		bldgDTOs := make([]dtos.Building, len(buildings))
		for i, b := range buildings {
			bldgDTOs[i] = dtos.NewBuildingFromModel(b, unitMap[b.ID])
		}

		propDTO := dtos.NewPropertyFromModel(p, bldgDTOs, dumpsters)
		snapshot.Properties = append(snapshot.Properties, dtos.PropertySnapshot{
			Property:       propDTO,
			JobDefinitions: jobDefs,
		})
	}
	return snapshot, nil
}

// CreateProperty creates a new property for a manager.
func (s *AdminService) CreateProperty(ctx context.Context, adminID uuid.UUID, req dtos.CreatePropertyRequest) (*models.Property, error) {
	// Check if parent manager exists
	_, err := s.pmRepo.GetByID(ctx, req.ManagerID)
	if err != nil || err == pgx.ErrNoRows {
		return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Parent property manager not found"}
	}

	prop := &models.Property{
		ID:           uuid.New(),
		ManagerID:    req.ManagerID,
		PropertyName: req.PropertyName,
		Address:      req.Address,
		City:         req.City,
		State:        req.State,
		ZipCode:      req.ZipCode,
		TimeZone:     req.TimeZone,
		Latitude:     req.Latitude,
		Longitude:    req.Longitude,
	}

	if err := s.propRepo.Create(ctx, prop); err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to create property", Err: err}
	}

	s.logAudit(ctx, adminID, prop.ID, models.AuditCreate, models.TargetProperty, prop)
	return prop, nil
}

// CreateBuilding creates a new building for a property.
func (s *AdminService) CreateBuilding(ctx context.Context, adminID uuid.UUID, req dtos.CreateBuildingRequest) (*models.PropertyBuilding, error) {
	_, err := s.propRepo.GetByID(ctx, req.PropertyID)
	if err != nil || err == pgx.ErrNoRows {
		return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Parent property not found"}
	}

	building := &models.PropertyBuilding{
		ID:           uuid.New(),
		PropertyID:   req.PropertyID,
		BuildingName: req.BuildingName,
		Address:      req.Address,
		Latitude:     req.Latitude,
		Longitude:    req.Longitude,
	}

	if err := s.bldgRepo.Create(ctx, building); err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to create building", Err: err}
	}
	s.logAudit(ctx, adminID, building.ID, models.AuditCreate, models.TargetBuilding, building)
	return building, nil
}

// CreateUnit creates a new unit for a building.
func (s *AdminService) CreateUnit(ctx context.Context, adminID uuid.UUID, req dtos.CreateUnitRequest) (*models.Unit, error) {
	_, err := s.bldgRepo.GetByID(ctx, req.BuildingID)
	if err != nil || err == pgx.ErrNoRows {
		return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Parent building not found"}
	}

	unit := &models.Unit{
		ID:          uuid.New(),
		PropertyID:  req.PropertyID,
		BuildingID:  req.BuildingID,
		UnitNumber:  req.UnitNumber,
		TenantToken: uuid.NewString(),
	}

	if err := s.unitRepo.Create(ctx, unit); err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to create unit", Err: err}
	}
	s.logAudit(ctx, adminID, unit.ID, models.AuditCreate, models.TargetUnit, unit)
	return unit, nil
}

// CreateDumpster creates a new dumpster for a property.
func (s *AdminService) CreateDumpster(ctx context.Context, adminID uuid.UUID, req dtos.CreateDumpsterRequest) (*models.Dumpster, error) {
	_, err := s.propRepo.GetByID(ctx, req.PropertyID)
	if err != nil || err == pgx.ErrNoRows {
		return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Parent property not found"}
	}

	dumpster := &models.Dumpster{
		ID:             uuid.New(),
		PropertyID:     req.PropertyID,
		DumpsterNumber: req.DumpsterNumber,
		Latitude:       req.Latitude,
		Longitude:      req.Longitude,
	}

	if err := s.dumpsterRepo.Create(ctx, dumpster); err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to create dumpster", Err: err}
	}
	s.logAudit(ctx, adminID, dumpster.ID, models.AuditCreate, models.TargetDumpster, dumpster)
	return dumpster, nil
}