package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/mono-repo/backend/services/account-service/internal/config"
	internal_dtos "github.com/poofware/mono-repo/backend/services/account-service/internal/dtos"
	shared_dtos "github.com/poofware/mono-repo/backend/shared/go-dtos"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

type AdminService struct {
	cfg          *config.Config
	pmRepo       repositories.PropertyManagerRepository
	propRepo     repositories.PropertyRepository
	bldgRepo     repositories.PropertyBuildingRepository
	floorRepo    repositories.FloorRepository
	unitRepo     repositories.UnitRepository
	dumpsterRepo repositories.DumpsterRepository
	jobDefRepo   repositories.JobDefinitionRepository
	auditRepo    repositories.AdminAuditLogRepository
	adminRepo    repositories.AdminRepository
	agentRepo    repositories.AgentRepository
}

func NewAdminService(
	cfg *config.Config,
	pmRepo repositories.PropertyManagerRepository,
	propRepo repositories.PropertyRepository,
	bldgRepo repositories.PropertyBuildingRepository,
	floorRepo repositories.FloorRepository,
	unitRepo repositories.UnitRepository,
	dumpsterRepo repositories.DumpsterRepository,
	jobDefRepo repositories.JobDefinitionRepository,
	auditRepo repositories.AdminAuditLogRepository,
	adminRepo repositories.AdminRepository,
	agentRepo repositories.AgentRepository,
) *AdminService {
	return &AdminService{
		cfg:          cfg,
		pmRepo:       pmRepo,
		propRepo:     propRepo,
		bldgRepo:     bldgRepo,
		floorRepo:    floorRepo,
		unitRepo:     unitRepo,
		dumpsterRepo: dumpsterRepo,
		jobDefRepo:   jobDefRepo,
		auditRepo:    auditRepo,
		adminRepo:    adminRepo,
		agentRepo:    agentRepo,
	}
}

func (s *AdminService) authorizeAdmin(ctx context.Context, adminID uuid.UUID) error {
	admin, err := s.adminRepo.GetByID(ctx, adminID)
	if err != nil {
		if err == pgx.ErrNoRows {
			// A valid JWT subject should always correspond to a user. If not, it's a forbidden action.
			return &utils.AppError{StatusCode: http.StatusForbidden, Code: utils.ErrCodeUnauthorized, Message: "Access denied"}
		}
		// A different DB error occurred.
		return &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to verify admin status", Err: err}
	}

	// Ensure the admin account is active.
	if admin.AccountStatus != models.AccountStatusActive {
		return &utils.AppError{StatusCode: http.StatusForbidden, Code: utils.ErrCodeUnauthorized, Message: "Admin account is not active"}
	}

	return nil
}

func (s *AdminService) logAudit(ctx context.Context, adminID, targetID uuid.UUID, action models.AuditAction, targetType models.AuditTargetType, details any) {
	logEntry := &models.AdminAuditLog{
		ID:         uuid.New(),
		AdminID:    adminID,
		Action:     action,
		TargetID:   targetID,
		TargetType: targetType,
	}

	if details != nil {
		marshalled, _ := json.Marshal(details)
		raw := json.RawMessage(marshalled)
		logEntry.Details = &raw
	}

	_ = s.auditRepo.Create(ctx, logEntry)
}

// CreatePropertyManager creates a new property manager.
// CreatePropertyManager creates a new property manager.
func (s *AdminService) CreatePropertyManager(ctx context.Context, adminID uuid.UUID, req internal_dtos.CreatePropertyManagerRequest) (*shared_dtos.PropertyManager, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}
	// --- MODIFICATION START ---
	// Add diagnostic logging and proper error handling for the existence check.
	existing, err := s.pmRepo.GetByEmail(ctx, req.Email)
	if err != nil && err != pgx.ErrNoRows {
		// This diagnostic log will reveal the underlying scan error.
		utils.Logger.WithError(err).Error("Diagnostic: Failed to check for existing property manager by email")
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to check for existing property manager", Err: err}
	}
	// --- MODIFICATION END ---

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
	}

	if err := s.pmRepo.Create(ctx, pm); err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to create property manager", Err: err}
	}

	s.logAudit(ctx, adminID, pm.ID, models.AuditCreate, models.TargetPropertyManager, pm)
	dto := shared_dtos.NewPMFromModel(*pm)
	return &dto, nil
}

