package services

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
	"github.com/launchdarkly/go-sdk-common/v3/ldcontext"
	ld "github.com/launchdarkly/go-server-sdk/v7"
	"github.com/poofware/account-service/internal/config"
	internal_dtos "github.com/poofware/account-service/internal/dtos"
	"github.com/poofware/go-dtos"
	"github.com/poofware/go-models"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
)

type WorkerService struct {
	repo                repositories.WorkerRepository
	smsVerificationRepo repositories.WorkerSMSVerificationRepository
	cfg                 *config.Config
}

type zipRange struct {
	start int
	end   int
}

var (
	allowedStates = map[string]struct{}{utils.StateAL: {}}
	allowedZips   = []zipRange{{35739, 35775}, {35801, 35899}}
	nonDigits     = regexp.MustCompile(`[^0-9]`)
)

// NewWorkerService creates a WorkerService.
func NewWorkerService(
	cfg *config.Config,
	repo repositories.WorkerRepository,
	smsRepo repositories.WorkerSMSVerificationRepository,
) *WorkerService {
	return &WorkerService{
		cfg:                 cfg,
		repo:                repo,
		smsVerificationRepo: smsRepo,
	}
}

// GetWorkerByID retrieves the worker from the DB.
func (s *WorkerService) GetWorkerByID(ctx context.Context, userID string) (*models.Worker, error) {
	id, err := uuid.Parse(userID)
	if err != nil {
		return nil, err
	}
	worker, wErr := s.repo.GetByID(ctx, id)
	if wErr != nil {
		return nil, wErr
	}
	return worker, nil
}

// SubmitPersonalInfo updates the worker with their address and vehicle data.
// It sets the waitlisted_at timestamp if not already set and only advances
// setup_progress to ID_VERIFY
func (s *WorkerService) SubmitPersonalInfo(
	ctx context.Context,
	userID string,
	req internal_dtos.SubmitPersonalInfoRequest,
) (*models.Worker, error) {

	wID, err := uuid.Parse(userID)
	if err != nil {
		return nil, fmt.Errorf("invalid userID format: %w", err)
	}

	normalizedState, err := utils.NormalizeUSState(req.State)
	if err != nil {
		return nil, err
	}

	zipDigits := nonDigits.ReplaceAllString(req.ZipCode, "")
	if len(zipDigits) < 5 {
		return nil, fmt.Errorf("invalid zip code")
	}
	zipInt, _ := strconv.Atoi(zipDigits[:5])

	inState := false
	if _, ok := allowedStates[normalizedState]; ok {
		inState = true
	}

	inZip := false
	if inState {
		for _, r := range allowedZips {
			if zipInt >= r.start && zipInt <= r.end {
				inZip = true
				break
			}
		}
	}

	shouldWaitlist := false
	var reason *models.WaitlistReasonType
	if !inState || !inZip {
		shouldWaitlist = true
		r := models.WaitlistReasonGeographic
		reason = &r
	} else {
		ldClient, err := ld.MakeClient(s.cfg.LDSDKKey, config.LDConnectionTimeout)
		if err != nil {
			return nil, err
		}
		if !ldClient.Initialized() {
			ldClient.Close()
			return nil, errors.New("launchdarkly client failed to initialize")
		}
		ldCtx := ldcontext.NewWithKind(ldcontext.Kind(config.LDServerContextKind), config.LDServerContextKey)
		capacity, err := ldClient.IntVariation("worker_capacity_limit", ldCtx, 0)
		ldClient.Close()
		if err != nil {
			return nil, err
		}
		activeCount, err := s.repo.GetActiveWorkerCount(ctx)
		if err != nil {
			return nil, err
		}
		if activeCount >= int(capacity) {
			shouldWaitlist = true
			r := models.WaitlistReasonCapacity
			reason = &r
		}
	}

	var finalWorker *models.Worker
	updateErr := s.repo.UpdateWithRetry(ctx, wID, func(stored *models.Worker) error {
		if stored.SetupProgress != models.SetupProgressAwaitingPersonalInfo {
			return errors.New("worker not in AWAITING_PERSONAL_INFO state")
		}

		stored.StreetAddress = req.StreetAddress
		stored.AptSuite = req.AptSuite
		stored.City = req.City
		stored.State = normalizedState
		stored.ZipCode = req.ZipCode
		stored.VehicleYear = req.VehicleYear
		stored.VehicleMake = req.VehicleMake
		stored.VehicleModel = req.VehicleModel

		if shouldWaitlist {
			stored.OnWaitlist = true
			stored.WaitlistReason = reason
			if stored.WaitlistedAt == nil {
				now := time.Now().UTC()
				stored.WaitlistedAt = &now
			}
		} else {
			stored.OnWaitlist = false
			stored.WaitlistReason = nil
			stored.WaitlistedAt = nil
		}

		stored.SetupProgress = models.SetupProgressIDVerify
		finalWorker = stored
		return nil
	})

	if updateErr != nil {
		if updateErr == pgx.ErrNoRows {
			utils.Logger.Errorf("Worker with ID %s not found for personal info submission", userID)
			return nil, nil
		}
		return nil, updateErr
	}

	return finalWorker, nil
}

