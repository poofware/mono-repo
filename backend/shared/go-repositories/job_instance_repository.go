package repositories

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/mono-repo/backend/shared/go-models"
)

type JobInstanceRepository interface {
	Create(ctx context.Context, inst *models.JobInstance) error
	CreateIfNotExists(ctx context.Context, inst *models.JobInstance) error
	GetByID(ctx context.Context, id uuid.UUID) (*models.JobInstance, error)

	ListInstancesByDateRange(
		ctx context.Context,
		assignedWorker *uuid.UUID,
		statuses []models.InstanceStatusType,
		startDate, endDate time.Time,
	) ([]*models.JobInstance, error)

	ListInstancesByDefinitionIDs(ctx context.Context, definitionIDs []uuid.UUID, startDate, endDate time.Time) ([]*models.JobInstance, error)

	AcceptInstanceAtomic(ctx context.Context, instanceID uuid.UUID, workerID uuid.UUID, expectedVersion int64, newAssignCount int, flagged bool) (*models.JobInstance, error)
	UnassignInstanceAtomic(ctx context.Context, instanceID uuid.UUID, expectedVersion int64, newAssignCount int, flagged bool) (*models.JobInstance, error)
	UpdateStatusAtomic(ctx context.Context, instanceID uuid.UUID, newStatus models.InstanceStatusType, expectedVersion int64) (*models.JobInstance, error)

	UpdateEffectivePayAtomic(ctx context.Context, instanceID uuid.UUID, expectedVersion int64, newPay float64) error
	UpdateStatusToInProgress(ctx context.Context, instanceID uuid.UUID, expectedVersion int64) (*models.JobInstance, error)
	UpdateStatusToCompleted(ctx context.Context, instanceID uuid.UUID, expectedVersion int64) (*models.JobInstance, error)

	// Marks a job as completed by an agent using an escalation token
	CompleteByAgent(ctx context.Context, instanceID uuid.UUID, agentID uuid.UUID) (*models.JobInstance, error)

	// NEW
	UpdateStatusToCancelled(ctx context.Context, instanceID uuid.UUID, expectedVersion int64) (*models.JobInstance, error)

	// NEW
	RevertInProgressToOpenAtomic(ctx context.Context, instanceID uuid.UUID, expectedVersion int64, newAssignCount int, flagged bool) (*models.JobInstance, error)

	RetireInstancesForDate(ctx context.Context, date time.Time, oldStatuses []models.InstanceStatusType) error
	DeleteFutureOpenInstances(ctx context.Context, defID uuid.UUID, today time.Time) error

	AddExcludedWorker(ctx context.Context, instanceID uuid.UUID, workerID uuid.UUID) error
	SetWarning90MinSent(ctx context.Context, instanceID uuid.UUID) error
	SetWarning40MinSent(ctx context.Context, instanceID uuid.UUID) error
}

type jobInstanceRepo struct {
	db DB
}

func NewJobInstanceRepository(db DB) JobInstanceRepository {
	return &jobInstanceRepo{db: db}
}

func baseSelectInstance() string {
	return `
        SELECT
            id, definition_id, service_date, status,
            assigned_worker_id, effective_pay,
            check_in_at, check_out_at,
            excluded_worker_ids, assign_unassign_count, flagged_for_review,
            row_version, created_at, updated_at, completed_by_agent_id
        FROM job_instances
    `
}

func scanInstance(row pgx.Row) (*models.JobInstance, error) {
	var inst models.JobInstance
	var excluded []uuid.UUID
	var checkIn, checkOut *time.Time
	err := row.Scan(
		&inst.ID,
		&inst.DefinitionID,
		&inst.ServiceDate,
		&inst.Status,
		&inst.AssignedWorkerID,
		&inst.EffectivePay,
		&checkIn,
		&checkOut,
		&excluded,
		&inst.AssignUnassignCount,
		&inst.FlaggedForReview,
		&inst.RowVersion,
		&inst.CreatedAt,
		&inst.UpdatedAt,
		&inst.CompletedByAgentID,
	)
	if err != nil {
		return nil, err
	}
	inst.CheckInAt = checkIn
	inst.CheckOutAt = checkOut
	inst.ExcludedWorkerIDs = excluded
	return &inst, nil
}