// UpdatePropertyManager updates an existing property manager.
func (s *AdminService) UpdatePropertyManager(ctx context.Context, adminID uuid.UUID, req internal_dtos.UpdatePropertyManagerRequest) (*shared_dtos.PropertyManager, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}
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
	dto := shared_dtos.NewPMFromModel(*updatedPM)
	return &dto, nil
}

// SoftDeletePropertyManager marks a property manager as deleted.
func (s *AdminService) SoftDeletePropertyManager(ctx context.Context, adminID, pmID uuid.UUID) error {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return err
	}

	// Cascade delete to all properties owned by this manager
	properties, err := s.propRepo.ListByManagerID(ctx, pmID)
	if err != nil && err != pgx.ErrNoRows {
		return &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to list properties for deletion", Err: err}
	}
	for _, prop := range properties {
		if err := s.SoftDeleteProperty(ctx, adminID, prop.ID); err != nil {
			// We continue even if one property fails to ensure we try to delete as much as possible
			utils.Logger.WithError(err).Errorf("Failed to cascade soft-delete to property %s", prop.ID)
		}
	}

	// Now delete the manager itself
	if err := s.pmRepo.SoftDelete(ctx, pmID); err != nil {
		if err == pgx.ErrNoRows {
			return &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Property manager not found"}
		}
		return &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to delete property manager", Err: err}
	}
	s.logAudit(ctx, adminID, pmID, models.AuditDelete, models.TargetPropertyManager, nil)
	return nil
}

// SearchPropertyManagers searches for property managers with pagination.
func (s *AdminService) SearchPropertyManagers(ctx context.Context, adminID uuid.UUID, req internal_dtos.SearchPropertyManagersRequest) (*internal_dtos.PagedPropertyManagersResponse, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}
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

	dtosList := make([]shared_dtos.PropertyManager, len(pms))
	for i, pm := range pms {
		dtosList[i] = shared_dtos.NewPMFromModel(*pm)
	}

	return &internal_dtos.PagedPropertyManagersResponse{
		Data:     dtosList,
		Total:    total,
		Page:     req.Page,
		PageSize: req.PageSize,
	}, nil
}

