// go-repositories/unit_repository.go

package repositories

import (
	"context"

	"github.com/google/uuid"
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
	Delete(ctx context.Context, id uuid.UUID) error
	DeleteByPropertyID(ctx context.Context, propID uuid.UUID) error

	// NEW: for tenant tokens
	FindByTenantToken(ctx context.Context, token string) (*models.Unit, error)
}

/* ───────────── implementation ───────────── */

type unitRepo struct{ db DB }

func NewUnitRepository(db DB) UnitRepository { return &unitRepo{db} }

/* ---------- create ---------- */

func (r *unitRepo) Create(ctx context.Context, u *models.Unit) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO units (
			id, property_id, building_id, unit_number, tenant_token, created_at
		) VALUES ($1,$2,$3,$4,$5,NOW())
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
	return scanUnit(r.db.QueryRow(ctx, baseSelectUnit()+" WHERE id=$1", id))
}

func (r *unitRepo) ListByPropertyID(ctx context.Context, propID uuid.UUID) ([]*models.Unit, error) {
	rows, err := r.db.Query(ctx, baseSelectUnit()+" WHERE property_id=$1 ORDER BY unit_number", propID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanUnits(rows)
}

func (r *unitRepo) ListByBuildingID(ctx context.Context, bldgID uuid.UUID) ([]*models.Unit, error) {
	rows, err := r.db.Query(ctx, baseSelectUnit()+" WHERE building_id=$1 ORDER BY unit_number", bldgID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanUnits(rows)
}

/* ---------- update / delete ---------- */

func (r *unitRepo) Update(ctx context.Context, u *models.Unit) error {
	_, err := r.db.Exec(ctx, `
		UPDATE units
		SET unit_number=$1, tenant_token=$2, building_id=$3
		WHERE id=$4
	`, u.UnitNumber, u.TenantToken, u.BuildingID, u.ID)
	return err
}

func (r *unitRepo) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM units WHERE id=$1`, id)
	return err
}

func (r *unitRepo) DeleteByPropertyID(ctx context.Context, propID uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM units WHERE property_id=$1`, propID)
	return err
}

// NEW: find exactly one unit by tenant_token (if multiple, we take the first).
func (r *unitRepo) FindByTenantToken(ctx context.Context, token string) (*models.Unit, error) {
	row := r.db.QueryRow(ctx, baseSelectUnit()+" WHERE tenant_token=$1 LIMIT 1", token)
	return scanUnit(row)
}

/* ---------- internals ---------- */

func baseSelectUnit() string {
	return `
		SELECT id,property_id,building_id,unit_number,tenant_token,created_at
		FROM units`
}

func scanUnit(row pgx.Row) (*models.Unit, error) {
	var u models.Unit
	if err := row.Scan(
		&u.ID, &u.PropertyID, &u.BuildingID,
		&u.UnitNumber, &u.TenantToken, &u.CreatedAt,
	); err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &u, nil
}

func scanUnits(rows pgx.Rows) ([]*models.Unit, error) {
	var out []*models.Unit
	for rows.Next() {
		u, err := scanUnit(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

