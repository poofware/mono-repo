// backend/services/auth-service/internal/services/pm_auth_service.go
package services

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
	"github.com/sendgrid/sendgrid-go"
	"github.com/sendgrid/sendgrid-go/helpers/mail"
	"github.com/twilio/twilio-go"
	twilioApi "github.com/twilio/twilio-go/rest/api/v2010"

	"github.com/poofware/mono-repo/backend/services/auth-service/internal/config"
	"github.com/poofware/mono-repo/backend/services/auth-service/internal/dtos"
	auth_repositories "github.com/poofware/mono-repo/backend/services/auth-service/internal/repositories"
	internal_utils "github.com/poofware/mono-repo/backend/services/auth-service/internal/utils"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

// PMAuthService interface
type PMAuthService interface {
	Register(ctx context.Context, req dtos.RegisterPMRequest) error

	// Now includes platform param but we do NOT do device attestation for PM
	Login(
		ctx context.Context,
		email string,
		totpCode string,
		clientIdentifier utils.ClientIdentifier,
		tokenExpiry time.Duration,
		refreshExpiry time.Duration,
		platform utils.PlatformType,
	) (*models.PropertyManager, string, string, error)

	// Also includes platform param for consistency
	RefreshToken(
		ctx context.Context,
		refreshTokenString string,
		clientIdentifier utils.ClientIdentifier,
		tokenExpiry time.Duration,
		refreshExpiry time.Duration,
		platform utils.PlatformType,
	) (string, string, error)

	Logout(ctx context.Context, refreshTokenString string) error

	ValidateNewPMEmail(ctx context.Context, email string) error
	ValidateNewPMPhone(ctx context.Context, phone string) error

	RequestEmailCode(ctx context.Context, pmEmail string, pmID *uuid.UUID, clientID string) error
	VerifyEmailCode(ctx context.Context, pmEmail, code string, pmID *uuid.UUID, clientID string) (bool, error)
	RequestSMSCode(ctx context.Context, pmPhone string, pmID *uuid.UUID, clientID string) error
	VerifySMSCode(ctx context.Context, pmPhone, code string, pmID *uuid.UUID, clientID string) (bool, error)

	CheckEmailVerifiedBeforeRegistration(ctx context.Context, pmEmail, clientID string) (bool, *uuid.UUID, error)
	DeleteEmailVerificationRow(ctx context.Context, verificationID uuid.UUID) error
	// NEW: Add a check for SMS verification before registration
	CheckSMSVerifiedBeforeRegistration(ctx context.Context, pmPhone, clientID string) (bool, *uuid.UUID, error)
	DeleteSMSVerificationRow(ctx context.Context, verificationID uuid.UUID) error
	InitiateDeletion(ctx context.Context, email string, clientID string) (string, error)
	ConfirmDeletion(ctx context.Context, req dtos.ConfirmDeletionRequest) error
}

type pmAuthService struct {
	pmRepo                  repositories.PropertyManagerRepository
	pmLoginRepo             auth_repositories.PMLoginAttemptsRepository
	pmTokenRepo             auth_repositories.PMTokenRepository
	pmEmailVerificationRepo repositories.PMEmailVerificationRepository
	pmSMSVerificationRepo   repositories.PMSMSVerificationRepository
	pendingDeletionRepo     auth_repositories.PendingPMDeletionRepository
	rateLimiter             RateLimiterService

	Cfg            *config.Config
	pmJWTService   JWTService
	sendgridClient *sendgrid.Client
	twilioClient   *twilio.RestClient
}

