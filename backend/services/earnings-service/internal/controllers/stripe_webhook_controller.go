package controllers

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/poofware/earnings-service/internal/config"
	"github.com/poofware/earnings-service/internal/constants"
	"github.com/poofware/earnings-service/internal/dtos"
	"github.com/poofware/earnings-service/internal/services"
	"github.com/poofware/go-utils"
	"github.com/stripe/stripe-go/v82"
	"github.com/stripe/stripe-go/v82/webhook"
)

const webhookCheckParam = "id"

type StripeWebhookController struct {
	cfg                     *config.Config
	payoutService           *services.PayoutService
	webhookCheckService     *services.StripeWebhookCheckService
	webhookCheckGeneratedBy string
}

func NewStripeWebhookController(cfg *config.Config, payoutService *services.PayoutService, webhookCheckService *services.StripeWebhookCheckService) *StripeWebhookController {
	wc := "webhook_check-" + fmt.Sprintf("%s-%s-%s", cfg.AppName, cfg.UniqueRunnerID, cfg.UniqueRunNumber)
	return &StripeWebhookController{
		cfg:                     cfg,
		payoutService:           payoutService,
		webhookCheckService:     webhookCheckService,
		webhookCheckGeneratedBy: wc,
	}
}

// WebhookHandler -> POST /api/v1/earnings/stripe/webhook
func (c *StripeWebhookController) WebhookHandler(w http.ResponseWriter, r *http.Request) {
	sigHeader := r.Header.Get("Stripe-Signature")
	if sigHeader == "" {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Missing Stripe-Signature header", nil)
		return
	}

	payload, err := io.ReadAll(r.Body)
	if err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Failed to read webhook body", err)
		return
	}

	var event stripe.Event
	var verifyErr error

	platformSecret := c.payoutService.PlatformWebhookSecret()
	connectSecret := c.payoutService.ConnectWebhookSecret()

	event, verifyErr = webhook.ConstructEvent(payload, sigHeader, platformSecret)
	if verifyErr != nil {
		event, verifyErr = webhook.ConstructEvent(payload, sigHeader, connectSecret)
		if verifyErr != nil {
			utils.Logger.WithError(verifyErr).Error("Stripe webhook signature verification failed for both platform and connect secrets")
			w.WriteHeader(http.StatusBadRequest)
			return
		}
	}

	switch event.Type {
	case stripe.EventTypePayoutPaid, stripe.EventTypePayoutFailed:
		var payout stripe.Payout
		if err := json.Unmarshal(event.Data.Raw, &payout); err == nil {
			_ = c.payoutService.HandlePayoutEvent(r.Context(), &payout)
		} else {
			utils.Logger.WithError(err).Errorf("Could not parse stripe.Payout object for event type %s", event.Type)
		}
	case stripe.EventTypeAccountUpdated:
		var account stripe.Account
		if err := json.Unmarshal(event.Data.Raw, &account); err == nil {
			_ = c.payoutService.HandleAccountUpdatedEvent(r.Context(), &account)
		} else {
			utils.Logger.WithError(err).Error("Could not parse stripe.Account object")
		}
	case stripe.EventTypeCapabilityUpdated:
		var capability stripe.Capability
		if err := json.Unmarshal(event.Data.Raw, &capability); err == nil {
			_ = c.payoutService.HandleCapabilityUpdatedEvent(r.Context(), &capability)
		} else {
			utils.Logger.WithError(err).Error("Could not parse stripe.Capability object")
		}
	case stripe.EventTypeTransferReversed:
		// Note: `transfer.failed` is deprecated and has been removed.
		var transfer stripe.Transfer
		if err := json.Unmarshal(event.Data.Raw, &transfer); err == nil {
			_ = c.payoutService.HandleTransferEvent(r.Context(), &transfer)
		} else {
			utils.Logger.WithError(err).Errorf("Could not parse stripe.Transfer object for event type %s", event.Type)
		}
	case stripe.EventTypePaymentIntentCreated:
		var pi stripe.PaymentIntent
		if err := json.Unmarshal(event.Data.Raw, &pi); err == nil {
			if pi.Metadata[constants.WebhookMetadataGeneratedByKey] == c.webhookCheckGeneratedBy {
				c.webhookCheckService.HandlePaymentIntentCreated(event.ID, &pi)
			}
		} else {
			utils.Logger.WithError(err).Error("Could not parse payment intent in payment_intent.created")
		}
	case stripe.EventTypeBalanceAvailable:
		var balance stripe.Balance
		if err := json.Unmarshal(event.Data.Raw, &balance); err == nil {
			_ = c.payoutService.HandleBalanceAvailableEvent(r.Context(), &balance)
		} else {
			utils.Logger.WithError(err).Error("Could not parse stripe.Balance object")
		}
	default:
		utils.Logger.Infof("Unhandled Stripe event type received in earnings-service: %s", event.Type)
	}

	w.WriteHeader(http.StatusOK)
}

// WebhookCheckHandler -> GET /api/v1/earnings/stripe/webhook/check
func (c *StripeWebhookController) WebhookCheckHandler(w http.ResponseWriter, r *http.Request) {
	eventID := r.URL.Query().Get(webhookCheckParam)
	if eventID == "" {
		utils.RespondErrorWithCode(
			w,
			http.StatusBadRequest,
			utils.ErrCodeInvalidPayload,
			"Missing 'id' query param",
			nil,
		)
		return
	}

	found := c.webhookCheckService.ConsumeWebhookCheckEvent(eventID)
	if !found {
		utils.RespondErrorWithCode(
			w,
			http.StatusNotFound,
			utils.ErrCodeNotFound,
			"Event ID not recognized or already consumed",
			nil,
		)
		return
	}

	resp := dtos.WebhookCheckResponse{Message: "Webhook event recognized"}
	utils.RespondWithJSON(w, http.StatusOK, resp)
}
