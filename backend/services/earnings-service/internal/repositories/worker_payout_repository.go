package repositories

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/earnings-service/internal/constants"
	internal_models "github.com/poofware/earnings-service/internal/models"
	"github.com/poofware/go-repositories"
	"github.com/stripe/stripe-go/v82"
)

// WorkerPayoutRepository defines the interface for payout data operations.
type WorkerPayoutRepository interface {
	Create(ctx context.Context, payout *internal_models.WorkerPayout) error
	GetByID(ctx context.Context, id uuid.UUID) (*internal_models.WorkerPayout, error)
	GetByWorkerAndWeek(ctx context.Context, workerID uuid.UUID, weekStartDate time.Time) (*internal_models.WorkerPayout, error)
	UpdateIfVersion(ctx context.Context, p *internal_models.WorkerPayout, expectedVersion int64) (pgconn.CommandTag, error)
	UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*internal_models.WorkerPayout) error) error
	FindReadyForPayout(ctx context.Context) ([]*internal_models.WorkerPayout, error)
	FindForWorkerByDateRange(ctx context.Context, workerID uuid.UUID, startDate, endDate time.Time) ([]*internal_models.WorkerPayout, error)
	FindFailedPayoutsForWorkerByAccountError(ctx context.Context, workerID uuid.UUID) ([]*internal_models.WorkerPayout, error)
	FindFailedByReason(ctx context.Context, reason string) ([]*internal_models.WorkerPayout, error)
}

type workerPayoutRepo struct {
	*repositories.BaseVersionedRepo[*internal_models.WorkerPayout]
	db repositories.DB
}

// NewWorkerPayoutRepository creates a new instance of the repository.
func NewWorkerPayoutRepository(db repositories.DB) WorkerPayoutRepository {
	r := &workerPayoutRepo{db: db}
	selectStmt := baseSelectPayout() + " WHERE id = $1"
	r.BaseVersionedRepo = repositories.NewBaseRepo(db, selectStmt, r.scanPayout)
	return r
}

func (r *workerPayoutRepo) GetByID(ctx context.Context, id uuid.UUID) (*internal_models.WorkerPayout, error) {
	return r.BaseVersionedRepo.GetByID(ctx, id.String())
}

func baseSelectPayout() string {
	return `
		SELECT
			id, worker_id, week_start_date, week_end_date, amount_cents, status,
			stripe_transfer_id, stripe_payout_id, job_instance_ids, last_failure_reason, retry_count,
			last_attempt_at, next_attempt_at, created_at, updated_at, row_version
		FROM worker_payouts
	`
}

func (r *workerPayoutRepo) scanPayout(row pgx.Row) (*internal_models.WorkerPayout, error) {
	var p internal_models.WorkerPayout
	err := row.Scan(
		&p.ID, &p.WorkerID, &p.WeekStartDate, &p.WeekEndDate, &p.AmountCents, &p.Status,
		&p.StripeTransferID, &p.StripePayoutID, &p.JobInstanceIDs, &p.LastFailureReason, &p.RetryCount,
		&p.LastAttemptAt, &p.NextAttemptAt, &p.CreatedAt, &p.UpdatedAt, &p.RowVersion,
	)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &p, nil
}

func (r *workerPayoutRepo) Create(ctx context.Context, p *internal_models.WorkerPayout) error {
	q := `
		INSERT INTO worker_payouts (
			id, worker_id, week_start_date, week_end_date, amount_cents, status,
			stripe_transfer_id, stripe_payout_id, job_instance_ids, retry_count, created_at, updated_at, row_version
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 0, NOW(), NOW(), 1)
		ON CONFLICT (worker_id, week_start_date) DO NOTHING
	`
	_, err := r.db.Exec(ctx, q, p.ID, p.WorkerID, p.WeekStartDate, p.WeekEndDate, p.AmountCents, p.Status, p.StripeTransferID, p.StripePayoutID, p.JobInstanceIDs)
	return err
}

func (r *workerPayoutRepo) GetByWorkerAndWeek(ctx context.Context, workerID uuid.UUID, weekStartDate time.Time) (*internal_models.WorkerPayout, error) {
	q := baseSelectPayout() + " WHERE worker_id = $1 AND week_start_date = $2"
	row := r.db.QueryRow(ctx, q, workerID, weekStartDate)
	return r.scanPayout(row)
}

