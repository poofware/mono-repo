// backend/shared/go-repositories/admin_audit_log_repository.go
// NEW FILE
package repositories

import (
	"context"
	"github.com/poofware/go-models"
)

type AdminAuditLogRepository interface {
	Create(ctx context.Context, logEntry *models.AdminAuditLog) error
}

type adminAuditLogRepo struct {
	db DB
}

func NewAdminAuditLogRepository(db DB) AdminAuditLogRepository {
	return &adminAuditLogRepo{db: db}
}

func (r *adminAuditLogRepo) Create(ctx context.Context, logEntry *models.AdminAuditLog) error {
	q := `
        INSERT INTO admin_audit_logs (
            id, admin_id, action, target_id, target_type, details, created_at
        ) VALUES ($1, $2, $3, $4, $5, $6, NOW())
    `
	_, err := r.db.Exec(ctx, q,
		logEntry.ID,
		logEntry.AdminID,
		logEntry.Action,
		logEntry.TargetID,
		logEntry.TargetType,
		logEntry.Details,
	)
	return err
}