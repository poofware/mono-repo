package repositories

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/jackc/pgtype"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/mono-repo/backend/shared/go-models"
)

type FloorRepository interface {
	Create(ctx context.Context, f *models.Floor) error
	GetByID(ctx context.Context, id uuid.UUID) (*models.Floor, error)
	GetByBuildingAndNumber(ctx context.Context, buildingID uuid.UUID, number int16) (*models.Floor, error)
	ListByBuildingID(ctx context.Context, buildingID uuid.UUID) ([]*models.Floor, error)
	Update(ctx context.Context, f *models.Floor) error
	UpdateIfVersion(ctx context.Context, f *models.Floor, expected int64) (pgconn.CommandTag, error)
	UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.Floor) error) error
	SoftDelete(ctx context.Context, id uuid.UUID) error
}

type floorRepo struct {
	*BaseVersionedRepo[*models.Floor]
	db DB
}

func NewFloorRepository(db DB) FloorRepository {
	r := &floorRepo{db: db}
	selectStmt := baseSelectFloor() + " WHERE id=$1 AND deleted_at IS NULL"
	r.BaseVersionedRepo = NewBaseRepo(db, selectStmt, r.scanFloor)
	return r
}

func (r *floorRepo) Create(ctx context.Context, f *models.Floor) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO floors (
			id, property_id, building_id, number, created_at, updated_at, row_version
		) VALUES ($1,$2,$3,$4, NOW(), NOW(), 1)
	`, f.ID, f.PropertyID, f.BuildingID, f.Number)
	return err
}

func (r *floorRepo) GetByID(ctx context.Context, id uuid.UUID) (*models.Floor, error) {
	return r.BaseVersionedRepo.GetByID(ctx, id.String())
}

func (r *floorRepo) GetByBuildingAndNumber(ctx context.Context, buildingID uuid.UUID, number int16) (*models.Floor, error) {
	row := r.db.QueryRow(ctx, baseSelectFloor()+" WHERE building_id=$1 AND number=$2 AND deleted_at IS NULL", buildingID, number)
	return r.scanFloor(row)
}

func (r *floorRepo) ListByBuildingID(ctx context.Context, buildingID uuid.UUID) ([]*models.Floor, error) {
	rows, err := r.db.Query(ctx, baseSelectFloor()+" WHERE building_id=$1 AND deleted_at IS NULL ORDER BY number", buildingID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*models.Floor
	for rows.Next() {
		f, err := r.scanFloor(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, f)
	}
	return out, rows.Err()
}

func (r *floorRepo) Update(ctx context.Context, f *models.Floor) error {
	_, err := r.update(ctx, f, false, 0)
	return err
}

func (r *floorRepo) UpdateIfVersion(ctx context.Context, f *models.Floor, expected int64) (pgconn.CommandTag, error) {
	return r.update(ctx, f, true, expected)
}

func (r *floorRepo) UpdateWithRetry(ctx context.Context, id uuid.UUID, mutate func(*models.Floor) error) error {
	return r.BaseVersionedRepo.UpdateWithRetry(ctx, id.String(), mutate, r.UpdateIfVersion)
}

func (r *floorRepo) update(ctx context.Context, f *models.Floor, check bool, expected int64) (pgconn.CommandTag, error) {
	sql := `
		UPDATE floors SET number=$1, updated_at=NOW()
	`
	args := []any{f.Number}
	if check {
		sql += `, row_version=row_version+1 WHERE id=$2 AND row_version=$3`
		args = append(args, f.ID, expected)
	} else {
		sql += ` WHERE id=$2`
		args = append(args, f.ID)
	}
	return r.db.Exec(ctx, sql, args...)
}

func (r *floorRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	tag, err := r.db.Exec(ctx, `UPDATE floors SET deleted_at=NOW() WHERE id=$1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

func baseSelectFloor() string {
	return `
		SELECT id, property_id, building_id, number, created_at, updated_at, row_version, deleted_at
		FROM floors`
}

func (r *floorRepo) scanFloor(row pgx.Row) (*models.Floor, error) {
	var f models.Floor
	var deletedAt pgtype.Timestamptz
	if err := row.Scan(&f.ID, &f.PropertyID, &f.BuildingID, &f.Number, &f.CreatedAt, &f.UpdatedAt, &f.RowVersion, &deletedAt); err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	if deletedAt.Status == pgtype.Present {
		f.DeletedAt = &deletedAt.Time
	} else {
		f.DeletedAt = nil
	}
	return &f, nil
}
