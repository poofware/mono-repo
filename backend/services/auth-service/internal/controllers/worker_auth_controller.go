// backend/services/auth-service/internal/controllers/worker_auth_controller.go
package controllers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/go-playground/validator/v10"
	"github.com/google/uuid"

	"github.com/jackc/pgx/v4"
	"github.com/poofware/mono-repo/backend/services/auth-service/internal/config"
	auth_dtos "github.com/poofware/mono-repo/backend/services/auth-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/services/auth-service/internal/services"
	auth_utils "github.com/poofware/mono-repo/backend/services/auth-service/internal/utils"
	"github.com/poofware/mono-repo/backend/shared/go-dtos"
	"github.com/poofware/mono-repo/backend/shared/go-middleware"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

type WorkerAuthController struct {
	workerAuthService services.WorkerAuthService
	cfg               *config.Config
}

func NewWorkerAuthController(workerAuth services.WorkerAuthService, cfg *config.Config) *WorkerAuthController {
	return &WorkerAuthController{workerAuthService: workerAuth, cfg: cfg}
}

var workerValidate = validator.New()

// parse workerID from context if JWT is present
func getWorkerIDFromContext(r *http.Request) *uuid.UUID {
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	if !ok || userID == "" {
		return nil
	}
	parsed, err := uuid.Parse(userID)
	if err != nil {
		return nil
	}
	return &parsed
}

// Platform Enforcement – Worker must be mobile (android or ios).
func ensurePlatformIsMobile(w http.ResponseWriter, r *http.Request) bool {
	platform := utils.GetClientPlatform(r)
	if !utils.IsMobile(platform) {
		utils.RespondErrorWithCode(
			w,
			http.StatusForbidden,
			utils.ErrCodeUnauthorized,
			"This endpoint is for mobile (android/ios) only",
			nil,
		)
		return false
	}
	return true
}

// ---------------------------------------------------------------------
// NEW: IssueChallenge
// ---------------------------------------------------------------------
func (c *WorkerAuthController) IssueChallenge(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsMobile(w, r) {
		return
	}

	platform := utils.GetClientPlatform(r)

	utils.Logger.Debug("Issuing challenge for worker authentication")

	challengeToken, challenge, err := c.workerAuthService.IssueChallenge(r.Context(), platform)
	if err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusInternalServerError, utils.ErrCodeInternal, "Failed to issue challenge", err,
		)
		return
	}

	resp := auth_dtos.ChallengeResponse{
		ChallengeToken: challengeToken,
		Challenge:      challenge,
	}
	utils.RespondWithJSON(w, http.StatusOK, resp)
}

// ---------------------------------------------------------------------
// Worker Email / SMS Code endpoints
// ---------------------------------------------------------------------
func (c *WorkerAuthController) RequestWorkerEmailCode(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsMobile(w, r) {
		return
	}

	var req auth_dtos.RequestEmailCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err,
		)
		return
	}
	if err := workerValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid email format", err,
		)
		return
	}

	platform := utils.GetClientPlatform(r)
	workerID := getWorkerIDFromContext(r)
	clientID := utils.GetClientIdentifier(r, platform).Value

	if err := c.workerAuthService.RequestEmailCode(r.Context(), req.Email, workerID, clientID); err != nil {
		if errors.Is(err, utils.ErrRateLimitExceeded) {
			utils.RespondErrorWithCode(
				w, http.StatusTooManyRequests, utils.ErrCodeRateLimitExceeded, "Too many requests. Please try again later.", nil,
			)
			return
		}
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Failed to send email code", err,
		)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, auth_dtos.RequestEmailCodeResponse{Message: "Verification code sent"})
}