// GetPropertyManagerSnapshot retrieves the full hierarchy for a property manager.
func (s *AdminService) GetPropertyManagerSnapshot(ctx context.Context, adminID, managerID uuid.UUID) (*internal_dtos.PropertyManagerSnapshotResponse, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}
	pm, err := s.pmRepo.GetByID(ctx, managerID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Property manager not found"}
		}
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to retrieve property manager", Err: err}
	}

	pmDTO := shared_dtos.NewPMFromModel(*pm)
	snapshot := &internal_dtos.PropertyManagerSnapshotResponse{PropertyManager: pmDTO}

	props, err := s.propRepo.ListByManagerID(ctx, managerID)
	if err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to list properties"}
	}

	for _, p := range props {
		buildings, _ := s.bldgRepo.ListByPropertyID(ctx, p.ID)
		allUnits, _ := s.unitRepo.ListByPropertyID(ctx, p.ID)
		dumpsters, _ := s.dumpsterRepo.ListByPropertyID(ctx, p.ID)
		jobDefs, _ := s.jobDefRepo.ListByPropertyID(ctx, p.ID)

		utils.Logger.Infof("[SnapshotDebug] For Property %s, unitRepo.ListByPropertyID returned %d units.", p.ID, len(allUnits))

		unitMap := make(map[uuid.UUID][]*models.Unit)
		for _, u := range allUnits {
			deletedAtStr := "nil"
			if u.DeletedAt != nil {
				deletedAtStr = u.DeletedAt.Format(time.RFC3339)
			}
			utils.Logger.Infof("[SnapshotDebug]  - Processing Unit ID: %s, DeletedAt: %s", u.ID, deletedAtStr)
			if u.DeletedAt != nil {
				utils.Logger.Warnf("[SnapshotDebug]  - SKIPPING soft-deleted Unit ID: %s", u.ID)
				continue
			}
			unitMap[u.BuildingID] = append(unitMap[u.BuildingID], u)
		}

		bldgDTOs := make([]internal_dtos.Building, len(buildings))
		for i, b := range buildings {
			floors, _ := s.floorRepo.ListByBuildingID(ctx, b.ID)
			bldgDTOs[i] = internal_dtos.NewBuildingFromModel(b, floors, unitMap[b.ID])
		}

		propDTO := internal_dtos.NewPropertyFromModel(p, bldgDTOs, dumpsters)
		snapshot.Properties = append(snapshot.Properties, internal_dtos.PropertySnapshot{
			Property:       propDTO,
			JobDefinitions: jobDefs,
		})
	}
	return snapshot, nil
}

// CreateProperty creates a new property for a manager and returns it as a DTO.
func (s *AdminService) CreateProperty(ctx context.Context, adminID uuid.UUID, req internal_dtos.CreatePropertyRequest) (*internal_dtos.Property, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}
	// Check if parent manager exists
	pmCheck, err := s.pmRepo.GetByID(ctx, req.ManagerID)
	if err != nil {
		// Diagnostic log
		utils.Logger.WithError(err).Warnf("Failed to find parent property manager %s during property creation", req.ManagerID)
		utils.Logger.Infof("Detailed error check: Type is '%T', Value is '%v', Is pgx.ErrNoRows? %t", err, err, err == pgx.ErrNoRows)

		if errors.Is(err, pgx.ErrNoRows) {
			return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Parent property manager not found"}
		}
		// Any other error from GetByID is unexpected and indicates an internal issue.
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to check for property manager", Err: err}
	}
	if pmCheck == nil {
		// Defensive: repository implementations may return (nil, nil) when not found
		return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Parent property manager not found"}
	}

	// Auto-geocode latitude/longitude if not provided (or provided as zeros)
	lat := req.Latitude
	lng := req.Longitude
	if (lat == 0 && lng == 0) || lat == 0 || lng == 0 {
		fullAddr := fmt.Sprintf("%s, %s, %s %s", req.Address, req.City, req.State, req.ZipCode)
		gLat, gLng, gErr := utils.GeocodeAddress(fullAddr, s.cfg.GMapsAPIKey)
		if gErr == nil {
			lat, lng = gLat, gLng
		} else {
			// Log and continue with provided values
			utils.Logger.WithError(gErr).Warnf("Geocoding failed for address '%s'", fullAddr)
		}
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
		Latitude:     lat,
		Longitude:    lng,
	}

	if err := s.propRepo.Create(ctx, prop); err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to create property", Err: err}
	}

	s.logAudit(ctx, adminID, prop.ID, models.AuditCreate, models.TargetProperty, prop)

	// Construct the DTO with empty slices for buildings and dumpsters
	propDTO := internal_dtos.NewPropertyFromModel(prop, []internal_dtos.Building{}, []*models.Dumpster{})
	return &propDTO, nil
}

