package repositories

import (
	"context"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/go-models"
	"github.com/poofware/go-utils"
)

/* ------------------------------------------------------------------
   Public interface
------------------------------------------------------------------ */

type PropertyManagerRepository interface {
	Create(ctx context.Context, pm *models.PropertyManager) error

	GetByEmail(ctx context.Context, email string) (*models.PropertyManager, error)
	GetByPhoneNumber(ctx context.Context, phone string) (*models.PropertyManager, error)
	GetByID(ctx context.Context, id uuid.UUID) (*models.PropertyManager, error)

	// Legacy blind overwrite
	Update(ctx context.Context, pm *models.PropertyManager) error

	// Optimistic‑lock helpers
	UpdateIfVersion(ctx context.Context, pm *models.PropertyManager, expected int64) (pgconn.CommandTag, error)
	UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.PropertyManager) error) error

	// NEW
	SoftDelete(ctx context.Context, id uuid.UUID) error
	Search(ctx context.Context, filters map[string]any, limit, offset int) ([]*models.PropertyManager, int, error)
}

/* ------------------------------------------------------------------
   Implementation
------------------------------------------------------------------ */

type pmRepo struct {
	*BaseVersionedRepo[*models.PropertyManager]

	db     DB
	encKey []byte
}

/* ---------- constructor ---------- */

func NewPropertyManagerRepository(db DB, key []byte) PropertyManagerRepository {
	r := &pmRepo{db: db, encKey: key}
	selectStmt := baseSelectPM() + " WHERE id=$1"
	r.BaseVersionedRepo = NewBaseRepo(db, selectStmt, r.scanPM)
	return r
}

/* ---------- Create ---------- */

func (r *pmRepo) Create(ctx context.Context, pm *models.PropertyManager) error {
	var encTOTP string
	if pm.TOTPSecret != "" {
		tempEncTOTP, err := utils.Encrypt(r.encKey, pm.TOTPSecret)
		if err != nil {
			return err
		}
		encTOTP = tempEncTOTP
	}

	_, err := r.db.Exec(ctx, `
		INSERT INTO property_managers (
			id,email,phone_number,totp_secret,
			business_name,business_address,city,state,zip_code,
			created_at,updated_at,row_version
		) VALUES (
			$1,$2,$3,$4,
			$5,$6,$7,$8,$9,
			NOW(),NOW(),1
		)`,
		pm.ID, pm.Email, pm.PhoneNumber, encTOTP,
		pm.BusinessName, pm.BusinessAddress, pm.City, pm.State, pm.ZipCode,
	)
	return err
}

/* ---------- Reads ---------- */

func (r *pmRepo) GetByEmail(ctx context.Context, email string) (*models.PropertyManager, error) {
	row := r.db.QueryRow(ctx, baseSelectPM()+" WHERE email=$1 AND deleted_at IS NULL", email)
	return r.scanPM(row)
}

func (r *pmRepo) GetByPhoneNumber(ctx context.Context, phone string) (*models.PropertyManager, error) {
	row := r.db.QueryRow(ctx, baseSelectPM()+" WHERE phone_number=$1 AND deleted_at IS NULL", phone)
	return r.scanPM(row)
}

func (r *pmRepo) GetByID(ctx context.Context, id uuid.UUID) (*models.PropertyManager, error) {
	row := r.db.QueryRow(ctx, baseSelectPM()+" WHERE id=$1 AND deleted_at IS NULL", id)
	return r.scanPM(row)
}

/* ---------- Updates ---------- */

// Legacy blind overwrite
func (r *pmRepo) Update(ctx context.Context, pm *models.PropertyManager) error {
	_, err := r.update(ctx, pm, false, 0)
	return err
}

// Optimistic
func (r *pmRepo) UpdateIfVersion(ctx context.Context, pm *models.PropertyManager, expected int64) (pgconn.CommandTag, error) {
	return r.update(ctx, pm, true, expected)
}

func (r *pmRepo) UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.PropertyManager) error) error {
	return r.BaseVersionedRepo.UpdateWithRetry(ctx, id.String(), mutate, r.UpdateIfVersion)
}

