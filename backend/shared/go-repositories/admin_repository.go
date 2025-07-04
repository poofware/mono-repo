// go-repositories/admin_repository.go
package repositories

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/go-models"
	"github.com/poofware/go-utils"
)

// AdminRepository defines the interface for admin data operations.
type AdminRepository interface {
	Create(ctx context.Context, admin *models.Admin) error
	GetByUsername(ctx context.Context, username string) (*models.Admin, error)
	GetByID(ctx context.Context, id uuid.UUID) (*models.Admin, error)
	UpdateIfVersion(ctx context.Context, admin *models.Admin, expected int64) (pgconn.CommandTag, error)
	UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.Admin) error) error
}

type adminRepo struct {
	*BaseVersionedRepo[*models.Admin]
	db     DB
	encKey []byte
}

// NewAdminRepository creates a new instance of the admin repository.
func NewAdminRepository(db DB, key []byte) AdminRepository {
	r := &adminRepo{db: db, encKey: key}
	selectStmt := baseSelectAdmin() + " WHERE id=$1"
	r.BaseVersionedRepo = NewBaseRepo(db, selectStmt, r.scanAdmin)
	return r
}

func (r *adminRepo) Create(ctx context.Context, admin *models.Admin) error {
	var encTOTP string
	if admin.TOTPSecret != "" {
		tempEncTOTP, err := utils.Encrypt(r.encKey, admin.TOTPSecret)
		if err != nil {
			return err
		}
		encTOTP = tempEncTOTP
	}

		// The caller is responsible for hashing the password. This repository
	// should just store the hash it's given.
		_, err := r.db.Exec(ctx, `
			 INSERT INTO admins (
				 id, username, password_hash, totp_secret,
				 account_status, setup_progress,
				 created_at, updated_at, row_version
			 ) VALUES ($1, $2, $3, $4, 'INCOMPLETE', 'ID_VERIFY', NOW(), NOW(), 1)
		`, admin.ID, admin.Username, admin.PasswordHash, encTOTP)
		 return err
}

func (r *adminRepo) GetByUsername(ctx context.Context, username string) (*models.Admin, error) {
	row := r.db.QueryRow(ctx, baseSelectAdmin()+" WHERE username=$1", username)
	return r.scanAdmin(row)
}

func (r *adminRepo) GetByID(ctx context.Context, id uuid.UUID) (*models.Admin, error) {
	return r.BaseVersionedRepo.GetByID(ctx, id.String())
}

func (r *adminRepo) UpdateIfVersion(ctx context.Context, admin *models.Admin, expected int64) (pgconn.CommandTag, error) {
	if admin.TOTPSecret != "" {
		enc, err := utils.Encrypt(r.encKey, admin.TOTPSecret)
		if err != nil {
			return nil, err
		}
		admin.TOTPSecret = enc
	}

	// Password updates should be handled in a separate, dedicated flow.
	// This update function will not change the password hash.
	sql := `
		UPDATE admins SET
			username=$1, totp_secret=$2,
			account_status=$3, setup_progress=$4,
			updated_at=NOW(), row_version=row_version+1
		WHERE id=$5 AND row_version=$6`
	args := []any{
		admin.Username, admin.TOTPSecret,
		string(admin.AccountStatus), string(admin.SetupProgress),
		admin.ID, expected,
	}
	return r.db.Exec(ctx, sql, args...)
}

func (r *adminRepo) UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.Admin) error) error {
	return r.BaseVersionedRepo.UpdateWithRetry(ctx, id.String(), mutate, r.UpdateIfVersion)
}

func baseSelectAdmin() string {
	return `
		SELECT id, username, password_hash, totp_secret,
		       account_status, setup_progress,
		       row_version, created_at, updated_at
		FROM admins`
}

func (r *adminRepo) scanAdmin(row pgx.Row) (*models.Admin, error) {
	var admin models.Admin
	var enc *string
	var acc, prog string

	err := row.Scan(
		&admin.ID, &admin.Username, &admin.PasswordHash, &enc,
		&acc, &prog,
		&admin.RowVersion, &admin.CreatedAt, &admin.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	admin.AccountStatus = models.AccountStatusType(acc)
	admin.SetupProgress = models.SetupProgressType(prog)

	if enc != nil && *enc != "" {
		dec, decErr := utils.Decrypt(r.encKey, *enc)
		if decErr != nil {
			return nil, decErr
		}
		admin.TOTPSecret = dec
	}

	return &admin, nil
}