// UpdateProperty updates an existing property.
func (s *AdminService) UpdateProperty(ctx context.Context, adminID uuid.UUID, req internal_dtos.UpdatePropertyRequest) (*models.Property, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}
	var updatedProp *models.Property
	err := s.propRepo.UpdateWithRetry(ctx, req.ID, func(p *models.Property) error {
		if req.PropertyName != nil {
			p.PropertyName = *req.PropertyName
		}
		if req.Address != nil {
			p.Address = *req.Address
		}
		if req.City != nil {
			p.City = *req.City
		}
		if req.State != nil {
			p.State = *req.State
		}
		if req.ZipCode != nil {
			p.ZipCode = *req.ZipCode
		}
		if req.TimeZone != nil {
			p.TimeZone = *req.TimeZone
		}
		if req.Latitude != nil {
			p.Latitude = *req.Latitude
		}
		if req.Longitude != nil {
			p.Longitude = *req.Longitude
		}
		updatedProp = p
		return nil
	})

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Property not found"}
		}
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to update property", Err: err}
	}

	s.logAudit(ctx, adminID, updatedProp.ID, models.AuditUpdate, models.TargetProperty, updatedProp)
	return updatedProp, nil
}

// SoftDeleteProperty marks a property as deleted.
func (s *AdminService) SoftDeleteProperty(ctx context.Context, adminID, propID uuid.UUID) error {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return err
	}

	// Cascade delete to all buildings within this property
	buildings, err := s.bldgRepo.ListByPropertyID(ctx, propID)
	if err != nil && err != pgx.ErrNoRows {
		return &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to list buildings for deletion", Err: err}
	}
	for _, bldg := range buildings {
		if err := s.SoftDeleteBuilding(ctx, adminID, bldg.ID); err != nil {
			utils.Logger.WithError(err).Errorf("Failed to cascade soft-delete to building %s", bldg.ID)
		}
	}

	// Soft-delete all units directly associated with the property.
	// This is a critical fallback for units that might be orphaned from buildings.
	if err := s.unitRepo.DeleteByPropertyID(ctx, propID); err != nil {
		utils.Logger.WithError(err).Errorf("Failed to cascade soft-delete to units for property %s", propID)
	}

	// Soft-delete dumpsters associated with the property
	if err := s.dumpsterRepo.DeleteByPropertyID(ctx, propID); err != nil {
		utils.Logger.WithError(err).Errorf("Failed to cascade soft-delete to dumpsters for property %s", propID)
	}

	// Now delete the property itself
	if err := s.propRepo.SoftDelete(ctx, propID); err != nil {
		if err == pgx.ErrNoRows {
			return &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Property not found"}
		}
		return &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to delete property", Err: err}
	}
	s.logAudit(ctx, adminID, propID, models.AuditDelete, models.TargetProperty, nil)
	return nil
}

// CreateBuilding creates a new building for a property and returns it as a DTO.
func (s *AdminService) CreateBuilding(ctx context.Context, adminID uuid.UUID, req internal_dtos.CreateBuildingRequest) (*internal_dtos.Building, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}
	_, err := s.propRepo.GetByID(ctx, req.PropertyID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Parent property not found"}
		}
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to check for parent property", Err: err}
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

	// Construct the DTO with an empty slice for units
	buildingDTO := internal_dtos.NewBuildingFromModel(building, []*models.Floor{}, []*models.Unit{})
	return &buildingDTO, nil
}

// CreateFloor creates a new floor for a building.
func (s *AdminService) CreateFloor(ctx context.Context, adminID uuid.UUID, req internal_dtos.CreateFloorRequest) (*models.Floor, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}
	// Validate parent building and property relationship
	bldg, err := s.bldgRepo.GetByID(ctx, req.BuildingID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Parent building not found"}
		}
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to check for parent building", Err: err}
	}
	if bldg.PropertyID != req.PropertyID {
		return nil, &utils.AppError{StatusCode: http.StatusBadRequest, Code: utils.ErrCodeInvalidPayload, Message: "The specified building does not belong to the specified property."}
	}

	// Enforce uniqueness of (building_id, number)
	existing, err := s.floorRepo.GetByBuildingAndNumber(ctx, req.BuildingID, req.Number)
	if err != nil && err != pgx.ErrNoRows {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to check existing floors", Err: err}
	}
	if existing != nil {
		return nil, &utils.AppError{StatusCode: http.StatusConflict, Code: utils.ErrCodeConflict, Message: "A floor with this number already exists in this building."}
	}

	f := &models.Floor{
		ID:         uuid.New(),
		PropertyID: req.PropertyID,
		BuildingID: req.BuildingID,
		Number:     req.Number,
	}
	if err := s.floorRepo.Create(ctx, f); err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to create floor", Err: err}
	}
	s.logAudit(ctx, adminID, f.ID, models.AuditCreate, models.TargetFloor, f)
	return f, nil
}

