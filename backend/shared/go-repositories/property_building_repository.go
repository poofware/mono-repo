package repositories

import (
	"context"

	"github.com/google/uuid"
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
	Delete(ctx context.Context, id uuid.UUID) error
	DeleteByPropertyID(ctx context.Context, propertyID uuid.UUID) error
}

/* ------------------------------------------------------------------
   Implementation
------------------------------------------------------------------ */

type buildingRepo struct{ db DB }

func NewPropertyBuildingRepository(db DB) PropertyBuildingRepository {
	return &buildingRepo{db: db}
}

/* ---------- Create ---------- */

func (r *buildingRepo) Create(ctx context.Context, b *models.PropertyBuilding) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO property_buildings (
			id,property_id,building_name,address,latitude,longitude
		) VALUES ($1,$2,$3,$4,$5,$6)
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
	row := r.db.QueryRow(ctx, baseSelectBuilding()+" WHERE id=$1", id)
	return scanBuilding(row)
}

func (r *buildingRepo) ListByPropertyID(ctx context.Context, propertyID uuid.UUID) ([]*models.PropertyBuilding, error) {
	rows, err := r.db.Query(ctx, baseSelectBuilding()+" WHERE property_id=$1 ORDER BY building_name NULLS LAST", propertyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.PropertyBuilding
	for rows.Next() {
		b, err := scanBuilding(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

/* ---------- Update / Delete ---------- */

func (r *buildingRepo) Update(ctx context.Context, b *models.PropertyBuilding) error {
	_, err := r.db.Exec(ctx, `
		UPDATE property_buildings SET
		      building_name=$1,address=$2,latitude=$3,longitude=$4
		WHERE id=$5
	`, b.BuildingName, b.Address, b.Latitude, b.Longitude, b.ID)
	return err
}

func (r *buildingRepo) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM property_buildings WHERE id=$1`, id)
	return err
}

func (r *buildingRepo) DeleteByPropertyID(ctx context.Context, propertyID uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM property_buildings WHERE property_id=$1`, propertyID)
	return err
}

/* ---------- internals ---------- */

func baseSelectBuilding() string {
	return `
		SELECT id,property_id,building_name,address,latitude,longitude
		FROM property_buildings`
}

func scanBuilding(row pgx.Row) (*models.PropertyBuilding, error) {
	var b models.PropertyBuilding
	if err := row.Scan(
		&b.ID, &b.PropertyID, &b.BuildingName, &b.Address, &b.Latitude, &b.Longitude,
	); err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &b, nil
}

