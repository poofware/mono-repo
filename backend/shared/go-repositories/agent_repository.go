package repositories

import (
    "context"

    "github.com/google/uuid"
    "github.com/jackc/pgx/v4"
    "github.com/poofware/go-models"
)

type AgentRepository interface {
    Create(ctx context.Context, rep *models.Agent) error
    GetByID(ctx context.Context, id uuid.UUID) (*models.Agent, error)
    ListAll(ctx context.Context) ([]*models.Agent, error)
    ListByRegion(ctx context.Context, region string) ([]*models.Agent, error)
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
            id, name, email, phone_number, region, created_at, updated_at
        ) VALUES ($1,$2,$3,$4,$5, NOW(), NOW())
    `
    _, err := r.db.Exec(ctx, q,
        rep.ID, rep.Name, rep.Email, rep.PhoneNumber, rep.Region,
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

func (r *poofRepRepo) ListByRegion(ctx context.Context, region string) ([]*models.Agent, error) {
    q := baseSelectAgent() + " WHERE region=$1 ORDER BY created_at"
    rows, err := r.db.Query(ctx, q, region)
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

func baseSelectAgent() string {
    return `
        SELECT
            id, name, email, phone_number, region,
            created_at, updated_at
        FROM agents
    `
}

func scanAgent(row pgx.Row) (*models.Agent, error) {
    var rep models.Agent
    err := row.Scan(
        &rep.ID, &rep.Name, &rep.Email, &rep.PhoneNumber, &rep.Region,
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