// ListFloorsByBuilding returns non-deleted floors for a building ordered by number.
func (s *AdminService) ListFloorsByBuilding(ctx context.Context, adminID uuid.UUID, buildingID uuid.UUID) ([]*models.Floor, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}
	floors, err := s.floorRepo.ListByBuildingID(ctx, buildingID)
	if err != nil && err != pgx.ErrNoRows {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to list floors", Err: err}
	}
	if floors == nil {
		floors = []*models.Floor{}
	}
	return floors, nil
}

// UpdateBuilding updates an existing building.
func (s *AdminService) UpdateBuilding(ctx context.Context, adminID uuid.UUID, req internal_dtos.UpdateBuildingRequest) (*models.PropertyBuilding, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}
	var updatedBldg *models.PropertyBuilding
	err := s.bldgRepo.UpdateWithRetry(ctx, req.ID, func(b *models.PropertyBuilding) error {
		if req.BuildingName != nil {
			b.BuildingName = *req.BuildingName
		}
		if req.Address != nil {
			b.Address = req.Address
		}
		if req.Latitude != nil {
			b.Latitude = *req.Latitude
		}
		if req.Longitude != nil {
			b.Longitude = *req.Longitude
		}
		updatedBldg = b
		return nil
	})

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Building not found"}
		}
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to update building", Err: err}
	}

	s.logAudit(ctx, adminID, updatedBldg.ID, models.AuditUpdate, models.TargetBuilding, updatedBldg)
	return updatedBldg, nil
}

// SoftDeleteBuilding marks a building as deleted.
func (s *AdminService) SoftDeleteBuilding(ctx context.Context, adminID, bldgID uuid.UUID) error {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return err
	}

	// Cascade delete to all units within this building
	units, err := s.unitRepo.ListByBuildingID(ctx, bldgID)
	if err != nil && err != pgx.ErrNoRows {
		return &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to list units for deletion", Err: err}
	}
	for _, unit := range units {
		if err := s.SoftDeleteUnit(ctx, adminID, unit.ID); err != nil {
			utils.Logger.WithError(err).Errorf("Failed to cascade soft-delete to unit %s", unit.ID)
		}
	}

	// Now delete the building itself
	if err := s.bldgRepo.SoftDelete(ctx, bldgID); err != nil {
		if err == pgx.ErrNoRows {
			return &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Building not found"}
		}
		return &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to delete building", Err: err}
	}
	s.logAudit(ctx, adminID, bldgID, models.AuditDelete, models.TargetBuilding, nil)
	return nil
}