// Constructor
func NewPMAuthService(
	pmRepo repositories.PropertyManagerRepository,
	pmLoginRepo auth_repositories.PMLoginAttemptsRepository,
	pmTokenRepo auth_repositories.PMTokenRepository,
	pmEmailVerificationRepo repositories.PMEmailVerificationRepository,
	pmSMSVerificationRepo repositories.PMSMSVerificationRepository,
	pendingDeletionRepo auth_repositories.PendingPMDeletionRepository,
	rateLimiter RateLimiterService,
	cfg *config.Config,
) PMAuthService {

	pmJWTService := NewJWTService(cfg, pmTokenRepo)
	sgClient := sendgrid.NewSendClient(cfg.SendGridAPIKey)
	tClient := twilio.NewRestClientWithParams(twilio.ClientParams{
		Username: cfg.TwilioAccountSID,
		Password: cfg.TwilioAuthToken,
	})

	return &pmAuthService{
		pmRepo:                  pmRepo,
		pmLoginRepo:             pmLoginRepo,
		pmTokenRepo:             pmTokenRepo,
		pmEmailVerificationRepo: pmEmailVerificationRepo,
		pmSMSVerificationRepo:   pmSMSVerificationRepo,
		pendingDeletionRepo:     pendingDeletionRepo,
		rateLimiter:             rateLimiter,
		Cfg:                     cfg,
		pmJWTService:            pmJWTService,
		sendgridClient:          sgClient,
		twilioClient:            tClient,
	}
}
// Add CheckSMSVerifiedBeforeRegistration to satisfy the interface
func (s *pmAuthService) CheckSMSVerifiedBeforeRegistration(ctx context.Context, pmPhone, clientID string) (bool, *uuid.UUID, error) {
	return s.pmSMSVerificationRepo.IsCurrentlyVerified(ctx, nil, pmPhone, clientID)
}

// Add DeleteSMSVerificationRow to satisfy the interface
func (s *pmAuthService) DeleteSMSVerificationRow(ctx context.Context, verificationID uuid.UUID) error {
	return s.pmSMSVerificationRepo.DeleteCode(ctx, verificationID)
}

// ---------------------------------------------------------------------
// Register
// ---------------------------------------------------------------------
func (s *pmAuthService) Register(ctx context.Context, req dtos.RegisterPMRequest) error {
	// Phone number is optional for PMs, but if it's provided, we must validate it.
	if req.PhoneNumber != nil && *req.PhoneNumber != "" {
		ok, err := utils.ValidatePhoneNumber(ctx, *req.PhoneNumber, nil, s.Cfg.LDFlag_ValidatePhoneWithTwilio, s.twilioClient)
		if err != nil {
			return err // Error during validation call (e.g., Twilio API down)
		}
		if !ok {
			return utils.ErrInvalidPhone // Specific error for invalid phone format
		}
	}

	pm := &models.PropertyManager{
		ID:              uuid.New(),
		Email:           req.Email,
		PhoneNumber:     req.PhoneNumber,
		TOTPSecret:      req.TOTPSecret,
		BusinessName:    req.BusinessName,
		BusinessAddress: req.BusinessAddress,
		City:            req.City,
		State:           req.State,
		ZipCode:         req.ZipCode,
	}
	return s.pmRepo.Create(ctx, pm)
}

