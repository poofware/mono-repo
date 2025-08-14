package controllers

import (
	"encoding/json"
	"io"
	"net/http"
	"fmt"

	"github.com/poofware/mono-repo/backend/services/account-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/services/account-service/internal/services"
	"github.com/poofware/mono-repo/backend/services/account-service/internal/config"
	"github.com/poofware/mono-repo/backend/services/account-service/internal/constants"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
	stripe "github.com/stripe/stripe-go/v82"
	"github.com/stripe/stripe-go/v82/webhook"
)

// We'll also define a const for the ephemeral check param
const webhookCheckParam = "id"

// StripeWebhookController is the single webhook endpoint for all user roles (worker, pm, etc.)
type StripeWebhookController struct {
	// For now, we only have workerStripeService. In the future,
	// we might also have pmStripeService, etc.
	cfg *config.Config
	workerStripeService *services.WorkerStripeService
	stripeWebhookCheckService *services.StripeWebhookCheckService
	webhookCheckGeneratedBy string
}

func NewStripeWebhookController(cfg *config.Config, workerService *services.WorkerStripeService, webhookCheckService *services.StripeWebhookCheckService) *StripeWebhookController {

    wc := "webhook_check-" + fmt.Sprintf("%s-%s-%s", cfg.AppName, cfg.UniqueRunnerID, cfg.UniqueRunNumber)

	return &StripeWebhookController{
		cfg: cfg,
		workerStripeService: workerService,
		stripeWebhookCheckService: webhookCheckService,
		webhookCheckGeneratedBy: wc,
	}
}

// WebhookHandler -> POST /api/v1/account/stripe/webhook
// We parse the event, look at metadata[constants.WebhookMetadataAccountTypeKey], and delegate accordingly.
func (c *StripeWebhookController) WebhookHandler(w http.ResponseWriter, r *http.Request) {
	sigHeader := r.Header.Get("Stripe-Signature")
	if sigHeader == "" {
		utils.Logger.Error("Missing Stripe-Signature header")
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	payload, err := io.ReadAll(r.Body)
	if err != nil {
		utils.Logger.WithError(err).Error("Failed to read webhook body")
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	// We might parse different services later. For now, we only do worker.
	var (
		event stripe.Event
		verifyErr error
	)

	platformSecret := c.workerStripeService.PlatformWebhookSecret()
	connectSecret  := c.workerStripeService.ConnectWebhookSecret()

	event, verifyErr = webhook.ConstructEvent(payload, sigHeader, platformSecret)
	if verifyErr == nil {
		utils.Logger.Debug("Webhook verified with platform secret")
	} else {
		// 2) Fallback: try Connect secret
		event, verifyErr = webhook.ConstructEvent(payload, sigHeader, connectSecret)
		if verifyErr == nil {
			utils.Logger.Debug("Webhook verified with Connect secret")
		}
	}

	if verifyErr != nil {
		// Both attempts failed
		utils.Logger.WithError(verifyErr).Error("Stripe webhook signature verification failed")
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	// We'll parse out the constants.WebhookMetadataAccountTypeKey from the event's data object if possible
	// But not all events have the same object structure, so we'll handle on a per-case basis.
	switch event.Type {
	case "account.updated":
		var acct stripe.Account
		if err := json.Unmarshal(event.Data.Raw, &acct); err == nil {
			// Check the metadata
			if acct.Metadata[constants.WebhookMetadataAccountTypeKey] == utils.WorkerAccountType {
				_ = c.workerStripeService.HandleAccountUpdated(&acct)
			} else {
				utils.Logger.Infof("Skipping account.updated for acctID=%s, unrecognized account_type=%q",
					acct.ID, acct.Metadata[constants.WebhookMetadataAccountTypeKey])
			}
		} else {
			utils.Logger.WithError(err).Error("Could not parse account in account.updated")
		}

	case "capability.updated":
		var capObj stripe.Capability
		if err := json.Unmarshal(event.Data.Raw, &capObj); err == nil {
			// We'll have to fetch the account to see metadata, so let's do that in the service
			_ = c.workerStripeService.HandleCapabilityUpdated(&capObj)
		} else {
			utils.Logger.WithError(err).Error("Could not parse capability in capability.updated")
		}

	case "identity.verification_session.created",
		"identity.verification_session.requires_input",
		"identity.verification_session.verified",
		"identity.verification_session.canceled":

		var session stripe.IdentityVerificationSession
		if err := json.Unmarshal(event.Data.Raw, &session); err == nil {
			switch session.Metadata[constants.WebhookMetadataAccountTypeKey] {
			case utils.WorkerAccountType:
				switch event.Type {
				case "identity.verification_session.created":
					_ = c.workerStripeService.HandleVerificationSessionCreated(&session)
				case "identity.verification_session.requires_input":
					_ = c.workerStripeService.HandleVerificationSessionRequiresInput(&session)
				case "identity.verification_session.verified":
					_ = c.workerStripeService.HandleVerificationSessionVerified(&session)
				case "identity.verification_session.canceled":
					_ = c.workerStripeService.HandleVerificationSessionCanceled(&session)
				}
			default:
				utils.Logger.Infof("Skipping %s for sessionID=%s, unrecognized account_type=%q",
					event.Type, session.ID, session.Metadata[constants.WebhookMetadataAccountTypeKey])
			}
		} else {
			utils.Logger.WithError(err).Errorf("Could not parse session in %s", event.Type)
		}

	case "payment_intent.created":
		var pi stripe.PaymentIntent
		if err := json.Unmarshal(event.Data.Raw, &pi); err == nil {
			if pi.Metadata[constants.WebhookMetadataGeneratedByKey] == c.webhookCheckGeneratedBy {
				c.stripeWebhookCheckService.HandlePaymentIntentCreated(event.ID, &pi)
			} else {
				utils.Logger.Infof("Skipping payment_intent.created for id=%s, unrecognized account_type=%q",
					pi.ID, pi.Metadata[constants.WebhookMetadataAccountTypeKey])
			}
		} else {
			utils.Logger.WithError(err).Error("Could not parse payment intent in payment_intent.created")
		}

	default:
		utils.Logger.Infof("Unhandled Stripe event type: %s", event.Type)
	}

	// Acknowledge with 200
	w.WriteHeader(http.StatusOK)
}

// WebhookCheckHandler -> GET /api/v1/account/stripe/webhook/check?id=<eventID>
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

	found := c.stripeWebhookCheckService.ConsumeWebhookCheckEvent(eventID)
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

