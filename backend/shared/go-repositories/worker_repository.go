// go-repositories/worker_repository.go

package repositories

import (
    "context"
    "fmt"
    "time"

    "github.com/google/uuid"
    "github.com/jackc/pgconn"
    "github.com/jackc/pgx/v4"
    "github.com/poofware/go-models"
    "github.com/poofware/go-utils"
)

type WorkerRepository interface {
    Create(ctx context.Context, w *models.Worker) error
    GetByEmail(ctx context.Context, email string) (*models.Worker, error)
    GetByPhoneNumber(ctx context.Context, phone string) (*models.Worker, error)
    GetByID(ctx context.Context, id uuid.UUID) (*models.Worker, error)
    Update(ctx context.Context, w *models.Worker) error
    UpdateIfVersion(ctx context.Context, w *models.Worker, expected int64) (pgconn.CommandTag, error)
    UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.Worker) error) error

    GetByStripeConnectAccountID(ctx context.Context, acct string) (*models.Worker, error)
    GetByCheckrInvitationID(ctx context.Context, inv string) (*models.Worker, error)
    GetByCheckrReportID(ctx context.Context, rep string) (*models.Worker, error)
    GetByCheckrCandidateID(ctx context.Context, cand string) (*models.Worker, error)

    AdjustWorkerScoreAtomic(ctx context.Context, workerID uuid.UUID, delta int, eventType string) error
}

type workerRepo struct {
    *BaseVersionedRepo[*models.Worker]
    db     DB
    encKey []byte
}

func NewWorkerRepository(db DB, key []byte) WorkerRepository {
    r := &workerRepo{db: db, encKey: key}
    selectStmt := baseSelectWorker() + " WHERE id=$1"
    r.BaseVersionedRepo = NewBaseRepo(db, selectStmt, r.scanWorker)
    return r
}

func (r *workerRepo) Create(ctx context.Context, w *models.Worker) error {
	var encTOTP string
	if w.TOTPSecret != "" {
		tempEncTOTP, err := utils.Encrypt(r.encKey, w.TOTPSecret)
		if err != nil {
			return err
		}
		encTOTP = tempEncTOTP
	}
	// MODIFIED: Removed address and vehicle info from the INSERT statement.
	// The database will now use the DEFAULT values for these columns.
	_, err := r.db.Exec(ctx, `
        INSERT INTO workers (
            id,email,phone_number,totp_secret,
            first_name,last_name, tenant_token
        ) VALUES (
            $1,$2,$3,$4,
            $5,$6,$7
        )
    `,
		w.ID, w.Email, w.PhoneNumber, encTOTP,
		w.FirstName, w.LastName,
		w.TenantToken,
	)
	return err
}

func (r *workerRepo) GetByEmail(ctx context.Context, email string) (*models.Worker, error) {
    row := r.db.QueryRow(ctx, baseSelectWorker()+" WHERE email=$1", email)
    return r.scanWorker(row)
}

func (r *workerRepo) GetByPhoneNumber(ctx context.Context, phone string) (*models.Worker, error) {
    row := r.db.QueryRow(ctx, baseSelectWorker()+" WHERE phone_number=$1", phone)
    return r.scanWorker(row)
}

func (r *workerRepo) GetByID(ctx context.Context, id uuid.UUID) (*models.Worker, error) {
    return r.BaseVersionedRepo.GetByID(ctx, id.String())
}

func (r *workerRepo) Update(ctx context.Context, w *models.Worker) error {
    _, err := r.update(ctx, w, false, 0)
    return err
}

func (r *workerRepo) UpdateIfVersion(ctx context.Context, w *models.Worker, expected int64) (pgconn.CommandTag, error) {
    return r.update(ctx, w, true, expected)
}

func (r *workerRepo) UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.Worker) error) error {
    return r.BaseVersionedRepo.UpdateWithRetry(ctx, id.String(), mutate, r.UpdateIfVersion)
}

func (r *workerRepo) GetByStripeConnectAccountID(ctx context.Context, acct string) (*models.Worker, error) {
    row := r.db.QueryRow(ctx, baseSelectWorker()+" WHERE stripe_connect_account_id=$1", acct)
    return r.scanWorker(row)
}

func (r *workerRepo) GetByCheckrInvitationID(ctx context.Context, inv string) (*models.Worker, error) {
    row := r.db.QueryRow(ctx, baseSelectWorker()+" WHERE checkr_invitation_id=$1 LIMIT 1", inv)
    return r.scanWorker(row)
}

func (r *workerRepo) GetByCheckrReportID(ctx context.Context, rep string) (*models.Worker, error) {
    row := r.db.QueryRow(ctx, baseSelectWorker()+" WHERE checkr_report_id=$1 LIMIT 1", rep)
    return r.scanWorker(row)
}

func (r *workerRepo) GetByCheckrCandidateID(ctx context.Context, cand string) (*models.Worker, error) {
    row := r.db.QueryRow(ctx, baseSelectWorker()+" WHERE checkr_candidate_id=$1 LIMIT 1", cand)
    return r.scanWorker(row)
}

