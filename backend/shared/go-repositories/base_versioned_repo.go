package repositories

import (
	"context"

	"github.com/jackc/pgx/v4"
)

/*
BaseVersionedRepo holds the DB connection, a SELECT‑by‑ID statement,
and a scanner for a single entity type T.  It gives you:

	• GetByID(ctx, id string) (T, error)
	• UpdateWithRetry(ctx, id, mutate, updateIfVersion)
*/
type BaseVersionedRepo[T EntityWithVersion] struct {
	db         DB
	selectByID string
	scan       func(row pgx.Row) (T, error)
}

// NewBaseRepo is called by concrete repositories.
func NewBaseRepo[T EntityWithVersion](
	db DB,
	selectByID string,
	scan func(pgx.Row) (T, error),
) *BaseVersionedRepo[T] {
	return &BaseVersionedRepo[T]{db: db, selectByID: selectByID, scan: scan}
}

// -------------------------- public helpers --------------------------

func (b *BaseVersionedRepo[T]) GetByID(ctx context.Context, id string) (T, error) {
	row := b.db.QueryRow(ctx, b.selectByID, id)
	return b.scan(row)
}

// UpdateWithRetry wires the generic optimistic‑locking loop.
func (b *BaseVersionedRepo[T]) UpdateWithRetry(
	ctx context.Context,
	id string,
	mutate func(T) error,
	updateIfVersion UpdateIfVersionFunc[T],
) error {
	return WithRetry(
		ctx,
		3, // maxRetries
		id,
		b.GetByID,
		updateIfVersion,
		mutate,
	)
}

