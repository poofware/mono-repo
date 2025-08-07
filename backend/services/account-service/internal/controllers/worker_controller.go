package controllers

import (
	"context"
	"encoding/json"
	"net/http"
	"errors"

	"github.com/go-playground/validator/v10"
	internal_dtos "github.com/poofware/mono-repo/backend/services/account-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/services/account-service/internal/services"
	"github.com/poofware/mono-repo/backend/shared/go-dtos"
	"github.com/poofware/mono-repo/backend/shared/go-middleware"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

// WorkerController contains methods for Worker endpoints.
type WorkerController struct {
	workerService *services.WorkerService
}

var workerValidate = validator.New()

func NewWorkerController(workerService *services.WorkerService) *WorkerController {
	return &WorkerController{workerService: workerService}
}

// GET /api/v1/account/worker
func (c *WorkerController) GetWorkerHandler(w http.ResponseWriter, r *http.Request) {
	ctxUserID := r.Context().Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Missing userID in context", nil)
		return
	}

	worker, err := c.workerService.GetWorkerByID(context.Background(), ctxUserID.(string))
	if err != nil {
		utils.Logger.WithError(err).Error("Failed to retrieve worker record")
		utils.RespondErrorWithCode(
			w,
			http.StatusInternalServerError,
			utils.ErrCodeInternal,
			"Unable to retrieve worker record",
			err,
		)
		return
	}
	if worker == nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusNotFound,
			utils.ErrCodeNotFound,
			"No worker found for this user",
			nil,
		)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, dtos.NewWorkerFromModel(*worker))
}

// PATCH /api/v1/account/worker
func (c *WorkerController) PatchWorkerHandler(w http.ResponseWriter, r *http.Request) {
	ctxUserID := r.Context().Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Missing userID in context", nil)
		return
	}

	var patchReq dtos.WorkerPatchRequest
	if err := json.NewDecoder(r.Body).Decode(&patchReq); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

        updatedWorker, err := c.workerService.PatchWorker(context.Background(), ctxUserID.(string), patchReq)
        if err != nil {
                switch {
                case errors.Is(err, utils.ErrPhoneNotVerified):
                        utils.RespondErrorWithCode(w, http.StatusForbidden, utils.ErrCodePhoneNotVerified, "New phone number is not verified. Please verify it before updating.", err)
                case errors.Is(err, utils.ErrInvalidTenantToken):
                        utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidTenantToken, "Invalid tenant token", err)
                default:
                        utils.Logger.WithError(err).Error("Failed to patch worker record")
                        utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Failed to update worker", err)
                }
                return
        }

	// Service returned nil worker but no error.
	if updatedWorker == nil {
		utils.RespondErrorWithCode(w, http.StatusNotFound, utils.ErrCodeNotFound, "No worker found for this user", nil)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, dtos.NewWorkerFromModel(*updatedWorker))
}

// SubmitPersonalInfoHandler handles the dedicated submission of a worker's personal and vehicle info.
func (c *WorkerController) SubmitPersonalInfoHandler(w http.ResponseWriter, r *http.Request) {
	ctxUserID := r.Context().Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Missing userID in context", nil)
		return
	}

	var req internal_dtos.SubmitPersonalInfoRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err)
		return
	}

	if err := workerValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	updatedWorker, err := c.workerService.SubmitPersonalInfo(r.Context(), ctxUserID.(string), req)
	if err != nil {
		if errors.Is(err, utils.ErrRowVersionConflict) {
			utils.RespondErrorWithCode(w, http.StatusConflict, utils.ErrCodeRowVersionConflict, "State conflict, please retry", err)
			return
		}
		if err.Error() == "worker not in AWAITING_PERSONAL_INFO state" {
			utils.RespondErrorWithCode(w, http.StatusForbidden, utils.ErrCodeConflict, err.Error(), err)
			return
		}
		utils.Logger.WithError(err).Error("Failed to submit personal info for worker")
		utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Failed to update worker information", err)
		return
	}

	if updatedWorker == nil {
		utils.RespondErrorWithCode(w, http.StatusNotFound, utils.ErrCodeNotFound, "No worker found for this user", nil)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, dtos.NewWorkerFromModel(*updatedWorker))
}