// PatchWorker partially updates the worker's fields if present in patchReq.
// If patchReq.<field> == nil, we leave that field unchanged.
func (s *WorkerService) PatchWorker(
	ctx context.Context,
	userID string,
	patchReq dtos.WorkerPatchRequest,
) (*models.Worker, error) {

	wID, err := uuid.Parse(userID)
	if err != nil {
		return nil, fmt.Errorf("invalid userID format: %w", err)
	}

	// We'll capture the final updated worker here in a closure variable.
	var finalWorker *models.Worker

	updateErr := s.repo.UpdateWithRetry(ctx, wID, func(stored *models.Worker) error {

		// 1) Email
		if patchReq.Email != nil {
			newEmail := *patchReq.Email
			ok, err := utils.ValidateEmail(ctx, s.cfg.SendgridAPIKey, newEmail, s.cfg.LDFlag_ValidateEmailWithSendGrid)
			if err != nil {
				return err
			}
			if !ok {
				return errors.New("undeliverable email address")
			}
			stored.Email = newEmail
		}

		// 2) PhoneNumber
		if patchReq.PhoneNumber != nil {
			newPhone := *patchReq.PhoneNumber
			ok, _, err := s.smsVerificationRepo.IsCurrentlyVerified(ctx, &wID, newPhone, "")
			if err != nil {
				utils.Logger.Errorf("Error checking phone verification: %v", err)
				return err
			}
			if !ok {
				utils.Logger.Errorf("Phone number %s is not verified for worker %s", newPhone, wID)
				// Return our custom error so the controller can respond accordingly:
				return utils.ErrPhoneNotVerified
			}
			stored.PhoneNumber = newPhone
		}

		// 3) Other fields
		if patchReq.FirstName != nil {
			stored.FirstName = *patchReq.FirstName
		}
		if patchReq.LastName != nil {
			stored.LastName = *patchReq.LastName
		}
		if patchReq.StreetAddress != nil {
			stored.StreetAddress = *patchReq.StreetAddress
		}
		if patchReq.AptSuite != nil {
			stored.AptSuite = patchReq.AptSuite
		}
		if patchReq.City != nil {
			stored.City = *patchReq.City
		}
		if patchReq.State != nil {
			stored.State = *patchReq.State
		}
		if patchReq.ZipCode != nil {
			stored.ZipCode = *patchReq.ZipCode
		}
		if patchReq.VehicleYear != nil {
			stored.VehicleYear = *patchReq.VehicleYear
		}
		if patchReq.VehicleMake != nil {
			stored.VehicleMake = *patchReq.VehicleMake
		}
		if patchReq.VehicleModel != nil {
			stored.VehicleModel = *patchReq.VehicleModel
		}

		// Remember the final, updated Worker
		finalWorker = stored
		return nil
	})

	// If the entity isn't found, UpdateWithRetry returns pgx.ErrNoRows
	if updateErr != nil {
		if updateErr == pgx.ErrNoRows {
			utils.Logger.Errorf("Worker with ID %s not found", userID)
			// return nil, nil so the controller can produce a 404
			return nil, nil
		}
		return nil, updateErr
	}

	// finalWorker is our updated Worker after a successful update.
	return finalWorker, nil
}
