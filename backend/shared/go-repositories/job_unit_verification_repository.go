package repositories

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/go-models"
)

// JobUnitVerificationRepository manages job_unit_verifications.
type JobUnitVerificationRepository interface {
	Create(ctx context.Context, v *models.JobUnitVerification) error
	UpdateIfVersion(ctx context.Context, v *models.JobUnitVerification, expected int64) (pgconn.CommandTag, error)
	GetByInstanceAndUnit(ctx context.Context, instanceID, unitID uuid.UUID) (*models.JobUnitVerification, error)
	ListByInstanceID(ctx context.Context, instanceID uuid.UUID) ([]*models.JobUnitVerification, error)
}

type jobUnitVerificationRepo struct {
	*BaseVersionedRepo[*models.JobUnitVerification]
	db DB
}

// NewJobUnitVerificationRepository returns a repo instance.
func NewJobUnitVerificationRepository(db DB) JobUnitVerificationRepository {
	r := &jobUnitVerificationRepo{db: db}
	selectStmt := baseSelectJobUnitVerification() + " WHERE id=$1"
	r.BaseVersionedRepo = NewBaseRepo(db, selectStmt, r.scanVerification)
	return r
}

func (r *jobUnitVerificationRepo) Create(ctx context.Context, v *models.JobUnitVerification) error {
	_, err := r.db.Exec(ctx, `
        INSERT INTO job_unit_verifications (
            id, job_instance_id, unit_id, status, attempt_count, failure_reasons, permanent_failure, missing_trash_can,
            created_at, updated_at, row_version
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,NOW(),NOW(),1)
    `, v.ID, v.JobInstanceID, v.UnitID, v.Status, v.AttemptCount, v.FailureReasons, v.PermanentFailure, v.MissingTrashCan)
	return err
}

func (r *jobUnitVerificationRepo) UpdateIfVersion(ctx context.Context, v *models.JobUnitVerification, expected int64) (pgconn.CommandTag, error) {
	return r.db.Exec(ctx, `
        UPDATE job_unit_verifications
        SET status=$1, attempt_count=$2, failure_reasons=$3, permanent_failure=$4, missing_trash_can=$5, row_version=row_version+1, updated_at=NOW()
        WHERE id=$6 AND row_version=$7
    `, v.Status, v.AttemptCount, v.FailureReasons, v.PermanentFailure, v.MissingTrashCan, v.ID, expected)
}

func (r *jobUnitVerificationRepo) GetByInstanceAndUnit(ctx context.Context, instanceID, unitID uuid.UUID) (*models.JobUnitVerification, error) {
	row := r.db.QueryRow(ctx, baseSelectJobUnitVerification()+" WHERE job_instance_id=$1 AND unit_id=$2", instanceID, unitID)
	return r.scanVerification(row)
}

func (r *jobUnitVerificationRepo) ListByInstanceID(ctx context.Context, instanceID uuid.UUID) ([]*models.JobUnitVerification, error) {
	rows, err := r.db.Query(ctx, baseSelectJobUnitVerification()+" WHERE job_instance_id=$1 ORDER BY created_at", instanceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.JobUnitVerification
	for rows.Next() {
		v, err := r.scanVerification(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

func baseSelectJobUnitVerification() string {
	return `
        SELECT
            id, job_instance_id, unit_id, status, attempt_count, failure_reasons, permanent_failure, missing_trash_can,
            row_version, created_at, updated_at
        FROM job_unit_verifications`
}

func (r *jobUnitVerificationRepo) scanVerification(row pgx.Row) (*models.JobUnitVerification, error) {
	var v models.JobUnitVerification
	err := row.Scan(
		&v.ID, &v.JobInstanceID, &v.UnitID, &v.Status, &v.AttemptCount, &v.FailureReasons, &v.PermanentFailure, &v.MissingTrashCan,
		&v.RowVersion, &v.CreatedAt, &v.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &v, nil
}