// ---------------------------------------------------------------------
// Login (PM only uses web, no device attestation logic here)
// ---------------------------------------------------------------------
func (s *pmAuthService) Login(
	ctx context.Context,
	email string,
	totpCode string,
	clientIdentifier utils.ClientIdentifier,
	tokenExpiry time.Duration,
	refreshExpiry time.Duration,
	platform utils.PlatformType,
) (*models.PropertyManager, string, string, error) {

	// (No device-att checks for PM)

	pm, err := s.pmRepo.GetByEmail(ctx, email)
	if err != nil || pm == nil {
		return nil, "", "", errors.New("invalid credentials")
	}

	// FIX: Ensure a login attempt record exists before we check or increment it.
	if _, err := s.pmLoginRepo.GetOrCreate(ctx, pm.ID); err != nil {
		utils.Logger.WithError(err).Error("Failed to get or create PM login attempt record")
		return nil, "", "", errors.New("internal server error")
	}

	locked, lockedUntil, err := s.pmLoginRepo.IsLocked(ctx, pm.ID)
	if err == nil && locked {
		return nil, "", "", fmt.Errorf("PM account locked until %s", lockedUntil.Format(time.RFC3339))
	}

	if !internal_utils.ValidateTOTPCode(pm.TOTPSecret, totpCode) {
		// FIX: Handle error from Increment call for robust logging.
		if incErr := s.pmLoginRepo.Increment(ctx, pm.ID, s.Cfg.LockDuration, s.Cfg.AttemptWindow, s.Cfg.MaxLoginAttempts); incErr != nil {
			utils.Logger.WithError(incErr).Error("Failed to increment PM login attempts")
		}
		return nil, "", "", errors.New("invalid credentials")
	}
	_ = s.pmLoginRepo.Reset(ctx, pm.ID)

	// remove old refresh tokens
	if removeErr := s.pmTokenRepo.RemoveAllRefreshTokensByUserID(ctx, pm.ID); removeErr != nil {
		utils.Logger.WithError(removeErr).Error("failed to remove old PM tokens on login")
	}

	// Generate Access token + Refresh token
	accessToken, aErr := s.pmJWTService.GenerateAccessToken(ctx, pm.ID, clientIdentifier, tokenExpiry, refreshExpiry, "")
	if aErr != nil {
		utils.Logger.WithError(aErr).Error("Failed to generate PM access token (login)")
		return nil, "", "", errors.New("token generation failed")
	}

	refreshObj, rErr := s.pmJWTService.GenerateRefreshToken(ctx, pm.ID, clientIdentifier, refreshExpiry)
	if rErr != nil {
		utils.Logger.WithError(rErr).Error("Failed to generate PM refresh token (login)")
		return nil, "", "", errors.New("token generation failed")
	}

	return pm, accessToken, refreshObj.Token, nil
}

// ---------------------------------------------------------------------
// Refresh (still no device att for PM)
// ---------------------------------------------------------------------
func (s *pmAuthService) RefreshToken(
	ctx context.Context,
	refreshTokenString string,
	clientIdentifier utils.ClientIdentifier,
	tokenExpiry time.Duration,
	refreshExpiry time.Duration,
	platform utils.PlatformType,
) (string, string, error) {

	return s.pmJWTService.RefreshToken(
		ctx,
		refreshTokenString,
		clientIdentifier,
		tokenExpiry,
		refreshExpiry,
		"", // no attFingerprint for PM
	)
}

// ---------------------------------------------------------------------
// Logout
// ---------------------------------------------------------------------
func (s *pmAuthService) Logout(ctx context.Context, refreshTokenString string) error {
	return s.pmJWTService.Logout(ctx, refreshTokenString)
}

// ---------------------------------------------------------------------
// Validate new PM Email / Phone
// ---------------------------------------------------------------------
func (s *pmAuthService) ValidateNewPMEmail(ctx context.Context, email string) error {
	ok, err := utils.ValidateEmail(ctx, s.Cfg.SendGridAPIKey, email, s.Cfg.LDFlag_ValidateEmailWithSendGrid)
	if err != nil {
		return err
	}
	if !ok {
		return utils.ErrInvalidEmail
	}

	pm, err := s.pmRepo.GetByEmail(ctx, email)
	if err != nil && err != pgx.ErrNoRows {
		return err
	}
	if pm != nil {
		return utils.ErrEmailExists
	}
	return nil
}

func (s *pmAuthService) ValidateNewPMPhone(ctx context.Context, phone string) error {
	ok, err := utils.ValidatePhoneNumber(ctx, phone, nil, s.Cfg.LDFlag_ValidatePhoneWithTwilio, s.twilioClient)
	if err != nil {
		return err
	}
	if !ok {
		return utils.ErrInvalidPhone
	}

	pm, err := s.pmRepo.GetByPhoneNumber(ctx, phone)
	if err != nil && err != pgx.ErrNoRows {
		return err
	}
	if pm != nil {
		return utils.ErrPhoneExists
	}
	return nil
}

