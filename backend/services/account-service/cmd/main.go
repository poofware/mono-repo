package main

import (
	"context"
	"net/http"
	"time"

	"github.com/gorilla/mux"
	"github.com/rs/cors"
	_ "time/tzdata" // Load timezone data

	"github.com/poofware/account-service/internal/app"
	"github.com/poofware/account-service/internal/config"
	"github.com/poofware/account-service/internal/controllers"
	"github.com/poofware/account-service/internal/routes"
	"github.com/poofware/account-service/internal/services"
	"github.com/poofware/go-middleware"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
)

func main() {
	utils.InitLogger(config.AppName)
	cfg := config.LoadConfig()

	application, err := app.NewApp(cfg)
	if err != nil {
		utils.Logger.Fatal("Failed to initialize the application:", err)
	}
	defer application.Close()

	// Repositories
	workerRepo := repositories.NewWorkerRepository(application.DB, cfg.DBEncryptionKey)
	pmRepo := repositories.NewPropertyManagerRepository(application.DB, cfg.DBEncryptionKey)
	propRepo := repositories.NewPropertyRepository(application.DB)
	bldgRepo := repositories.NewPropertyBuildingRepository(application.DB)
	dumpRepo := repositories.NewDumpsterRepository(application.DB)
	unitRepo := repositories.NewUnitRepository(application.DB)
	jobDefRepo := repositories.NewJobDefinitionRepository(application.DB)
	adminRepo := repositories.NewAdminRepository(application.DB, cfg.DBEncryptionKey)
	auditRepo := repositories.NewAdminAuditLogRepository(application.DB)

	if cfg.LDFlag_SeedDbWithTestAccounts {
		if err := app.SeedAllTestAccounts(workerRepo, pmRepo, adminRepo); err != nil {
			utils.Logger.Fatal("Failed to seed default accounts:", err)
		}
	}

	workerSMSRepo := repositories.NewWorkerSMSVerificationRepository(application.DB)

	// Services
	pmService := services.NewPMService(pmRepo, propRepo, bldgRepo, unitRepo, dumpRepo)
	workerService := services.NewWorkerService(cfg, workerRepo, workerSMSRepo)
	workerStripeService := services.NewWorkerStripeService(cfg, workerRepo)
	stripeWebhookCheckService := services.NewStripeWebhookCheckService()
	adminService := services.NewAdminService(pmRepo, propRepo, bldgRepo, unitRepo, dumpRepo, jobDefRepo, auditRepo, adminRepo)

	checkrService, err := services.NewCheckrService(cfg, workerRepo)
	if err != nil {
		utils.Logger.Fatal("Failed to initialize CheckrService:", err)
	}

	// Controllers
	pmController := controllers.NewPMController(pmService)
	adminController := controllers.NewAdminController(adminService)

	stripeWebhookController := controllers.NewStripeWebhookController(cfg, workerStripeService, stripeWebhookCheckService)
	healthController := controllers.NewHealthController(application)
	workerController := controllers.NewWorkerController(workerService)
	workerStripeController := controllers.NewWorkerStripeController(workerStripeService)

	checkrWebhookController := controllers.NewCheckrWebhookController(checkrService)
	workerCheckrController := controllers.NewWorkerCheckrController(checkrService)

	workerUnversalLinksStripeController := controllers.NewWorkerUniversalLinksController(cfg.AppUrl)
	wellKnownController := controllers.NewWellKnownController()

	// Start dynamic Checkr webhook if needed
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := checkrService.Start(ctx); err != nil {
		utils.Logger.WithError(err).Fatal("Failed to start CheckrService (dynamic webhook)")
	}
	defer func() {
		// On shutdown, remove the dynamic Checkr webhook
		stopCtx, stopCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer stopCancel()
		if err := checkrService.Stop(stopCtx); err != nil {
			utils.Logger.WithError(err).Error("Failed to stop CheckrService (remove webhook)")
		}
	}()

	stripeCtx, stripeCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer stripeCancel()
	if err := workerStripeService.Start(stripeCtx); err != nil {
		utils.Logger.WithError(err).Fatal("Failed to start Stripe dynamic webhooks")
	}
	defer func() {
		stopCtx, stopCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer stopCancel()
		_ = workerStripeService.Stop(stopCtx) // already logs on error
	}()

	// Router
	router := mux.NewRouter()

	// Health
	router.HandleFunc(routes.Health, healthController.HealthCheckHandler).Methods(http.MethodGet)

	// Public universal link metadata well-known
	router.HandleFunc(routes.WellKnownAppleAppSiteAssociation, wellKnownController.AppleAppSiteAssociationHandler).Methods(http.MethodGet)
	router.HandleFunc(routes.WellKnownAssetLinksJson, wellKnownController.AssetLinksHandler).Methods(http.MethodGet)

	// Public universal link endpoints
	router.HandleFunc(routes.WorkerUniversalLinkStripeConnectReturn, workerUnversalLinksStripeController.WorkerStripeConnectReturnHandler).Methods(http.MethodGet)
	router.HandleFunc(routes.WorkerUniversalLinkStripeConnectRefresh, workerUnversalLinksStripeController.WorkerStripeConnectRefreshHandler).Methods(http.MethodGet)
	router.HandleFunc(routes.WorkerUniversalLinkStripeIdentityReturn, workerUnversalLinksStripeController.WorkerStripeIdentityReturnHandler).Methods(http.MethodGet)

	// Public stripe connect flow redirect routes
	router.HandleFunc(routes.WorkerStripeConnectFlowReturn, workerStripeController.ConnectFlowReturnHandler).Methods(http.MethodGet)
	router.HandleFunc(routes.WorkerStripeConnectFlowRefresh, workerStripeController.ConnectFlowRefreshHandler).Methods(http.MethodGet)
	router.HandleFunc(routes.WorkerStripeIdentityFlowReturn, workerStripeController.IdentityFlowReturnHandler).Methods(http.MethodGet)

	// Stripe webhook routes
	router.HandleFunc(routes.AccountStripeWebhook, stripeWebhookController.WebhookHandler).Methods(http.MethodPost)
	router.HandleFunc(routes.AccountStripeWebhookCheck, stripeWebhookController.WebhookCheckHandler).Methods(http.MethodGet)

	// Checkr webhook route
	router.HandleFunc(routes.CheckrWebhook, checkrWebhookController.HandleWebhook).Methods(http.MethodPost)

	// Protected routes (JWT middleware)
	secured := router.NewRoute().Subrouter()
	secured.Use(middleware.AuthMiddleware(cfg.RSAPublicKey, cfg.LDFlag_DoRealMobileDeviceAttestation))

	secured.HandleFunc(routes.WorkerBase, workerController.GetWorkerHandler).Methods(http.MethodGet)
	secured.HandleFunc(routes.WorkerBase, workerController.PatchWorkerHandler).Methods(http.MethodPatch)
	secured.HandleFunc(routes.WorkerSubmitPersonalInfo, workerController.SubmitPersonalInfoHandler).Methods(http.MethodPost)

	secured.HandleFunc(routes.PMBase, pmController.GetPMHandler).Methods(http.MethodGet)
	secured.HandleFunc(routes.PMProperties, pmController.ListPropertiesHandler).Methods(http.MethodGet)

	// Worker Stripe
	secured.HandleFunc(routes.WorkerStripeConnectFlowURL, workerStripeController.ConnectFlowURLHandler).Methods(http.MethodGet)
	secured.HandleFunc(routes.WorkerStripeConnectFlowStatus, workerStripeController.ConnectFlowStatusHandler).Methods(http.MethodGet)
	secured.HandleFunc(routes.WorkerStripeIdentityFlowURL, workerStripeController.IdentityFlowURLHandler).Methods(http.MethodGet)
	secured.HandleFunc(routes.WorkerStripeIdentityFlowStatus, workerStripeController.IdentityFlowStatusHandler).Methods(http.MethodGet)
	secured.HandleFunc(routes.WorkerStripeExpressLoginLink, workerStripeController.ExpressLoginLinkHandler).Methods(http.MethodGet)

	// Worker Checkr
	secured.HandleFunc(routes.WorkerCheckrInvitation, workerCheckrController.CreateInvitationHandler).Methods(http.MethodPost)
	secured.HandleFunc(routes.WorkerCheckrStatus, workerCheckrController.GetCheckrStatusHandler).Methods(http.MethodGet)
	secured.HandleFunc(routes.WorkerCheckrReportETA, workerCheckrController.GetCheckrReportETAHandler).Methods(http.MethodGet)
	secured.HandleFunc(routes.WorkerCheckrOutcome, workerCheckrController.GetCheckrOutcomeHandler).Methods(http.MethodGet)
	secured.HandleFunc(routes.WorkerCheckrSessionToken, workerCheckrController.CreateSessionTokenHandler).Methods(http.MethodGet)

	// Admin Routes (now using standard AuthMiddleware)
	secured.HandleFunc(routes.AdminBase+routes.AdminPM, adminController.CreatePropertyManagerHandler).Methods(http.MethodPost)
	secured.HandleFunc(routes.AdminBase+routes.AdminPM, adminController.UpdatePropertyManagerHandler).Methods(http.MethodPatch)
	secured.HandleFunc(routes.AdminBase+routes.AdminPM, adminController.DeletePropertyManagerHandler).Methods(http.MethodDelete)
	secured.HandleFunc(routes.AdminBase+routes.AdminPMSearch, adminController.SearchPropertyManagersHandler).Methods(http.MethodPost)
	secured.HandleFunc(routes.AdminBase+routes.AdminPMSnapshot, adminController.GetPropertyManagerSnapshotHandler).Methods(http.MethodPost)

	secured.HandleFunc(routes.AdminBase+routes.AdminProperties, adminController.CreatePropertyHandler).Methods(http.MethodPost)
	secured.HandleFunc(routes.AdminBase+routes.AdminProperties, adminController.UpdatePropertyHandler).Methods(http.MethodPatch)
	secured.HandleFunc(routes.AdminBase+routes.AdminProperties, adminController.DeletePropertyHandler).Methods(http.MethodDelete)

	secured.HandleFunc(routes.AdminBase+routes.AdminBuildings, adminController.CreateBuildingHandler).Methods(http.MethodPost)
	secured.HandleFunc(routes.AdminBase+routes.AdminBuildings, adminController.UpdateBuildingHandler).Methods(http.MethodPatch)
	secured.HandleFunc(routes.AdminBase+routes.AdminBuildings, adminController.DeleteBuildingHandler).Methods(http.MethodDelete)

	secured.HandleFunc(routes.AdminBase+routes.AdminUnits, adminController.CreateUnitHandler).Methods(http.MethodPost)
	secured.HandleFunc(routes.AdminBase+routes.AdminUnits, adminController.UpdateUnitHandler).Methods(http.MethodPatch)
	secured.HandleFunc(routes.AdminBase+routes.AdminUnits, adminController.DeleteUnitHandler).Methods(http.MethodDelete)

	secured.HandleFunc(routes.AdminBase+routes.AdminDumpsters, adminController.CreateDumpsterHandler).Methods(http.MethodPost)
	secured.HandleFunc(routes.AdminBase+routes.AdminDumpsters, adminController.UpdateDumpsterHandler).Methods(http.MethodPatch)
	secured.HandleFunc(routes.AdminBase+routes.AdminDumpsters, adminController.DeleteDumpsterHandler).Methods(http.MethodDelete)

	allowedOrigins := []string{cfg.AppUrl}
	if !cfg.LDFlag_CORSHighSecurity {
		allowedOrigins = append(allowedOrigins, utils.CORSLowSecurityAllowedOriginLocalhost)
	}

	// CORS config
	c := cors.New(cors.Options{
		AllowedOrigins:   allowedOrigins,
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Authorization", "Content-Type", "X-Platform", "X-Device-ID", "X-Device-Integrity", "X-Key-Id", "ngrok-skip-browser-warning"},
		AllowCredentials: true,
	})

	utils.Logger.Infof("Starting %s on port: %s", cfg.AppName, cfg.AppPort)
	if err := http.ListenAndServe(":"+cfg.AppPort, c.Handler(router)); err != nil {
		utils.Logger.Fatal("Failed to start server:", err)
	}
}