func (r *jobInstanceRepo) Create(ctx context.Context, inst *models.JobInstance) error {
	_, err := r.db.Exec(ctx, `
        INSERT INTO job_instances (
            id, definition_id, service_date, status,
            assigned_worker_id, effective_pay,
            excluded_worker_ids, assign_unassign_count, flagged_for_review,
            created_at, updated_at, row_version
        ) VALUES (
            $1,$2,$3,$4,$5,$6,'{}',0,FALSE,NOW(),NOW(),1
        )
    `,
		inst.ID,
		inst.DefinitionID,
		inst.ServiceDate,
		inst.Status,
		inst.AssignedWorkerID,
		inst.EffectivePay,
	)
	return err
}

func (r *jobInstanceRepo) CreateIfNotExists(ctx context.Context, inst *models.JobInstance) error {
	_, err := r.db.Exec(ctx, `
        INSERT INTO job_instances (
            id, definition_id, service_date, status,
            assigned_worker_id, effective_pay,
            excluded_worker_ids, assign_unassign_count, flagged_for_review,
            created_at, updated_at, row_version
        ) VALUES (
            $1,$2,$3,$4,$5,$6,'{}',0,FALSE,NOW(),NOW(),1
        )
        ON CONFLICT (definition_id, service_date) DO NOTHING
    `,
		inst.ID,
		inst.DefinitionID,
		inst.ServiceDate,
		inst.Status,
		inst.AssignedWorkerID,
		inst.EffectivePay,
	)
	return err
}

func (r *jobInstanceRepo) GetByID(ctx context.Context, id uuid.UUID) (*models.JobInstance, error) {
	row := r.db.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1", id)
	return scanInstance(row)
}

func (r *jobInstanceRepo) ListInstancesByDateRange(
	ctx context.Context,
	assignedWorker *uuid.UUID,
	statuses []models.InstanceStatusType,
	startDate, endDate time.Time,
) ([]*models.JobInstance, error) {

	var (
		qb   strings.Builder
		args []any
		idx  = 1
	)

	qb.WriteString(baseSelectInstance())
	qb.WriteString(" WHERE service_date >= $")
	qb.WriteString(strconv.Itoa(idx))
	args = append(args, startDate.Format("2006-01-02"))
	idx++

	qb.WriteString(" AND service_date <= $")
	qb.WriteString(strconv.Itoa(idx))
	args = append(args, endDate.Format("2006-01-02"))
	idx++

	if len(statuses) > 0 {
		var stStrings []string
		for _, st := range statuses {
			stStrings = append(stStrings, string(st))
		}
		qb.WriteString(" AND status = ANY($")
		qb.WriteString(strconv.Itoa(idx))
		qb.WriteString(")")
		args = append(args, stStrings)
		idx++
	}

	if assignedWorker != nil {
		qb.WriteString(" AND assigned_worker_id = $")
		qb.WriteString(strconv.Itoa(idx))
		args = append(args, *assignedWorker)
		idx++
	}

	qb.WriteString(" ORDER BY service_date")
	query := qb.String()

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.JobInstance
	for rows.Next() {
		inst, err := scanInstance(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, inst)
	}
	return out, rows.Err()
}

// ListInstancesByDefinitionIDs fetches all job instances associated with a list
// of definition IDs within a given date range.
func (r *jobInstanceRepo) ListInstancesByDefinitionIDs(
	ctx context.Context,
	definitionIDs []uuid.UUID,
	startDate, endDate time.Time,
) ([]*models.JobInstance, error) {
	if len(definitionIDs) == 0 {
		return []*models.JobInstance{}, nil
	}

	q := baseSelectInstance() + `
        WHERE definition_id = ANY($1)
          AND service_date >= $2
          AND service_date <= $3
        ORDER BY service_date DESC
    `

	rows, err := r.db.Query(ctx, q, definitionIDs, startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("querying instances by definition IDs: %w", err)
	}
	defer rows.Close()

	var out []*models.JobInstance
	for rows.Next() {
		inst, err := scanInstance(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, inst)
	}
	return out, rows.Err()
}

