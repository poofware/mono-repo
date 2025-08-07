// meta-service/services/jobs-service/cmd/main.go

package main

import (
	"context"
	"net/http"
	_ "time/tzdata"

	"github.com/gorilla/mux"
	"github.com/poofware/mono-repo/backend/shared/go-middleware"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
	cron "github.com/robfig/cron/v3"
	"github.com/rs/cors"
	"github.com/sendgrid/sendgrid-go"
	twilio "github.com/twilio/twilio-go"

	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/app"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/config"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/controllers"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/routes"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/services"
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

	defRepo := repositories.NewJobDefinitionRepository(application.DB)
	instRepo := repositories.NewJobInstanceRepository(application.DB)
	propRepo := repositories.NewPropertyRepository(application.DB)
	bldgRepo := repositories.NewPropertyBuildingRepository(application.DB)
	dumpRepo := repositories.NewDumpsterRepository(application.DB)
	workerRepo := repositories.NewWorkerRepository(application.DB, cfg.DBEncryptionKey)
	agentRepo := repositories.NewAgentRepository(application.DB)

	// NEW: unitRepo for tenant tokens
	unitRepo := repositories.NewUnitRepository(application.DB)
	juvRepo := repositories.NewJobUnitVerificationRepository(application.DB)

	openaiSvc := services.NewOpenAIService(cfg.OpenAIAPIKey)

	twClient := twilio.NewRestClientWithParams(twilio.ClientParams{
		Username: cfg.TwilioAccountSID,
		Password: cfg.TwilioAuthToken,
	})
	sgClient := sendgrid.NewSendClient(cfg.SendGridAPIKey)

	// UPDATED: pass unitRepo to jobService
	jobService := services.NewJobService(
		cfg,
		defRepo,
		instRepo,
		propRepo,
		bldgRepo,
		dumpRepo,
		workerRepo,
		agentRepo,
		unitRepo,
		juvRepo,
		openaiSvc,
		twClient,
		sgClient,
	)

	if cfg.LDFlag_SeedDbWithTestData {
		if err := app.SeedAllTestData(
			context.Background(),
			application.DB,
			cfg.DBEncryptionKey,
			propRepo,
			bldgRepo,
			dumpRepo,
			defRepo,
			jobService,
		); err != nil {
			utils.Logger.WithError(err).Fatal("Failed to seed test data")
		} else {
			utils.Logger.Info("Seeded test data successfully")
		}
	}

	escalationService := services.NewJobEscalationService(
		cfg,
		defRepo,
		instRepo,
		workerRepo,
		propRepo,
		agentRepo,
		jobService,
	)
	jobScheduler := services.NewJobSchedulerService(cfg, defRepo, instRepo, propRepo)

	jobsController := controllers.NewJobsController(jobService)
	healthController := controllers.NewHealthController(application)
	jobDefsController := controllers.NewJobDefinitionsController(jobService)

	router := mux.NewRouter()

	// Public
	router.HandleFunc(routes.Health, healthController.HealthCheckHandler).Methods(http.MethodGet)

	secured := router.NewRoute().Subrouter()
	secured.Use(middleware.AuthMiddleware(cfg.RSAPublicKey, cfg.LDFlag_DoRealMobileDeviceAttestation))

	secured.HandleFunc(routes.JobsOpen, jobsController.ListJobsHandler).Methods(http.MethodGet)
	secured.HandleFunc(routes.JobsMy, jobsController.ListMyJobsHandler).Methods(http.MethodGet)
	secured.HandleFunc(routes.JobsUnaccept, jobsController.UnacceptJobHandler).Methods(http.MethodPost)
	secured.HandleFunc(routes.JobsCancel, jobsController.CancelJobHandler).Methods(http.MethodPost)

	secured.HandleFunc(routes.JobsDefinitionStatus, jobDefsController.SetDefinitionStatusHandler).Methods(http.MethodPatch, http.MethodPut)
	secured.HandleFunc(routes.JobsDefinitionCreate, jobDefsController.CreateDefinitionHandler).Methods(http.MethodPost)

	attestationRepo := repositories.NewAttestationRepository(application.DB)
	challengeRepo := repositories.NewAttestationChallengeRepository(application.DB)
	attVerifier, attErr := utils.NewAttestationVerifier(
		context.Background(),
		cfg.PlayIntegritySAJSON,
		cfg.AppleDeviceCheckKey,
		attestationRepo.LookupKey,
		attestationRepo.SaveKey,
		challengeRepo.Consume,
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
	locationSecured.HandleFunc(routes.JobsAccept, jobsController.AcceptJobHandler).Methods(http.MethodPost)
	locationSecured.HandleFunc(routes.JobsVerifyUnitPhoto, jobsController.VerifyPhotoHandler).Methods(http.MethodPost)
	locationSecured.HandleFunc(routes.JobsDumpBags, jobsController.DumpBagsHandler).Methods(http.MethodPost)

	c := cron.New()
	_, dailyErr := c.AddFunc("5 0 * * *", func() {
		if e := jobScheduler.RunDailyWindowMaintenance(context.Background()); e != nil {
			utils.Logger.WithError(e).Error("Scheduled daily maintenance failed")
		}
	})
	if dailyErr != nil {
		utils.Logger.WithError(dailyErr).Fatal("Failed to schedule daily maintenance cron")
	}

	_, jcasErr := c.AddFunc("@every 2m", func() {
		if e := escalationService.RunEscalationCheck(context.Background()); e != nil {
			utils.Logger.WithError(e).Error("JCAS escalation check failed")
		}
	})
	if jcasErr != nil {
		utils.Logger.WithError(jcasErr).Fatal("Failed to schedule JCAS escalation cron")
	}
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