// CreateUnit creates a new unit for a building.
func (s *AdminService) CreateUnit(ctx context.Context, adminID uuid.UUID, req internal_dtos.CreateUnitRequest) (*models.Unit, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}
	bldg, err := s.bldgRepo.GetByID(ctx, req.BuildingID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Parent building not found"}
		}
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to check for parent building", Err: err}
	}

	// Check that the building belongs to the specified property
	if bldg.PropertyID != req.PropertyID {
		return nil, &utils.AppError{
			StatusCode: http.StatusBadRequest,
			Code:       utils.ErrCodeInvalidPayload,
			Message:    "The specified building does not belong to the specified property.",
		}
	}

	// Check for uniqueness of unit number within the building
	existingUnits, err := s.unitRepo.ListByBuildingID(ctx, req.BuildingID)
	if err != nil && err != pgx.ErrNoRows {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to check for existing units", Err: err}
	}
	for _, u := range existingUnits {
		if u.UnitNumber == req.UnitNumber {
			return nil, &utils.AppError{
				StatusCode: http.StatusConflict,
				Code:       utils.ErrCodeConflict,
				Message:    fmt.Sprintf("A unit with number '%s' already exists in this building.", req.UnitNumber),
			}
		}
	}

	// Generate a tenant token if not provided by admin; allow admin-specified token when present
	token := strings.TrimSpace(req.TenantToken)
	if token == "" {
		token = uuid.NewString()
	}
	unit := &models.Unit{
		ID:          uuid.New(),
		PropertyID:  req.PropertyID,
		BuildingID:  req.BuildingID,
		FloorID:     &req.FloorID,
		UnitNumber:  req.UnitNumber,
		TenantToken: token,
	}

	if err := s.unitRepo.Create(ctx, unit); err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to create unit", Err: err}
	}
	s.logAudit(ctx, adminID, unit.ID, models.AuditCreate, models.TargetUnit, unit)
	return unit, nil
}

// CreateUnitsBatch creates multiple units atomically for a building.
func (s *AdminService) CreateUnitsBatch(ctx context.Context, adminID uuid.UUID, req internal_dtos.CreateUnitsRequest) (*internal_dtos.CreateUnitsResponse, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}

	if len(req.Items) == 0 {
		return &internal_dtos.CreateUnitsResponse{Created: []models.Unit{}}, nil
	}

	// Validate all belong to same property and building and check duplicate unit_numbers within payload
	propID := req.Items[0].PropertyID
	bldgID := req.Items[0].BuildingID
	seen := make(map[string]bool)
	for _, it := range req.Items {
		if it.PropertyID != propID || it.BuildingID != bldgID {
			return nil, &utils.AppError{StatusCode: http.StatusBadRequest, Code: utils.ErrCodeInvalidPayload, Message: "All units in batch must target the same property and building"}
		}
		if it.UnitNumber == "" {
			return nil, &utils.AppError{StatusCode: http.StatusBadRequest, Code: utils.ErrCodeInvalidPayload, Message: "Unit number is required for all items"}
		}
		if seen[strings.ToLower(it.UnitNumber)] {
			return nil, &utils.AppError{StatusCode: http.StatusBadRequest, Code: utils.ErrCodeInvalidPayload, Message: "Duplicate unit_number in batch payload"}
		}
		seen[strings.ToLower(it.UnitNumber)] = true
	}

	// Ensure building exists and belongs to property
	bldg, err := s.bldgRepo.GetByID(ctx, bldgID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Parent building not found"}
		}
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to check for parent building", Err: err}
	}
	if bldg.PropertyID != propID {
		return nil, &utils.AppError{StatusCode: http.StatusBadRequest, Code: utils.ErrCodeInvalidPayload, Message: "The specified building does not belong to the specified property."}
	}

	// Conflict check against existing units in building
	existingUnits, err := s.unitRepo.ListByBuildingID(ctx, bldgID)
	if err != nil && err != pgx.ErrNoRows {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to check for existing units", Err: err}
	}
	existingSet := make(map[string]bool)
	for _, u := range existingUnits {
		existingSet[strings.ToLower(u.UnitNumber)] = true
	}
	for k := range seen {
		if existingSet[k] {
			return nil, &utils.AppError{StatusCode: http.StatusConflict, Code: utils.ErrCodeConflict, Message: "One or more unit_numbers already exist in this building"}
		}
	}

	// Build models
	units := make([]models.Unit, 0, len(req.Items))
	for _, it := range req.Items {
		token := strings.TrimSpace(it.TenantToken)
		if token == "" {
			token = uuid.NewString()
		}

		units = append(units, models.Unit{
			ID:          uuid.New(),
			PropertyID:  propID,
			BuildingID:  bldgID,
			FloorID:     &it.FloorID,
			UnitNumber:  it.UnitNumber,
			TenantToken: token,
		})
	}

	if err := s.unitRepo.CreateMany(ctx, units); err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to create units batch", Err: err}
	}

	// Audit each unit creation
	for i := range units {
		s.logAudit(ctx, adminID, units[i].ID, models.AuditCreate, models.TargetUnit, units[i])
	}

	return &internal_dtos.CreateUnitsResponse{Created: units}, nil
}