func (r *jobInstanceRepo) AcceptInstanceAtomic(
	ctx context.Context,
	instanceID uuid.UUID,
	workerID uuid.UUID,
	expectedVersion int64,
	newAssignCount int,
	flagged bool,
) (*models.JobInstance, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback(ctx)
		} else {
			_ = tx.Commit(ctx)
		}
	}()

	row := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1 FOR UPDATE", instanceID)
	inst, err := scanInstance(row)
	if err != nil {
		return nil, err
	}
	if inst == nil {
		return nil, pgx.ErrNoRows
	}
	if inst.RowVersion != expectedVersion {
		return inst, fmt.Errorf("row_version_conflict")
	}
	if inst.Status != models.InstanceStatusOpen {
		return inst, fmt.Errorf("cannot accept non-open instance")
	}

	_, err = tx.Exec(ctx, `
        UPDATE job_instances
        SET status='ASSIGNED',
            assigned_worker_id=$1,
            assign_unassign_count=$2,
            flagged_for_review=$3,
            row_version=row_version+1, updated_at=NOW()
        WHERE id=$4
    `, workerID, newAssignCount, flagged, instanceID)
	if err != nil {
		return nil, err
	}

	newRow := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1", instanceID)
	return scanInstance(newRow)
}

func (r *jobInstanceRepo) UnassignInstanceAtomic(
	ctx context.Context,
	instanceID uuid.UUID,
	expectedVersion int64,
	newAssignCount int,
	flagged bool,
) (*models.JobInstance, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() {
		if err != nil {
			tx.Rollback(ctx)
		} else {
			tx.Commit(ctx)
		}
	}()

	row := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1 FOR UPDATE", instanceID)
	inst, err := scanInstance(row)
	if err != nil {
		return nil, err
	}
	if inst == nil {
		return nil, pgx.ErrNoRows
	}
	if inst.RowVersion != expectedVersion {
		return inst, fmt.Errorf("row_version_conflict")
	}
	if inst.Status != models.InstanceStatusAssigned {
		return inst, fmt.Errorf("cannot unassign a job that is not assigned")
	}

	_, err = tx.Exec(ctx, `
        UPDATE job_instances
        SET status='OPEN',
            assigned_worker_id=NULL,
            assign_unassign_count=$1,
            flagged_for_review=$2,
            row_version=row_version+1,
            updated_at=NOW()
        WHERE id=$3
    `, newAssignCount, flagged, instanceID)
	if err != nil {
		return nil, err
	}
	newRow := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1", instanceID)
	return scanInstance(newRow)
}

func (r *jobInstanceRepo) UpdateStatusAtomic(
	ctx context.Context,
	instanceID uuid.UUID,
	newStatus models.InstanceStatusType,
	expectedVersion int64,
) (*models.JobInstance, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() {
		if err != nil {
			tx.Rollback(ctx)
		} else {
			tx.Commit(ctx)
		}
	}()

	row := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1 FOR UPDATE", instanceID)
	inst, err := scanInstance(row)
	if err != nil {
		return nil, err
	}
	if inst == nil {
		return nil, pgx.ErrNoRows
	}
	if inst.RowVersion != expectedVersion {
		return inst, fmt.Errorf("row_version_conflict")
	}

	_, err = tx.Exec(ctx, `
        UPDATE job_instances
        SET status=$1, row_version=row_version+1, updated_at=NOW()
        WHERE id=$2
    `, newStatus, instanceID)
	if err != nil {
		return nil, err
	}
	newRow := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1", instanceID)
	return scanInstance(newRow)
}

func (r *jobInstanceRepo) UpdateEffectivePayAtomic(
	ctx context.Context,
	instanceID uuid.UUID,
	expectedVersion int64,
	newPay float64,
) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() {
		if err != nil {
			tx.Rollback(ctx)
		} else {
			tx.Commit(ctx)
		}
	}()

	row := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1 FOR UPDATE", instanceID)
	inst, err := scanInstance(row)
	if err != nil {
		return err
	}
	if inst == nil {
		return fmt.Errorf("no rows found for job_instance=%s", instanceID)
	}
	if inst.RowVersion != expectedVersion {
		return fmt.Errorf("row_version_conflict")
	}
	if inst.Status != models.InstanceStatusOpen {
		return nil // do nothing if not open
	}

	_, err = tx.Exec(ctx, `
        UPDATE job_instances
        SET effective_pay=$1, row_version=row_version+1, updated_at=NOW()
        WHERE id=$2
    `, newPay, instanceID)
	return err
}

