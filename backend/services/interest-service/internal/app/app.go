package app

import (
    "github.com/poofware/mono-repo/backend/services/interest-service/internal/config"
    "github.com/poofware/mono-repo/backend/services/interest-service/internal/services"
    "github.com/poofware/mono-repo/backend/shared/go-utils"
)

// App struct holds references to config & services.
type App struct {
    Config          *config.Config
    InterestService services.InterestService
}

// NewApp sets up the core application context (no DB needed).
func NewApp(cfg *config.Config) *App {
    utils.Logger.Info("Initializing interest-service App")

    // Construct our service(s)
    interestSvc := services.NewInterestService(cfg)

    return &App{
        Config:          cfg,
        InterestService: interestSvc,
    }
}

// Close is a no-op here but included for consistency.
func (a *App) Close() {
    utils.Logger.Info("interest-service app shutting down.")
}