// ---------------------------------------------------------------------
// Request/Verify Email Code
// ---------------------------------------------------------------------
func (s *pmAuthService) RequestEmailCode(
	ctx context.Context,
	pmEmail string,
	pmID *uuid.UUID,
	clientID string,
) error {
	if err := s.rateLimiter.CheckEmailRateLimits(ctx, clientID, pmEmail); err != nil {
		return err
	}

	ok, err := utils.ValidateEmail(ctx, s.Cfg.SendGridAPIKey, pmEmail, s.Cfg.LDFlag_ValidateEmailWithSendGrid)
	if err != nil {
		return err
	}
	if !ok {
		return errors.New("email address failed deliverability check")
	}

	existing, _ := s.pmEmailVerificationRepo.GetCode(ctx, pmEmail)
	if existing != nil {
		_ = s.pmEmailVerificationRepo.DeleteCode(ctx, existing.ID)
	}

	expiresAt := time.Now().Add(s.Cfg.VerificationCodeExpiry)
	if s.Cfg.LDFlag_AcceptFakePhonesEmails && utils.TestEmailRegex.MatchString(pmEmail) {
		return s.pmEmailVerificationRepo.CreateCode(ctx, pmID, pmEmail, TestEmailCode, expiresAt)
	}

	code, genErr := generateVerificationCode(s.Cfg.VerificationCodeLength)
	if genErr != nil {
		return genErr
	}

	if cErr := s.pmEmailVerificationRepo.CreateCode(ctx, pmID, pmEmail, code, expiresAt); cErr != nil {
		return cErr
	}

	from := mail.NewEmail(s.Cfg.OrganizationName, s.Cfg.LDFlag_SendgridFromEmail)
	to := mail.NewEmail("", pmEmail)
	subject := s.Cfg.OrganizationName + " - Verification Code"
	// Create both plain text and HTML content
	plainTextContent := fmt.Sprintf("Your verification code is %s", code)
	htmlContent := fmt.Sprintf(verificationEmailHTML, "Verification Code", "Please use the following code to complete your verification. This code will expire in 5 minutes.", code, time.Now().Year())
	message := mail.NewSingleEmail(from, subject, to, plainTextContent, htmlContent)

	if s.Cfg.LDFlag_SendgridSandboxMode {
		ms := mail.NewMailSettings()
		ms.SetSandboxMode(mail.NewSetting(true))
		message.MailSettings = ms
	}

	_, sendErr := s.sendgridClient.Send(message)
	if sendErr != nil {
		utils.Logger.WithError(sendErr).Errorf("Failed to send verification email to %s via SendGrid", pmEmail)
		return fmt.Errorf("%w: failed to send email via sendgrid: %v", utils.ErrExternalServiceFailure, sendErr)
	}
	return nil
}

func (s *pmAuthService) VerifyEmailCode(
	ctx context.Context,
	pmEmail, code string,
	pmID *uuid.UUID,
	clientID string,
) (bool, error) {
	rec, err := s.pmEmailVerificationRepo.GetCode(ctx, pmEmail)
	if err != nil || rec == nil {
		return false, err
	}

	// FIXED: Prevent re-use of an already verified code.
	if rec.Verified {
		return false, nil
	}

	if rec.VerificationCode != code || time.Now().After(rec.ExpiresAt) {
		_ = s.pmEmailVerificationRepo.IncrementAttempts(ctx, rec.ID)
		return false, nil
	}

	pm, _ := s.pmRepo.GetByEmail(ctx, pmEmail)
	if pm != nil {
		if delErr := s.pmEmailVerificationRepo.DeleteCode(ctx, rec.ID); delErr != nil {
			return false, delErr
		}
	} else {
		if markErr := s.pmEmailVerificationRepo.MarkVerified(ctx, rec.ID, clientID); markErr != nil {
			return false, markErr
		}
	}
	return true, nil
}

