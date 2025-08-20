package controllers

import (
	"context"
	"net/http"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/services/account-service/internal/services"
	"github.com/poofware/mono-repo/backend/shared/go-middleware"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
	"github.com/poofware/mono-repo/backend/shared/go-dtos"
)

type PMController struct {
	pmService *services.PMService
}

func NewPMController(pmService *services.PMService) *PMController {
	return &PMController{pmService: pmService}
}

// GET /api/v1/account/pm
func (c *PMController) GetPMHandler(w http.ResponseWriter, r *http.Request) {
	ctxUserID := r.Context().Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Missing userID in context", nil)
		return
	}

	pm, err := c.pmService.GetPMByID(context.Background(), ctxUserID.(string))
	if err != nil {
		utils.Logger.WithError(err).Error("Failed to retrieve pm record")
		utils.RespondErrorWithCode(
			w,
			http.StatusInternalServerError,
			utils.ErrCodeInternal,
			"Unable to retrieve pm record",
			err,
		)
		return
	}
	if pm == nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusNotFound,
			utils.ErrCodeNotFound,
			"No pm found for this user",
			nil,
		)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, dtos.NewPMFromModel(*pm))
}

func (c *PMController) ListPropertiesHandler(w http.ResponseWriter, r *http.Request) {
	ctxUserID := r.Context().Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Missing userID in context", nil)
		return
	}
	pmID, err := uuid.Parse(ctxUserID.(string))
	if err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid userID format", err)
		return
	}

	props, err := c.pmService.ListProperties(r.Context(), pmID)
	if err != nil {
		utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Failed to retrieve properties", err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, props)
}


