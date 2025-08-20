// meta-service/services/auth-service/internal/controllers/admin_auth_controller.go
package controllers

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/go-playground/validator/v10"
	"github.com/poofware/mono-repo/backend/services/auth-service/internal/config"
	auth_dtos "github.com/poofware/mono-repo/backend/services/auth-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/services/auth-service/internal/services"
	auth_utils "github.com/poofware/mono-repo/backend/services/auth-service/internal/utils"
	dtos "github.com/poofware/mono-repo/backend/shared/go-dtos"
	"github.com/poofware/mono-repo/backend/shared/go-middleware"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

type AdminAuthController struct {
	adminAuthService services.AdminAuthService
	cfg              *config.Config
}

func NewAdminAuthController(adminAuth services.AdminAuthService, cfg *config.Config) *AdminAuthController {
	return &AdminAuthController{adminAuthService: adminAuth, cfg: cfg}
}

var adminValidate = validator.New()

func (c *AdminAuthController) LoginAdmin(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsWeb(w, r) {
		return
	}

	var req auth_dtos.LoginAdminRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid request", err)
		return
	}
	if err := adminValidate.Struct(req); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeValidation, "Validation error", err)
		return
	}

	platform := utils.PlatformWeb
	clientID := utils.GetClientIdentifier(r, platform)
	tokenPolicy := DecideTokenPolicy(platform, c.cfg)

	admin, access, refresh, err := c.adminAuthService.Login(
		r.Context(),
		req.Username,
		req.Password,
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

	resp := auth_dtos.LoginAdminResponse{
		Admin: dtos.NewAdminFromModel(*admin),
	}

	auth_utils.SetAuthCookies(w, access, refresh, c.cfg.WebTokenExpiry, c.cfg.WebRefreshTokenExpiry, "/auth/v1/admin/refresh_token", c.cfg.LDFlag_CORSHighSecurity)
	utils.RespondWithJSON(w, http.StatusOK, resp)
}

func (c *AdminAuthController) RefreshTokenAdmin(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsWeb(w, r) {
		return
	}

	platform := utils.PlatformWeb
	clientID := utils.GetClientIdentifier(r, platform)
	tokenPolicy := DecideTokenPolicy(platform, c.cfg)

	cookie, err := r.Cookie(middleware.RefreshTokenCookieName)
	if err != nil || cookie.Value == "" {
		utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Missing refresh cookie", err)
		return
	}
	refresh := cookie.Value

	access, newRefresh, err := c.adminAuthService.RefreshToken(
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

	auth_utils.SetAuthCookies(w, access, newRefresh, c.cfg.WebTokenExpiry, c.cfg.WebRefreshTokenExpiry, "/auth/v1/admin/refresh_token", c.cfg.LDFlag_CORSHighSecurity)
	resp.AccessToken = ""
	resp.RefreshToken = ""

	utils.RespondWithJSON(w, http.StatusOK, resp)
}

func (c *AdminAuthController) LogoutAdmin(w http.ResponseWriter, r *http.Request) {
	if !ensurePlatformIsWeb(w, r) {
		return
	}

	var refresh string
	if ck, err := r.Cookie(middleware.RefreshTokenCookieName); err == nil {
		refresh = ck.Value
	}

	if err := c.adminAuthService.Logout(r.Context(), refresh); err != nil {
		utils.RespondErrorWithCode(w, http.StatusInternalServerError, utils.ErrCodeInternal, "Failed to logout", err)
		return
	}

	auth_utils.ClearAuthCookies(w, "/auth/v1/admin/refresh_token", c.cfg.LDFlag_CORSHighSecurity)
	utils.RespondWithJSON(w, http.StatusOK, auth_dtos.LogoutResponse{Message: "Logged out successfully"})
}