func (c *WorkerAuthController) VerifyWorkerEmailCode(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsMobile(w, r) {
		return
	}

	var req auth_dtos.VerifyEmailCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err,
		)
		return
	}
	if err := workerValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid code format", err,
		)
		return
	}

	platform := utils.GetClientPlatform(r)
	workerID := getWorkerIDFromContext(r)
	clientID := utils.GetClientIdentifier(r, platform).Value

	valid, err := c.workerAuthService.VerifyEmailCode(r.Context(), req.Email, req.Code, workerID, clientID)
	if err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusInternalServerError, utils.ErrCodeInternal, "Verification failed", err,
		)
		return
	}
	if !valid {
		utils.RespondErrorWithCode(
			w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Invalid or expired code", nil,
		)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, auth_dtos.VerifyEmailCodeResponse{Message: "Email verified"})
}

func (c *WorkerAuthController) RequestWorkerSMSCode(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsMobile(w, r) {
		return
	}

	var req auth_dtos.RequestSMSCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err,
		)
		return
	}
	if err := workerValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid phone format", err,
		)
		return
	}

	platform := utils.GetClientPlatform(r)
	workerID := getWorkerIDFromContext(r)
	clientID := utils.GetClientIdentifier(r, platform).Value

	if err := c.workerAuthService.RequestSMSCode(r.Context(), req.PhoneNumber, workerID, clientID); err != nil {
		if errors.Is(err, utils.ErrRateLimitExceeded) {
			utils.RespondErrorWithCode(
				w, http.StatusTooManyRequests, utils.ErrCodeRateLimitExceeded, "Too many requests. Please try again later.", nil,
			)
			return
		}
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Failed to send SMS code", err,
		)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, auth_dtos.RequestSMSCodeResponse{Message: "SMS code sent"})
}

func (c *WorkerAuthController) VerifyWorkerSMSCode(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsMobile(w, r) {
		return
	}

	var req auth_dtos.VerifySMSCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err,
		)
		return
	}
	if err := workerValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid code format", err,
		)
		return
	}

	platform := utils.GetClientPlatform(r)
	workerID := getWorkerIDFromContext(r)
	clientID := utils.GetClientIdentifier(r, platform).Value

	valid, err := c.workerAuthService.VerifySMSCode(r.Context(), req.PhoneNumber, req.Code, workerID, clientID)
	if err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusInternalServerError, utils.ErrCodeInternal, "Verification failed", err,
		)
		return
	}
	if !valid {
		utils.RespondErrorWithCode(
			w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Invalid or expired code", nil,
		)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, auth_dtos.VerifySMSCodeResponse{Message: "Phone verified"})
}

// ---------------------------------------------------------------------
// Register Worker
// ---------------------------------------------------------------------
func (c *WorkerAuthController) RegisterWorker(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsMobile(w, r) {
		return
	}

	var req auth_dtos.RegisterWorkerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err,
		)
		return
	}

	if err := workerValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err,
		)
		return
	}

	platform := utils.GetClientPlatform(r)
	clientID := utils.GetClientIdentifier(r, platform).Value
	ctx := r.Context()

	verified, verificationID, err := c.workerAuthService.CheckPhoneVerifiedBeforeRegistration(ctx, req.PhoneNumber, clientID)
	if err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusInternalServerError, utils.ErrCodeInternal, "Could not verify phone code", err,
		)
		return
	}
	if !verified {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodePhoneNotVerified, "Phone verification has expired. Please start registration again.", nil,
		)
		return
	}

	if !auth_utils.ValidateTOTPCode(req.TOTPSecret, req.TOTPToken) {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidTotp, "Invalid TOTP code", nil,
		)
		return
	}

	if regErr := c.workerAuthService.Register(ctx, req); regErr != nil {
		switch {
		case errors.Is(regErr, utils.ErrInvalidPhone):
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid phone number format", regErr)
		case errors.Is(regErr, utils.ErrInvalidEmail):
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid email format", regErr)
		default:
			utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Failed to register worker", regErr)
		}
		return
	}

	if verificationID != nil {
		_ = c.workerAuthService.DeleteSMSVerificationRow(ctx, *verificationID)
	}

	utils.RespondWithJSON(w, http.StatusCreated, auth_dtos.RegisterWorkerResponse{Message: "Worker registered successfully"})
}

