// verification_cleanup_service.go
package services

import (
    "context"

    "github.com/poofware/go-utils"
    "github.com/poofware/go-repositories"
)

// VerificationCleanupService handles purging old/expired PM/Worker email and SMS codes.
type VerificationCleanupService interface {
    // CleanupDaily deletes expired verification codes for PM and Worker.
    CleanupDaily(ctx context.Context) error
}

// verificationCleanupService is the concrete struct implementing VerificationCleanupService.
type verificationCleanupService struct {
    pmEmailRepo     repositories.PMEmailVerificationRepository
    pmSMSRepo       repositories.PMSMSVerificationRepository
    workerEmailRepo repositories.WorkerEmailVerificationRepository
    workerSMSRepo   repositories.WorkerSMSVerificationRepository
}

// NewVerificationCleanupService constructs a new instance of verificationCleanupService.
func NewVerificationCleanupService(
    pmEmailRepo repositories.PMEmailVerificationRepository,
    pmSMSRepo repositories.PMSMSVerificationRepository,
    workerEmailRepo repositories.WorkerEmailVerificationRepository,
    workerSMSRepo repositories.WorkerSMSVerificationRepository,
) VerificationCleanupService {
    return &verificationCleanupService{
        pmEmailRepo:     pmEmailRepo,
        pmSMSRepo:       pmSMSRepo,
        workerEmailRepo: workerEmailRepo,
        workerSMSRepo:   workerSMSRepo,
    }
}

// CleanupDaily deletes expired verification codes and logs any errors encountered.
func (s *verificationCleanupService) CleanupDaily(ctx context.Context) error {
    logger := utils.Logger

    if err := s.pmEmailRepo.CleanupExpired(ctx); err != nil {
        logger.WithError(err).Error("Failed to cleanup pm_email_verification_codes")
        return err
    }
    if err := s.pmSMSRepo.CleanupExpired(ctx); err != nil {
        logger.WithError(err).Error("Failed to cleanup pm_sms_verification_codes")
        return err
    }
    if err := s.workerEmailRepo.CleanupExpired(ctx); err != nil {
        logger.WithError(err).Error("Failed to cleanup worker_email_verification_codes")
        return err
    }
    if err := s.workerSMSRepo.CleanupExpired(ctx); err != nil {
        logger.WithError(err).Error("Failed to cleanup worker_sms_verification_codes")
        return err
    }

    logger.Info("Daily verification-codes cleanup completed successfully.")
    return nil
}

