package controllers

import (
	"io"
	"net/http"

	"github.com/poofware/account-service/internal/services"
	"github.com/poofware/go-utils"
)

type CheckrWebhookController struct {
	checkrService *services.CheckrService
}

func NewCheckrWebhookController(checkrService *services.CheckrService) *CheckrWebhookController {
	return &CheckrWebhookController{checkrService: checkrService}
}

func (c *CheckrWebhookController) HandleWebhook(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		utils.Logger.WithError(err).Error("Failed to read Checkr webhook body")
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	sigHeader := r.Header.Get("X-Checkr-Signature")
	if sigHeader == "" {
		utils.Logger.Error("Missing X-Checkr-Signature header")
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	if !c.checkrService.VerifyWebhookSignature(body, sigHeader) {
		utils.Logger.Error("Checkr webhook signature verification failed")
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}

	if err := c.checkrService.HandleWebhook(r.Context(), body); err != nil {
		utils.Logger.WithError(err).Error("Failed to handle Checkr webhook event")
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusOK)
}

