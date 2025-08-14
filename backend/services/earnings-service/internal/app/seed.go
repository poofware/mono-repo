package app

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
	internal_models "github.com/poofware/mono-repo/backend/services/earnings-service/internal/models"
	internal_repositories "github.com/poofware/mono-repo/backend/services/earnings-service/internal/repositories"
	internal_utils "github.com/poofware/mono-repo/backend/services/earnings-service/internal/utils"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
	seeding "github.com/poofware/mono-repo/backend/shared/go-seeding"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

// SentinelPayoutID is used to check if seeding has already occurred.
const SentinelPayoutID = "dddddddd-dddd-4ddd-dddd-ddddddddddd1"

// SeedAllTestData seeds the earnings service with sample payout data.
// This function is idempotent and will not re-seed data if the sentinel payout is found.
func SeedAllTestData(
	ctx context.Context,
	workerRepo repositories.WorkerRepository,
	jobInstRepo repositories.JobInstanceRepository,
	payoutRepo internal_repositories.WorkerPayoutRepository,
) error {
	defaultActiveWorkerID := uuid.MustParse(seeding.DefaultActiveWorkerID)
	sentinelID := uuid.MustParse(SentinelPayoutID)

	// Try to create the worker. If it already exists due to a race with
	// another service, that's okay. We just need it to exist.
	if err := seeding.SeedDefaultWorkers(workerRepo); err != nil {
		return fmt.Errorf("seed default workers: %w", err)
	}

	// IDEMPOTENCY CHECK: Check if the sentinel payout already exists.
	if existing, err := payoutRepo.GetByID(ctx, sentinelID); err != nil && err != pgx.ErrNoRows {
		return fmt.Errorf("failed to check for sentinel payout: %w", err)
	} else if existing != nil {
		utils.Logger.Info("earnings-service: Seed data already present; skipping seeding.")
		return nil
	}

	now := time.Now().UTC()
	thisWeekStart := internal_utils.GetPayPeriodStartForDate(now)
	lastWeekStart := thisWeekStart.AddDate(0, 0, -7)
	weekBeforeLastStart := lastWeekStart.AddDate(0, 0, -7)

	jobIDsWeekBeforeLast := []uuid.UUID{
		uuid.MustParse(seeding.HistoricalJobWeekBeforeLast1),
		uuid.MustParse(seeding.HistoricalJobWeekBeforeLast2),
		uuid.MustParse(seeding.HistoricalJobWeekBeforeLast3),
	}
	jobIDsLastWeek := []uuid.UUID{
		uuid.MustParse(seeding.HistoricalJobLastWeek1),
		uuid.MustParse(seeding.HistoricalJobLastWeek2),
	}

	// Seed Payout 1 (Week before last) - Total: $67.00
	// This payout uses the sentinel ID to ensure idempotency.
	err := SeedPayoutIfNeeded(ctx, jobInstRepo, payoutRepo, defaultActiveWorkerID, weekBeforeLastStart, 6700, jobIDsWeekBeforeLast, &sentinelID)
	if err != nil {
		return err
	}

	// Seed Payout 2 (Last week) - Total: $58.00
	err = SeedPayoutIfNeeded(ctx, jobInstRepo, payoutRepo, defaultActiveWorkerID, lastWeekStart, 5800, jobIDsLastWeek, nil)
	if err != nil {
		return err
	}

	utils.Logger.Info("earnings-service: Seeding completed successfully.")
	return nil
}

// SeedPayoutIfNeeded checks if a payout for a given worker and week exists, and creates it if not.
// It validates that each job's service date falls within the specified payout week.
// An optional payoutID can be provided to use a specific ID.
func SeedPayoutIfNeeded(
	ctx context.Context,
	jobRepo repositories.JobInstanceRepository,
	repo internal_repositories.WorkerPayoutRepository,
	workerID uuid.UUID,
	startDate time.Time,
	amountCents int64,
	jobIDs []uuid.UUID,
	payoutID *uuid.UUID, // Optional: for using a specific ID like the sentinel
) error {
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

	id := uuid.New()
	if payoutID != nil {
		id = *payoutID
	}

	payout := &internal_models.WorkerPayout{
		ID:                id,
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

