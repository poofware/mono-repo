// meta-service/services/auth-service/internal/services/admin_auth_service.go
package services

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/poofware/mono-repo/backend/services/auth-service/internal/config"
	auth_repositories "github.com/poofware/mono-repo/backend/services/auth-service/internal/repositories"
	internal_utils "github.com/poofware/mono-repo/backend/services/auth-service/internal/utils"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

// AdminAuthService defines the interface for admin authentication logic.
type AdminAuthService interface {
	Login(
		ctx context.Context,
		username string,
		password string,
		totpCode string,
		clientIdentifier utils.ClientIdentifier,
		tokenExpiry time.Duration,
		refreshExpiry time.Duration,
	) (*models.Admin, string, string, error)
	RefreshToken(
		ctx context.Context,
		refreshTokenString string,
		clientIdentifier utils.ClientIdentifier,
		tokenExpiry time.Duration,
		refreshExpiry time.Duration,
	) (string, string, error)
	Logout(ctx context.Context, refreshTokenString string) error
}

type adminAuthService struct {
	adminRepo       repositories.AdminRepository
	adminLoginRepo  auth_repositories.AdminLoginAttemptsRepository
	adminTokenRepo  auth_repositories.AdminTokenRepository
	rateLimiter     RateLimiterService
	cfg             *config.Config
	adminJWTService JWTService
}

// NewAdminAuthService creates a new AdminAuthService.
func NewAdminAuthService(
	adminRepo repositories.AdminRepository,
	adminLoginRepo auth_repositories.AdminLoginAttemptsRepository,
	adminTokenRepo auth_repositories.AdminTokenRepository,
	rateLimiter RateLimiterService,
	cfg *config.Config,
) AdminAuthService {
	jwtSvc := NewJWTService(cfg, adminTokenRepo)
	return &adminAuthService{
		adminRepo:       adminRepo,
		adminLoginRepo:  adminLoginRepo,
		adminTokenRepo:  adminTokenRepo,
		rateLimiter:     rateLimiter,
		cfg:             cfg,
		adminJWTService: jwtSvc,
	}
}

func (s *adminAuthService) Login(
	ctx context.Context,
	username string,
	password string,
	totpCode string,
	clientIdentifier utils.ClientIdentifier,
	tokenExpiry time.Duration,
	refreshExpiry time.Duration,
) (*models.Admin, string, string, error) {
	admin, err := s.adminRepo.GetByUsername(ctx, username)
	if err != nil || admin == nil {
		return nil, "", "", errors.New("invalid credentials")
	}

	if _, err := s.adminLoginRepo.GetOrCreate(ctx, admin.ID); err != nil {
		utils.Logger.WithError(err).Error("Failed to get or create Admin login attempt record")
		return nil, "", "", errors.New("internal server error")
	}

	locked, lockedUntil, err := s.adminLoginRepo.IsLocked(ctx, admin.ID)
	if err == nil && locked {
		return nil, "", "", fmt.Errorf("admin account locked until %s", lockedUntil.Format(time.RFC3339))
	}

	if !utils.CheckPasswordHash(password, admin.PasswordHash) {
		if incErr := s.adminLoginRepo.Increment(ctx, admin.ID, s.cfg.LockDuration, s.cfg.AttemptWindow, s.cfg.MaxLoginAttempts); incErr != nil {
			utils.Logger.WithError(incErr).Error("Failed to increment admin login attempts")
		}
		return nil, "", "", errors.New("invalid credentials")
	}

	if !internal_utils.ValidateTOTPCode(admin.TOTPSecret, totpCode) {
		if incErr := s.adminLoginRepo.Increment(ctx, admin.ID, s.cfg.LockDuration, s.cfg.AttemptWindow, s.cfg.MaxLoginAttempts); incErr != nil {
			utils.Logger.WithError(incErr).Error("Failed to increment admin login attempts")
		}
		return nil, "", "", errors.New("invalid credentials")
	}

	_ = s.adminLoginRepo.Reset(ctx, admin.ID)

	if removeErr := s.adminTokenRepo.RemoveAllRefreshTokensByUserID(ctx, admin.ID); removeErr != nil {
		utils.Logger.WithError(removeErr).Error("failed to remove old admin tokens on login")
	}

	accessToken, aErr := s.adminJWTService.GenerateAccessToken(ctx, admin.ID, clientIdentifier, tokenExpiry, refreshExpiry, "")
	if aErr != nil {
		utils.Logger.WithError(aErr).Error("Failed to generate admin access token")
		return nil, "", "", errors.New("token generation failed")
	}

	refreshObj, rErr := s.adminJWTService.GenerateRefreshToken(ctx, admin.ID, clientIdentifier, refreshExpiry)
	if rErr != nil {
		utils.Logger.WithError(rErr).Error("Failed to generate admin refresh token")
		return nil, "", "", errors.New("token generation failed")
	}

	return admin, accessToken, refreshObj.Token, nil
}

func (s *adminAuthService) RefreshToken(
	ctx context.Context,
	refreshTokenString string,
	clientIdentifier utils.ClientIdentifier,
	tokenExpiry time.Duration,
	refreshExpiry time.Duration,
) (string, string, error) {
	return s.adminJWTService.RefreshToken(ctx, refreshTokenString, clientIdentifier, tokenExpiry, refreshExpiry, "")
}

func (s *adminAuthService) Logout(ctx context.Context, refreshTokenString string) error {
	return s.adminJWTService.Logout(ctx, refreshTokenString)
}