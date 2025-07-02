package app

import (
	"context"
	"fmt"
	"time"
	"strings"

	"github.com/jackc/pgx/v4/pgxpool"
	"github.com/poofware/auth-service/internal/config"
	"github.com/poofware/go-utils"
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
	// Decide which URL to use (shared vs. isolated schema).
	effectiveURL := cfg.DBUrl
	if cfg.LDFlag_UsingIsolatedSchema {
		var err error
		effectiveURL, err = utils.WithIsolatedRole(
			cfg.DBUrl,
			cfg.UniqueRunnerID,
			cfg.UniqueRunNumber,
		)
		if err != nil {
			return nil, err
		}
		utils.Logger.Infof("Using isolated schema; connecting as role %s",
		strings.ToLower(cfg.UniqueRunnerID+"-"+cfg.UniqueRunNumber))
	} else {
		utils.Logger.Info("Isolated schema disabled; using public schema.")
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
			utils.Logger.Infof("Successfully connected to database on attempt %d", i)
			break
		}

		utils.Logger.WithError(err).Warnf(
			"Failed to connect to database on attempt %d/%d. Retrying in %v...",
			i, maxRetries, backoff,
		)

		if i == maxRetries {
			return nil, fmt.Errorf("unable to connect to database after %d attempts: %w", maxRetries, err)
		}

		time.Sleep(backoff)
		backoff *= 2
	}

	return &App{
		Config: cfg,
		DB:     dbPool,
	}, nil
}

func (a *App) Close() {
	if a.DB != nil {
		a.DB.Close()
		utils.Logger.Info("Database connection closed.")
	}
}

// newDBPool constructs the pgx pool with production‑safe settings.
//
//   • MaxConnIdleTime     – closes idle sockets *before* Fly’s proxy (≈60 s)
//   • HealthCheckPeriod   – background “SELECT 1” keeps every conn warm
//
// Call this from NewApp() or anywhere you previously used pgxpool.Connect().
func newDBPool(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) {
    cfg, err := pgxpool.ParseConfig(databaseURL)
    if err != nil {
        return nil, err
    }

    // ────────────────────────────────────────────────────────────
    // Production hardening knobs
    // ────────────────────────────────────────────────────────────
    cfg.MaxConnIdleTime   = 2 * time.Minute  // retire before Fly proxy kills it
    cfg.HealthCheckPeriod = 30 * time.Second // cheap keep‑alive on every socket

    // (Optional) tune parallelism
    // cfg.MaxConns = int32(runtime.NumCPU() * 4)

    return pgxpool.ConnectConfig(ctx, cfg)
}
