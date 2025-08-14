package controllers

import (
	"net/http"

	"github.com/poofware/mono-repo/backend/services/earnings-service/internal/services"
	"github.com/poofware/mono-repo/backend/shared/go-middleware"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

type EarningsController struct {
	earningsService *services.EarningsService
}

func NewEarningsController(s *services.EarningsService) *EarningsController {
	return &EarningsController{earningsService: s}
}

// GET /api/v1/earnings/summary
func (c *EarningsController) GetEarningsSummaryHandler(w http.ResponseWriter, r *http.Request) {
	ctxUserID := r.Context().Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Missing userID in context", nil)
		return
	}

	userID := ctxUserID.(string)
	summary, err := c.earningsService.GetEarningsSummary(r.Context(), userID)
	if err != nil {
		utils.Logger.WithError(err).Errorf("Failed to get earnings summary for worker %s", userID)
		utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Could not retrieve earnings summary", err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, summary)
}
