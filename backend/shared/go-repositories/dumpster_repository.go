package repositories

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/mono-repo/backend/shared/go-models"
)

/* ------------------------------------------------------------------
   Public interface
------------------------------------------------------------------ */

type DumpsterRepository interface {
	Create(ctx context.Context, d *models.Dumpster) error
	CreateMany(ctx context.Context, list []models.Dumpster) error

	GetByID(ctx context.Context, id uuid.UUID) (*models.Dumpster, error)
	ListByPropertyID(ctx context.Context, propertyID uuid.UUID) ([]*models.Dumpster, error)

	Update(ctx context.Context, d *models.Dumpster) error
	Delete(ctx context.Context, id uuid.UUID) error
	DeleteByPropertyID(ctx context.Context, propertyID uuid.UUID) error
}

/* ------------------------------------------------------------------
   Implementation
------------------------------------------------------------------ */

type dumpsterRepo struct{ db DB }

func NewDumpsterRepository(db DB) DumpsterRepository { return &dumpsterRepo{db: db} }

/* ---------- Create ---------- */

func (r *dumpsterRepo) Create(ctx context.Context, d *models.Dumpster) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO dumpsters (
			id, property_id, dumpster_number, latitude, longitude
		) VALUES ($1,$2,$3,$4,$5)
	`, d.ID, d.PropertyID, d.DumpsterNumber, d.Latitude, d.Longitude)
	return err
}

func (r *dumpsterRepo) CreateMany(ctx context.Context, list []models.Dumpster) error {
	for _, d := range list {
		if err := r.Create(ctx, &d); err != nil {
			return err
		}
	}
	return nil
}

/* ---------- Reads ---------- */

func (r *dumpsterRepo) GetByID(ctx context.Context, id uuid.UUID) (*models.Dumpster, error) {
	row := r.db.QueryRow(ctx, baseSelectDumpster()+" WHERE id=$1", id)
	return scanDumpster(row)
}

func (r *dumpsterRepo) ListByPropertyID(ctx context.Context, propertyID uuid.UUID) ([]*models.Dumpster, error) {
	rows, err := r.db.Query(ctx, baseSelectDumpster()+" WHERE property_id=$1 ORDER BY dumpster_number", propertyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.Dumpster
	for rows.Next() {
		d, err := scanDumpster(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

/* ---------- Update / Delete ---------- */

func (r *dumpsterRepo) Update(ctx context.Context, d *models.Dumpster) error {
	_, err := r.db.Exec(ctx, `
		UPDATE dumpsters
		SET dumpster_number=$1, latitude=$2, longitude=$3
		WHERE id=$4
	`, d.DumpsterNumber, d.Latitude, d.Longitude, d.ID)
	return err
}

func (r *dumpsterRepo) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM dumpsters WHERE id=$1`, id)
	return err
}

func (r *dumpsterRepo) DeleteByPropertyID(ctx context.Context, propertyID uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM dumpsters WHERE property_id=$1`, propertyID)
	return err
}

/* ---------- internals ---------- */

func baseSelectDumpster() string {
	return `
		SELECT id,property_id,dumpster_number,latitude,longitude
		FROM dumpsters`
}

func scanDumpster(row pgx.Row) (*models.Dumpster, error) {
	var d models.Dumpster
	if err := row.Scan(
		&d.ID, &d.PropertyID, &d.DumpsterNumber, &d.Latitude, &d.Longitude,
	); err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &d, nil
}

