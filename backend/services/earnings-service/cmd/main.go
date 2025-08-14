package main

import (
	"context"
	"net/http"
	"time"

	"github.com/gorilla/mux"
	"github.com/poofware/mono-repo/backend/services/earnings-service/internal/app"
	"github.com/poofware/mono-repo/backend/services/earnings-service/internal/config"
	"github.com/poofware/mono-repo/backend/services/earnings-service/internal/constants"
	"github.com/poofware/mono-repo/backend/services/earnings-service/internal/controllers"
	internal_repositories "github.com/poofware/mono-repo/backend/services/earnings-service/internal/repositories"
	"github.com/poofware/mono-repo/backend/services/earnings-service/internal/routes"
	"github.com/poofware/mono-repo/backend/services/earnings-service/internal/services"
	"github.com/poofware/mono-repo/backend/shared/go-middleware"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
	"github.com/robfig/cron/v3"
	"github.com/rs/cors"
	_ "time/tzdata"
)

func main() {
	utils.InitLogger(config.AppName)
	cfg := config.LoadConfig()
	defer cfg.Close()

	application, err := app.NewApp(cfg)
	if err != nil {
		utils.Logger.Fatal("Failed to initialize earnings-service:", err)
	}
	defer application.Close()

	// Repositories
	jobInstRepo := repositories.NewJobInstanceRepository(application.DB)
	defRepo := repositories.NewJobDefinitionRepository(application.DB)
	payoutRepo := internal_repositories.NewWorkerPayoutRepository(application.DB)
	workerRepo := repositories.NewWorkerRepository(application.DB, cfg.DBEncryptionKey)
	propRepo := repositories.NewPropertyRepository(application.DB) // NEW

	if cfg.LDFlag_SeedDbWithTestData {
		if err := app.SeedAllTestData(context.Background(), workerRepo, jobInstRepo, payoutRepo); err != nil {
			utils.Logger.Fatal("Failed to seed default payouts:", err)
		}
	}

	// Services
	payoutService := services.NewPayoutService(cfg, workerRepo, jobInstRepo, payoutRepo)
	// MODIFIED: Inject PayoutService into EarningsService
	earningsService := services.NewEarningsService(cfg, jobInstRepo, payoutRepo, defRepo, propRepo, payoutService)
	webhookCheckService := services.NewStripeWebhookCheckService()

	// Start dynamic webhook manager
	if err := payoutService.Start(context.Background()); err != nil {
		utils.Logger.WithError(err).Fatal("Failed to start PayoutService (dynamic webhooks)")
	}
	defer func() {
		if err := payoutService.Stop(context.Background()); err != nil {
			utils.Logger.WithError(err).Error("Error stopping PayoutService")
		}
	}()

	// Controllers
	healthController := controllers.NewHealthController(application)
	earningsController := controllers.NewEarningsController(earningsService)
	stripeWebhookController := controllers.NewStripeWebhookController(cfg, payoutService, webhookCheckService)

	// Router setup
	router := mux.NewRouter()

	// Public Routes
	router.HandleFunc(routes.Health, healthController.HealthCheckHandler).Methods(http.MethodGet)
	router.HandleFunc(routes.EarningsStripeWebhook, stripeWebhookController.WebhookHandler).Methods(http.MethodPost)
	router.HandleFunc(routes.EarningsStripeWebhookCheck, stripeWebhookController.WebhookCheckHandler).Methods(http.MethodGet)

	// Secured routes for workers
	secured := router.NewRoute().Subrouter()
	secured.Use(middleware.AuthMiddleware(cfg.RSAPublicKey, cfg.LDFlag_DoRealMobileDeviceAttestation))
	secured.HandleFunc(routes.EarningsSummary, earningsController.GetEarningsSummaryHandler).Methods(http.MethodGet)

	// Cron job setup
	c := cron.New(cron.WithLocation(time.UTC)) // Use UTC for cron scheduling

	// Conditionally set cron specs based on LaunchDarkly flag
	aggSpec := constants.PayoutAggregationCronSpec
	procSpec := constants.PayoutProcessingCronSpec
	if cfg.LDFlag_UseShortPayPeriod {
		aggSpec = constants.ShortPayoutAggregationCronSpec
		procSpec = constants.ShortPayoutProcessingCronSpec
		utils.Logger.Warnf("Using short pay period cron specs: agg='%s', proc='%s'", aggSpec, procSpec)
	}

	// Schedule payout aggregation.
	_, err = c.AddFunc(aggSpec, func() {
		ctx, cancel := context.WithTimeout(context.Background(), constants.PayoutAggregationJobTimeout)
		defer cancel()
		utils.Logger.Info("Starting payout aggregation cron job...")
		if err := payoutService.AggregateAndCreatePayouts(ctx); err != nil {
			utils.Logger.WithError(err).Error("Failed to aggregate weekly payouts")
		}
	})
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to schedule payout aggregation cron")
	}

	// Schedule pending payout processing.
	_, err = c.AddFunc(procSpec, func() {
		ctx, cancel := context.WithTimeout(context.Background(), constants.PayoutProcessingJobTimeout)
		defer cancel()
		utils.Logger.Info("Starting pending payout processing cron job...")
		if err := payoutService.ProcessPendingPayouts(ctx); err != nil {
			utils.Logger.WithError(err).Error("Failed to process pending payouts")
		}
	})
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to schedule pending payout processing cron")
	}

	c.Start()
	utils.Logger.Info("Scheduled payout cron jobs")

	allowedOrigins := []string{cfg.AppUrl}
	if !cfg.LDFlag_CORSHighSecurity {
		allowedOrigins = append(allowedOrigins, utils.CORSLowSecurityAllowedOriginLocalhost)
	}

	co := cors.New(cors.Options{
		AllowedOrigins:   allowedOrigins,
		AllowedMethods:   []string{"GET", "POST", "OPTIONS"},
		AllowedHeaders:   []string{"Authorization", "Content-Type", "X-Platform", "X-Device-ID", "X-Device-Integrity", "X-Key-Id", "ngrok-skip-browser-warning"},
		AllowCredentials: true,
	})

	utils.Logger.Infof("Starting %s on port: %s", cfg.AppName, cfg.AppPort)
	if err := http.ListenAndServe(":"+cfg.AppPort, co.Handler(router)); err != nil {
		utils.Logger.Fatal("earnings-service failed to start:", err)
	}
}
