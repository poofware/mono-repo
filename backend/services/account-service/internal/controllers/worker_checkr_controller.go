package controllers

import (
	"net/http"
	"time"

	"github.com/google/uuid"
	internal_dtos "github.com/poofware/account-service/internal/dtos"
	"github.com/poofware/account-service/internal/services"
	"github.com/poofware/go-middleware"
	"github.com/poofware/go-utils"
	"github.com/poofware/go-dtos"
)

// WorkerCheckrController handles Checkr-related endpoints for the Worker role.
type WorkerCheckrController struct {
	checkrService *services.CheckrService
}

// NewWorkerCheckrController instantiates a WorkerCheckrController.
func NewWorkerCheckrController(s *services.CheckrService) *WorkerCheckrController {
	return &WorkerCheckrController{checkrService: s}
}

// POST /api/v1/account/worker/checkr/invitation
//
// The package slug is hard-coded in the service ("poof_gig_worker").
func (c *WorkerCheckrController) CreateInvitationHandler(w http.ResponseWriter, r *http.Request) {
	// Extract userID from the JWT middleware context
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

	// Call the service to create or reuse a Checkr invitation.
	invURL, invErr := c.checkrService.CreateCheckrInvitation(r.Context(), workerID)
	if invErr != nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusInternalServerError,
			utils.ErrCodeInternal,
			"Failed to create or reuse Checkr invitation",
			invErr,
		)
		return
	}

	// Construct the response
	resp := internal_dtos.CheckrInvitationResponse{
		Message:       "Checkr invitation (and candidate if needed) created/reused",
		InvitationURL: invURL,
	}
	utils.RespondWithJSON(w, http.StatusOK, resp)
}

// GET /api/v1/account/worker/checkr/status
func (c *WorkerCheckrController) GetCheckrStatusHandler(w http.ResponseWriter, r *http.Request) {
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

	// Fetch the worker's background-check flow status (incomplete or complete).
	flowStatus, stErr := c.checkrService.GetCheckrStatus(r.Context(), workerID)
	if stErr != nil {
		utils.Logger.WithError(stErr).Error("Error retrieving Checkr status")
		utils.RespondErrorWithCode(
			w,
			http.StatusInternalServerError,
			utils.ErrCodeInternal,
			"Failed to retrieve Checkr status",
			stErr,
		)
		return
	}

	// Construct the DTO response
	resp := internal_dtos.CheckrStatusResponse{
		Status: flowStatus,
	}
	utils.RespondWithJSON(w, http.StatusOK, resp)
}

// ───────────────────────────────────────────────────────────────────
// GET /api/v1/account/worker/checkr/report-eta      (UPDATED)
//   - expects query‑param `time_zone` (IANA TZ, e.g. America/Denver)
//   - returns localised ETA or null
//
// ───────────────────────────────────────────────────────────────────
func (c *WorkerCheckrController) GetCheckrReportETAHandler(w http.ResponseWriter, r *http.Request) {
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

	timeZone := r.URL.Query().Get("time_zone")
	if timeZone == "" {
		utils.RespondErrorWithCode(
			w,
			http.StatusBadRequest,
			utils.ErrCodeInvalidPayload,
			"time_zone query parameter is required",
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

	etaTime, svcErr := c.checkrService.GetWorkerCheckrETA(r.Context(), workerID)
	if svcErr != nil {
		utils.Logger.WithError(svcErr).Error("Failed to retrieve worker's Checkr ETA")
		utils.RespondErrorWithCode(
			w,
			http.StatusInternalServerError,
			utils.ErrCodeInternal,
			"Could not retrieve Checkr ETA",
			svcErr,
		)
		return
	}

	var etaString *string
	if etaTime != nil {
		loc, tzErr := time.LoadLocation(timeZone)
		if tzErr != nil {
			utils.RespondErrorWithCode(
				w,
				http.StatusBadRequest,
				utils.ErrCodeInvalidPayload,
				"Unrecognized or invalid time_zone",
				tzErr,
			)
			return
		}
		localTime := etaTime.In(loc)
		str := localTime.Format(time.RFC3339)
		etaString = &str
	}

	resp := internal_dtos.CheckrETAResponse{
		ReportETA: etaString,
	}
	utils.RespondWithJSON(w, http.StatusOK, resp)
}

// GetCheckrOutcomeHandler -> GET /api/v1/account/worker/checkr/outcome
func (c *WorkerCheckrController) GetCheckrOutcomeHandler(
	w http.ResponseWriter,
	r *http.Request,
) {
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

	worker, svcErr := c.checkrService.GetWorkerCheckrOutcome(r.Context(), workerID)
	if svcErr != nil {
		utils.Logger.WithError(svcErr).Error("Failed to retrieve Checkr outcome")
		utils.RespondErrorWithCode(
			w,
			http.StatusInternalServerError,
			utils.ErrCodeInternal,
			"Unable to retrieve worker",
			svcErr,
		)
		return
	}
	if worker == nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusNotFound,
			utils.ErrCodeNotFound,
			"Worker not found",
			nil,
		)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, dtos.NewWorkerFromModel(*worker))
}

// NEW: CreateSessionTokenHandler -> GET /api/v1/account/worker/checkr/session-token
func (c *WorkerCheckrController) CreateSessionTokenHandler(w http.ResponseWriter, r *http.Request) {
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

	// Call the service to create a session token
	token, svcErr := c.checkrService.CreateSessionToken(r.Context(), workerID)
	if svcErr != nil {
		utils.Logger.WithError(svcErr).Error("Failed to create Checkr session token")
		utils.RespondErrorWithCode(
			w,
			http.StatusInternalServerError,
			utils.ErrCodeInternal,
			"Could not create Checkr session token",
			svcErr,
		)
		return
	}

	resp := internal_dtos.CheckrSessionTokenResponse{
		Token: token,
	}
	utils.RespondWithJSON(w, http.StatusOK, resp)
}
