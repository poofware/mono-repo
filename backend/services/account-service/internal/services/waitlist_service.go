package services

import (
	"context"
	"errors"

	"github.com/launchdarkly/go-sdk-common/v3/ldcontext"
	ld "github.com/launchdarkly/go-server-sdk/v7"

	"github.com/poofware/mono-repo/backend/services/account-service/internal/config"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
)

type WaitlistService struct {
	cfg  *config.Config
	repo repositories.WorkerRepository
}

func NewWaitlistService(cfg *config.Config, repo repositories.WorkerRepository) *WaitlistService {
	return &WaitlistService{cfg: cfg, repo: repo}
}

func (s *WaitlistService) ProcessWaitlist(ctx context.Context) error {
	ldClient, err := ld.MakeClient(s.cfg.LDSDKKey, config.LDConnectionTimeout)
	if err != nil {
		return err
	}
	if !ldClient.Initialized() {
		ldClient.Close()
		return errors.New("launchdarkly client failed to initialize")
	}
	ldCtx := ldcontext.NewWithKind(ldcontext.Kind(config.LDServerContextKind), config.LDServerContextKey)
	capacity, err := ldClient.IntVariation("worker_capacity_limit", ldCtx, 0)
	ldClient.Close()
	if err != nil {
		return err
	}

	activeCount, err := s.repo.GetActiveWorkerCount(ctx)
	if err != nil {
		return err
	}
	slots := int(capacity) - activeCount
	if slots <= 0 {
		return nil
	}

	workers, err := s.repo.ListOldestWaitlistedWorkers(ctx, slots, models.WaitlistReasonCapacity)
	if err != nil {
		return err
	}
	for _, w := range workers {
		w.OnWaitlist = false
		w.WaitlistReason = nil
		if err := s.repo.Update(ctx, w); err != nil {
			return err
		}
	}
	return nil
}
