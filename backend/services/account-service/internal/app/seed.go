package app

import (
	"fmt"

	"github.com/poofware/go-repositories"
	seeding "github.com/poofware/go-seeding"
)

// SeedAllAccounts seeds permanent shared accounts (e.g., reviewer accounts).
func SeedAllAccounts(
	workerRepo repositories.WorkerRepository,
	pmRepo repositories.PropertyManagerRepository,
) error {
	if err := seeding.SeedGooglePlayReviewerWorker(workerRepo); err != nil {
		return fmt.Errorf("seed google play reviewer account: %w", err)
	}
	return nil
}

// SeedAllTestAccounts seeds default demo accounts for development and testing.
func SeedAllTestAccounts(
	workerRepo repositories.WorkerRepository,
	pmRepo repositories.PropertyManagerRepository,
) error {
	if err := seeding.SeedDefaultWorkers(workerRepo); err != nil {
		return fmt.Errorf("seed default workers: %w", err)
	}
	if err := seeding.SeedDefaultPropertyManager(pmRepo); err != nil {
		return fmt.Errorf("seed default property manager account: %w", err)
	}
	return nil
}