// NEW SoftDelete
func (r *pmRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `UPDATE property_managers SET deleted_at=NOW(), updated_at=NOW() WHERE id=$1`, id)
	return err
}

// NEW Search
func (r *pmRepo) Search(ctx context.Context, filters map[string]any, limit, offset int) ([]*models.PropertyManager, int, error) {
	var qb strings.Builder
	var args []any
	idx := 1

	countQb := strings.Builder{}
	countQb.WriteString("SELECT count(*) FROM property_managers WHERE deleted_at IS NULL")

	qb.WriteString(baseSelectPM())
	qb.WriteString(" WHERE deleted_at IS NULL")

	for key, value := range filters {
		// Basic validation to prevent injection on key
		if !isValidColumn(key) {
			return nil, 0, fmt.Errorf("invalid filter key: %s", key)
		}
		condition := fmt.Sprintf(" AND %s ILIKE $%d", key, idx)
		qb.WriteString(condition)
		countQb.WriteString(condition)
		args = append(args, fmt.Sprintf("%%%v%%", value))
		idx++
	}

	var total int
	err := r.db.QueryRow(ctx, countQb.String(), args...).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	qb.WriteString(fmt.Sprintf(" ORDER BY created_at DESC LIMIT $%d OFFSET $%d", idx, idx+1))
	args = append(args, limit, offset)

	rows, err := r.db.Query(ctx, qb.String(), args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var pms []*models.PropertyManager
	for rows.Next() {
		pm, err := r.scanPM(rows)
		if err != nil {
			return nil, 0, err
		}
		pms = append(pms, pm)
	}
	return pms, total, rows.Err()
}

func isValidColumn(name string) bool {
	// Simple allow-list for column names to prevent SQL injection
	switch name {
	case "email", "business_name":
		return true
	default:
		return false
	}
}

/* ---------- internals ---------- */

func (r *pmRepo) update(
	ctx context.Context,
	pm *models.PropertyManager,
	check bool,
	expected int64,
) (pgconn.CommandTag, error) {
	if pm.TOTPSecret != "" {
		enc, err := utils.Encrypt(r.encKey, pm.TOTPSecret)
		if err != nil {
			return nil, err
		}
		pm.TOTPSecret = enc
	}

	sql := `
		UPDATE property_managers SET
			email=$1,phone_number=$2,totp_secret=$3,
			business_name=$4,business_address=$5,city=$6,state=$7,zip_code=$8,
			account_status=$9,setup_progress=$10,
			updated_at=NOW()`
	args := []any{
		pm.Email, pm.PhoneNumber, pm.TOTPSecret,
		pm.BusinessName, pm.BusinessAddress, pm.City, pm.State, pm.ZipCode,
		string(pm.AccountStatus), string(pm.SetupProgress),
	}

	if check {
		sql += `, row_version=row_version+1 WHERE id=$11 AND row_version=$12`
		args = append(args, pm.ID, expected)
	} else {
		sql += ` WHERE id=$11`
		args = append(args, pm.ID)
	}

	return r.db.Exec(ctx, sql, args...)
}

func baseSelectPM() string {
	return `
		SELECT id,email,phone_number,totp_secret,
		       business_name,business_address,city,state,zip_code,
		       account_status,setup_progress,
		       row_version,created_at,updated_at,deleted_at
		FROM property_managers`
}

func (r *pmRepo) scanPM(row pgx.Row) (*models.PropertyManager, error) {
	var pm models.PropertyManager
	var enc *string
	var acc, prog string

	err := row.Scan(
		&pm.ID, &pm.Email, &pm.PhoneNumber, &enc,
		&pm.BusinessName, &pm.BusinessAddress, &pm.City, &pm.State, &pm.ZipCode,
		&acc, &prog,
		&pm.RowVersion, &pm.CreatedAt, &pm.UpdatedAt, &pm.DeletedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	pm.AccountStatus = models.AccountStatusType(acc)
	pm.SetupProgress = models.SetupProgressType(prog)

	if enc != nil && *enc != "" {
		dec, decErr := utils.Decrypt(r.encKey, *enc)
		if decErr != nil {
			return nil, decErr
		}
		pm.TOTPSecret = dec
	}

	return &pm, nil
}