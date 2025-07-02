// meta-service/services/auth-service/internal/services/worker_auth_service.go
package services

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
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

	"github.com/poofware/auth-service/internal/config"
	"github.com/poofware/auth-service/internal/dtos"
	auth_repositories "github.com/poofware/auth-service/internal/repositories"
	internal_utils "github.com/poofware/auth-service/internal/utils"
	"github.com/poofware/go-models"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
)

// ---------------------------------------------------------------------
// WorkerAuthService interface
// ---------------------------------------------------------------------
type WorkerAuthService interface {
	Register(ctx context.Context, req dtos.RegisterWorkerRequest) error
	Login(
		ctx context.Context,
		phoneNumber string,
		totpCode string,
		clientIdentifier utils.ClientIdentifier,
		tokenExpiry time.Duration,
		refreshExpiry time.Duration,
	) (*models.Worker, string, string, error)
	RefreshToken(
		ctx context.Context,
		refreshTokenString string,
		clientIdentifier utils.ClientIdentifier,
		tokenExpiry time.Duration,
		refreshExpiry time.Duration,
	) (string, string, error)
	Logout(ctx context.Context, refreshTokenString string) error
	IssueChallenge(ctx context.Context, platform utils.PlatformType) (string, string, error)

	ValidateNewWorkerEmail(ctx context.Context, email string) error
	ValidateNewWorkerPhone(ctx context.Context, phone string) error

	RequestEmailCode(ctx context.Context, workerEmail string, workerID *uuid.UUID, clientID string) error
	VerifyEmailCode(ctx context.Context, workerEmail, code string, workerID *uuid.UUID, clientID string) (bool, error)
	RequestSMSCode(ctx context.Context, workerPhone string, workerID *uuid.UUID, clientID string) error
	VerifySMSCode(ctx context.Context, workerPhone, code string, workerID *uuid.UUID, clientID string) (bool, error)

	CheckPhoneVerifiedBeforeRegistration(ctx context.Context, phoneNumber, clientID string) (bool, *uuid.UUID, error)
	DeleteSMSVerificationRow(ctx context.Context, verificationID uuid.UUID) error
}

// ---------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------
type workerAuthService struct {
	workerRepo                  repositories.WorkerRepository
	workerLoginRepo             auth_repositories.WorkerLoginAttemptsRepository
	workerTokenRepo             auth_repositories.WorkerTokenRepository
	workerEmailVerificationRepo repositories.WorkerEmailVerificationRepository
	workerSMSVerificationRepo   repositories.WorkerSMSVerificationRepository
	challengeRepo               repositories.AttestationChallengeRepository
	rateLimiter                 RateLimiterService

	cfg              *config.Config
	workerJWTService JWTService
	sendgridClient   *sendgrid.Client
	twilioClient     *twilio.RestClient
}

func NewWorkerAuthService(
	workerRepo repositories.WorkerRepository,
	workerLoginRepo auth_repositories.WorkerLoginAttemptsRepository,
	workerTokenRepo auth_repositories.WorkerTokenRepository,
	workerEmailVerificationRepo repositories.WorkerEmailVerificationRepository,
	workerSMSVerificationRepo repositories.WorkerSMSVerificationRepository,
	rateLimiter RateLimiterService,
	challengeRepo repositories.AttestationChallengeRepository,
	cfg *config.Config,
) WorkerAuthService {

	jwtSvc := NewJWTService(cfg, workerTokenRepo)
	sgClient := sendgrid.NewSendClient(cfg.SendGridAPIKey)
	twClient := twilio.NewRestClientWithParams(twilio.ClientParams{
		Username: cfg.TwilioAccountSID,
		Password: cfg.TwilioAuthToken,
	})

	return &workerAuthService{
		workerRepo:                  workerRepo,
		workerLoginRepo:             workerLoginRepo,
		workerTokenRepo:             workerTokenRepo,
		workerEmailVerificationRepo: workerEmailVerificationRepo,
		workerSMSVerificationRepo:   workerSMSVerificationRepo,
		challengeRepo:               challengeRepo,
		rateLimiter:                 rateLimiter,
		cfg:                         cfg,
		workerJWTService:            jwtSvc,
		sendgridClient:              sgClient,
		twilioClient:                twClient,
	}
}

