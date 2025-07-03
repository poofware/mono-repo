package repositories

import (
	"context"
	"encoding/json"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/go-models"
)

/* ------------------------------------------------------------------
   Public interface
------------------------------------------------------------------ */

type JobDefinitionRepository interface {
	Create(ctx context.Context, j *models.JobDefinition) error

	GetByID(ctx context.Context, id uuid.UUID) (*models.JobDefinition, error)
	ListByManagerID(ctx context.Context, managerID uuid.UUID) ([]*models.JobDefinition, error)
	ListByPropertyID(ctx context.Context, propertyID uuid.UUID) ([]*models.JobDefinition, error)
	ListByStatus(ctx context.Context, status models.JobStatusType) ([]*models.JobDefinition, error)

	Update(ctx context.Context, j *models.JobDefinition) error
	UpdateIfVersion(ctx context.Context, j *models.JobDefinition, expected int64) (pgconn.CommandTag, error)
	UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.JobDefinition) error) error

	ChangeStatus(ctx context.Context, id uuid.UUID, status models.JobStatusType, expected int64) (pgconn.CommandTag, error)
}

/* ------------------------------------------------------------------
   Implementation
------------------------------------------------------------------ */

type jobRepo struct {
	*BaseVersionedRepo[*models.JobDefinition]
	db DB
}

func NewJobDefinitionRepository(db DB) JobDefinitionRepository {
	r := &jobRepo{db: db}
	selectStmt := baseSelectJob() + " WHERE id=$1"
	r.BaseVersionedRepo = NewBaseRepo(db, selectStmt, r.scanJob)
	return r
}

/* ---------- Create ---------- */

func (r *jobRepo) Create(ctx context.Context, j *models.JobDefinition) error {
	details, _ := json.Marshal(j.Details)
	reqs, _ := json.Marshal(j.Requirements)
	// REMOVED: pay, _ := json.Marshal(j.PayStructure)
	dailyPayEstimates, _ := json.Marshal(j.DailyPayEstimates) // NEW
	comp, _ := json.Marshal(j.CompletionRules)
	support, _ := json.Marshal(j.SupportContact)

	_, err := r.db.Exec(ctx, `
        INSERT INTO job_definitions (
            id, manager_id, property_id, title, description,
            assigned_building_ids, dumpster_ids, status, frequency,
            weekdays, interval_weeks, start_date, end_date,
            earliest_start_time, latest_start_time, start_time_hint,
            skip_holidays, holiday_exceptions,
            details, requirements, daily_pay_estimates, completion_rules, support_contact, -- UPDATED
            created_at, updated_at, row_version
        ) VALUES (
            $1,$2,$3,$4,$5,
            $6,$7,$8,$9,
            $10,$11,$12,$13,
            $14,$15,$16,
            $17,$18,
            $19,$20,$21,$22,$23, -- UPDATED
            NOW(),NOW(),1
        )
    `,
		j.ID, j.ManagerID, j.PropertyID, j.Title, j.Description,
		j.AssignedBuildingIDs, j.DumpsterIDs, j.Status, j.Frequency,
		j.Weekdays, j.IntervalWeeks, j.StartDate, j.EndDate,
		j.EarliestStartTime, j.LatestStartTime, j.StartTimeHint,
		j.SkipHolidays, j.HolidayExceptions,
		details, reqs, dailyPayEstimates, comp, support, // UPDATED
	)
	return err
}

/* ---------- Reads ---------- */

func (r *jobRepo) GetByID(ctx context.Context, id uuid.UUID) (*models.JobDefinition, error) {
	return r.BaseVersionedRepo.GetByID(ctx, id.String())
}

func (r *jobRepo) ListByManagerID(ctx context.Context, managerID uuid.UUID) ([]*models.JobDefinition, error) {
	rows, err := r.db.Query(ctx, baseSelectJob()+" WHERE manager_id=$1 ORDER BY created_at", managerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.JobDefinition
	for rows.Next() {
		j, err := r.scanJob(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, j)
	}
	return out, rows.Err()
}

func (r *jobRepo) ListByPropertyID(ctx context.Context, propertyID uuid.UUID) ([]*models.JobDefinition, error) {
	rows, err := r.db.Query(ctx, baseSelectJob()+" WHERE property_id=$1 ORDER BY created_at", propertyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.JobDefinition
	for rows.Next() {
		j, err := r.scanJob(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, j)
	}
	return out, rows.Err()
}

func (r *jobRepo) ListByStatus(ctx context.Context, status models.JobStatusType) ([]*models.JobDefinition, error) {
	q := baseSelectJob() + " WHERE status=$1 ORDER BY created_at"
	rows, err := r.db.Query(ctx, q, status)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.JobDefinition
	for rows.Next() {
		j, err := r.scanJob(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, j)
	}
	return out, rows.Err()
}

/* ---------- Updates ---------- */

func (r *jobRepo) Update(ctx context.Context, j *models.JobDefinition) error {
	_, err := r.update(ctx, j, false, 0)
	return err
}

func (r *jobRepo) UpdateIfVersion(ctx context.Context, j *models.JobDefinition, expected int64) (pgconn.CommandTag, error) {
	return r.update(ctx, j, true, expected)
}

func (r *jobRepo) UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.JobDefinition) error) error {
	return r.BaseVersionedRepo.UpdateWithRetry(ctx, id.String(), mutate, r.UpdateIfVersion)
}