// ---------------------------------------------------------------------
// Login Worker
// ---------------------------------------------------------------------
func (c *WorkerAuthController) LoginWorker(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsMobile(w, r) {
		return
	}

	var req auth_dtos.LoginWorkerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid request", err)
		return
	}
	if err := workerValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	platform := utils.GetClientPlatform(r)
	clientID := utils.GetClientIdentifier(r, platform)
	tokenPolicy := DecideTokenPolicy(platform, c.cfg)

	worker, access, refresh, err := c.workerAuthService.Login(
		r.Context(),
		req.PhoneNumber,
		req.TOTPCode,
		clientID,
		tokenPolicy.AccessTTL,
		tokenPolicy.RefreshTTL,
	)
	if err != nil {
		if strings.Contains(err.Error(), "locked") {
			utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeLockedAccount, err.Error(), err)
		} else {
			utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeInvalidCredentials, "Login failed", err)
		}
		return
	}

	resp := auth_dtos.LoginWorkerResponse{
		Worker:       dtos.NewWorkerFromModel(*worker),
		AccessToken:  access,
		RefreshToken: refresh,
	}

	if platform == utils.PlatformWeb {
		// Theoretically unreachable after ensurePlatformIsMobile, but:
		auth_utils.SetAuthCookies(w, access, refresh, c.cfg.WebTokenExpiry, c.cfg.WebRefreshTokenExpiry, "/auth/v1/worker/refresh_token", c.cfg.LDFlag_CORSHighSecurity)
		resp.AccessToken = ""
		resp.RefreshToken = ""
	}

	utils.RespondWithJSON(w, http.StatusOK, resp)
}

// ---------------------------------------------------------------------
// Validate Worker Email / Phone
// ---------------------------------------------------------------------
func (c *WorkerAuthController) ValidateWorkerEmail(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsMobile(w, r) {
		return
	}

	var req auth_dtos.ValidateWorkerEmailRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid request payload", err,
		)
		return
	}
	if err := workerValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid email format", err,
		)
		return
	}

	if err := c.workerAuthService.ValidateNewWorkerEmail(r.Context(), req.Email); err != nil {
		switch {
		case errors.Is(err, utils.ErrInvalidEmail):
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Email failed validation checks", err)
		case errors.Is(err, utils.ErrEmailExists):
			utils.RespondErrorWithCode(w, http.StatusConflict, utils.ErrCodeConflict, "Email already in use", err)
		default:
			utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Server error", err)
		}
		return
	}

	w.WriteHeader(http.StatusOK)
}

func (c *WorkerAuthController) ValidateWorkerPhone(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsMobile(w, r) {
		return
	}

	var req auth_dtos.ValidateWorkerPhoneRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid request payload", err,
		)
		return
	}
	if err := workerValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid phone format", err,
		)
		return
	}

	if err := c.workerAuthService.ValidateNewWorkerPhone(r.Context(), req.PhoneNumber); err != nil {
		switch {
		case errors.Is(err, utils.ErrInvalidPhone):
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Phone number failed validation checks", err)
		case errors.Is(err, utils.ErrPhoneExists):
			utils.RespondErrorWithCode(w, http.StatusConflict, utils.ErrCodeConflict, "Phone number already in use", err)
		default:
			utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Server error", err)
		}
		return
	}

	w.WriteHeader(http.StatusOK)
}

// ---------------------------------------------------------------------
// Worker Account Deletion
// ---------------------------------------------------------------------

