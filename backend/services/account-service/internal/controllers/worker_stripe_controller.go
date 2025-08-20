package controllers

import (
	"net/http"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/services/account-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/services/account-service/internal/routes"
	"github.com/poofware/mono-repo/backend/services/account-service/internal/services"
	"github.com/poofware/mono-repo/backend/shared/go-middleware"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

// WorkerStripeController handles worker-specific Stripe endpoints
type WorkerStripeController struct {
	workerStripeService *services.WorkerStripeService
}

func NewWorkerStripeController(s *services.WorkerStripeService) *WorkerStripeController {
	return &WorkerStripeController{workerStripeService: s}
}

// GET /api/v1/account/worker/stripe/express-login-link
func (c *WorkerStripeController) ExpressLoginLinkHandler(w http.ResponseWriter, r *http.Request) {
	ctxUserID := r.Context().Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusUnauthorized,
			utils.ErrCodeUnauthorized,
			"Missing userID in context",
			nil,
		)
		return
	}

	workerID, err := uuid.Parse(ctxUserID.(string))
	if err != nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusBadRequest,
			utils.ErrCodeInvalidPayload,
			"Invalid worker ID format",
			err,
		)
		return
	}

	url, err := c.workerStripeService.GetExpressLoginLink(r.Context(), workerID)
	if err != nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusInternalServerError,
			utils.ErrCodeInternal,
			"Failed to create Express login link",
			err,
		)
		return
	}

	resp := dtos.StripeExpressLoginLinkResponse{
		LoginLinkURL: url,
	}
	utils.RespondWithJSON(w, http.StatusOK, resp)
}

// GET /api/v1/account/worker/stripe/connect-flow
func (c *WorkerStripeController) ConnectFlowURLHandler(w http.ResponseWriter, r *http.Request) {
	ctxUserID := r.Context().Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusUnauthorized,
			utils.ErrCodeUnauthorized,
			"Missing userID in context",
			nil,
		)
		return
	}

	workerID, err := uuid.Parse(ctxUserID.(string))
	if err != nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusBadRequest,
			utils.ErrCodeInvalidPayload,
			"Invalid worker ID format",
			err,
		)
		return
	}

	url, err := c.workerStripeService.GetExpressOnboardingURL(r.Context(), workerID)
	if err != nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusInternalServerError,
			utils.ErrCodeInternal,
			"Failed to create onboarding link",
			err,
		)
		return
	}

	resp := dtos.StripeConnectFlowURLResponse{
		ConnectFlowURL: url,
	}
	utils.RespondWithJSON(w, http.StatusOK, resp)
}

// GET /api/v1/account/worker/stripe/connect-flow-return
func (c *WorkerStripeController) ConnectFlowReturnHandler(w http.ResponseWriter, r *http.Request) {
	redirectURL := c.workerStripeService.Cfg.AppUrl + routes.WorkerUniversalLinkStripeConnectReturn
	http.Redirect(w, r, redirectURL, http.StatusFound)
}

// GET /api/v1/account/worker/stripe/connect-flow-refresh
func (c *WorkerStripeController) ConnectFlowRefreshHandler(w http.ResponseWriter, r *http.Request) {
	redirectURL := c.workerStripeService.Cfg.AppUrl + routes.WorkerUniversalLinkStripeConnectRefresh
	http.Redirect(w, r, redirectURL, http.StatusFound)
}

// GET /api/v1/account/worker/stripe/connect-flow-status
func (c *WorkerStripeController) ConnectFlowStatusHandler(w http.ResponseWriter, r *http.Request) {
	ctxUserID := r.Context().Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusUnauthorized,
			utils.ErrCodeUnauthorized,
			"Missing userID in context",
			nil,
		)
		return
	}

	userID := ctxUserID.(string)
	flowStatus, err := c.workerStripeService.GetConnectFlowStatus(r.Context(), userID)
	if err != nil {
		// A real system/db error => return 500
		utils.Logger.WithError(err).Error("System error checking connect-flow status")
		utils.RespondErrorWithCode(
			w,
			http.StatusInternalServerError,
			utils.ErrCodeInternal,
			"Failed to retrieve connect-flow status",
			err,
		)
		return
	}

	// Always return 200 with the enum
	resp := dtos.StripeFlowStatusResponse{
		Status: flowStatus,
	}
	utils.RespondWithJSON(w, http.StatusOK, resp)
}

// GET /api/v1/account/worker/stripe/identity-flow
func (c *WorkerStripeController) IdentityFlowURLHandler(w http.ResponseWriter, r *http.Request) {
	ctxUserID := r.Context().Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusUnauthorized,
			utils.ErrCodeUnauthorized,
			"Missing userID in context",
			nil,
		)
		return
	}

	workerID, err := uuid.Parse(ctxUserID.(string))
	if err != nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusBadRequest,
			utils.ErrCodeInvalidPayload,
			"Invalid worker ID format",
			err,
		)
		return
	}

	url, err := c.workerStripeService.GetIdentityVerificationURL(r.Context(), workerID)
	if err != nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusInternalServerError,
			utils.ErrCodeInternal,
			"Failed to create identity verification session",
			err,
		)
		return
	}

	resp := dtos.StripeIdentityFlowURLResponse{
		IdentityFlowURL: url,
	}
	utils.RespondWithJSON(w, http.StatusOK, resp)
}

// GET /api/v1/account/worker/stripe/identity-flow-return
func (c *WorkerStripeController) IdentityFlowReturnHandler(w http.ResponseWriter, r *http.Request) {
	redirectURL := c.workerStripeService.Cfg.AppUrl + routes.WorkerUniversalLinkStripeIdentityReturn
	http.Redirect(w, r, redirectURL, http.StatusFound)
}

// GET /api/v1/account/worker/stripe/identity-flow-status
func (c *WorkerStripeController) IdentityFlowStatusHandler(w http.ResponseWriter, r *http.Request) {
	ctxUserID := r.Context().Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusUnauthorized,
			utils.ErrCodeUnauthorized,
			"Missing userID in context",
			nil,
		)
		return
	}

	userID := ctxUserID.(string)
	flowStatus, err := c.workerStripeService.CheckIdentityFlowStatus(r.Context(), userID)
	if err != nil {
		// Only a real system/db error => respond 500
		utils.Logger.WithError(err).Error("System error checking identity-flow status")
		utils.RespondErrorWithCode(
			w,
			http.StatusInternalServerError,
			utils.ErrCodeInternal,
			"Failed to retrieve identity-flow status",
			err,
		)
		return
	}

	resp := dtos.StripeFlowStatusResponse{
		Status: flowStatus,
	}
	utils.RespondWithJSON(w, http.StatusOK, resp)
}
