package controllers

import (
    "context"
    "net/http"

    "github.com/poofware/mono-repo/backend/services/auth-service/internal/app"
    "github.com/poofware/mono-repo/backend/services/auth-service/internal/dtos"
    "github.com/poofware/mono-repo/backend/shared/go-utils"
)

type HealthController struct {
    app *app.App
}

func NewHealthController(app *app.App) *HealthController {
    return &HealthController{
        app: app,
    }
}

func (c *HealthController) HealthCheckHandler(w http.ResponseWriter, r *http.Request) {
    // Check database connectivity
    if err := c.app.DB.Ping(context.Background()); err != nil {
        utils.Logger.WithError(err).Error("Database unreachable")
        utils.RespondErrorWithCode(
            w,
            http.StatusServiceUnavailable,
            utils.ErrCodeInternal,
            "Database unreachable",
            err,
        )
        return
    }

    // Everything is OK
    resp := dtos.HealthCheckResponse{
        Status: "OK",
    }
    utils.RespondWithJSON(w, http.StatusOK, resp)
}

