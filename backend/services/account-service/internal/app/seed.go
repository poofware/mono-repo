package app

import (
	"fmt"

	"github.com/poofware/mono-repo/backend/shared/go-repositories"
	seeding "github.com/poofware/mono-repo/backend/shared/go-seeding"
)

// SeedAllAccounts seeds permanent shared accounts (e.g., reviewer accounts).
func SeedAllAccounts(
	workerRepo repositories.WorkerRepository,
	pmRepo repositories.PropertyManagerRepository,
	agentRepo repositories.AgentRepository,
) error {
	if err := seeding.SeedGooglePlayReviewerWorker(workerRepo); err != nil {
		return fmt.Errorf("seed google play reviewer account: %w", err)
	}
	if err := seeding.SeedDefaultAgents(agentRepo); err != nil {
		return fmt.Errorf("seed default agents: %w", err)
	}
	return nil
}

// SeedAllTestAccounts seeds default demo accounts for development and testing.
func SeedAllTestAccounts(
	workerRepo repositories.WorkerRepository,
	pmRepo repositories.PropertyManagerRepository,
	agentRepo repositories.AgentRepository,
) error {
	if err := seeding.SeedDefaultWorkers(workerRepo); err != nil {
		return fmt.Errorf("seed default workers: %w", err)
	}
	if err := seeding.SeedDefaultPropertyManager(pmRepo); err != nil {
		return fmt.Errorf("seed default property manager account: %w", err)
	}
	return nil
}