func (r *jobInstanceRepo) UpdateStatusToInProgress(
	ctx context.Context,
	instanceID uuid.UUID,
	expectedVersion int64,
) (*models.JobInstance, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() {
		if err != nil {
			tx.Rollback(ctx)
		} else {
			tx.Commit(ctx)
		}
	}()

	row := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1 FOR UPDATE", instanceID)
	inst, err := scanInstance(row)
	if err != nil {
		return nil, err
	}
	if inst == nil {
		return nil, pgx.ErrNoRows
	}
	if inst.RowVersion != expectedVersion {
		return nil, fmt.Errorf("row_version_conflict")
	}

	_, err = tx.Exec(ctx, `
        UPDATE job_instances
        SET status='IN_PROGRESS',
            check_in_at=NOW(),
            row_version=row_version+1,
            updated_at=NOW()
        WHERE id=$1
    `, instanceID)
	if err != nil {
		return nil, err
	}
	newRow := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1", instanceID)
	return scanInstance(newRow)
}

func (r *jobInstanceRepo) UpdateStatusToCompleted(
	ctx context.Context,
	instanceID uuid.UUID,
	expectedVersion int64,
) (*models.JobInstance, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() {
		if err != nil {
			tx.Rollback(ctx)
		} else {
			tx.Commit(ctx)
		}
	}()

	row := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1 FOR UPDATE", instanceID)
	inst, err := scanInstance(row)
	if err != nil {
		return nil, err
	}
	if inst == nil {
		return nil, pgx.ErrNoRows
	}
	if inst.RowVersion != expectedVersion {
		return nil, fmt.Errorf("row_version_conflict")
	}

	_, err = tx.Exec(ctx, `
        UPDATE job_instances
        SET status='COMPLETED',
            check_out_at=NOW(),
            row_version=row_version+1,
            updated_at=NOW()
        WHERE id=$1
    `, instanceID)
	if err != nil {
		return nil, err
	}
	newRow := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1", instanceID)
	return scanInstance(newRow)
}

// CompleteByAgent sets a job instance to COMPLETED and records the agent responsible.
// It returns an error if the job has already been claimed (status != OPEN).
func (r *jobInstanceRepo) CompleteByAgent(ctx context.Context, instanceID uuid.UUID, agentID uuid.UUID) (*models.JobInstance, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback(ctx)
		} else {
			_ = tx.Commit(ctx)
		}
	}()

	row := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1 FOR UPDATE", instanceID)
	inst, err := scanInstance(row)
	if err != nil {
		return nil, err
	}
	if inst == nil {
		return nil, pgx.ErrNoRows
	}
	if inst.Status != models.InstanceStatusOpen {
		return inst, fmt.Errorf("job_not_open")
	}

	_, err = tx.Exec(ctx, `
                UPDATE job_instances
                SET status='COMPLETED',
                    completed_by_agent_id=$2,
                    row_version=row_version+1,
                    updated_at=NOW()
                WHERE id=$1
        `, instanceID, agentID)
	if err != nil {
		return nil, err
	}
	newRow := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1", instanceID)
	return scanInstance(newRow)
}

// NEW: UpdateStatusToCancelled
func (r *jobInstanceRepo) UpdateStatusToCancelled(
	ctx context.Context,
	instanceID uuid.UUID,
	expectedVersion int64,
) (*models.JobInstance, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback(ctx)
		} else {
			_ = tx.Commit(ctx)
		}
	}()

	row := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1 FOR UPDATE", instanceID)
	inst, err := scanInstance(row)
	if err != nil {
		return nil, err
	}
	if inst == nil {
		return nil, pgx.ErrNoRows
	}
	if inst.RowVersion != expectedVersion {
		return nil, fmt.Errorf("row_version_conflict")
	}

	_, err = tx.Exec(ctx, `
        UPDATE job_instances
        SET status='CANCELED',
            check_out_at=NOW(),
            row_version=row_version+1,
            updated_at=NOW()
        WHERE id=$1
    `, instanceID)
	if err != nil {
		return nil, err
	}
	newRow := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1", instanceID)
	return scanInstance(newRow)
}