// ---------------------------------------------------------------------
// IssueChallenge (NEW)
// ---------------------------------------------------------------------
func (s *workerAuthService) IssueChallenge(ctx context.Context, platform utils.PlatformType) (string, string, error) {
	rawChallenge := make([]byte, 32)
	if _, err := rand.Read(rawChallenge); err != nil {
		return "", "", fmt.Errorf("failed to generate random challenge: %w", err)
	}

	challengeToStore := &models.AttestationChallenge{
		ID:           uuid.New(),
		RawChallenge: rawChallenge,
		Platform:     platform.String(),
		ExpiresAt:    time.Now().Add(5 * time.Minute),
	}

	if err := s.challengeRepo.Create(ctx, challengeToStore); err != nil {
		return "", "", fmt.Errorf("failed to store challenge: %w", err)
	}

	var platformChallenge string
	if platform == utils.PlatformIOS {
		platformChallenge = base64.RawURLEncoding.EncodeToString(rawChallenge)
	} else { // android
		hash := sha256.Sum256(rawChallenge)
		platformChallenge = base64.RawURLEncoding.EncodeToString(hash[:])
	}

	return challengeToStore.ID.String(), platformChallenge, nil
}

// ---------------------------------------------------------------------
// Register
// ---------------------------------------------------------------------
func (s *workerAuthService) Register(ctx context.Context, req dtos.RegisterWorkerRequest) error {
	ok, err := utils.ValidateEmail(ctx, s.cfg.SendGridAPIKey, req.Email, s.cfg.LDFlag_ValidateEmailWithSendGrid)
	if err != nil {
		return err
	}
	if !ok {
		return errors.New("undeliverable email address")
	}

	w := &models.Worker{
		ID:          uuid.New(),
		Email:       req.Email,
		PhoneNumber: req.PhoneNumber,
		TOTPSecret:  req.TOTPSecret,
		FirstName:   req.FirstName,
		LastName:    req.LastName,
	}
	return s.workerRepo.Create(ctx, w)
}

// ---------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------
func (s *workerAuthService) Login(
	ctx context.Context,
	phoneNumber string,
	totpCode string,
	clientIdentifier utils.ClientIdentifier,
	tokenExpiry time.Duration,
	refreshExpiry time.Duration,
) (*models.Worker, string, string, error) {

	w, err := s.workerRepo.GetByPhoneNumber(ctx, phoneNumber)
	if err != nil || w == nil {
		return nil, "", "", errors.New("invalid credentials")
	}

	if _, err := s.workerLoginRepo.GetOrCreate(ctx, w.ID); err != nil {
		utils.Logger.WithError(err).Error("Failed to get or create Worker login attempt record")
		return nil, "", "", errors.New("internal server error")
	}

	locked, lockedUntil, err := s.workerLoginRepo.IsLocked(ctx, w.ID)
	if err == nil && locked {
		return nil, "", "", fmt.Errorf("Worker account locked until %s", lockedUntil.Format(time.RFC3339))
	}

	// Special case for Google Play reviewer with a static code
	isReviewerBypass := w.PhoneNumber == utils.GooglePlayStoreReviewerPhone && totpCode == utils.GooglePlayStoreReviewerBypassTOTP

	// TOTP check (bypassed if isReviewerBypass is true)
	if !isReviewerBypass && !internal_utils.ValidateTOTPCode(w.TOTPSecret, totpCode) {
		if incErr := s.workerLoginRepo.Increment(ctx, w.ID, s.cfg.LockDuration, s.cfg.AttemptWindow, s.cfg.MaxLoginAttempts); incErr != nil {
			utils.Logger.WithError(incErr).Error("Failed to increment worker login attempts")
		}
		return nil, "", "", errors.New("invalid credentials")
	}
	_ = s.workerLoginRepo.Reset(ctx, w.ID)

	if removeErr := s.workerTokenRepo.RemoveAllRefreshTokensByUserID(ctx, w.ID); removeErr != nil {
		utils.Logger.WithError(removeErr).Error("failed to remove old worker tokens on login")
	}

	attFingerprint, _ := ctx.Value(utils.CtxKeyAttestation).(string)

	accessToken, aErr := s.workerJWTService.GenerateAccessToken(
		ctx,
		w.ID,
		clientIdentifier,
		tokenExpiry,
		refreshExpiry,
		attFingerprint,
	)
	if aErr != nil {
		utils.Logger.WithError(aErr).Error("Failed to generate worker access token (login)")
		return nil, "", "", errors.New("token generation failed")
	}

	refreshObj, rErr := s.workerJWTService.GenerateRefreshToken(ctx, w.ID, clientIdentifier, refreshExpiry)
	if rErr != nil {
		utils.Logger.WithError(rErr).Error("Failed to generate worker refresh token (login)")
		return nil, "", "", errors.New("token generation failed")
	}

	return w, accessToken, refreshObj.Token, nil
}

