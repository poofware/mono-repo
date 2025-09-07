package repositories

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/mono-repo/backend/shared/go-models"
)

type AgentRepository interface {
	Create(ctx context.Context, rep *models.Agent) error
	GetByID(ctx context.Context, id uuid.UUID) (*models.Agent, error)
	ListAll(ctx context.Context) ([]*models.Agent, error)
	Update(ctx context.Context, rep *models.Agent) error
	SoftDelete(ctx context.Context, id uuid.UUID) error
}

type poofRepRepo struct {
	db DB
}

func NewAgentRepository(db DB) AgentRepository {
	return &poofRepRepo{db}
}

func (r *poofRepRepo) Create(ctx context.Context, rep *models.Agent) error {
	q := `
        INSERT INTO agents (
            id, name, email, phone_number, address, city, state, zip_code, latitude, longitude, created_at, updated_at
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10, NOW(), NOW())
    `
	_, err := r.db.Exec(ctx, q,
		rep.ID, rep.Name, rep.Email, rep.PhoneNumber,
		rep.Address, rep.City, rep.State, rep.ZipCode,
		rep.Latitude, rep.Longitude,
	)
	return err
}

func (r *poofRepRepo) GetByID(ctx context.Context, id uuid.UUID) (*models.Agent, error) {
	q := baseSelectAgent() + " WHERE id=$1"
	row := r.db.QueryRow(ctx, q, id)
	return scanAgent(row)
}

func (r *poofRepRepo) ListAll(ctx context.Context) ([]*models.Agent, error) {
	q := baseSelectAgent() + " ORDER BY created_at"
	rows, err := r.db.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.Agent
	for rows.Next() {
		rep, err := scanAgent(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, rep)
	}
	return out, rows.Err()
}

func (r *poofRepRepo) Update(ctx context.Context, rep *models.Agent) error {
	q := `
		UPDATE agents
		SET
			name=$2,
			email=$3,
			phone_number=$4,
			address=$5,
			city=$6,
			state=$7,
			zip_code=$8,
			latitude=$9,
			longitude=$10,
			updated_at=NOW()
		WHERE id=$1
	`
	_, err := r.db.Exec(ctx, q,
		rep.ID, rep.Name, rep.Email, rep.PhoneNumber,
		rep.Address, rep.City, rep.State, rep.ZipCode,
		rep.Latitude, rep.Longitude,
	)
	return err
}

func (r *poofRepRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	q := `UPDATE agents SET deleted_at=NOW(), updated_at=NOW() WHERE id=$1`
	_, err := r.db.Exec(ctx, q, id)
	return err
}

func baseSelectAgent() string {
	return `
        SELECT
            id, name, email, phone_number,
            address, city, state, zip_code,
            latitude, longitude,
            created_at, updated_at
        FROM agents
    `
}

func scanAgent(row pgx.Row) (*models.Agent, error) {
	var rep models.Agent
	err := row.Scan(
		&rep.ID, &rep.Name, &rep.Email, &rep.PhoneNumber,
		&rep.Address, &rep.City, &rep.State, &rep.ZipCode,
		&rep.Latitude, &rep.Longitude,
		&rep.CreatedAt, &rep.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &rep, nil
}
