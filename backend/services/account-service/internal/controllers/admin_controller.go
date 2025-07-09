// backend/services/account-service/internal/controllers/admin_controller.go
// NEW FILE
package controllers

import (
	"encoding/json"
	"net/http"

	"github.com/go-playground/validator/v10"
	"github.com/google/uuid"
	"github.com/poofware/account-service/internal/dtos"
	"github.com/poofware/account-service/internal/services"
	"github.com/poofware/go-middleware"
	"github.com/poofware/go-utils"
)

type AdminController struct {
	adminService *services.AdminService
	validate     *validator.Validate
}

func NewAdminController(adminService *services.AdminService) *AdminController {
	return &AdminController{
		adminService: adminService,
		validate:     validator.New(),
	}
}

func (c *AdminController) getAdminID(r *http.Request) (uuid.UUID, error) {
	ctxAdminID := r.Context().Value(middleware.ContextKeyUserID)
	if ctxAdminID == nil {
		return uuid.Nil, &utils.AppError{
			StatusCode: http.StatusUnauthorized,
			Code:       utils.ErrCodeUnauthorized,
			Message:    "Missing adminID in context",
		}
	}
	adminID, err := uuid.Parse(ctxAdminID.(string))
	if err != nil {
		return uuid.Nil, &utils.AppError{
			StatusCode: http.StatusBadRequest,
			Code:       utils.ErrCodeInvalidPayload,
			Message:    "Invalid adminID format",
			Err:        err,
		}
	}
	return adminID, nil
}

// POST /api/v1/account/admin/property-managers
func (c *AdminController) CreatePropertyManagerHandler(w http.ResponseWriter, r *http.Request) {
	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.CreatePropertyManagerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	pm, err := c.adminService.CreatePropertyManager(r.Context(), adminID, req)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusCreated, pm)
}

// PATCH /api/v1/account/admin/property-managers
func (c *AdminController) UpdatePropertyManagerHandler(w http.ResponseWriter, r *http.Request) {
	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.UpdatePropertyManagerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	pm, err := c.adminService.UpdatePropertyManager(r.Context(), adminID, req)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, pm)
}

// DELETE /api/v1/account/admin/property-managers
func (c *AdminController) DeletePropertyManagerHandler(w http.ResponseWriter, r *http.Request) {
	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.DeleteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	if err := c.adminService.SoftDeletePropertyManager(r.Context(), adminID, req.ID); err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, dtos.ConfirmationResponse{
		Message: "Property Manager soft-deleted successfully",
		ID:      req.ID.String(),
	})
}

// POST /api/v1/account/admin/property-managers/search
func (c *AdminController) SearchPropertyManagersHandler(w http.ResponseWriter, r *http.Request) {
	_, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.SearchPropertyManagersRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	pms, err := c.adminService.SearchPropertyManagers(r.Context(), req)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, pms)
}

// POST /api/v1/account/admin/property-manager/snapshot
func (c *AdminController) GetPropertyManagerSnapshotHandler(w http.ResponseWriter, r *http.Request) {
	_, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.SnapshotRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	snapshot, err := c.adminService.GetPropertyManagerSnapshot(r.Context(), req.ManagerID)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, snapshot)
}

// POST /api/v1/account/admin/properties
func (c *AdminController) CreatePropertyHandler(w http.ResponseWriter, r *http.Request) {
	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.CreatePropertyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	prop, err := c.adminService.CreateProperty(r.Context(), adminID, req)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusCreated, prop)
}

// PATCH /api/v1/account/admin/properties
func (c *AdminController) UpdatePropertyHandler(w http.ResponseWriter, r *http.Request) {
	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.UpdatePropertyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	prop, err := c.adminService.UpdateProperty(r.Context(), adminID, req)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, prop)
}

// DELETE /api/v1/account/admin/properties
func (c *AdminController) DeletePropertyHandler(w http.ResponseWriter, r *http.Request) {
	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.DeleteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	if err := c.adminService.SoftDeleteProperty(r.Context(), adminID, req.ID); err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, dtos.ConfirmationResponse{
		Message: "Property soft-deleted successfully",
		ID:      req.ID.String(),
	})
}

// POST /api/v1/account/admin/property-buildings
func (c *AdminController) CreateBuildingHandler(w http.ResponseWriter, r *http.Request) {
	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.CreateBuildingRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	building, err := c.adminService.CreateBuilding(r.Context(), adminID, req)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusCreated, building)
}

// PATCH /api/v1/account/admin/property-buildings
func (c *AdminController) UpdateBuildingHandler(w http.ResponseWriter, r *http.Request) {
	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.UpdateBuildingRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	building, err := c.adminService.UpdateBuilding(r.Context(), adminID, req)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, building)
}

// DELETE /api/v1/account/admin/property-buildings
func (c *AdminController) DeleteBuildingHandler(w http.ResponseWriter, r *http.Request) {
	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.DeleteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	if err := c.adminService.SoftDeleteBuilding(r.Context(), adminID, req.ID); err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, dtos.ConfirmationResponse{
		Message: "Building soft-deleted successfully",
		ID:      req.ID.String(),
	})
}

// POST /api/v1/account/admin/units
func (c *AdminController) CreateUnitHandler(w http.ResponseWriter, r *http.Request) {
	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.CreateUnitRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	unit, err := c.adminService.CreateUnit(r.Context(), adminID, req)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusCreated, unit)
}

// PATCH /api/v1/account/admin/units
func (c *AdminController) UpdateUnitHandler(w http.ResponseWriter, r *http.Request) {
	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.UpdateUnitRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	unit, err := c.adminService.UpdateUnit(r.Context(), adminID, req)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, unit)
}

// DELETE /api/v1/account/admin/units
func (c *AdminController) DeleteUnitHandler(w http.ResponseWriter, r *http.Request) {
	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.DeleteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	if err := c.adminService.SoftDeleteUnit(r.Context(), adminID, req.ID); err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, dtos.ConfirmationResponse{
		Message: "Unit soft-deleted successfully",
		ID:      req.ID.String(),
	})
}

// POST /api/v1/account/admin/dumpsters
func (c *AdminController) CreateDumpsterHandler(w http.ResponseWriter, r *http.Request) {
	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.CreateDumpsterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	dumpster, err := c.adminService.CreateDumpster(r.Context(), adminID, req)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusCreated, dumpster)
}

// PATCH /api/v1/account/admin/dumpsters
func (c *AdminController) UpdateDumpsterHandler(w http.ResponseWriter, r *http.Request) {
	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.UpdateDumpsterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	dumpster, err := c.adminService.UpdateDumpster(r.Context(), adminID, req)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, dumpster)
}

// DELETE /api/v1/account/admin/dumpsters
func (c *AdminController) DeleteDumpsterHandler(w http.ResponseWriter, r *http.Request) {
	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	var req dtos.DeleteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := c.validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	if err := c.adminService.SoftDeleteDumpster(r.Context(), adminID, req.ID); err != nil {
		utils.HandleAppError(w, err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, dtos.ConfirmationResponse{
		Message: "Dumpster soft-deleted successfully",
		ID:      req.ID.String(),
	})
}