// ---------------------------------------------------------------------
// Request/Verify SMS Code
// ---------------------------------------------------------------------
func (s *pmAuthService) RequestSMSCode(
	ctx context.Context,
	pmPhone string,
	pmID *uuid.UUID,
	clientID string,
) error {
	if err := s.rateLimiter.CheckSMSRateLimits(ctx, clientID, pmPhone); err != nil {
		return err
	}

	ok, err := utils.ValidatePhoneNumber(ctx, pmPhone, nil, s.Cfg.LDFlag_ValidatePhoneWithTwilio, s.twilioClient)
	if err != nil {
		return err
	}
	if !ok {
		return errors.New("phone number failed validation")
	}

	existing, _ := s.pmSMSVerificationRepo.GetCode(ctx, pmPhone)
	if existing != nil {
		_ = s.pmSMSVerificationRepo.DeleteCode(ctx, existing.ID)
	}

	expiresAt := time.Now().Add(s.Cfg.VerificationCodeExpiry)
	if s.Cfg.LDFlag_AcceptFakePhonesEmails && strings.HasPrefix(pmPhone, utils.TestPhoneNumberBase) {
		return s.pmSMSVerificationRepo.CreateCode(ctx, pmID, pmPhone, TestPhoneCode, expiresAt)
	}

	code, genErr := generateVerificationCode(s.Cfg.VerificationCodeLength)
	if genErr != nil {
		return genErr
	}

	if cErr := s.pmSMSVerificationRepo.CreateCode(ctx, pmID, pmPhone, code, expiresAt); cErr != nil {
		return cErr
	}

	params := &twilioApi.CreateMessageParams{}
	params.SetTo(pmPhone)
	params.SetFrom(s.Cfg.LDFlag_TwilioFromPhone)
	params.SetBody(fmt.Sprintf("Your PM verification code is %s", code))

	_, twErr := s.twilioClient.Api.CreateMessage(params)
	if twErr != nil {
		utils.Logger.WithError(twErr).Errorf("Failed to send verification SMS to %s via Twilio", pmPhone)
		return fmt.Errorf("%w: failed to send sms via twilio: %v", utils.ErrExternalServiceFailure, twErr)
	}
	return nil
}

func (s *pmAuthService) VerifySMSCode(
	ctx context.Context,
	pmPhone, code string,
	pmID *uuid.UUID,
	clientID string,
) (bool, error) {
	rec, err := s.pmSMSVerificationRepo.GetCode(ctx, pmPhone)
	if err != nil || rec == nil {
		return false, err
	}

	// FIXED: Prevent re-use of an already verified code.
	if rec.Verified {
		return false, nil
	}

	if rec.VerificationCode != code || time.Now().After(rec.ExpiresAt) {
		_ = s.pmSMSVerificationRepo.IncrementAttempts(ctx, rec.ID)
		return false, nil
	}

	pm, _ := s.pmRepo.GetByPhoneNumber(ctx, pmPhone)
	if pm != nil {
		if delErr := s.pmSMSVerificationRepo.DeleteCode(ctx, rec.ID); delErr != nil {
			return false, delErr
		}
	} else {
		if markErr := s.pmSMSVerificationRepo.MarkVerified(ctx, rec.ID, clientID); markErr != nil {
			return false, markErr
		}
	}
	return true, nil
}

// ---------------------------------------------------------------------
// CheckEmailVerifiedBeforeRegistration
// ---------------------------------------------------------------------
func (s *pmAuthService) CheckEmailVerifiedBeforeRegistration(
	ctx context.Context,
	pmEmail, clientID string,
) (bool, *uuid.UUID, error) {
	verified, id, err := s.pmEmailVerificationRepo.IsCurrentlyVerified(ctx, nil, pmEmail, clientID)
	return verified, id, err
}

// ---------------------------------------------------------------------
// DeleteEmailVerificationRow
// ---------------------------------------------------------------------
func (s *pmAuthService) DeleteEmailVerificationRow(ctx context.Context, verificationID uuid.UUID) error {
	return s.pmEmailVerificationRepo.DeleteCode(ctx, verificationID)
}

// ---------------------------------------------------------------------
// Account Deletion Flow
// ---------------------------------------------------------------------

