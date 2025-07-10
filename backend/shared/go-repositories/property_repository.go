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

type PropertyRepository interface {
	Create(ctx context.Context, p *models.Property) error

	GetByID(ctx context.Context, id uuid.UUID) (*models.Property, error)
	ListByManagerID(ctx context.Context, managerID uuid.UUID) ([]*models.Property, error)

	Update(ctx context.Context, p *models.Property) error
	UpdateIfVersion(ctx context.Context, p *models.Property, expected int64) (pgconn.CommandTag, error)
	UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.Property) error) error
	Delete(ctx context.Context, id uuid.UUID) error
	SoftDelete(ctx context.Context, id uuid.UUID) error

	ListAllProperties(ctx context.Context) ([]*models.Property, error)
}

/* ------------------------------------------------------------------
   Implementation
------------------------------------------------------------------ */

type propertyRepo struct {
	*BaseVersionedRepo[*models.Property]
	db DB
}

func NewPropertyRepository(db DB) PropertyRepository {
	r := &propertyRepo{db: db}
	selectStmt := baseSelectProperty() + " WHERE id=$1"
	r.BaseVersionedRepo = NewBaseRepo(db, selectStmt, scanProperty)
	return r
}

func (r *propertyRepo) Create(ctx context.Context, p *models.Property) error {
	_, err := r.db.Exec(ctx, `
        INSERT INTO properties (
            id, manager_id, property_name, address, city, state, zip_code, time_zone,
            latitude, longitude,
            created_at, updated_at, row_version
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10, NOW(), NOW(), 1)
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
	return r.BaseVersionedRepo.GetByID(ctx, id.String())
}

func (r *propertyRepo) ListByManagerID(ctx context.Context, managerID uuid.UUID) ([]*models.Property, error) {
	rows, err := r.db.Query(ctx, baseSelectProperty()+" WHERE manager_id=$1 ORDER BY created_at", managerID)
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
	_, err := r.update(ctx, p, false, 0)
	return err
}

func (r *propertyRepo) UpdateIfVersion(ctx context.Context, p *models.Property, expected int64) (pgconn.CommandTag, error) {
	return r.update(ctx, p, true, expected)
}

func (r *propertyRepo) UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.Property) error) error {
	return r.BaseVersionedRepo.UpdateWithRetry(ctx, id.String(), mutate, r.UpdateIfVersion)
}

func (r *propertyRepo) update(ctx context.Context, p *models.Property, check bool, expected int64) (pgconn.CommandTag, error) {
	sql := `
        UPDATE properties SET
            property_name=$1, address=$2, city=$3, state=$4, zip_code=$5,
            time_zone=$6, latitude=$7, longitude=$8, updated_at=NOW()
    `
	args := []any{
		p.PropertyName, p.Address, p.City, p.State, p.ZipCode,
		p.TimeZone, p.Latitude, p.Longitude,
	}
	if check {
		sql += `, row_version=row_version+1 WHERE id=$9 AND row_version=$10`
		args = append(args, p.ID, expected)
	} else {
		sql += ` WHERE id=$9`
		args = append(args, p.ID)
	}

	return r.db.Exec(ctx, sql, args...)
}

func (r *propertyRepo) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM properties WHERE id=$1`, id)
	return err
}

func (r *propertyRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	tag, err := r.db.Exec(ctx, `DELETE FROM properties WHERE id=$1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

func (r *propertyRepo) ListAllProperties(ctx context.Context) ([]*models.Property, error) {
	rows, err := r.db.Query(ctx, baseSelectProperty()+" ORDER BY created_at")
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
            created_at, updated_at, row_version
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
		&p.UpdatedAt,
		&p.RowVersion,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &p, nil
}