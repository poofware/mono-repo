package controllers

import (
	"context"
	"net/http"

	"github.com/poofware/interest-service/internal/app"
	"github.com/poofware/interest-service/internal/dtos"
	"github.com/poofware/go-utils"
)

type HealthController struct {
	app *app.App
}

func NewHealthController(a *app.App) *HealthController {
	return &HealthController{app: a}
}

func (c *HealthController) HealthCheckHandler(w http.ResponseWriter, r *http.Request) {
	// Probe the only external dependency (SendGrid key length, etc.)
	if err := c.app.InterestService.Ping(context.Background()); err != nil {
		utils.Logger.WithError(err).Error("interest-service unhealthy")
		utils.RespondErrorWithCode(
			w,
			http.StatusServiceUnavailable,
			utils.ErrCodeInternal,
			"Service unhealthy",
			err,
		)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, dtos.HealthCheckResponse{Status: "OK"})
}

