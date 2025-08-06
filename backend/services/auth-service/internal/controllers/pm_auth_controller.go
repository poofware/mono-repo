// backend/services/auth-service/internal/controllers/pm_auth_controller.go
package controllers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/go-playground/validator/v10"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"

	"github.com/poofware/auth-service/internal/config"
	auth_dtos "github.com/poofware/auth-service/internal/dtos"
	"github.com/poofware/auth-service/internal/services"
	auth_utils "github.com/poofware/auth-service/internal/utils"
	"github.com/poofware/go-dtos"
	"github.com/poofware/go-middleware"
	"github.com/poofware/go-utils"
)

type PMAuthController struct {
	pmAuthService services.PMAuthService
	cfg           *config.Config
}

func NewPMAuthController(pmAuth services.PMAuthService, cfg *config.Config) *PMAuthController {
	return &PMAuthController{pmAuthService: pmAuth, cfg: cfg}
}

var pmValidate = validator.New()

// Helper to parse a PM ID from context if there's a valid JWT
func getPMIDFromContext(r *http.Request) *uuid.UUID {
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

// ---------------------------------------------------------------------
// Platform Enforcement Helper – PM must be "web"
// ---------------------------------------------------------------------
func ensurePlatformIsWeb(w http.ResponseWriter, r *http.Request) bool {
	platform := utils.GetClientPlatform(r)
	if platform != utils.PlatformWeb {
		utils.RespondErrorWithCode(
			w, http.StatusForbidden, utils.ErrCodeUnauthorized,
			"This endpoint is for web (PM) only", nil,
		)
		return false
	}
	return true
}

// -------------------
// PM Code Endpoints
// -------------------

func (c *PMAuthController) RequestPMEmailCode(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsWeb(w, r) {
		return
	}

	var req auth_dtos.RequestEmailCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err,
		)
		return
	}
	if err := pmValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid email format", err,
		)
		return
	}

	pmID := getPMIDFromContext(r)
	platform := utils.PlatformWeb
	clientID := utils.GetClientIdentifier(r, platform).Value

	if err := c.pmAuthService.RequestEmailCode(r.Context(), req.Email, pmID, clientID); err != nil {
		switch {
		case errors.Is(err, utils.ErrRateLimitExceeded):
			utils.RespondErrorWithCode(
				w, http.StatusTooManyRequests, utils.ErrCodeRateLimitExceeded, "Too many requests. Please try again later.", nil,
			)
		case errors.Is(err, utils.ErrExternalServiceFailure):
			utils.RespondErrorWithCode(
				w, http.StatusFailedDependency, utils.ErrCodeExternalServiceFailure, "Failed to send email due to an external service issue.", err,
			)
		default:
			utils.RespondErrorWithCode(
				w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Failed to send email code", err,
			)
		}
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, auth_dtos.RequestEmailCodeResponse{Message: "Verification code sent"})
}

func (c *PMAuthController) VerifyPMEmailCode(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsWeb(w, r) {
		return
	}

	var req auth_dtos.VerifyEmailCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err,
		)
		return
	}
	if err := pmValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid code format", err,
		)
		return
	}

	pmID := getPMIDFromContext(r)
	platform := utils.PlatformWeb
	clientID := utils.GetClientIdentifier(r, platform).Value

	valid, err := c.pmAuthService.VerifyEmailCode(r.Context(), req.Email, req.Code, pmID, clientID)
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

func (c *PMAuthController) RequestPMSMSCode(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsWeb(w, r) {
		return
	}

	var req auth_dtos.RequestSMSCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err,
		)
		return
	}
	if err := pmValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid phone format", err,
		)
		return
	}

	pmID := getPMIDFromContext(r)
	platform := utils.PlatformWeb
	clientID := utils.GetClientIdentifier(r, platform).Value

	if err := c.pmAuthService.RequestSMSCode(r.Context(), req.PhoneNumber, pmID, clientID); err != nil {
		switch {
		case errors.Is(err, utils.ErrRateLimitExceeded):
			utils.RespondErrorWithCode(
				w, http.StatusTooManyRequests, utils.ErrCodeRateLimitExceeded, "Too many requests. Please try again later.", nil,
			)
		case errors.Is(err, utils.ErrExternalServiceFailure):
			utils.RespondErrorWithCode(
				w, http.StatusFailedDependency, utils.ErrCodeExternalServiceFailure, "Failed to send SMS due to an external service issue.", err,
			)
		default:
			utils.RespondErrorWithCode(
				w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Failed to send SMS code", err,
			)
		}
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, auth_dtos.RequestSMSCodeResponse{Message: "SMS code sent"})
}

