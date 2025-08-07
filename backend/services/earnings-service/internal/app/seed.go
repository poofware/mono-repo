package app

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
	internal_models "github.com/poofware/earnings-service/internal/models"
	internal_repositories "github.com/poofware/earnings-service/internal/repositories"
	internal_utils "github.com/poofware/earnings-service/internal/utils"
	"github.com/poofware/go-repositories"
	seeding "github.com/poofware/go-seeding"
	"github.com/poofware/go-utils"
)

// SeedAllTestData seeds the earnings service with sample payout data.
func SeedAllTestData(
	ctx context.Context,
	workerRepo repositories.WorkerRepository,
	jobInstRepo repositories.JobInstanceRepository,
	payoutRepo internal_repositories.WorkerPayoutRepository,
) error {
	defaultActiveWorkerID := uuid.MustParse("1d30bfa5-e42f-457e-a21c-6b7e1aaa2222")

	// Try to create the worker. If it already exists due to a race with
	// another service, that's okay. We just need it to exist.
	if err := seeding.SeedDefaultWorkers(workerRepo); err != nil {
		return fmt.Errorf("seed default workers: %w", err)
	}

	now := time.Now().UTC()
	thisWeekStart := internal_utils.GetPayPeriodStartForDate(now)
	lastWeekStart := thisWeekStart.AddDate(0, 0, -7)
	weekBeforeLastStart := lastWeekStart.AddDate(0, 0, -7)

	jobIDsWeekBeforeLast := []uuid.UUID{
		uuid.MustParse("aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaa1"),
		uuid.MustParse("aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaa2"),
		uuid.MustParse("aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaa3"),
	}
	jobIDsLastWeek := []uuid.UUID{
		uuid.MustParse("bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbb1"),
		uuid.MustParse("bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbb2"),
	}

	err := SeedPayoutIfNeeded(ctx, jobInstRepo, payoutRepo, defaultActiveWorkerID, weekBeforeLastStart, 6700, jobIDsWeekBeforeLast)
	if err != nil {
		return err
	}
	err = SeedPayoutIfNeeded(ctx, jobInstRepo, payoutRepo, defaultActiveWorkerID, lastWeekStart, 5800, jobIDsLastWeek)
	if err != nil {
		return err
	}

	utils.Logger.Info("earnings-service: Seeding completed successfully.")
	return nil
}

// SeedPayoutIfNeeded checks if a payout for a given worker and week exists, and creates it if not.
// It validates that each job's service date falls within the specified payout week.
func SeedPayoutIfNeeded(
	ctx context.Context,
	jobRepo repositories.JobInstanceRepository,
	repo internal_repositories.WorkerPayoutRepository,
	workerID uuid.UUID,
	startDate time.Time,
	amountCents int64,
	jobIDs []uuid.UUID,
) error {
	existing, err := repo.GetByWorkerAndWeek(ctx, workerID, startDate)
	if err != nil && err != pgx.ErrNoRows {
		return fmt.Errorf("failed to check for existing payout for worker %s, week %s: %w", workerID, startDate.Format("2006-01-02"), err)
	}

	if existing != nil {
		utils.Logger.Infof("Payout for worker %s, week %s already exists. Skipping.", workerID, startDate.Format("2006-01-02"))
		return nil
	}

	endDate := startDate.AddDate(0, 0, 6)

	validJobIDs := make([]uuid.UUID, 0, len(jobIDs))
	for _, id := range jobIDs {
		job, err := jobRepo.GetByID(ctx, id)
		if err != nil {
			utils.Logger.WithError(err).Warnf("Unable to fetch job %s for payout seeding", id)
			continue
		}
		if job == nil {
			utils.Logger.Warnf("Job %s not found while seeding payout", id)
			continue
		}
		if job.ServiceDate.Before(startDate) || job.ServiceDate.After(endDate) {
			utils.Logger.Warnf("Found job %s with service date %s outside of payout week [%s - %s]; skipping", id, job.ServiceDate.Format(time.RFC3339), startDate.Format("2006-01-02"), endDate.Format("2006-01-02"))
			continue
		}
		validJobIDs = append(validJobIDs, id)
	}

	if len(validJobIDs) == 0 {
		utils.Logger.Warnf("No valid jobs for worker %s in week %s. Skipping payout seeding.", workerID, startDate.Format("2006-01-02"))
		return nil
	}

	payout := &internal_models.WorkerPayout{
		ID:                uuid.New(),
		WorkerID:          workerID,
		WeekStartDate:     startDate,
		WeekEndDate:       endDate,
		AmountCents:       amountCents,
		Status:            internal_models.PayoutStatusPaid,
		JobInstanceIDs:    validJobIDs,
		StripeTransferID:  utils.Ptr(fmt.Sprintf("tr_seed_%s", uuid.NewString()[:8])),
		StripePayoutID:    utils.Ptr(fmt.Sprintf("po_seed_%s", uuid.NewString()[:8])),
		LastFailureReason: nil,
		RetryCount:        0,
		LastAttemptAt:     utils.Ptr(time.Now()),
		NextAttemptAt:     nil, // This is a final state
	}

	if err := repo.Create(ctx, payout); err != nil {
		return fmt.Errorf("failed to create seed payout for worker %s, week %s: %w", workerID, startDate.Format("2006-01-02"), err)
	}

	utils.Logger.Infof("Seeded PAID payout of $%d.%02d for worker %s for period starting %s.", amountCents/100, amountCents%100, workerID, startDate.Format("2006-01-02"))
	return nil
}

