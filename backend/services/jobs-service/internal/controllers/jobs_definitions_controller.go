package controllers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/go-playground/validator/v10"
	"github.com/google/uuid"
	"github.com/poofware/go-middleware"
	"github.com/poofware/go-utils"
	"github.com/poofware/jobs-service/internal/dtos"
	"github.com/poofware/jobs-service/internal/services"
	internal_utils "github.com/poofware/jobs-service/internal/utils"
)

type JobDefinitionsController struct {
	jobService *services.JobService
}

func NewJobDefinitionsController(js *services.JobService) *JobDefinitionsController {
	return &JobDefinitionsController{jobService: js}
}

var jobDefValidate = validator.New()

// POST /api/v1/manager/jobs/definition
// This endpoint is for creating a new job definition.
func (c *JobDefinitionsController) CreateDefinitionHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	pmUserID := ctx.Value(middleware.ContextKeyUserID)
	if pmUserID == nil {
		utils.RespondErrorWithCode(w, http.StatusForbidden, utils.ErrCodeUnauthorized, "No manager ID in context", nil, nil)
		return
	}

	var req dtos.CreateJobDefinitionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON body", err, nil)
		return
	}

	if err := jobDefValidate.StructCtx(ctx, req); err != nil {
		var validationErrors validator.ValidationErrors
		if errors.As(err, &validationErrors) {
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Validation failed", validationErrors, nil)
		} else {
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid request data", err, nil)
		}
		return
	}

	trimmedStatus := strings.ToUpper(strings.TrimSpace(req.Status))
	if trimmedStatus == "" {
		trimmedStatus = "ACTIVE" // default
	}

	defID, err := c.jobService.CreateJobDefinition(ctx, pmUserID.(string), req, trimmedStatus)
	if err != nil {
		if errors.Is(err, internal_utils.ErrMismatchedPayEstimatesFrequency) ||
			errors.Is(err, internal_utils.ErrMissingPayEstimateInput) ||
			errors.Is(err, internal_utils.ErrInvalidPayload) { // Catching specific validation errors from service
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, err.Error(), nil, err)
		} else {
			utils.Logger.WithError(err).Error("CreateJobDefinition error")
			utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Could not create job definition", nil, err)
		}
		return
	}

	resp := dtos.CreateJobDefinitionResponse{
		DefinitionID: defID,
	}
	utils.RespondWithJSON(w, http.StatusCreated, resp)
}

// ListJobsForPropertyHandler -> GET /api/v1/manager/properties//jobs
func (c *JobDefinitionsController) ListJobsForPropertyHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	pmUserID := ctx.Value(middleware.ContextKeyUserID)
	if pmUserID == nil {
		utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "No manager ID in context", nil, nil)
		return
	}

	var req dtos.ListJobsForPropertyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON body", err, nil)
		return
	}

	resp, svcErr := c.jobService.ListJobsForPropertyByManager(ctx, pmUserID.(string), req.PropertyID)
	if svcErr != nil {
		// Handle specific "unauthorized" error from the service layer gracefully
		if svcErr.Error() == "unauthorized: property does not belong to this manager" {
			utils.RespondErrorWithCode(w, http.StatusForbidden, utils.ErrCodeUnauthorized, "Access to this property is denied", nil, svcErr)
			return
		}
		utils.Logger.WithError(svcErr).Error("Failed to list jobs for property")
		utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Failed to list jobs for property", nil, svcErr)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, resp)
}

// PUT or PATCH /api/v1/jobs/definition/status
func (c *JobDefinitionsController) SetDefinitionStatusHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	ctxUserID := ctx.Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "No userID in context", nil, nil)
		return
	}

	var req dtos.SetDefinitionStatusRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON body", err, nil)
		return
	}
	if req.DefinitionID == uuid.Nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "definition_id is required", nil, nil)
		return
	}
	newStatus := strings.TrimSpace(req.NewStatus)
	if newStatus == "" {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "new_status is required", nil, nil)
		return
	}

	err := c.jobService.SetDefinitionStatus(ctx, req.DefinitionID, newStatus)
	if err != nil {
		if errors.Is(err, utils.ErrRowVersionConflict) {
			utils.RespondErrorWithCode(w, http.StatusConflict, utils.ErrCodeConflict, "Job definition update conflict", err, nil)
			return
		}
		utils.Logger.WithError(err).Error("SetDefinitionStatus error")
		utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Could not change job definition status", err, nil)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