// NEW: RevertInProgressToOpenAtomic
//
//	transitions from IN_PROGRESS to OPEN, removing assigned_worker_id, clearing check_in_at, etc.
func (r *jobInstanceRepo) RevertInProgressToOpenAtomic(
	ctx context.Context,
	instanceID uuid.UUID,
	expectedVersion int64,
	newAssignCount int,
	flagged bool,
) (*models.JobInstance, error) {

	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback(ctx)
		} else {
			_ = tx.Commit(ctx)
		}
	}()

	row := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1 FOR UPDATE", instanceID)
	inst, err := scanInstance(row)
	if err != nil {
		return nil, err
	}
	if inst == nil {
		return nil, pgx.ErrNoRows
	}
	if inst.RowVersion != expectedVersion {
		return inst, fmt.Errorf("row_version_conflict")
	}
	if inst.Status != models.InstanceStatusInProgress {
		return inst, fmt.Errorf("cannot revert to OPEN from a non-IN_PROGRESS job")
	}

	_, err = tx.Exec(ctx, `
        UPDATE job_instances
        SET status='OPEN',
            assigned_worker_id=NULL,
            check_in_at=NULL,
            check_out_at=NULL,
            assign_unassign_count=$1,
            flagged_for_review=$2,
            row_version=row_version+1,
            updated_at=NOW()
        WHERE id=$3
    `, newAssignCount, flagged, instanceID)
	if err != nil {
		return nil, err
	}
	newRow := tx.QueryRow(ctx, baseSelectInstance()+" WHERE id=$1", instanceID)
	return scanInstance(newRow)
}

func (r *jobInstanceRepo) RetireInstancesForDate(
	ctx context.Context,
	date time.Time,
	oldStatuses []models.InstanceStatusType,
) error {
	var inList string
	for i, st := range oldStatuses {
		if i > 0 {
			inList += ","
		}
		inList += "'" + string(st) + "'"
	}

	_, err := r.db.Exec(ctx, fmt.Sprintf(`
        UPDATE job_instances
        SET status='RETIRED', row_version=row_version+1, updated_at=NOW()
        WHERE service_date=$1
          AND status IN (%s)
    `, inList), date.Format("2006-01-02"))
	return err
}

func (r *jobInstanceRepo) DeleteFutureOpenInstances(
	ctx context.Context,
	defID uuid.UUID,
	today time.Time,
) error {
	q := `
        DELETE FROM job_instances
        WHERE definition_id=$1
          AND service_date>$2
          AND status='OPEN'
    `
	_, err := r.db.Exec(ctx, q, defID, today.Format("2006-01-02"))
	return err
}

func (r *jobInstanceRepo) AddExcludedWorker(ctx context.Context, instanceID uuid.UUID, workerID uuid.UUID) error {
	_, err := r.db.Exec(ctx, `
        UPDATE job_instances
        SET excluded_worker_ids=array_append(excluded_worker_ids,$1),
            updated_at=NOW()
        WHERE id=$2
    `, workerID, instanceID)
	return err
}

func (r *jobInstanceRepo) SetWarning90MinSent(ctx context.Context, instanceID uuid.UUID) error {
	_, err := r.db.Exec(ctx, `
        UPDATE job_instances
        SET warning_90_min_sent_at=NOW(),
            updated_at=NOW()
        WHERE id=$1
    `, instanceID)
	return err
}

func (r *jobInstanceRepo) SetWarning40MinSent(ctx context.Context, instanceID uuid.UUID) error {
	_, err := r.db.Exec(ctx, `
        UPDATE job_instances
        SET warning_40_min_sent_at=NOW(),
            updated_at=NOW()
        WHERE id=$1
    `, instanceID)
	return err
}
