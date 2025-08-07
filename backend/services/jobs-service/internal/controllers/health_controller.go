package controllers

import (
	"context"
	"net/http"

	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/app"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

// HealthController checks DB connectivity, etc.
type HealthController struct {
	app *app.App
}

func NewHealthController(app *app.App) *HealthController {
	return &HealthController{app}
}

// HealthCheckHandler => GET /health
func (c *HealthController) HealthCheckHandler(w http.ResponseWriter, r *http.Request) {
	if err := c.app.DB.Ping(context.Background()); err != nil {
		utils.Logger.WithError(err).Error("jobs-service DB unreachable")
		utils.RespondErrorWithCode(w, http.StatusServiceUnavailable, utils.ErrCodeInternal, "Database unreachable", err, nil)
		return
	}
	resp := dtos.HealthCheckResponse{Status: "OK"}
	utils.RespondWithJSON(w, http.StatusOK, resp)
}