func (s *pmAuthService) InitiateDeletion(ctx context.Context, email string, clientID string) (string, error) {
	if err := s.rateLimiter.CheckEmailRateLimits(ctx, clientID, email); err != nil {
		return "", err
	}
	if err := s.rateLimiter.CheckSMSRateLimits(ctx, clientID, ""); err != nil {
		return "", err
	}

	pm, err := s.pmRepo.GetByEmail(ctx, email)
	if err != nil {
		return "", err
	}
	if pm == nil {
		return "", pgx.ErrNoRows
	}

	pmID := pm.ID
	deletionClientID := "pm-account-deletion"

	if err := s.RequestEmailCode(ctx, email, &pmID, deletionClientID); err != nil {
		return "", fmt.Errorf("%w: failed to send email code: %v", utils.ErrExternalServiceFailure, err)
	}

	if pm.PhoneNumber != nil && *pm.PhoneNumber != "" {
		if err := s.RequestSMSCode(ctx, *pm.PhoneNumber, &pmID, deletionClientID); err != nil {
			return "", fmt.Errorf("%w: failed to send sms code: %v", utils.ErrExternalServiceFailure, err)
		}
	}

	token := uuid.NewString()
	expires := time.Now().Add(15 * time.Minute)
	if err := s.pendingDeletionRepo.Create(ctx, token, pmID, expires); err != nil {
		return "", err
	}

	return token, nil
}

func (s *pmAuthService) ConfirmDeletion(ctx context.Context, req dtos.ConfirmDeletionRequest) error {
	pd, err := s.pendingDeletionRepo.Get(ctx, req.PendingToken)
	if err != nil {
		return err
	}
	if time.Now().After(pd.ExpiresAt) {
		_ = s.pendingDeletionRepo.Delete(ctx, req.PendingToken)
		return errors.New("token expired")
	}

	pm, err := s.pmRepo.GetByID(ctx, pd.PMID)
	if err != nil {
		return err
	}

	clientID := "pm-account-deletion"

	if req.TOTPCode != nil {
		if !internal_utils.ValidateTOTPCode(pm.TOTPSecret, *req.TOTPCode) {
			return errors.New("invalid totp")
		}
	} else {
		if req.EmailCode == nil || (pm.PhoneNumber != nil && req.SMSCode == nil) {
			return errors.New("missing verification codes")
		}
		ok, err := s.VerifyEmailCode(ctx, pm.Email, *req.EmailCode, &pm.ID, clientID)
		if err != nil || !ok {
			return errors.New("email verification failed")
		}
		if pm.PhoneNumber != nil && *pm.PhoneNumber != "" {
			ok, err = s.VerifySMSCode(ctx, *pm.PhoneNumber, *req.SMSCode, &pm.ID, clientID)
			if err != nil || !ok {
				return errors.New("sms verification failed")
			}
		}
	}

	if err := s.SendDeletionRequestNotification(ctx, pm.Email); err != nil {
		return err
	}
	return s.pendingDeletionRepo.Delete(ctx, req.PendingToken)
}

func (s *pmAuthService) SendDeletionRequestNotification(ctx context.Context, pmEmail string) error {
	from := mail.NewEmail(s.Cfg.OrganizationName, s.Cfg.LDFlag_SendgridFromEmail)
	to := mail.NewEmail("", "team@thepoofapp.com") // Internal team email
	subject := fmt.Sprintf("URGENT: PM Account Deletion Request for %s", pmEmail)
	ts := time.Now().Format(time.RFC1123)
	plain := fmt.Sprintf("A verified property manager deletion request was received for %s at %s", pmEmail, ts)
	html := fmt.Sprintf(internalNotificationEmailHTML, "Account Deletion Request", fmt.Sprintf("A new account deletion request has been submitted by a user. Please process this request promptly.<ul><li><strong>Account Type:</strong> pm</li><li><strong>Email:</strong> %s</li><li><strong>Timestamp (UTC):</strong> %s</li></ul>", pmEmail, ts), time.Now().Year())
	msg := mail.NewSingleEmail(from, subject, to, plain, html)
	if s.Cfg.LDFlag_SendgridSandboxMode {
		ms := mail.NewMailSettings()
		ms.SetSandboxMode(mail.NewSetting(true))
		msg.MailSettings = ms
	}
	_, err := s.sendgridClient.Send(msg)
	return err
}