func (c *PMAuthController) VerifyPMSMSCode(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsWeb(w, r) {
		return
	}

	var req auth_dtos.VerifySMSCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err,
		)
		return
	}
	if err := pmValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid code format", err,
		)
		return
	}

	pmID := getPMIDFromContext(r)
	platform := utils.PlatformWeb
	clientID := utils.GetClientIdentifier(r, platform).Value

	valid, err := c.pmAuthService.VerifySMSCode(r.Context(), req.PhoneNumber, req.Code, pmID, clientID)
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

// ----------------
// Existing Endpoints
// ----------------

func (c *PMAuthController) RegisterPM(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsWeb(w, r) {
		return
	}

	var req auth_dtos.RegisterPMRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err,
		)
		return
	}
	if err := pmValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err,
		)
		return
	}

	platform := utils.PlatformWeb
	clientID := utils.GetClientIdentifier(r, platform).Value
	ctx := r.Context()

	// Email Verification Check
	emailVerified, emailVerificationID, err := c.pmAuthService.CheckEmailVerifiedBeforeRegistration(ctx, req.Email, clientID)
	if err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusInternalServerError, utils.ErrCodeInternal, "Could not verify email code", err,
		)
		return
	}
	if !emailVerified {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Email is not verified for your IP or has expired", nil,
		)
		return
	}

	// SMS Verification Check (if phone number is provided)
	var smsVerificationID *uuid.UUID
	if req.PhoneNumber != nil && *req.PhoneNumber != "" {
		smsVerified, id, err := c.pmAuthService.CheckSMSVerifiedBeforeRegistration(ctx, *req.PhoneNumber, clientID)
		if err != nil {
			utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Could not verify phone code", err)
			return
		}
		if !smsVerified {
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Phone number is not verified for your IP or has expired", nil)
			return
		}
		smsVerificationID = id // Keep this to delete it later
	}

	// TOTP Check
	if !auth_utils.ValidateTOTPCode(req.TOTPSecret, req.TOTPToken) {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidTotp, "Invalid TOTP code", nil,
		)
		return
	}

	// Registration
	if regErr := c.pmAuthService.Register(ctx, req); regErr != nil {
		switch {
		case errors.Is(regErr, utils.ErrInvalidPhone):
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid phone number format", regErr)
		case errors.Is(regErr, utils.ErrInvalidEmail):
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid email format", regErr)
		default:
			utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Failed to register pm", regErr)
		}
		return
	}

	// Cleanup verification rows on success
	if emailVerificationID != nil {
		_ = c.pmAuthService.DeleteEmailVerificationRow(ctx, *emailVerificationID)
	}
	if smsVerificationID != nil {
		_ = c.pmAuthService.DeleteSMSVerificationRow(ctx, *smsVerificationID)
	}

	utils.RespondWithJSON(w, http.StatusCreated, auth_dtos.RegisterPMResponse{Message: "PM registered successfully"})
}

func (c *PMAuthController) LoginPM(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsWeb(w, r) {
		return
	}

	var req auth_dtos.LoginPMRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid request", err)
		return
	}
	if err := pmValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	platform := utils.PlatformWeb
	clientID := utils.GetClientIdentifier(r, platform)
	tokenPolicy := DecideTokenPolicy(platform, c.cfg)

	pm, access, refresh, err := c.pmAuthService.Login(
		r.Context(),
		req.Email,
		req.TOTPCode,
		clientID,
		tokenPolicy.AccessTTL,
		tokenPolicy.RefreshTTL,
		platform, // newly added param
	)
	if err != nil {
		// FIX: Check for specific "locked" error to provide a better user message.
		if strings.Contains(err.Error(), "locked") {
			utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeLockedAccount, err.Error(), err)
		} else {
			utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeInvalidCredentials, "Login failed", err)
		}
		return
	}

	resp := auth_dtos.LoginPMResponse{
		PM: dtos.NewPMFromModel(*pm),
	}

	// For PM endpoints, we expect web usage => store tokens in cookie
	auth_utils.SetAuthCookies(w, access, refresh, c.cfg.WebTokenExpiry, c.cfg.WebRefreshTokenExpiry, "/auth/v1/pm/refresh_token", c.cfg.LDFlag_CORSHighSecurity)
	utils.RespondWithJSON(w, http.StatusOK, resp)
}

