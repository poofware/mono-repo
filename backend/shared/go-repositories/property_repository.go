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

type PropertyRepository interface {
	Create(ctx context.Context, p *models.Property) error

	GetByID(ctx context.Context, id uuid.UUID) (*models.Property, error)
	ListByManagerID(ctx context.Context, managerID uuid.UUID) ([]*models.Property, error)

	Update(ctx context.Context, p *models.Property) error
	Delete(ctx context.Context, id uuid.UUID) error
	SoftDelete(ctx context.Context, id uuid.UUID) error // NEW

	ListAllProperties(ctx context.Context) ([]*models.Property, error)
}

/* ------------------------------------------------------------------
   Implementation
------------------------------------------------------------------ */

type propertyRepo struct {
	db DB
}

func NewPropertyRepository(db DB) PropertyRepository {
	return &propertyRepo{db: db}
}

func (r *propertyRepo) Create(ctx context.Context, p *models.Property) error {
	_, err := r.db.Exec(ctx, `
        INSERT INTO properties (
            id, manager_id, property_name, address, city, state, zip_code, time_zone,
            latitude, longitude,
            created_at
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10, NOW())
    `,
		p.ID,
		p.ManagerID,
		p.PropertyName,
		p.Address,
		p.City,
		p.State,
		p.ZipCode,
		p.TimeZone,
		p.Latitude,
		p.Longitude,
	)
	return err
}

func (r *propertyRepo) GetByID(ctx context.Context, id uuid.UUID) (*models.Property, error) {
	row := r.db.QueryRow(ctx, baseSelectProperty()+" WHERE id=$1 AND deleted_at IS NULL", id)
	return scanProperty(row)
}

func (r *propertyRepo) ListByManagerID(ctx context.Context, managerID uuid.UUID) ([]*models.Property, error) {
	rows, err := r.db.Query(ctx, baseSelectProperty()+" WHERE manager_id=$1 AND deleted_at IS NULL ORDER BY created_at", managerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.Property
	for rows.Next() {
		p, err := scanProperty(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (r *propertyRepo) Update(ctx context.Context, p *models.Property) error {
	_, err := r.db.Exec(ctx, `
        UPDATE properties SET
            property_name=$1, address=$2, city=$3, state=$4, zip_code=$5,
            time_zone=$6, latitude=$7, longitude=$8
        WHERE id=$9
    `,
		p.PropertyName,
		p.Address,
		p.City,
		p.State,
		p.ZipCode,
		p.TimeZone,
		p.Latitude,
		p.Longitude,
		p.ID,
	)
	return err
}

func (r *propertyRepo) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM properties WHERE id=$1`, id)
	return err
}

func (r *propertyRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `UPDATE properties SET deleted_at=NOW() WHERE id=$1`, id)
	return err
}

func (r *propertyRepo) ListAllProperties(ctx context.Context) ([]*models.Property, error) {
	rows, err := r.db.Query(ctx, baseSelectProperty()+" WHERE deleted_at IS NULL ORDER BY created_at")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.Property
	for rows.Next() {
		p, err := scanProperty(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func baseSelectProperty() string {
	return `
        SELECT
            id, manager_id, property_name,
            address, city, state, zip_code, time_zone,
            latitude, longitude,
            created_at, deleted_at
        FROM properties
    `
}

func scanProperty(row pgx.Row) (*models.Property, error) {
	var p models.Property
	err := row.Scan(
		&p.ID,
		&p.ManagerID,
		&p.PropertyName,
		&p.Address,
		&p.City,
		&p.State,
		&p.ZipCode,
		&p.TimeZone,
		&p.Latitude,
		&p.Longitude,
		&p.CreatedAt,
		&p.DeletedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &p, nil
}