// ---------------------------------------------------------------------
// Refresh
// ---------------------------------------------------------------------
func (s *workerAuthService) RefreshToken(
	ctx context.Context,
	refreshTokenString string,
	clientIdentifier utils.ClientIdentifier,
	tokenExpiry time.Duration,
	refreshExpiry time.Duration,
) (string, string, error) {

	attFingerprint, _ := ctx.Value(utils.CtxKeyAttestation).(string)

	return s.workerJWTService.RefreshToken(
		ctx,
		refreshTokenString,
		clientIdentifier,
		tokenExpiry,
		refreshExpiry,
		attFingerprint,
	)
}

// ---------------------------------------------------------------------
// Logout
// ---------------------------------------------------------------------
func (s *workerAuthService) Logout(ctx context.Context, refreshTokenString string) error {
	return s.workerJWTService.Logout(ctx, refreshTokenString)
}

// ---------------------------------------------------------------------
// Validate new Worker Email / Phone
// ---------------------------------------------------------------------
func (s *workerAuthService) ValidateNewWorkerEmail(ctx context.Context, email string) error {
	ok, err := utils.ValidateEmail(ctx, s.cfg.SendGridAPIKey, email, s.cfg.LDFlag_ValidateEmailWithSendGrid)
	if err != nil {
		return err
	}
	if !ok {
		return utils.ErrInvalidEmail
	}
	w, err := s.workerRepo.GetByEmail(ctx, email)
	if err != nil && err != pgx.ErrNoRows {
		return err
	}
	if w != nil {
		return utils.ErrEmailExists
	}
	return nil
}

func (s *workerAuthService) ValidateNewWorkerPhone(ctx context.Context, phone string) error {
	ok, err := utils.ValidatePhoneNumber(ctx, phone, nil, s.cfg.LDFlag_ValidatePhoneWithTwilio, s.twilioClient)
	if err != nil {
		return err
	}
	if !ok {
		return utils.ErrInvalidPhone
	}
	w, err := s.workerRepo.GetByPhoneNumber(ctx, phone)
	if err != nil && err != pgx.ErrNoRows {
		return err
	}
	if w != nil {
		return utils.ErrPhoneExists
	}
	return nil
}

// ---------------------------------------------------------------------
// RequestEmailCode / VerifyEmailCode
// ---------------------------------------------------------------------
func (s *workerAuthService) RequestEmailCode(
	ctx context.Context,
	workerEmail string,
	workerID *uuid.UUID,
	clientID string,
) error {
	if err := s.rateLimiter.CheckEmailRateLimits(ctx, clientID, workerEmail); err != nil {
		return err
	}

	ok, err := utils.ValidateEmail(ctx, s.cfg.SendGridAPIKey, workerEmail, s.cfg.LDFlag_ValidateEmailWithSendGrid)
	if err != nil {
		return err
	}
	if !ok {
		return errors.New("email address failed deliverability check")
	}

	existing, _ := s.workerEmailVerificationRepo.GetCode(ctx, workerEmail)
	if existing != nil {
		_ = s.workerEmailVerificationRepo.DeleteCode(ctx, existing.ID)
	}

	expiresAt := time.Now().Add(s.cfg.VerificationCodeExpiry)
	if s.cfg.LDFlag_AcceptFakePhonesEmails && utils.TestEmailRegex.MatchString(workerEmail) {
		return s.workerEmailVerificationRepo.CreateCode(ctx, workerID, workerEmail, TestEmailCode, expiresAt)
	}

	code, genErr := generateVerificationCode(s.cfg.VerificationCodeLength)
	if genErr != nil {
		return genErr
	}

	if cErr := s.workerEmailVerificationRepo.CreateCode(ctx, workerID, workerEmail, code, expiresAt); cErr != nil {
		return cErr
	}

	from := mail.NewEmail(s.cfg.OrganizationName, s.cfg.LDFlag_SendgridFromEmail)
	to := mail.NewEmail("", workerEmail)
	subject := s.cfg.OrganizationName + " - Worker Verification Code"
	plainTextContent := fmt.Sprintf("Your verification code is %s", code)
	htmlContent := fmt.Sprintf(verificationEmailHTML, code, time.Now().Year())
	message := mail.NewSingleEmail(from, subject, to, plainTextContent, htmlContent)

	if s.cfg.LDFlag_SendgridSandboxMode {
		ms := mail.NewMailSettings()
		ms.SetSandboxMode(mail.NewSetting(true))
		message.MailSettings = ms
	}

	_, sendErr := s.sendgridClient.Send(message)
	return sendErr
}