// ------------------------------------------------------------
// Validate Email / Phone
// ------------------------------------------------------------
func (c *PMAuthController) ValidatePMEmail(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsWeb(w, r) {
		return
	}

	var req auth_dtos.ValidatePMEmailRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid request payload", err,
		)
		return
	}
	if err := pmValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid email format", err,
		)
		return
	}

	if err := c.pmAuthService.ValidateNewPMEmail(r.Context(), req.Email); err != nil {
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

func (c *PMAuthController) ValidatePMPhone(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsWeb(w, r) {
		return
	}

	var req auth_dtos.ValidatePMPhoneRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid request payload", err,
		)
		return
	}
	if err := pmValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid phone format", err,
		)
		return
	}

	if err := c.pmAuthService.ValidateNewPMPhone(r.Context(), req.PhoneNumber); err != nil {
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

// ------------------------------------------------------------
// Refresh + Logout
// ------------------------------------------------------------

func (c *PMAuthController) RefreshTokenPM(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsWeb(w, r) {
		return
	}

	platform := utils.PlatformWeb
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
		// (Technically unreachable after ensurePlatformIsWeb, but included for completeness)
		var req auth_dtos.RefreshTokenRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err)
			return
		}
		if err := pmValidate.Struct(req); err != nil {
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
			return
		}
		refresh = req.RefreshToken
	}

	access, newRefresh, err := c.pmAuthService.RefreshToken(
		r.Context(),
		refresh,
		clientID,
		tokenPolicy.AccessTTL,
		tokenPolicy.RefreshTTL,
		platform, // newly added
	)
	if err != nil {
		utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Refresh token failed", err)
		return
	}

	resp := auth_dtos.RefreshTokenResponse{
		AccessToken:  access,
		RefreshToken: newRefresh,
	}

	// PM endpoints => cookies
	auth_utils.SetAuthCookies(w, access, newRefresh, c.cfg.WebTokenExpiry, c.cfg.WebRefreshTokenExpiry, "/auth/v1/pm/refresh_token", c.cfg.LDFlag_CORSHighSecurity)
	resp.AccessToken = ""
	resp.RefreshToken = ""

	utils.RespondWithJSON(w, http.StatusOK, resp)
}

func (c *PMAuthController) LogoutPM(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsWeb(w, r) {
		return
	}

	platform := utils.PlatformWeb

	var refresh string
	if platform == utils.PlatformWeb {
		if ck, err := r.Cookie(middleware.RefreshTokenCookieName); err == nil {
			refresh = ck.Value
		}
	} else {
		// unreachable
		var req auth_dtos.LogoutRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err)
			return
		}
		if err := pmValidate.Struct(req); err != nil {
			utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
			return
		}
		refresh = req.RefreshToken
	}

	if err := c.pmAuthService.Logout(r.Context(), refresh); err != nil {
		utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Failed to logout", err)
		return
	}

	auth_utils.ClearAuthCookies(w, "/auth/v1/pm/refresh_token", c.cfg.LDFlag_CORSHighSecurity)
	utils.RespondWithJSON(w, http.StatusOK, auth_dtos.LogoutResponse{Message: "Logged out successfully"})
}

// ------------------------------------------------------------
// PM Account Deletion
// ------------------------------------------------------------

func (c *PMAuthController) InitiateDeletion(w http.ResponseWriter, r *http.Request) {
	var req auth_dtos.InitiateDeletionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err)
		return
	}
	if err := pmValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Invalid email format", err)
		return
	}

	platform := utils.GetClientPlatform(r)
	clientID := utils.GetClientIdentifier(r, platform).Value

	token, err := c.pmAuthService.InitiateDeletion(r.Context(), req.Email, clientID)
	if err != nil {
		switch {
		case errors.Is(err, utils.ErrRateLimitExceeded):
			utils.RespondErrorWithCode(
				w, http.StatusTooManyRequests, utils.ErrCodeRateLimitExceeded, "Too many requests. Please try again later.", nil,
			)
		case errors.Is(err, pgx.ErrNoRows):
			utils.RespondErrorWithCode(w, http.StatusNotFound, utils.ErrCodeNotFound, "Property Manager not found", err)
		case errors.Is(err, utils.ErrExternalServiceFailure):
			utils.RespondErrorWithCode(w, http.StatusFailedDependency, utils.ErrCodeExternalServiceFailure, "A required service is temporarily unavailable. Please try again later.", err)
		default:
			utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Failed to initiate deletion", err)
		}
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, auth_dtos.InitiateDeletionResponse{PendingToken: token})
}

func (c *PMAuthController) ConfirmDeletion(w http.ResponseWriter, r *http.Request) {
	var req auth_dtos.ConfirmDeletionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid payload", err)
		return
	}
	if err := pmValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	if err := c.pmAuthService.ConfirmDeletion(r.Context(), req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Verification failed", err)
		return
	}

	utils.RespondWithJSON(w, http.StatusOK, auth_dtos.ConfirmDeletionResponse{Message: "Your account deletion request has been successfully submitted for processing."})
}
