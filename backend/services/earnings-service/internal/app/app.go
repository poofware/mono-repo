package app

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v4/pgxpool"
	"github.com/poofware/mono-repo/backend/services/earnings-service/internal/config"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

const (
	maxRetries     = 5
	connectTimeout = 5 * time.Second
	initialBackoff = 500 * time.Millisecond
)

type App struct {
	Config *config.Config
	DB     *pgxpool.Pool
}

func NewApp(cfg *config.Config) (*App, error) {
	effectiveURL := cfg.DBUrl
	if cfg.LDFlag_UsingIsolatedSchema {
		var err error
		effectiveURL, err = utils.WithIsolatedRole(cfg.DBUrl, cfg.UniqueRunnerID, cfg.UniqueRunNumber)
		if err != nil {
			return nil, err
		}
		utils.Logger.Infof("Using isolated schema for earnings-service; role=%s", strings.ToLower(cfg.UniqueRunnerID+"-"+cfg.UniqueRunNumber))
	} else {
		utils.Logger.Info("Isolated schema disabled; using public schema for earnings-service.")
	}

	var (
		dbPool  *pgxpool.Pool
		err     error
		backoff = initialBackoff
	)

	for i := 1; i <= maxRetries; i++ {
		ctx, cancel := context.WithTimeout(context.Background(), connectTimeout)
		defer cancel()

		dbPool, err = newDBPool(ctx, effectiveURL)
		if err == nil {
			utils.Logger.Infof("earnings-service connected to DB on attempt %d", i)
			break
		}

		utils.Logger.WithError(err).Warnf(
			"Failed DB connect on attempt %d/%d. Retrying in %v...",
			i, maxRetries, backoff,
		)

		if i == maxRetries {
			return nil, fmt.Errorf("unable to connect after %d attempts: %w", maxRetries, err)
		}
		time.Sleep(backoff)
		backoff *= 2
	}

	app := &App{
		Config: cfg,
		DB:     dbPool,
	}
	return app, nil
}

func (a *App) Close() {
	if a.DB != nil {
		a.DB.Close()
		utils.Logger.Info("earnings-service DB connection closed.")
	}
}

func newDBPool(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, err
	}
	cfg.MaxConnIdleTime = 2 * time.Minute
	cfg.HealthCheckPeriod = 30 * time.Second
	return pgxpool.ConnectConfig(ctx, cfg)
}