func (s *workerAuthService) VerifyEmailCode(
	ctx context.Context,
	workerEmail, code string,
	workerID *uuid.UUID,
	clientID string,
) (bool, error) {
	rec, err := s.workerEmailVerificationRepo.GetCode(ctx, workerEmail)
	if err != nil || rec == nil {
		return false, err
	}

	if rec.Verified {
		return false, nil
	}

	if rec.VerificationCode != code || time.Now().After(rec.ExpiresAt) {
		_ = s.workerEmailVerificationRepo.IncrementAttempts(ctx, rec.ID)
		return false, nil
	}

	w, _ := s.workerRepo.GetByEmail(ctx, workerEmail)
	if w != nil {
		if delErr := s.workerEmailVerificationRepo.DeleteCode(ctx, rec.ID); delErr != nil {
			return false, delErr
		}
	} else {
		if markErr := s.workerEmailVerificationRepo.MarkVerified(ctx, rec.ID, clientID); markErr != nil {
			return false, markErr
		}
	}
	return true, nil
}

// ---------------------------------------------------------------------
// RequestSMSCode / VerifySMSCode
// ---------------------------------------------------------------------
func (s *workerAuthService) RequestSMSCode(
	ctx context.Context,
	workerPhone string,
	workerID *uuid.UUID,
	clientID string,
) error {
	if err := s.rateLimiter.CheckSMSRateLimits(ctx, clientID, workerPhone); err != nil {
		return err
	}

	ok, err := utils.ValidatePhoneNumber(ctx, workerPhone, nil, s.cfg.LDFlag_ValidatePhoneWithTwilio, s.twilioClient)
	if err != nil {
		return err
	}
	if !ok {
		return errors.New("phone number failed validation")
	}

	existing, _ := s.workerSMSVerificationRepo.GetCode(ctx, workerPhone)
	if existing != nil {
		_ = s.workerSMSVerificationRepo.DeleteCode(ctx, existing.ID)
	}

	expiresAt := time.Now().Add(s.cfg.VerificationCodeExpiry)
	if s.cfg.LDFlag_AcceptFakePhonesEmails && strings.HasPrefix(workerPhone, utils.TestPhoneNumberBase) {
		return s.workerSMSVerificationRepo.CreateCode(ctx, workerID, workerPhone, TestPhoneCode, expiresAt)
	}

	code, genErr := generateVerificationCode(s.cfg.VerificationCodeLength)
	if genErr != nil {
		return genErr
	}

	if cErr := s.workerSMSVerificationRepo.CreateCode(ctx, workerID, workerPhone, code, expiresAt); cErr != nil {
		return cErr
	}

	params := &twilioApi.CreateMessageParams{}
	params.SetTo(workerPhone)
	params.SetFrom(s.cfg.LDFlag_TwilioFromPhone)
	params.SetBody(fmt.Sprintf("Your Worker verification code is %s", code))

	_, sendErr := s.twilioClient.Api.CreateMessage(params)
	return sendErr
}

func (s *workerAuthService) VerifySMSCode(
	ctx context.Context,
	workerPhone, code string,
	workerID *uuid.UUID,
	clientID string,
) (bool, error) {
	rec, err := s.workerSMSVerificationRepo.GetCode(ctx, workerPhone)
	if err != nil || rec == nil {
		return false, err
	}

	if rec.Verified {
		return false, nil
	}

	if rec.VerificationCode != code || time.Now().After(rec.ExpiresAt) {
		_ = s.workerSMSVerificationRepo.IncrementAttempts(ctx, rec.ID)
		return false, nil
	}

	w, _ := s.workerRepo.GetByPhoneNumber(ctx, workerPhone)
	if w != nil {
		if delErr := s.workerSMSVerificationRepo.DeleteCode(ctx, rec.ID); delErr != nil {
			return false, delErr
		}
	} else {
		if markErr := s.workerSMSVerificationRepo.MarkVerified(ctx, rec.ID, clientID); markErr != nil {
			return false, markErr
		}
	}
	return true, nil
}

// ---------------------------------------------------------------------
// CheckPhoneVerifiedBeforeRegistration
// ---------------------------------------------------------------------
func (s *workerAuthService) CheckPhoneVerifiedBeforeRegistration(
	ctx context.Context,
	phoneNumber, clientID string,
) (bool, *uuid.UUID, error) {
	ok, id, err := s.workerSMSVerificationRepo.IsCurrentlyVerified(ctx, nil, phoneNumber, clientID)
	return ok, id, err
}

func (s *workerAuthService) DeleteSMSVerificationRow(ctx context.Context, verificationID uuid.UUID) error {
	return s.workerSMSVerificationRepo.DeleteCode(ctx, verificationID)
}