/* ---------- Status helpers ---------- */

func (r *jobRepo) ChangeStatus(
	ctx context.Context,
	id uuid.UUID,
	status models.JobStatusType,
	expected int64,
) (pgconn.CommandTag, error) {
	return r.db.Exec(ctx, `
        UPDATE job_definitions
        SET status=$1, row_version=row_version+1, updated_at=NOW()
        WHERE id=$2 AND row_version=$3
    `, status, id, expected)
}

/* ---------- internals ---------- */

func (r *jobRepo) update(
	ctx context.Context,
	j *models.JobDefinition,
	check bool,
	expected int64,
) (pgconn.CommandTag, error) {
	details, _ := json.Marshal(j.Details)
	reqs, _ := json.Marshal(j.Requirements)
	// REMOVED: pay, _ := json.Marshal(j.PayStructure)
	dailyPayEstimates, _ := json.Marshal(j.DailyPayEstimates) // NEW
	comp, _ := json.Marshal(j.CompletionRules)
	support, _ := json.Marshal(j.SupportContact)

	sql := `
        UPDATE job_definitions SET
            title=$1, description=$2,
            assigned_building_ids=$3, dumpster_ids=$4,
            status=$5, frequency=$6,
            weekdays=$7, interval_weeks=$8,
            start_date=$9, end_date=$10,
            earliest_start_time=$11, latest_start_time=$12, start_time_hint=$13,
            skip_holidays=$14, holiday_exceptions=$15,
            details=$16, requirements=$17, daily_pay_estimates=$18, completion_rules=$19, support_contact=$20, -- UPDATED
            updated_at=NOW()`
	args := []any{
		j.Title, j.Description,
		j.AssignedBuildingIDs, j.DumpsterIDs,
		j.Status, j.Frequency,
		j.Weekdays, j.IntervalWeeks,
		j.StartDate, j.EndDate,
		j.EarliestStartTime, j.LatestStartTime, j.StartTimeHint,
		j.SkipHolidays, j.HolidayExceptions,
		details, reqs, dailyPayEstimates, comp, support, // UPDATED
	}

	// Parameter indices shift by one due to removal of one field and addition of another.
	// Old was 21 fields before ID/row_version, new is 20.
	// The last field before ID/row_version is now $20.
	// So ID becomes $21 and row_version becomes $22.

	if check {
		sql += `, row_version=row_version+1 WHERE id=$21 AND row_version=$22` // UPDATED indices
		args = append(args, j.ID, expected)
	} else {
		sql += ` WHERE id=$21` // UPDATED index
		args = append(args, j.ID)
	}
	return r.db.Exec(ctx, sql, args...)
}

func baseSelectJob() string {
	return `
        SELECT
            id, manager_id, property_id, title, description,
            assigned_building_ids, dumpster_ids, status, frequency,
            weekdays, interval_weeks, start_date, end_date,
            earliest_start_time, latest_start_time, start_time_hint,
            skip_holidays, holiday_exceptions,
            details, requirements, daily_pay_estimates, completion_rules, support_contact, -- UPDATED
            row_version, created_at, updated_at
        FROM job_definitions
    `
}

func (r *jobRepo) scanJob(row pgx.Row) (*models.JobDefinition, error) {
	var j models.JobDefinition

	var desc *string
	var assigned, dumpsters []uuid.UUID
	var status, freq string
	var weekdays []int16
	var interval *int
	var startDate, endDate *time.Time
	var eStart, lStart, sHint time.Time
	var holExc []time.Time
	var detailsB, reqB, dailyPayEstB, compB, suppB []byte // UPDATED: dailyPayEstB
	// REMOVED: var estTime int

	err := row.Scan(
		&j.ID, &j.ManagerID, &j.PropertyID, &j.Title, &desc,
		&assigned, &dumpsters, &status, &freq,
		&weekdays, &interval, &startDate, &endDate,
		&eStart, &lStart, &sHint,
		&j.SkipHolidays, &holExc,
		&detailsB, &reqB, &dailyPayEstB, &compB, &suppB, // UPDATED
		// REMOVED: &estTime,
		&j.RowVersion, &j.CreatedAt, &j.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	j.Description = desc
	j.AssignedBuildingIDs = assigned
	j.DumpsterIDs = dumpsters
	j.Status = models.JobStatusType(status)
	j.Frequency = models.JobFrequencyType(freq)
	j.Weekdays = weekdays
	j.IntervalWeeks = interval
	j.StartDate = *startDate
	j.EndDate = endDate
	j.EarliestStartTime = eStart
	j.LatestStartTime = lStart
	j.StartTimeHint = sHint
	j.HolidayExceptions = holExc

	_ = json.Unmarshal(detailsB, &j.Details)
	_ = json.Unmarshal(reqB, &j.Requirements)
	_ = json.Unmarshal(dailyPayEstB, &j.DailyPayEstimates) // NEW
	_ = json.Unmarshal(compB, &j.CompletionRules)
	_ = json.Unmarshal(suppB, &j.SupportContact)

	return &j, nil
}