// UpdateUnit updates an existing unit.
func (s *AdminService) UpdateUnit(ctx context.Context, adminID uuid.UUID, req internal_dtos.UpdateUnitRequest) (*models.Unit, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}
	var updatedUnit *models.Unit
	err := s.unitRepo.UpdateWithRetry(ctx, req.ID, func(u *models.Unit) error {
		if req.UnitNumber != nil {
			u.UnitNumber = *req.UnitNumber
		}
		if req.FloorID != nil {
			u.FloorID = req.FloorID
		}
		updatedUnit = u
		return nil
	})

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Unit not found"}
		}
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to update unit", Err: err}
	}

	s.logAudit(ctx, adminID, updatedUnit.ID, models.AuditUpdate, models.TargetUnit, updatedUnit)
	return updatedUnit, nil
}

// SoftDeleteUnit marks a unit as deleted.
func (s *AdminService) SoftDeleteUnit(ctx context.Context, adminID, unitID uuid.UUID) error {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return err
	}
	if err := s.unitRepo.SoftDelete(ctx, unitID); err != nil {
		if err == pgx.ErrNoRows {
			return &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Unit not found"}
		}
		return &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to delete unit", Err: err}
	}
	s.logAudit(ctx, adminID, unitID, models.AuditDelete, models.TargetUnit, nil)
	return nil
}

// CreateDumpster creates a new dumpster for a property.
func (s *AdminService) CreateDumpster(ctx context.Context, adminID uuid.UUID, req internal_dtos.CreateDumpsterRequest) (*models.Dumpster, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}
	_, err := s.propRepo.GetByID(ctx, req.PropertyID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Parent property not found"}
		}
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to check for parent property", Err: err}
	}

	// Check for uniqueness of dumpster number within the property
	existingDumpsters, err := s.dumpsterRepo.ListByPropertyID(ctx, req.PropertyID)
	if err != nil && err != pgx.ErrNoRows {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to check for existing dumpsters", Err: err}
	}
	for _, d := range existingDumpsters {
		if d.DumpsterNumber == req.DumpsterNumber {
			return nil, &utils.AppError{
				StatusCode: http.StatusConflict,
				Code:       utils.ErrCodeConflict,
				Message:    fmt.Sprintf("A dumpster with number '%s' already exists in this property.", req.DumpsterNumber),
			}
		}
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

// UpdateDumpster updates an existing dumpster.
func (s *AdminService) UpdateDumpster(ctx context.Context, adminID uuid.UUID, req internal_dtos.UpdateDumpsterRequest) (*models.Dumpster, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}
	var updatedDumpster *models.Dumpster
	err := s.dumpsterRepo.UpdateWithRetry(ctx, req.ID, func(d *models.Dumpster) error {
		if req.DumpsterNumber != nil {
			d.DumpsterNumber = *req.DumpsterNumber
		}
		if req.Latitude != nil {
			d.Latitude = *req.Latitude
		}
		if req.Longitude != nil {
			d.Longitude = *req.Longitude
		}
		updatedDumpster = d
		return nil
	})

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Dumpster not found"}
		}
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to update dumpster", Err: err}
	}

	s.logAudit(ctx, adminID, updatedDumpster.ID, models.AuditUpdate, models.TargetDumpster, updatedDumpster)
	return updatedDumpster, nil
}

