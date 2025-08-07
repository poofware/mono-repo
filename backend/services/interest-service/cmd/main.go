package main

import (
	"net/http"

	"github.com/gorilla/mux"
	"github.com/rs/cors"
	_ "time/tzdata"

	"github.com/poofware/mono-repo/backend/services/interest-service/internal/app"
	"github.com/poofware/mono-repo/backend/services/interest-service/internal/config"
	"github.com/poofware/mono-repo/backend/services/interest-service/internal/controllers"
	"github.com/poofware/mono-repo/backend/services/interest-service/internal/routes"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

func main() {
	utils.InitLogger(config.AppName)

	// 1) Config
	cfg := config.LoadConfig()
	defer cfg.Close()

	// 2) Core application (services, etc.)
	application := app.NewApp(cfg)
	defer application.Close()

	// 3) Controllers
	healthCtrl   := controllers.NewHealthController(application)
	interestCtrl := controllers.NewInterestController(application.InterestService)

	// 4) Router
	router := mux.NewRouter()
	router.HandleFunc(routes.Health,        healthCtrl.HealthCheckHandler).Methods(http.MethodGet)
	router.HandleFunc(routes.InterestWorker, interestCtrl.SubmitWorkerInterest).Methods(http.MethodPost)
	router.HandleFunc(routes.InterestPM,     interestCtrl.SubmitPMInterest).Methods(http.MethodPost)

	// 5) CORS
	c := cors.New(cors.Options{
		AllowedOrigins:   []string{cfg.AppUrl},
		AllowedMethods:   []string{"GET", "POST", "OPTIONS"},
		AllowedHeaders:   []string{"Content-Type"},
		AllowCredentials: true,
	})

	utils.Logger.Infof("Starting %s on :%s", cfg.AppName, cfg.AppPort)
	if err := http.ListenAndServe(":"+cfg.AppPort, c.Handler(router)); err != nil {
		utils.Logger.Fatal("Server error:", err)
	}
}

