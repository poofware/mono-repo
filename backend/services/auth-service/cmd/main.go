package main

import (
	"context"
	"net/http"

	"github.com/gorilla/mux"
	cron "github.com/robfig/cron/v3"
	"github.com/rs/cors"

	"github.com/poofware/auth-service/internal/app"
	"github.com/poofware/auth-service/internal/config"
	"github.com/poofware/auth-service/internal/controllers"
	auth_repositories "github.com/poofware/auth-service/internal/repositories"
	"github.com/poofware/auth-service/internal/services"
	"github.com/poofware/go-middleware"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
)

func main() {
	utils.InitLogger(config.AppName)
	cfg := config.LoadConfig()
	defer cfg.Close()

	application, err := app.NewApp(cfg)
	if err != nil {
		utils.Logger.Fatal("Failed to initialize application:", err)
	}
	defer application.Close()

	attestRepo := repositories.NewAttestationRepository(application.DB)
	challengeRepo := repositories.NewAttestationChallengeRepository(application.DB)

	var attVerifier *utils.AttestationVerifier
	if cfg.LDFlag_DoRealMobileDeviceAttestation {
		attVerifier, err = utils.NewAttestationVerifier(
			context.Background(),
			cfg.PlayIntegritySAJSON,
			cfg.AppleDeviceCheckKey,
			attestRepo.LookupKey,
			attestRepo.SaveKey,
			challengeRepo.Consume,
		)
		if err != nil {
			utils.Logger.Fatal("Failed to create AttestationVerifier:", err)
		}
	}

	//----------------------------------------------------------------------
	// Repositories
	//----------------------------------------------------------------------
	pmRepo := repositories.NewPropertyManagerRepository(application.DB, cfg.DBEncryptionKey)
	pmLoginRepo := auth_repositories.NewPMLoginAttemptsRepository(application.DB)
	pmTokenRepo := auth_repositories.NewPMTokenRepository(application.DB)

	workerRepo := repositories.NewWorkerRepository(application.DB, cfg.DBEncryptionKey)
	workerLoginRepo := auth_repositories.NewWorkerLoginAttemptsRepository(application.DB)
	workerTokenRepo := auth_repositories.NewWorkerTokenRepository(application.DB)
	pendingDeletionRepo := auth_repositories.NewPendingDeletionRepository(application.DB)

	pmEmailRepo := repositories.NewPMEmailVerificationRepository(application.DB)
	pmSMSRepo := repositories.NewPMSMSVerificationRepository(application.DB)
	workerEmailRepo := repositories.NewWorkerEmailVerificationRepository(application.DB)
	workerSMSRepo := repositories.NewWorkerSMSVerificationRepository(application.DB)

	rateLimitRepo := auth_repositories.NewRateLimitRepository(application.DB)

	//----------------------------------------------------------------------
	// Services
	//----------------------------------------------------------------------
	rateLimiterService := services.NewRateLimiterService(rateLimitRepo, cfg)

	pmAuthService := services.NewPMAuthService(
		pmRepo,
		pmLoginRepo,
		pmTokenRepo,
		pmEmailRepo,
		pmSMSRepo,
		rateLimiterService,
		cfg,
	)

	workerAuthService := services.NewWorkerAuthService(
		workerRepo,
		workerLoginRepo,
		workerTokenRepo,
		workerEmailRepo,
		workerSMSRepo,
		pendingDeletionRepo,
		rateLimiterService,
		challengeRepo,
		cfg,
	)

	verificationCleanupService := services.NewVerificationCleanupService(
		pmEmailRepo,
		pmSMSRepo,
		workerEmailRepo,
		workerSMSRepo,
	)

	tokenCleanupService := services.NewTokenCleanupService(
		pmTokenRepo,
		workerTokenRepo,
	)

	rateLimitCleanupService := services.NewRateLimitCleanupService(rateLimitRepo)

	totpService := services.NewTOTPService(cfg)

	//----------------------------------------------------------------------
	// Controllers
	//----------------------------------------------------------------------
	pmController := controllers.NewPMAuthController(pmAuthService, cfg)
	workerController := controllers.NewWorkerAuthController(workerAuthService, cfg)
	registrationController := controllers.NewRegistrationController(totpService)
	healthController := controllers.NewHealthController(application)

	//----------------------------------------------------------------------
	// Router & Endpoints
	//----------------------------------------------------------------------
	router := mux.NewRouter()

	// Health
	router.HandleFunc("/health", healthController.HealthCheckHandler).Methods("GET")

	// /auth/v1
	authRouter := router.PathPrefix("/auth").Subrouter()
	v1Router := authRouter.PathPrefix("/v1").Subrouter()

	v1Router.HandleFunc("/register/totp_secret", registrationController.GenerateTOTPSecret).Methods("POST")

	// PM endpoints
	v1Router.HandleFunc("/pm/register", pmController.RegisterPM).Methods("POST")
	v1Router.HandleFunc("/pm/login", pmController.LoginPM).Methods("POST")
	v1Router.HandleFunc("/pm/email/valid", pmController.ValidatePMEmail).Methods("POST")
	v1Router.HandleFunc("/pm/phone/valid", pmController.ValidatePMPhone).Methods("POST")
	v1Router.HandleFunc("/pm/refresh_token", pmController.RefreshTokenPM).Methods("POST")

	// Worker endpoints that do NOT require the new mobile attestation middleware
	v1Router.HandleFunc("/worker/register", workerController.RegisterWorker).Methods("POST")
	v1Router.HandleFunc("/worker/email/valid", workerController.ValidateWorkerEmail).Methods("POST")
	v1Router.HandleFunc("/worker/phone/valid", workerController.ValidateWorkerPhone).Methods("POST")
	v1Router.HandleFunc("/worker/challenge", workerController.IssueChallenge).Methods("POST")
	v1Router.HandleFunc("/worker/initiate-deletion", workerController.InitiateDeletion).Methods("POST")
	v1Router.HandleFunc("/worker/confirm-deletion", workerController.ConfirmDeletion).Methods("POST")

	// Now, for worker login & refresh_token, we apply the MobileAttestationMiddleware:
	// The parameter cfg.LDFlag_DoRealMobileDeviceAttestation indicates if we do real or dummy calls.
	workerAttestation := v1Router.PathPrefix("/worker").Subrouter()
	workerAttestation.Use(middleware.MobileAttestationMiddleware(cfg.LDFlag_DoRealMobileDeviceAttestation, attVerifier))
	workerAttestation.HandleFunc("/login", workerController.LoginWorker).Methods("POST")
	workerAttestation.HandleFunc("/refresh_token", workerController.RefreshTokenWorker).Methods("POST")

	// Optionally Protected: use OptionalAuthMiddleware that checks the token if present
	pmOptionalProtected := v1Router.PathPrefix("/pm").Subrouter()
	pmOptionalProtected.Use(middleware.OptionalAuthMiddleware(cfg.RSAPublicKey, cfg.LDFlag_DoRealMobileDeviceAttestation))
	pmOptionalProtected.HandleFunc("/request_email_code", pmController.RequestPMEmailCode).Methods("POST")
	pmOptionalProtected.HandleFunc("/verify_email_code", pmController.VerifyPMEmailCode).Methods("POST")
	pmOptionalProtected.HandleFunc("/request_sms_code", pmController.RequestPMSMSCode).Methods("POST")
	pmOptionalProtected.HandleFunc("/verify_sms_code", pmController.VerifyPMSMSCode).Methods("POST")

	workerOptionalProtected := v1Router.PathPrefix("/worker").Subrouter()
	workerOptionalProtected.Use(middleware.OptionalAuthMiddleware(cfg.RSAPublicKey, cfg.LDFlag_DoRealMobileDeviceAttestation))
	workerOptionalProtected.HandleFunc("/request_email_code", workerController.RequestWorkerEmailCode).Methods("POST")
	workerOptionalProtected.HandleFunc("/verify_email_code", workerController.VerifyWorkerEmailCode).Methods("POST")
	workerOptionalProtected.HandleFunc("/request_sms_code", workerController.RequestWorkerSMSCode).Methods("POST")
	workerOptionalProtected.HandleFunc("/verify_sms_code", workerController.VerifyWorkerSMSCode).Methods("POST")

	// Protected endpoints require a valid token
	pmProtected := v1Router.PathPrefix("/pm").Subrouter()
	pmProtected.Use(middleware.AuthMiddleware(cfg.RSAPublicKey, cfg.LDFlag_DoRealMobileDeviceAttestation))
	pmProtected.HandleFunc("/logout", pmController.LogoutPM).Methods("POST")

	workerProtected := v1Router.PathPrefix("/worker").Subrouter()
	workerProtected.Use(middleware.AuthMiddleware(cfg.RSAPublicKey, cfg.LDFlag_DoRealMobileDeviceAttestation))
	workerProtected.HandleFunc("/logout", workerController.LogoutWorker).Methods("POST")

	//----------------------------------------------------------------------
	// Setup daily cleanup via cron
	//----------------------------------------------------------------------
	c := cron.New()

	// verification codes
	_, schErr1 := c.AddFunc("0 3 * * *", func() {
		if e := verificationCleanupService.CleanupDaily(context.Background()); e != nil {
			utils.Logger.WithError(e).Error("Scheduled verification-codes cleanup failed")
		}
	})
	if schErr1 != nil {
		utils.Logger.WithError(schErr1).Fatal("Failed to schedule verification-codes cleanup job")
	}

	// token cleanup
	_, schErr2 := c.AddFunc("5 3 * * *", func() {
		if e := tokenCleanupService.CleanupDaily(context.Background()); e != nil {
			utils.Logger.WithError(e).Error("Scheduled token cleanup failed")
		}
	})
	if schErr2 != nil {
		utils.Logger.WithError(schErr2).Fatal("Failed to schedule token cleanup job")
	}

	// rate limit counter cleanup
	_, schErr3 := c.AddFunc("10 3 * * *", func() {
		if e := rateLimitCleanupService.CleanupDaily(context.Background()); e != nil {
			utils.Logger.WithError(e).Error("Scheduled rate limit counter cleanup failed")
		}
	})
	if schErr3 != nil {
		utils.Logger.WithError(schErr3).Fatal("Failed to schedule rate limit counter cleanup job")
	}

	c.Start()

	allowedOrigins := []string{cfg.AppUrl}
	if !cfg.LDFlag_CORSHighSecurity {
		allowedOrigins = append(allowedOrigins, utils.CORSLowSecurityAllowedOriginLocalhost)
	}

	co := cors.New(cors.Options{
		AllowedOrigins:   allowedOrigins,
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Authorization", "Content-Type", "X-Platform", "X-Device-ID", "X-Device-Integrity", "X-Key-Id", "ngrok-skip-browser-warning"},
		AllowCredentials: true,
	})

	utils.Logger.Infof("Starting %s on port: %s", cfg.AppName, cfg.AppPort)
	if err := http.ListenAndServe(":"+cfg.AppPort, co.Handler(router)); err != nil {
		utils.Logger.Fatal("Failed to start server:", err)
	}
}