func (r *workerPayoutRepo) UpdateIfVersion(ctx context.Context, p *internal_models.WorkerPayout, expectedVersion int64) (pgconn.CommandTag, error) {
	q := `
		UPDATE worker_payouts SET
			status = $1,
			stripe_transfer_id = $2,
			stripe_payout_id = $3,
			last_failure_reason = $4,
			retry_count = $5,
			last_attempt_at = $6,
			next_attempt_at = $7,
			updated_at = NOW(),
			row_version = row_version + 1
		WHERE id = $8 AND row_version = $9
	`
	return r.db.Exec(ctx, q,
		p.Status, p.StripeTransferID, p.StripePayoutID, p.LastFailureReason, p.RetryCount,
		p.LastAttemptAt, p.NextAttemptAt, p.ID, expectedVersion)
}

func (r *workerPayoutRepo) UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*internal_models.WorkerPayout) error) error {
	return r.BaseVersionedRepo.UpdateWithRetry(ctx, id.String(), mutate, r.UpdateIfVersion)
}

func (r *workerPayoutRepo) FindReadyForPayout(ctx context.Context) ([]*internal_models.WorkerPayout, error) {
	q := baseSelectPayout() + " WHERE status = 'PENDING' OR (status = 'FAILED' AND next_attempt_at IS NOT NULL AND next_attempt_at <= NOW()) ORDER BY created_at"
	rows, err := r.db.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var payouts []*internal_models.WorkerPayout
	for rows.Next() {
		p, err := r.scanPayout(rows)
		if err != nil {
			return nil, err
		}
		payouts = append(payouts, p)
	}
	return payouts, rows.Err()
}

func (r *workerPayoutRepo) FindForWorkerByDateRange(ctx context.Context, workerID uuid.UUID, startDate, endDate time.Time) ([]*internal_models.WorkerPayout, error) {
	q := baseSelectPayout() + " WHERE worker_id = $1 AND week_start_date >= $2 AND week_start_date <= $3 ORDER BY week_start_date DESC"
	rows, err := r.db.Query(ctx, q, workerID, startDate, endDate)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var payouts []*internal_models.WorkerPayout
	for rows.Next() {
		p, err := r.scanPayout(rows)
		if err != nil {
			return nil, err
		}
		payouts = append(payouts, p)
	}
	return payouts, rows.Err()
}

func (r *workerPayoutRepo) FindFailedPayoutsForWorkerByAccountError(ctx context.Context, workerID uuid.UUID) ([]*internal_models.WorkerPayout, error) {
	// These reasons indicate a payout failed due to an issue with the worker's Stripe
	// account that they can resolve. An `account.updated` or `capability.updated` webhook
	// should trigger a retry for payouts failed with one of these reasons.
	userActionableReasons := []string{
		string(stripe.PayoutFailureCodeAccountClosed),
		string(stripe.PayoutFailureCodeBankAccountRestricted),
		string(stripe.PayoutFailureCodeInvalidAccountNumber),
		string(stripe.ErrorCodePayoutsNotAllowed),
		constants.ReasonMissingStripeID,
		constants.ReasonAccountPayoutsDisabled,
		constants.StripeFailureCodeAccountRestricted,
	}

	q := baseSelectPayout() + `
        WHERE worker_id = $1
          AND status = 'FAILED'
          AND next_attempt_at IS NULL
          AND last_failure_reason = ANY($2)
    `
	rows, err := r.db.Query(ctx, q, workerID, userActionableReasons)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var payouts []*internal_models.WorkerPayout
	for rows.Next() {
		p, err := r.scanPayout(rows)
		if err != nil {
			return nil, err
		}
		payouts = append(payouts, p)
	}
	return payouts, rows.Err()
}

// FindFailedByReason finds all payouts that are in a FAILED state with a specific reason.
func (r *workerPayoutRepo) FindFailedByReason(ctx context.Context, reason string) ([]*internal_models.WorkerPayout, error) {
	q := baseSelectPayout() + " WHERE status = 'FAILED' AND last_failure_reason = $1 ORDER BY created_at"
	rows, err := r.db.Query(ctx, q, reason)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var payouts []*internal_models.WorkerPayout
	for rows.Next() {
		p, err := r.scanPayout(rows)
		if err != nil {
			return nil, err
		}
		payouts = append(payouts, p)
	}
	return payouts, rows.Err()
}
