package repositories

import (
	"context"
	"fmt"

	"github.com/jackc/pgconn"
	"github.com/jackc/pgx/v4"
)

/*
EntityWithVersion:

* `comparable`  → lets us use `==` to compare two values of type T
* the three concurrency methods
*/
type EntityWithVersion interface {
	comparable
	GetID() string
	GetRowVersion() int64
	SetRowVersion(int64)
}

type UpdateIfVersionFunc[T EntityWithVersion] func(
	ctx context.Context,
	entity T,
	expectedVersion int64,
) (pgconn.CommandTag, error)

type GetByIDFunc[T EntityWithVersion] func(
	ctx context.Context,
	id string,
) (T, error)

/*
WithRetry runs a read‑mutate‑update loop with optimistic locking.
*/
func WithRetry[T EntityWithVersion](
	ctx context.Context,
	maxRetries int,
	id string,
	getByID GetByIDFunc[T],
	updateIfVersion UpdateIfVersionFunc[T],
	mutate func(T) error,
) error {
	for attempt := 0; attempt < maxRetries; attempt++ {
		current, err := getByID(ctx, id)
		if err != nil {
			return err
		}

		// zero value of T (nil for pointers)
		var zero T
		if current == zero {
			return pgx.ErrNoRows
		}

		oldVersion := current.GetRowVersion()

		if err := mutate(current); err != nil {
			return err
		}

		tag, err := updateIfVersion(ctx, current, oldVersion)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 1 {
			return nil
		}
		// someone else updated first – retry
	}
	return fmt.Errorf("too much contention updating %q", id)
}

