package repositories

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/jackc/pgtype"
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
	UpdateIfVersion(ctx context.Context, d *models.Dumpster, expected int64) (pgconn.CommandTag, error)
	UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.Dumpster) error) error
	Delete(ctx context.Context, id uuid.UUID) error
	DeleteByPropertyID(ctx context.Context, propertyID uuid.UUID) error
	SoftDelete(ctx context.Context, id uuid.UUID) error
}

/* ------------------------------------------------------------------
   Implementation
------------------------------------------------------------------ */

type dumpsterRepo struct {
	*BaseVersionedRepo[*models.Dumpster]
	db DB
}

func NewDumpsterRepository(db DB) DumpsterRepository {
	r := &dumpsterRepo{db: db}
	selectStmt := baseSelectDumpster() + " WHERE id=$1 AND deleted_at IS NULL"
	r.BaseVersionedRepo = NewBaseRepo(db, selectStmt, r.scanDumpster)
	return r
}

/* ---------- Create ---------- */

func (r *dumpsterRepo) Create(ctx context.Context, d *models.Dumpster) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO dumpsters (
			id, property_id, dumpster_number, latitude, longitude,
			created_at, updated_at, row_version
		) VALUES ($1,$2,$3,$4,$5, NOW(), NOW(), 1)
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
	return r.BaseVersionedRepo.GetByID(ctx, id.String())
}

func (r *dumpsterRepo) ListByPropertyID(ctx context.Context, propertyID uuid.UUID) ([]*models.Dumpster, error) {
	rows, err := r.db.Query(ctx, baseSelectDumpster()+" WHERE property_id=$1 AND deleted_at IS NULL ORDER BY dumpster_number", propertyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.Dumpster
	for rows.Next() {
		d, err := r.scanDumpster(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

/* ---------- Update / Delete ---------- */

func (r *dumpsterRepo) Update(ctx context.Context, d *models.Dumpster) error {
	_, err := r.update(ctx, d, false, 0)
	return err
}

func (r *dumpsterRepo) UpdateIfVersion(ctx context.Context, d *models.Dumpster, expected int64) (pgconn.CommandTag, error) {
	return r.update(ctx, d, true, expected)
}

func (r *dumpsterRepo) UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.Dumpster) error) error {
	return r.BaseVersionedRepo.UpdateWithRetry(ctx, id.String(), mutate, r.UpdateIfVersion)
}

func (r *dumpsterRepo) update(ctx context.Context, d *models.Dumpster, check bool, expected int64) (pgconn.CommandTag, error) {
	sql := `
		UPDATE dumpsters
		SET dumpster_number=$1, latitude=$2, longitude=$3, updated_at=NOW()
	`
	args := []any{d.DumpsterNumber, d.Latitude, d.Longitude}
	if check {
		sql += `, row_version=row_version+1 WHERE id=$4 AND row_version=$5`
		args = append(args, d.ID, expected)
	} else {
		sql += ` WHERE id=$4`
		args = append(args, d.ID)
	}
	return r.db.Exec(ctx, sql, args...)
}

func (r *dumpsterRepo) Delete(ctx context.Context, id uuid.UUID) error {
	return r.SoftDelete(ctx, id)
}

func (r *dumpsterRepo) DeleteByPropertyID(ctx context.Context, propertyID uuid.UUID) error {
	_, err := r.db.Exec(ctx, `UPDATE dumpsters SET deleted_at=NOW() WHERE property_id=$1`, propertyID)
	return err
}

func (r *dumpsterRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	tag, err := r.db.Exec(ctx, `UPDATE dumpsters SET deleted_at=NOW() WHERE id=$1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

/* ---------- internals ---------- */

func baseSelectDumpster() string {
	return `
		SELECT id,property_id,dumpster_number,latitude,longitude,
		created_at, updated_at, row_version, deleted_at
		FROM dumpsters`
}

func (r *dumpsterRepo) scanDumpster(row pgx.Row) (*models.Dumpster, error) {
	var d models.Dumpster
	var deletedAt pgtype.Timestamptz
	if err := row.Scan(
		&d.ID, &d.PropertyID, &d.DumpsterNumber, &d.Latitude, &d.Longitude,
		&d.CreatedAt, &d.UpdatedAt, &d.RowVersion, &deletedAt,
	); err != nil {
		return nil, err
	}

	if deletedAt.Status == pgtype.Present {
		d.DeletedAt = &deletedAt.Time
	} else {
		d.DeletedAt = nil
	}

	return &d, nil
}