func (c *WorkerAuthController) InitiateDeletion(w http.ResponseWriter, r *http.Request) {
	var req auth_dtos.InitiateDeletionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err)
		return
	}
	if err := workerValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid email format", err)
		return
	}

	platform := utils.GetClientPlatform(r)
	clientID := utils.GetClientIdentifier(r, platform).Value

	token, err := c.workerAuthService.InitiateDeletion(r.Context(), req.Email, clientID)
	if err != nil {
		switch {
		case errors.Is(err, utils.ErrRateLimitExceeded):
			utils.RespondErrorWithCode(
				w, http.StatusTooManyRequests, utils.ErrCodeRateLimitExceeded, "Too many requests. Please try again later.", nil,
			)
		case errors.Is(err, pgx.ErrNoRows):
			utils.RespondErrorWithCode(w, http.StatusNotFound, utils.ErrCodeNotFound, "Worker not found", err)
		case errors.Is(err, utils.ErrExternalServiceFailure):
			// NEW: Handle external service failures with a more specific status code
			utils.RespondErrorWithCode(w, http.StatusFailedDependency, utils.ErrCodeExternalServiceFailure, "A required service is temporarily unavailable. Please try again later.", err)
		default:
			// This was the original generic 500 error
			utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Failed to initiate deletion", err)
		}
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, auth_dtos.InitiateDeletionResponse{PendingToken: token})
}

func (c *WorkerAuthController) ConfirmDeletion(w http.ResponseWriter, r *http.Request) {
	var req auth_dtos.ConfirmDeletionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err)
		return
	}
	if err := workerValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	if req.TOTPCode == nil && (req.EmailCode == nil || req.SMSCode == nil) {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Missing verification codes", nil)
		return
	}

	if err := c.workerAuthService.ConfirmDeletion(r.Context(), req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Verification failed", err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, auth_dtos.ConfirmDeletionResponse{Message: "Your account deletion request has been successfully submitted for processing."})
}

// ---------------------------------------------------------------------
// Refresh + Logout Worker
// ---------------------------------------------------------------------
func (c *WorkerAuthController) RefreshTokenWorker(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsMobile(w, r) {
		return
	}

	platform := utils.GetClientPlatform(r)
	clientID := utils.GetClientIdentifier(r, platform)
	tokenPolicy := DecideTokenPolicy(platform, c.cfg)

	var refresh string

	if platform == utils.PlatformWeb {
		cookie, err := r.Cookie(middleware.RefreshTokenCookieName)
		if err != nil || cookie.Value == "" {
			utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Missing refresh cookie", err)
			return
		}
		refresh = cookie.Value
	} else {
		var req auth_dtos.RefreshTokenRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err)
			return
		}
		if err := workerValidate.Struct(req); err != nil {
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
			return
		}
		refresh = req.RefreshToken
	}

	access, newRefresh, err := c.workerAuthService.RefreshToken(
		r.Context(),
		refresh,
		clientID,
		tokenPolicy.AccessTTL,
		tokenPolicy.RefreshTTL,
	)
	if err != nil {
		utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Refresh token failed", err)
		return
	}

	resp := auth_dtos.RefreshTokenResponse{
		AccessToken:  access,
		RefreshToken: newRefresh,
	}

	if platform == utils.PlatformWeb {
		auth_utils.SetAuthCookies(w, access, newRefresh, c.cfg.WebTokenExpiry, c.cfg.WebRefreshTokenExpiry, "/auth/v1/worker/refresh_token", c.cfg.LDFlag_CORSHighSecurity)
		resp.AccessToken = ""
		resp.RefreshToken = ""
	}

	utils.RespondWithJSON(w, http.StatusOK, resp)
}

func (c *WorkerAuthController) LogoutWorker(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsMobile(w, r) {
		return
	}

	platform := utils.GetClientPlatform(r)

	var refresh string
	if platform == utils.PlatformWeb {
		if ck, err := r.Cookie(middleware.RefreshTokenCookieName); err == nil {
			refresh = ck.Value
		}
	} else {
		var req auth_dtos.LogoutRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err)
			return
		}
		if err := workerValidate.Struct(req); err != nil {
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
			return
		}
		refresh = req.RefreshToken
	}

	if err := c.workerAuthService.Logout(r.Context(), refresh); err != nil {
		utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Failed to logout", err)
		return
	}

	if platform == utils.PlatformWeb {
		auth_utils.ClearAuthCookies(w, "/auth/v1/worker/refresh_token", c.cfg.LDFlag_CORSHighSecurity)
	}

	utils.RespondWithJSON(w, http.StatusOK, auth_dtos.LogoutResponse{Message: "Logged out successfully"})
}
