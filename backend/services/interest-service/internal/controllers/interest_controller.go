package controllers

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/go-playground/validator/v10"

	"github.com/poofware/mono-repo/backend/services/interest-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/services/interest-service/internal/services"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

type InterestController struct {
	svc services.InterestService
}

func NewInterestController(s services.InterestService) *InterestController {
	return &InterestController{svc: s}
}

var validate = validator.New()

// -----------------------------------------------------------------------------
// POST /interest/worker
// -----------------------------------------------------------------------------
func (c *InterestController) SubmitWorkerInterest(w http.ResponseWriter, r *http.Request) {
	c.handle(w, r, c.svc.SubmitWorkerInterest)
}

// -----------------------------------------------------------------------------
// POST /interest/pm
// -----------------------------------------------------------------------------
func (c *InterestController) SubmitPMInterest(w http.ResponseWriter, r *http.Request) {
	c.handle(w, r, c.svc.SubmitPMInterest)
}

// -----------------------------------------------------------------------------
// shared helper
// -----------------------------------------------------------------------------
func (c *InterestController) handle(
	w http.ResponseWriter,
	r *http.Request,
	fn func(ctx context.Context, email string) error,
) {
	var req dtos.InterestRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON payload", err,
		)
		return
	}
	if err := validate.Struct(req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Email required / malformed", err,
		)
		return
	}

	if err := fn(r.Context(), req.Email); err != nil {
		httpStatus := http.StatusInternalServerError
		if err == utils.ErrInvalidEmail {
			httpStatus = http.StatusBadRequest
		}
		utils.RespondErrorWithCode(
			w, httpStatus, utils.ErrCodeInvalidPayload, err.Error(), err,
		)
		return
	}

	utils.RespondWithJSON(
		w, http.StatusOK,
		dtos.InterestResponse{Message: "Received – check your inbox!"},
	)
}

