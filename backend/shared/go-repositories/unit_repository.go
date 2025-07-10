package repositories

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/go-models"
)

/* ───────────── public interface ───────────── */

type UnitRepository interface {
	Create(ctx context.Context, u *models.Unit) error
	CreateMany(ctx context.Context, list []models.Unit) error

	GetByID(ctx context.Context, id uuid.UUID) (*models.Unit, error)
	ListByPropertyID(ctx context.Context, propID uuid.UUID) ([]*models.Unit, error)
	ListByBuildingID(ctx context.Context, bldgID uuid.UUID) ([]*models.Unit, error)

	Update(ctx context.Context, u *models.Unit) error
	UpdateIfVersion(ctx context.Context, u *models.Unit, expected int64) (pgconn.CommandTag, error)
	UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.Unit) error) error
	Delete(ctx context.Context, id uuid.UUID) error
	DeleteByPropertyID(ctx context.Context, propID uuid.UUID) error
	SoftDelete(ctx context.Context, id uuid.UUID) error

	FindByTenantToken(ctx context.Context, token string) (*models.Unit, error)
}

/* ───────────── implementation ───────────── */

type unitRepo struct {
	*BaseVersionedRepo[*models.Unit]
	db DB
}

func NewUnitRepository(db DB) UnitRepository {
	r := &unitRepo{db: db}
	// FIXED: Add deleted_at check
	selectStmt := baseSelectUnit() + " WHERE id=$1 AND deleted_at IS NULL"
	r.BaseVersionedRepo = NewBaseRepo(db, selectStmt, r.scanUnit)
	return r
}

/* ---------- create ---------- */

func (r *unitRepo) Create(ctx context.Context, u *models.Unit) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO units (
			id, property_id, building_id, unit_number, tenant_token, 
			created_at, updated_at, row_version
		) VALUES ($1,$2,$3,$4,$5, NOW(), NOW(), 1)
	`, u.ID, u.PropertyID, u.BuildingID, u.UnitNumber, u.TenantToken)
	return err
}

func (r *unitRepo) CreateMany(ctx context.Context, list []models.Unit) error {
	for i := range list {
		if err := r.Create(ctx, &list[i]); err != nil {
			return err
		}
	}
	return nil
}

/* ---------- reads ---------- */

func (r *unitRepo) GetByID(ctx context.Context, id uuid.UUID) (*models.Unit, error) {
	return r.BaseVersionedRepo.GetByID(ctx, id.String())
}

func (r *unitRepo) ListByPropertyID(ctx context.Context, propID uuid.UUID) ([]*models.Unit, error) {
	// FIXED: Add deleted_at check
	rows, err := r.db.Query(ctx, baseSelectUnit()+" WHERE property_id=$1 AND deleted_at IS NULL ORDER BY unit_number", propID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return r.scanUnits(rows)
}

func (r *unitRepo) ListByBuildingID(ctx context.Context, bldgID uuid.UUID) ([]*models.Unit, error) {
	// FIXED: Add deleted_at check
	rows, err := r.db.Query(ctx, baseSelectUnit()+" WHERE building_id=$1 AND deleted_at IS NULL ORDER BY unit_number", bldgID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return r.scanUnits(rows)
}

/* ---------- update / delete ---------- */

func (r *unitRepo) Update(ctx context.Context, u *models.Unit) error {
	_, err := r.update(ctx, u, false, 0)
	return err
}

func (r *unitRepo) UpdateIfVersion(ctx context.Context, u *models.Unit, expected int64) (pgconn.CommandTag, error) {
	return r.update(ctx, u, true, expected)
}

func (r *unitRepo) UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.Unit) error) error {
	return r.BaseVersionedRepo.UpdateWithRetry(ctx, id.String(), mutate, r.UpdateIfVersion)
}

func (r *unitRepo) update(ctx context.Context, u *models.Unit, check bool, expected int64) (pgconn.CommandTag, error) {
	sql := `
		UPDATE units
		SET unit_number=$1, tenant_token=$2, building_id=$3, updated_at=NOW()
	`
	args := []any{u.UnitNumber, u.TenantToken, u.BuildingID}
	if check {
		sql += `, row_version=row_version+1 WHERE id=$4 AND row_version=$5`
		args = append(args, u.ID, expected)
	} else {
		sql += ` WHERE id=$4`
		args = append(args, u.ID)
	}
	return r.db.Exec(ctx, sql, args...)
}

func (r *unitRepo) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM units WHERE id=$1`, id)
	return err
}

func (r *unitRepo) DeleteByPropertyID(ctx context.Context, propID uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM units WHERE property_id=$1`, propID)
	return err
}

func (r *unitRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	// FIXED: Use UPDATE to set deleted_at instead of DELETE
	tag, err := r.db.Exec(ctx, `UPDATE units SET deleted_at=NOW() WHERE id=$1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

func (r *unitRepo) FindByTenantToken(ctx context.Context, token string) (*models.Unit, error) {
	// FIXED: Add deleted_at check
	row := r.db.QueryRow(ctx, baseSelectUnit()+" WHERE tenant_token=$1 AND deleted_at IS NULL LIMIT 1", token)
	return r.scanUnit(row)
}

/* ---------- internals ---------- */

func baseSelectUnit() string {
	return `
		SELECT id,property_id,building_id,unit_number,tenant_token,
		created_at, updated_at, row_version
		FROM units`
}

func (r *unitRepo) scanUnit(row pgx.Row) (*models.Unit, error) {
	var u models.Unit
	if err := row.Scan(
		&u.ID, &u.PropertyID, &u.BuildingID,
		&u.UnitNumber, &u.TenantToken,
		&u.CreatedAt, &u.UpdatedAt, &u.RowVersion,
	); err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &u, nil
}

func (r *unitRepo) scanUnits(rows pgx.Rows) ([]*models.Unit, error) {
	var out []*models.Unit
	for rows.Next() {
		u, err := r.scanUnit(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}