// backend/shared/go-repositories/property_building_repository.go

package repositories

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/go-models"
)

/* ------------------------------------------------------------------
   Public interface
------------------------------------------------------------------ */

type PropertyBuildingRepository interface {
	Create(ctx context.Context, b *models.PropertyBuilding) error
	CreateMany(ctx context.Context, list []models.PropertyBuilding) error

	GetByID(ctx context.Context, id uuid.UUID) (*models.PropertyBuilding, error)
	ListByPropertyID(ctx context.Context, propertyID uuid.UUID) ([]*models.PropertyBuilding, error)

	Update(ctx context.Context, b *models.PropertyBuilding) error
	UpdateIfVersion(ctx context.Context, b *models.PropertyBuilding, expected int64) (pgconn.CommandTag, error)
	UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.PropertyBuilding) error) error
	Delete(ctx context.Context, id uuid.UUID) error
	DeleteByPropertyID(ctx context.Context, propertyID uuid.UUID) error
	SoftDelete(ctx context.Context, id uuid.UUID) error
}

/* ------------------------------------------------------------------
   Implementation
------------------------------------------------------------------ */

type buildingRepo struct {
	*BaseVersionedRepo[*models.PropertyBuilding]
	db DB
}

func NewPropertyBuildingRepository(db DB) PropertyBuildingRepository {
	r := &buildingRepo{db: db}
	selectStmt := baseSelectBuilding() + " WHERE id=$1 AND deleted_at IS NULL"
	r.BaseVersionedRepo = NewBaseRepo(db, selectStmt, r.scanBuilding)
	return r
}

/* ---------- Create ---------- */

func (r *buildingRepo) Create(ctx context.Context, b *models.PropertyBuilding) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO property_buildings (
			id,property_id,building_name,address,latitude,longitude,
			created_at, updated_at, row_version
		) VALUES ($1,$2,$3,$4,$5,$6, NOW(), NOW(), 1)
	`, b.ID, b.PropertyID, b.BuildingName, b.Address, b.Latitude, b.Longitude)
	return err
}

func (r *buildingRepo) CreateMany(ctx context.Context, list []models.PropertyBuilding) error {
	for _, b := range list {
		if err := r.Create(ctx, &b); err != nil {
			return err
		}
	}
	return nil
}

/* ---------- Reads ---------- */

func (r *buildingRepo) GetByID(ctx context.Context, id uuid.UUID) (*models.PropertyBuilding, error) {
	return r.BaseVersionedRepo.GetByID(ctx, id.String())
}

func (r *buildingRepo) ListByPropertyID(ctx context.Context, propertyID uuid.UUID) ([]*models.PropertyBuilding, error) {
	rows, err := r.db.Query(ctx, baseSelectBuilding()+" WHERE property_id=$1 AND deleted_at IS NULL ORDER BY building_name NULLS LAST", propertyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.PropertyBuilding
	for rows.Next() {
		b, err := r.scanBuilding(rows) // FIXED
		if err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

/* ---------- Update / Delete ---------- */

func (r *buildingRepo) Update(ctx context.Context, b *models.PropertyBuilding) error {
	_, err := r.update(ctx, b, false, 0)
	return err
}

func (r *buildingRepo) UpdateIfVersion(ctx context.Context, b *models.PropertyBuilding, expected int64) (pgconn.CommandTag, error) {
	return r.update(ctx, b, true, expected)
}

func (r *buildingRepo) UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.PropertyBuilding) error) error {
	return r.BaseVersionedRepo.UpdateWithRetry(ctx, id.String(), mutate, r.UpdateIfVersion)
}

func (r *buildingRepo) update(ctx context.Context, b *models.PropertyBuilding, check bool, expected int64) (pgconn.CommandTag, error) {
	sql := `
		UPDATE property_buildings SET
		      building_name=$1,address=$2,latitude=$3,longitude=$4, updated_at=NOW()
	`
	args := []any{b.BuildingName, b.Address, b.Latitude, b.Longitude}
	if check {
		sql += `, row_version=row_version+1 WHERE id=$5 AND row_version=$6`
		args = append(args, b.ID, expected)
	} else {
		sql += ` WHERE id=$5`
		args = append(args, b.ID)
	}
	return r.db.Exec(ctx, sql, args...)
}

func (r *buildingRepo) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM property_buildings WHERE id=$1`, id)
	return err
}

func (r *buildingRepo) DeleteByPropertyID(ctx context.Context, propertyID uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM property_buildings WHERE property_id=$1`, propertyID)
	return err
}

func (r *buildingRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	tag, err := r.db.Exec(ctx, `UPDATE property_buildings SET deleted_at=NOW() WHERE id=$1 AND deleted_at IS NULL`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

/* ---------- internals ---------- */

func baseSelectBuilding() string {
	return `
		SELECT id,property_id,building_name,address,latitude,longitude,
		created_at, updated_at, deleted_at, row_version
		FROM property_buildings`
}

func (r *buildingRepo) scanBuilding(row pgx.Row) (*models.PropertyBuilding, error) {
	var b models.PropertyBuilding
	if err := row.Scan(
		&b.ID, &b.PropertyID, &b.BuildingName, &b.Address, &b.Latitude, &b.Longitude,
		&b.CreatedAt, &b.UpdatedAt, &b.DeletedAt, &b.RowVersion,
	); err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &b, nil
}