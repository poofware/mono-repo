package app

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/jackc/pgx/v4"
	internal_models "github.com/poofware/earnings-service/internal/models"
	internal_repositories "github.com/poofware/earnings-service/internal/repositories"
	internal_utils "github.com/poofware/earnings-service/internal/utils"
	"github.com/poofware/go-models"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
)

// Helper to check for unique violation error (PostgreSQL specific code)
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

// SeedAllTestData seeds the earnings service with sample payout data.
func SeedAllTestData(
	ctx context.Context,
	workerRepo repositories.WorkerRepository,
	payoutRepo internal_repositories.WorkerPayoutRepository,
) error {
	defaultActiveWorkerID := uuid.MustParse("1d30bfa5-e42f-457e-a21c-6b7e1aaa2222")

	// Try to create the worker. If it already exists due to a race with
	// another service, that's okay. We just need it to exist.
	wActive := &models.Worker{
		ID:            defaultActiveWorkerID,
		Email:         "team@thepoofapp.com",
		PhoneNumber:   "+15552220000",
		TOTPSecret:    "defaultworkerstatusactivestotpsecretokay",
		FirstName:     "DefaultWorker",
		LastName:      "SetupActive",
		StreetAddress: "123 Default Status Active St",
		City:          "SeedCity",
		State:         "AL",
		ZipCode:       "90000",
		VehicleYear:   2022,
		VehicleMake:   "Toyota",
		VehicleModel:  "Camry",
	}

	if err := workerRepo.Create(ctx, wActive); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Info("Default active worker already exists, skipping creation in earnings-service.")
		} else {
			return fmt.Errorf("failed to seed replica worker: %w", err)
		}
	} else {
		// If we successfully created it, update it to the correct status.
		// If another service created it, it should also be responsible for updating it.
		// This is a reasonable assumption in a seeding context.
		if err := workerRepo.UpdateWithRetry(ctx, wActive.ID, func(stored *models.Worker) error {
			stored.StreetAddress = "123 Default Status Active St"
			stored.City = "SeedCity"
			stored.State = "AL"
			stored.ZipCode = "90000"
			stored.VehicleYear = 2022
			stored.VehicleMake = "Toyota"
			stored.VehicleModel = "Camry"
			stored.AccountStatus = models.AccountStatusActive
			stored.SetupProgress = models.SetupProgressDone
			stored.StripeConnectAccountID = utils.Ptr("acct_1RZHahCLd3ZjFFWN") // Happy Path Connect ID
			return nil
		}); err != nil {
			return fmt.Errorf("update default worker (active) status: %w", err)
		}
		utils.Logger.Info("Successfully seeded local replica for default active worker.")
	}

	now := time.Now().UTC()
	thisWeekStart := internal_utils.GetPayPeriodStartForDate(now)
	lastWeekStart := thisWeekStart.AddDate(0, 0, -7)
	weekBeforeLastStart := lastWeekStart.AddDate(0, 0, -7)

	// Define the hardcoded UUIDs for the jobs seeded by the jobs-service.
	jobIDsWeekBeforeLast := []uuid.UUID{
		uuid.MustParse("aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaa1"),
		uuid.MustParse("aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaa2"),
		uuid.MustParse("aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaa3"),
	}
	jobIDsLastWeek := []uuid.UUID{
		uuid.MustParse("bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbb1"),
		uuid.MustParse("bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbb2"),
	}

	// Seed Payout 1 (Week before last) - Total: $67.00
	err := seedPayoutIfNeeded(ctx, payoutRepo, defaultActiveWorkerID, weekBeforeLastStart, 6700, jobIDsWeekBeforeLast)
	if err != nil {
		return err
	}

	// Seed Payout 2 (Last week) - Total: $58.00
	err = seedPayoutIfNeeded(ctx, payoutRepo, defaultActiveWorkerID, lastWeekStart, 5800, jobIDsLastWeek)
	if err != nil {
		return err
	}

	utils.Logger.Info("earnings-service: Seeding completed successfully.")
	return nil
}

// seedPayoutIfNeeded checks if a payout for a given worker and week exists, and creates it if not.
func seedPayoutIfNeeded(ctx context.Context, repo internal_repositories.WorkerPayoutRepository, workerID uuid.UUID, startDate time.Time, amountCents int64, jobIDs []uuid.UUID) error {
	existing, err := repo.GetByWorkerAndWeek(ctx, workerID, startDate)
	if err != nil && err != pgx.ErrNoRows {
		return fmt.Errorf("failed to check for existing payout for worker %s, week %s: %w", workerID, startDate.Format("2006-01-02"), err)
	}

	if existing != nil {
		utils.Logger.Infof("Payout for worker %s, week %s already exists. Skipping.", workerID, startDate.Format("2006-01-02"))
		return nil
	}

	// A standard pay period is 7 days, so the end date is 6 days after the start.
	endDate := startDate.AddDate(0, 0, 6)

	payout := &internal_models.WorkerPayout{
		ID:                uuid.New(),
		WorkerID:          workerID,
		WeekStartDate:     startDate,
		WeekEndDate:       endDate,
		AmountCents:       amountCents,
		Status:            internal_models.PayoutStatusPaid,
		JobInstanceIDs:    jobIDs,
		StripeTransferID:  utils.Ptr(fmt.Sprintf("tr_seed_%s", uuid.NewString()[:8])),
		StripePayoutID:    utils.Ptr(fmt.Sprintf("po_seed_%s", uuid.NewString()[:8])),
		LastFailureReason: nil,
		RetryCount:        0,
		LastAttemptAt:     utils.Ptr(time.Now()),
		NextAttemptAt:     nil, // This is a final state
	}

	err = repo.Create(ctx, payout)
	if err != nil {
		return fmt.Errorf("failed to create seed payout for worker %s, week %s: %w", workerID, startDate.Format("2006-01-02"), err)
	}

	utils.Logger.Infof("Seeded PAID payout of $%d.%02d for worker %s for period starting %s.", amountCents/100, amountCents%100, workerID, startDate.Format("2006-01-02"))
	return nil
}
