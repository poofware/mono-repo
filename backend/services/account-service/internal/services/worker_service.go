package services

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
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

	var finalWorker *models.Worker
	updateErr := s.repo.UpdateWithRetry(ctx, wID, func(stored *models.Worker) error {
		// This action is only valid if the worker is in the AWAITING_PERSONAL_INFO state.
		if stored.SetupProgress != models.SetupProgressAwaitingPersonalInfo {
			return errors.New("worker not in AWAITING_PERSONAL_INFO state")
		}

		// Apply all updates from the request DTO.
		stored.StreetAddress = req.StreetAddress
		stored.AptSuite = req.AptSuite
		stored.City = req.City
		stored.State = req.State
		stored.ZipCode = req.ZipCode
		stored.VehicleYear = req.VehicleYear
		stored.VehicleMake = req.VehicleMake
		stored.VehicleModel = req.VehicleModel

		if stored.WaitlistedAt == nil {
			now := time.Now().UTC()
			stored.WaitlistedAt = &now
		}
		stored.SetupProgress = models.SetupProgressIDVerify

		finalWorker = stored
		return nil
	})

	if updateErr != nil {
		if updateErr == pgx.ErrNoRows {
			utils.Logger.Errorf("Worker with ID %s not found for personal info submission", userID)
			return nil, nil // Let controller return 404
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