// SoftDeleteDumpster marks a dumpster as deleted.
func (s *AdminService) SoftDeleteDumpster(ctx context.Context, adminID, dumpsterID uuid.UUID) error {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return err
	}
	if err := s.dumpsterRepo.SoftDelete(ctx, dumpsterID); err != nil {
		if err == pgx.ErrNoRows {
			return &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Dumpster not found"}
		}
		return &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to delete dumpster", Err: err}
	}
	s.logAudit(ctx, adminID, dumpsterID, models.AuditDelete, models.TargetDumpster, nil)
	return nil
}

// CreateAgent creates a new agent.
func (s *AdminService) CreateAgent(ctx context.Context, adminID uuid.UUID, req internal_dtos.CreateAgentRequest) (*models.Agent, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}

	// Resolve coordinates from request or geocode from address (fallback when zero)
	lat := req.Latitude
	lng := req.Longitude
	if (lat == 0 && lng == 0) || lat == 0 || lng == 0 {
		fullAddr := fmt.Sprintf("%s, %s, %s %s", req.Address, req.City, req.State, req.ZipCode)
		gLat, gLng, gErr := utils.GeocodeAddress(fullAddr, s.cfg.GMapsAPIKey)
		if gErr != nil {
			utils.Logger.WithError(gErr).Warnf("Geocoding failed for agent address '%s'", fullAddr)
		} else {
			lat, lng = gLat, gLng
		}
	}

	agent := &models.Agent{
		ID:          uuid.New(),
		Name:        req.Name,
		Email:       req.Email,
		PhoneNumber: req.PhoneNumber,
		Address:     req.Address,
		City:        req.City,
		State:       req.State,
		ZipCode:     req.ZipCode,
		Latitude:    lat,
		Longitude:   lng,
	}

	if err := s.agentRepo.Create(ctx, agent); err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to create agent", Err: err}
	}

	s.logAudit(ctx, adminID, agent.ID, models.AuditCreate, models.TargetAgent, agent)
	return agent, nil
}

// UpdateAgent updates an existing agent.
func (s *AdminService) UpdateAgent(ctx context.Context, adminID uuid.UUID, req internal_dtos.UpdateAgentRequest) (*models.Agent, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}

	existing, err := s.agentRepo.GetByID(ctx, req.ID)
	if err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to retrieve agent", Err: err}
	}
	if existing == nil {
		return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Agent not found"}
	}

	if req.Name != nil {
		existing.Name = *req.Name
	}
	if req.Email != nil {
		existing.Email = *req.Email
	}
	if req.PhoneNumber != nil {
		existing.PhoneNumber = *req.PhoneNumber
	}
	if req.Address != nil {
		existing.Address = *req.Address
	}
	if req.City != nil {
		existing.City = *req.City
	}
	if req.State != nil {
		existing.State = *req.State
	}
	if req.ZipCode != nil {
		existing.ZipCode = *req.ZipCode
	}
	if req.Latitude != nil {
		existing.Latitude = *req.Latitude
	}
	if req.Longitude != nil {
		existing.Longitude = *req.Longitude
	}

	if err := s.agentRepo.Update(ctx, existing); err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to update agent", Err: err}
	}

	s.logAudit(ctx, adminID, existing.ID, models.AuditUpdate, models.TargetAgent, existing)
	return existing, nil
}

// SoftDeleteAgent marks an agent as deleted.
func (s *AdminService) SoftDeleteAgent(ctx context.Context, adminID, agentID uuid.UUID) error {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return err
	}
	if err := s.agentRepo.SoftDelete(ctx, agentID); err != nil {
		if err == pgx.ErrNoRows {
			return &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Agent not found"}
		}
		return &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to delete agent", Err: err}
	}
	s.logAudit(ctx, adminID, agentID, models.AuditDelete, models.TargetAgent, nil)
	return nil
}
