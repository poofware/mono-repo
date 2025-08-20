package controllers

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/go-playground/validator/v10"
	"github.com/google/uuid"
	shared_dtos "github.com/poofware/mono-repo/backend/shared/go-dtos"
	"github.com/poofware/mono-repo/backend/shared/go-middleware"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/services"
)

type AdminJobsController struct {
	adminJobService *services.AdminJobService
	validate        *validator.Validate
}

func NewAdminJobsController(s *services.AdminJobService) *AdminJobsController {
	return &AdminJobsController{
		adminJobService: s,
		validate:        validator.New(),
	}
}

// formatValidationErrors is a helper to convert validator errors into a user-friendly format.
func (c *AdminJobsController) formatValidationErrors(errs validator.ValidationErrors) []shared_dtos.ValidationErrorDetail {
	var details []shared_dtos.ValidationErrorDetail
	for _, err := range errs {
		var message string
		switch err.Tag() {
		case "required":
			message = fmt.Sprintf("Field '%s' is required", err.Field())
		case "email":
			message = fmt.Sprintf("Field '%s' must be a valid email address", err.Field())
		case "min":
			message = fmt.Sprintf("Field '%s' must be at least %s in length", err.Field(), err.Param())
		case "max":
			message = fmt.Sprintf("Field '%s' must not exceed %s in length", err.Field(), err.Param())
		case "oneof":
			message = fmt.Sprintf("Field '%s' must be one of [%s]", err.Field(), err.Param())
		default:
			message = fmt.Sprintf("Field validation for '%s' failed on the '%s' tag", err.Field(), err.Tag())
		}
		details = append(details, shared_dtos.ValidationErrorDetail{
			Field:   err.Field(),
			Message: message,
			Code:    "validation_" + err.Tag(),
		})
	}
	return details
}

func (c *AdminJobsController) getAdminID(r *http.Request) (uuid.UUID, error) {
	ctxAdminID := r.Context().Value(middleware.ContextKeyUserID)
	if ctxAdminID == nil {
		return uuid.Nil, &utils.AppError{StatusCode: http.StatusUnauthorized, Code: utils.ErrCodeUnauthorized, Message: "Missing adminID in context"}
	}
	adminID, err := uuid.Parse(ctxAdminID.(string))
	if err != nil {
		return uuid.Nil, &utils.AppError{StatusCode: http.StatusBadRequest, Code: utils.ErrCodeInvalidPayload, Message: "Invalid adminID format", Err: err}
	}
	return adminID, nil
}

// POST /api/v1/jobs/admin/job-definitions
func (c *AdminJobsController) AdminCreateJobDefinitionHandler(w http.ResponseWriter, r *http.Request) {
	logger := utils.Logger.WithField("handler", "AdminCreateJobDefinitionHandler")
	logger.Info("Request received")

	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	logger = logger.WithField("adminID", adminID)
	logger.Info("Admin ID extracted from context")

	var req dtos.AdminCreateJobDefinitionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", nil, err)
		return
	}
	logger.WithField("requestBody", req).Info("Request body decoded")

	if err := c.validate.Struct(req); err != nil {
		if validationErrs, ok := err.(validator.ValidationErrors); ok {
			utils.RespondWithJSON(w, http.StatusBadRequest, c.formatValidationErrors(validationErrs))
		} else {
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", nil, err)
		}
		return
	}

	jobDef, err := c.adminJobService.AdminCreateJobDefinition(r.Context(), adminID, req)
	if err != nil {
		logger.WithError(err).Error("Service call failed")
		utils.HandleAppError(w, err)
		return
	}
	logger.WithField("definitionID", jobDef.ID).Info("Service call successful")
	utils.RespondWithJSON(w, http.StatusCreated, jobDef)
}

// PATCH /api/v1/jobs/admin/job-definitions
func (c *AdminJobsController) AdminUpdateJobDefinitionHandler(w http.ResponseWriter, r *http.Request) {
	logger := utils.Logger.WithField("handler", "AdminUpdateJobDefinitionHandler")
	logger.Info("Request received")

	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	logger = logger.WithField("adminID", adminID)
	logger.Info("Admin ID extracted from context")

	var req dtos.AdminUpdateJobDefinitionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", nil, err)
		return
	}
	logger.WithField("requestBody", req).Info("Request body decoded")

	if err := c.validate.Struct(req); err != nil {
		if validationErrs, ok := err.(validator.ValidationErrors); ok {
			utils.RespondWithJSON(w, http.StatusBadRequest, c.formatValidationErrors(validationErrs))
		} else {
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", nil, err)
		}
		return
	}

	jobDef, err := c.adminJobService.AdminUpdateJobDefinition(r.Context(), adminID, req)
	if err != nil {
		logger.WithError(err).Error("Service call failed")
		utils.HandleAppError(w, err)
		return
	}
	logger.WithField("definitionID", jobDef.ID).Info("Service call successful")
	utils.RespondWithJSON(w, http.StatusOK, jobDef)
}

// DELETE /api/v1/jobs/admin/job-definitions
func (c *AdminJobsController) AdminSoftDeleteJobDefinitionHandler(w http.ResponseWriter, r *http.Request) {
	logger := utils.Logger.WithField("handler", "AdminSoftDeleteJobDefinitionHandler")
	logger.Info("Request received")

	adminID, err := c.getAdminID(r)
	if err != nil {
		utils.HandleAppError(w, err)
		return
	}

	logger = logger.WithField("adminID", adminID)
	logger.Info("Admin ID extracted from context")

	var req dtos.AdminDeleteJobDefinitionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", nil, err)
		return
	}
	logger.WithField("requestBody", req).Info("Request body decoded")

	if err := c.validate.Struct(req); err != nil {
		if validationErrs, ok := err.(validator.ValidationErrors); ok {
			utils.RespondWithJSON(w, http.StatusBadRequest, c.formatValidationErrors(validationErrs))
		} else {
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", nil, err)
		}
		return
	}

	if err := c.adminJobService.AdminSoftDeleteJobDefinition(r.Context(), adminID, req.DefinitionID); err != nil {
		logger.WithError(err).Error("Service call failed")
		utils.HandleAppError(w, err)
		return
	}

	logger.WithField("definitionID", req.DefinitionID).Info("Service call successful")
	utils.RespondWithJSON(w, http.StatusOK, dtos.AdminConfirmationResponse{
		Message: "Job Definition soft-deleted successfully",
		ID:      req.DefinitionID.String(),
	})
}