// meta-service/services/jobs-service/cmd/main.go

package main

import (
	"context"
	"net/http"
	_ "time/tzdata"

	"github.com/gorilla/mux"
	"github.com/poofware/go-middleware"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
	cron "github.com/robfig/cron/v3"
	"github.com/rs/cors"
	"github.com/sendgrid/sendgrid-go"
	twilio "github.com/twilio/twilio-go"

	"github.com/poofware/jobs-service/internal/app"
	"github.com/poofware/jobs-service/internal/config"
	"github.com/poofware/jobs-service/internal/controllers"
	"github.com/poofware/jobs-service/internal/routes"
	"github.com/poofware/jobs-service/internal/services"
)

func main() {
	utils.InitLogger(config.AppName)
	cfg := config.LoadConfig()
	defer cfg.Close()

	application, err := app.NewApp(cfg)
	if err != nil {
		utils.Logger.Fatal("Failed to initialize jobs-service:", err)
	}
	defer application.Close()

	// --- Repositories ---
	defRepo := repositories.NewJobDefinitionRepository(application.DB)
	instRepo := repositories.NewJobInstanceRepository(application.DB)
	propRepo := repositories.NewPropertyRepository(application.DB)
	bldgRepo := repositories.NewPropertyBuildingRepository(application.DB)
	dumpRepo := repositories.NewDumpsterRepository(application.DB)
	workerRepo := repositories.NewWorkerRepository(application.DB, cfg.DBEncryptionKey)
	agentRepo := repositories.NewAgentRepository(application.DB)
	unitRepo := repositories.NewUnitRepository(application.DB)
	// New repositories for admin service
	adminRepo := repositories.NewAdminRepository(application.DB, cfg.DBEncryptionKey)
	auditRepo := repositories.NewAdminAuditLogRepository(application.DB)
	pmRepo := repositories.NewPropertyManagerRepository(application.DB, cfg.DBEncryptionKey)

	// --- Services ---
	twClient := twilio.NewRestClientWithParams(twilio.ClientParams{
		Username: cfg.TwilioAccountSID,
		Password: cfg.TwilioAuthToken,
	})
	sgClient := sendgrid.NewSendClient(cfg.SendGridAPIKey)

	jobService := services.NewJobService(
		cfg, defRepo, instRepo, propRepo, bldgRepo, dumpRepo,
		workerRepo, agentRepo, unitRepo, twClient, sgClient,
	)
	// New admin service
	adminJobService := services.NewAdminJobService(
		adminRepo, auditRepo, defRepo, instRepo, pmRepo, propRepo, jobService,
	)

	if cfg.LDFlag_SeedDbWithTestData {
		if err := app.SeedDefaultAdmin(adminRepo); err != nil {
			utils.Logger.WithError(err).Fatal("Failed to seed default admin")
		}
		if err := app.SeedAllTestData(
			context.Background(), application.DB, cfg.DBEncryptionKey,
			propRepo, bldgRepo, dumpRepo, defRepo, jobService,
		); err != nil {
			utils.Logger.WithError(err).Fatal("Failed to seed test data")
		} else {
			utils.Logger.Info("Seeded test data successfully")
		}
	}

	escalationService := services.NewJobEscalationService(cfg, defRepo, instRepo, workerRepo, propRepo, agentRepo, jobService)
	jobScheduler := services.NewJobSchedulerService(cfg, defRepo, instRepo, propRepo)

	// --- Controllers ---
	jobsController := controllers.NewJobsController(jobService)
	healthController := controllers.NewHealthController(application)
	jobDefsController := controllers.NewJobDefinitionsController(jobService)
	adminJobsController := controllers.NewAdminJobsController(adminJobService) // New

	// --- Router ---
	router := mux.NewRouter()
	router.HandleFunc(routes.Health, healthController.HealthCheckHandler).Methods(http.MethodGet)

	secured := router.NewRoute().Subrouter()
	secured.Use(middleware.AuthMiddleware(cfg.RSAPublicKey, cfg.LDFlag_DoRealMobileDeviceAttestation))

	// Worker and PM routes
	secured.HandleFunc(routes.JobsOpen, jobsController.ListJobsHandler).Methods(http.MethodGet)
	secured.HandleFunc(routes.JobsMy, jobsController.ListMyJobsHandler).Methods(http.MethodGet)
	secured.HandleFunc(routes.JobsUnaccept, jobsController.UnacceptJobHandler).Methods(http.MethodPost)
	secured.HandleFunc(routes.JobsCancel, jobsController.CancelJobHandler).Methods(http.MethodPost)
	secured.HandleFunc(routes.JobsDefinitionStatus, jobDefsController.SetDefinitionStatusHandler).Methods(http.MethodPatch, http.MethodPut)
	secured.HandleFunc(routes.JobsDefinitionCreate, jobDefsController.CreateDefinitionHandler).Methods(http.MethodPost)
	secured.HandleFunc(routes.JobsPMInstances, jobDefsController.ListJobsForPropertyHandler).Methods(http.MethodPost)

	// Admin routes (NEW)
	secured.HandleFunc(routes.AdminJobDefinitions, adminJobsController.AdminCreateJobDefinitionHandler).Methods(http.MethodPost)
	secured.HandleFunc(routes.AdminJobDefinitions, adminJobsController.AdminUpdateJobDefinitionHandler).Methods(http.MethodPatch)
	secured.HandleFunc(routes.AdminJobDefinitions, adminJobsController.AdminSoftDeleteJobDefinitionHandler).Methods(http.MethodDelete)

	attestationRepo := repositories.NewAttestationRepository(application.DB)
	challengeRepo := repositories.NewAttestationChallengeRepository(application.DB)
	attVerifier, attErr := utils.NewAttestationVerifier(
		context.Background(), cfg.PlayIntegritySAJSON, cfg.AppleDeviceCheckKey,
		attestationRepo.LookupKey, attestationRepo.SaveKey, challengeRepo.Consume,
	)
	if attErr != nil {
		utils.Logger.Fatal("Failed to create attestation verifier:", attErr)
	}

	locationSecured := router.NewRoute().Subrouter()
	locationSecured.Use(
		middleware.AuthMiddleware(cfg.RSAPublicKey, cfg.LDFlag_DoRealMobileDeviceAttestation),
		middleware.MobileAttestationMiddleware(cfg.LDFlag_DoRealMobileDeviceAttestation, attVerifier),
	)
	locationSecured.HandleFunc(routes.JobsStart, jobsController.StartJobHandler).Methods(http.MethodPost)
	locationSecured.HandleFunc(routes.JobsComplete, jobsController.CompleteJobHandler).Methods(http.MethodPost)
	locationSecured.HandleFunc(routes.JobsAccept, jobsController.AcceptJobHandler).Methods(http.MethodPost)

	// --- Cron Jobs & Server Start ---
	c := cron.New()
	_, _ = c.AddFunc("5 0 * * *", func() {
		if e := jobScheduler.RunDailyWindowMaintenance(context.Background()); e != nil {
			utils.Logger.WithError(e).Error("Scheduled daily maintenance failed")
		}
	})
	_, _ = c.AddFunc("@every 2m", func() {
		if e := escalationService.RunEscalationCheck(context.Background()); e != nil {
			utils.Logger.WithError(e).Error("JCAS escalation check failed")
		}
	})
	c.Start()

	allowedOrigins := []string{cfg.AppUrl}
	if !cfg.LDFlag_CORSHighSecurity {
		allowedOrigins = append(allowedOrigins, utils.CORSLowSecurityAllowedOriginLocalhost)
	}
	co := cors.New(cors.Options{
		AllowedOrigins:   allowedOrigins,
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Authorization", "Content-Type", "X-Platform", "X-Device-ID", "X-Device-Integrity", "X-Key-Id", "ngrok-skip-browser-warning"},
		AllowCredentials: true,
	})

	utils.Logger.Infof("Starting %s on port: %s", cfg.AppName, cfg.AppPort)
	if err := http.ListenAndServe(":"+cfg.AppPort, co.Handler(router)); err != nil {
		utils.Logger.Fatal("jobs-service failed to start:", err)
	}
}