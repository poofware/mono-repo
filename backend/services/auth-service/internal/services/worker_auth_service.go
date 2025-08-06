// backend/services/auth-service/internal/services/worker_auth_service.go
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

	InitiateDeletion(ctx context.Context, email string, clientID string) (string, error)
	ConfirmDeletion(ctx context.Context, req dtos.ConfirmDeletionRequest) error
	SendDeletionRequestNotification(ctx context.Context, workerEmail string, accountType string) error
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
	pendingDeletionRepo         auth_repositories.PendingWorkerDeletionRepository
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
	pendingDeletionRepo auth_repositories.PendingWorkerDeletionRepository,
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
		pendingDeletionRepo:         pendingDeletionRepo,
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
		return nil, "", "", fmt.Errorf("worker account locked until %s", lockedUntil.Format(time.RFC3339))
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
	htmlContent := fmt.Sprintf(verificationEmailHTML, "Verification Code", "Please use the following code to complete your verification. This code will expire in 5 minutes.", code, time.Now().Year())
	message := mail.NewSingleEmail(from, subject, to, plainTextContent, htmlContent)

	if s.cfg.LDFlag_SendgridSandboxMode {
		ms := mail.NewMailSettings()
		ms.SetSandboxMode(mail.NewSetting(true))
		message.MailSettings = ms
	}

	_, sendErr := s.sendgridClient.Send(message)
	if sendErr != nil {
		utils.Logger.WithError(sendErr).Errorf("Failed to send verification email to %s via SendGrid", workerEmail)
		return fmt.Errorf("%w: failed to send email via sendgrid: %v", utils.ErrExternalServiceFailure, sendErr)
	}
	return nil
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
	if sendErr != nil {
		utils.Logger.WithError(sendErr).Errorf("Failed to send verification SMS to %s via Twilio", workerPhone)
		return fmt.Errorf("%w: failed to send sms via twilio: %v", utils.ErrExternalServiceFailure, sendErr)
	}
	return nil
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

// ---------------------------------------------------------------------
// Account Deletion Flow
// ---------------------------------------------------------------------

// InitiateDeletion sends verification codes and creates a pending deletion token.
func (s *workerAuthService) InitiateDeletion(ctx context.Context, email string, clientID string) (string, error) {
	utils.Logger.Infof("Initiating deletion process for email: %s", email)
	if err := s.rateLimiter.CheckEmailRateLimits(ctx, clientID, email); err != nil {
		return "", err
	}
	if err := s.rateLimiter.CheckSMSRateLimits(ctx, clientID, ""); err != nil {
		return "", err
	}

	w, err := s.workerRepo.GetByEmail(ctx, email)
	if err != nil {
		// This will catch pgx.ErrNoRows and other DB errors
		utils.Logger.WithError(err).Errorf("Failed to find worker with email: %s", email)
		return "", err
	}
	// The controller handles pgx.ErrNoRows specifically, so we just propagate it.
	if w == nil {
		return "", pgx.ErrNoRows
	}

	workerID := w.ID
	deletionClientID := ClientIDWorkerAccountDeletion // A unique identifier for this flow

	// Send email code
	utils.Logger.Debugf("Requesting email code for worker %s", workerID)
	if err := s.RequestEmailCode(ctx, email, &workerID, deletionClientID); err != nil {
		utils.Logger.WithError(err).Errorf("Failed to send email code to %s for deletion", email)
		return "", fmt.Errorf("%w: failed to send email code: %v", utils.ErrExternalServiceFailure, err)
	}

	// Send SMS code
	utils.Logger.Debugf("Requesting SMS code for worker %s", workerID)
	if err := s.RequestSMSCode(ctx, w.PhoneNumber, &workerID, deletionClientID); err != nil {
		utils.Logger.WithError(err).Errorf("Failed to send SMS code to %s for deletion", w.PhoneNumber)
		return "", fmt.Errorf("%w: failed to send sms code: %v", utils.ErrExternalServiceFailure, err)
	}

	// Create pending deletion token
	token := uuid.NewString()
	expires := time.Now().Add(15 * time.Minute)
	utils.Logger.Debugf("Creating pending deletion record for worker %s", workerID)
	if err := s.pendingDeletionRepo.Create(ctx, token, workerID, expires); err != nil {
		utils.Logger.WithError(err).Errorf("Failed to create pending deletion record for worker %s", workerID)
		return "", err
	}

	utils.Logger.Infof("Successfully initiated deletion for worker %s. Pending token created.", workerID)
	return token, nil
}

// ConfirmDeletion verifies codes/TOTP and notifies operations.
func (s *workerAuthService) ConfirmDeletion(ctx context.Context, req dtos.ConfirmDeletionRequest) error {
	pd, err := s.pendingDeletionRepo.Get(ctx, req.PendingToken)
	if err != nil {
		return err
	}
	if time.Now().After(pd.ExpiresAt) {
		_ = s.pendingDeletionRepo.Delete(ctx, req.PendingToken)
		return errors.New("token expired")
	}

	worker, err := s.workerRepo.GetByID(ctx, pd.WorkerID)
	if err != nil {
		return err
	}

	clientID := ClientIDWorkerAccountDeletion

	if req.TOTPCode != nil {
		if !internal_utils.ValidateTOTPCode(worker.TOTPSecret, *req.TOTPCode) {
			return errors.New("invalid totp")
		}
	} else {
		if req.EmailCode == nil || req.SMSCode == nil {
			return errors.New("missing verification codes")
		}
		ok, err := s.VerifyEmailCode(ctx, worker.Email, *req.EmailCode, &worker.ID, clientID)
		if err != nil || !ok {
			return errors.New("email verification failed")
		}
		ok, err = s.VerifySMSCode(ctx, worker.PhoneNumber, *req.SMSCode, &worker.ID, clientID)
		if err != nil || !ok {
			return errors.New("sms verification failed")
		}
	}

	if err := s.SendDeletionRequestNotification(ctx, worker.Email, "worker"); err != nil {
		return err
	}
	return s.pendingDeletionRepo.Delete(ctx, req.PendingToken)
}

// SendDeletionRequestNotification notifies the Poof team of a verified deletion request.
func (s *workerAuthService) SendDeletionRequestNotification(ctx context.Context, workerEmail string, accountType string) error {
	from := mail.NewEmail(s.cfg.OrganizationName, s.cfg.LDFlag_SendgridFromEmail)
	to := mail.NewEmail("", "team@thepoofapp.com")
	subject := fmt.Sprintf("URGENT: Account Deletion Request for %s", workerEmail)
	ts := time.Now().Format(time.RFC1123)
	plain := fmt.Sprintf("A verified deletion request was received for %s (account type: %s) at %s", workerEmail, accountType, ts)
	html := fmt.Sprintf(internalNotificationEmailHTML, "Account Deletion Request", fmt.Sprintf("A new account deletion request has been submitted by a user. Please process this request promptly.<ul><li><strong>Account Type:</strong> %s</li><li><strong>Email:</strong> %s</li><li><strong>Timestamp (UTC):</strong> %s</li></ul>", accountType, workerEmail, ts), time.Now().Year())
	msg := mail.NewSingleEmail(from, subject, to, plain, html)
	if s.cfg.LDFlag_SendgridSandboxMode {
		ms := mail.NewMailSettings()
		ms.SetSandboxMode(mail.NewSetting(true))
		msg.MailSettings = ms
	}
	_, err := s.sendgridClient.Send(msg)
	return err
}
