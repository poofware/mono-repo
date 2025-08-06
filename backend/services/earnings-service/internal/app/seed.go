package app

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
	internal_models "github.com/poofware/earnings-service/internal/models"
	internal_repositories "github.com/poofware/earnings-service/internal/repositories"
	"github.com/poofware/go-repositories"
	seeding "github.com/poofware/go-seeding"
	"github.com/poofware/go-utils"
)

// SeedAllTestData seeds the earnings service with sample payout data.
func SeedAllTestData(
	ctx context.Context,
	workerRepo repositories.WorkerRepository,
	payoutRepo internal_repositories.WorkerPayoutRepository,
) error {
	defaultActiveWorkerID := uuid.MustParse("1d30bfa5-e42f-457e-a21c-6b7e1aaa2222")

	if err := seeding.SeedDefaultWorkers(workerRepo); err != nil {
		return fmt.Errorf("seed default workers: %w", err)
	}

	sentinelStart := time.Date(2025, 7, 14, 0, 0, 0, 0, time.UTC)
	existing, err := payoutRepo.GetByWorkerAndWeek(ctx, defaultActiveWorkerID, sentinelStart)
	if err != nil {
		return fmt.Errorf("check existing payout: %w", err)
	}
	if existing != nil {
		utils.Logger.Info("earnings-service: seed data already present; skipping seeding")
		return nil
	}

	weekBeforeLastStart := sentinelStart
	lastWeekStart := weekBeforeLastStart.AddDate(0, 0, 7)

	jobIDsWeekBeforeLast := []uuid.UUID{
		uuid.MustParse("aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaa1"),
		uuid.MustParse("aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaa2"),
		uuid.MustParse("aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaa3"),
	}
	jobIDsLastWeek := []uuid.UUID{
		uuid.MustParse("bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbb1"),
		uuid.MustParse("bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbb2"),
	}

	if err := seedPayoutIfNeeded(ctx, payoutRepo, defaultActiveWorkerID, weekBeforeLastStart, 6700, jobIDsWeekBeforeLast); err != nil {
		return err
	}
	if err := seedPayoutIfNeeded(ctx, payoutRepo, defaultActiveWorkerID, lastWeekStart, 5800, jobIDsLastWeek); err != nil {
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
		NextAttemptAt:     nil,
	}

	if err := repo.Create(ctx, payout); err != nil {
		return fmt.Errorf("failed to create seed payout for worker %s, week %s: %w", workerID, startDate.Format("2006-01-02"), err)
	}

	utils.Logger.Infof("Seeded PAID payout of $%d.%02d for worker %s for period starting %s.", amountCents/100, amountCents%100, workerID, startDate.Format("2006-01-02"))
	return nil
}