// AdjustWorkerScoreAtomic ...
func (r *workerRepo) AdjustWorkerScoreAtomic(ctx context.Context, workerID uuid.UUID, delta int, eventType string) error {
    tx, err := r.db.Begin(ctx)
    if err != nil {
        return err
    }
    defer func() {
        if err != nil {
            _ = tx.Rollback(ctx)
        } else {
            _ = tx.Commit(ctx)
        }
    }()

    row := tx.QueryRow(ctx, baseSelectWorker()+" WHERE id=$1 FOR UPDATE", workerID)
    w, err := r.scanWorker(row)
    if err != nil {
        return err
    }
    if w == nil {
        return fmt.Errorf("worker not found for ID=%s", workerID)
    }

    oldScore := w.ReliabilityScore
    newScore := max(min(oldScore+delta, utils.WorkerScoreMax), utils.WorkerScoreMin)

    isBanned := w.IsBanned
    suspendedUntil := w.SuspendedUntil
    now := time.Now().UTC()

    if newScore <= utils.WorkerBanThresholdScore {
        isBanned = true
    } else if newScore <= utils.WorkerSuspendThresholdScore {
        if suspendedUntil == nil || suspendedUntil.Before(now) {
            st := now.AddDate(0, 0, utils.WorkerSuspensionDays)
            suspendedUntil = &st
        }
    }

    _, err = tx.Exec(ctx, `
        UPDATE workers
        SET reliability_score=$1,
            is_banned=$2,
            suspended_until=$3,
            row_version=row_version+1,
            updated_at=NOW()
        WHERE id=$4
    `, newScore, isBanned, suspendedUntil, w.ID)
    if err != nil {
        return err
    }

    _, err = tx.Exec(ctx, `
        INSERT INTO worker_score_events (id, worker_id, event_type, delta, old_score, new_score, created_at)
        VALUES ($1,$2,$3,$4,$5,$6,NOW())
    `,
        uuid.New(),
        w.ID,
        eventType,
        delta,
        oldScore,
        newScore,
    )
    return err
}

func (r *workerRepo) update(ctx context.Context, w *models.Worker, check bool, expected int64) (pgconn.CommandTag, error) {
    if w.TOTPSecret != "" {
        enc, err := utils.Encrypt(r.encKey, w.TOTPSecret)
        if err != nil {
            return nil, err
        }
        w.TOTPSecret = enc
    }

    sql := `
        UPDATE workers SET
            email=$1,phone_number=$2,totp_secret=$3,
            first_name=$4,last_name=$5,street_address=$6,apt_suite=$7,
            city=$8,state=$9,zip_code=$10,
            vehicle_year=$11,vehicle_make=$12,vehicle_model=$13,
            account_status=$14,setup_progress=$15,
            stripe_connect_account_id=$16,current_stripe_idv_session_id=$17,
            checkr_candidate_id=$18,checkr_invitation_id=$19,checkr_report_id=$20,
            checkr_report_outcome=$21,checkr_report_eta=$22,
            reliability_score=$23,is_banned=$24,suspended_until=$25,tenant_token=$26,
            updated_at=NOW()
    `
    args := []any{
        w.Email, w.PhoneNumber, w.TOTPSecret,
        w.FirstName, w.LastName, w.StreetAddress, w.AptSuite,
        w.City, w.State, w.ZipCode,
        w.VehicleYear, w.VehicleMake, w.VehicleModel,
        w.AccountStatus, w.SetupProgress,
        w.StripeConnectAccountID, w.CurrentStripeIdvSessionID,
        w.CheckrCandidateID, w.CheckrInvitationID, w.CheckrReportID,
        w.CheckrReportOutcome, w.CheckrReportETA,
        w.ReliabilityScore, w.IsBanned, w.SuspendedUntil,w.TenantToken,
    }

    if check {
        sql += `, row_version=row_version+1 WHERE id=$27 AND row_version=$28`
        args = append(args, w.ID, expected)
    } else {
        sql += ` WHERE id=$27`
        args = append(args, w.ID)
    }
    return r.db.Exec(ctx, sql, args...)
}

func baseSelectWorker() string {
    return `
    SELECT
        id,email,phone_number,totp_secret,
        first_name,last_name,street_address,apt_suite,city,state,zip_code,
        vehicle_year,vehicle_make,vehicle_model,
        account_status,setup_progress,
        stripe_connect_account_id,current_stripe_idv_session_id,
        checkr_candidate_id,checkr_invitation_id,checkr_report_id,
        checkr_report_outcome,checkr_report_eta,
        reliability_score,is_banned,suspended_until,tenant_token,
        row_version,created_at,updated_at
    FROM workers`
}

func (r *workerRepo) scanWorker(row pgx.Row) (*models.Worker, error) {
    var w models.Worker
    var enc *string
    var acc, prog, outcome string
    var eta *time.Time
    var suspendedUntil *time.Time
    var tenantToken *string

    err := row.Scan(
        &w.ID, &w.Email, &w.PhoneNumber, &enc,
        &w.FirstName, &w.LastName, &w.StreetAddress, &w.AptSuite, &w.City, &w.State, &w.ZipCode,
        &w.VehicleYear, &w.VehicleMake, &w.VehicleModel,
        &acc, &prog,
        &w.StripeConnectAccountID, &w.CurrentStripeIdvSessionID,
        &w.CheckrCandidateID, &w.CheckrInvitationID, &w.CheckrReportID,
        &outcome, &eta,
        &w.ReliabilityScore, &w.IsBanned, &suspendedUntil,&tenantToken,
        &w.RowVersion, &w.CreatedAt, &w.UpdatedAt,
    )
    if err != nil {
        if err == pgx.ErrNoRows {
            return nil, nil
        }
        return nil, err
    }

    w.AccountStatus = models.AccountStatusType(acc)
    w.SetupProgress = models.SetupProgressType(prog)
    w.CheckrReportOutcome = models.ReportOutcomeType(outcome)
    w.CheckrReportETA = eta
    w.SuspendedUntil = suspendedUntil
    w.TenantToken = tenantToken

    if enc != nil && *enc != "" {
        dec, decErr := utils.Decrypt(r.encKey, *enc)
        if decErr != nil {
            return nil, decErr
        }
        w.TOTPSecret = dec
    }

    return &w, nil
}
