// backend/shared/go-repositories/admin_audit_log_repository.go
// NEW FILE
package repositories

import (
	"context"

	"github.com/google/uuid"
	"github.com/poofware/go-models"
)

type AdminAuditLogRepository interface {
	Create(ctx context.Context, logEntry *models.AdminAuditLog) error
	ListByTargetID(ctx context.Context, targetID uuid.UUID) ([]*models.AdminAuditLog, error)
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

func (r *adminAuditLogRepo) ListByTargetID(ctx context.Context, targetID uuid.UUID) ([]*models.AdminAuditLog, error) {
	q := `
		SELECT id, admin_id, action, target_id, target_type, details, created_at
		FROM admin_audit_logs
		WHERE target_id = $1
		ORDER BY created_at ASC
	`
	rows, err := r.db.Query(ctx, q, targetID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var logs []*models.AdminAuditLog
	for rows.Next() {
		var log models.AdminAuditLog
		if err := rows.Scan(&log.ID, &log.AdminID, &log.Action, &log.TargetID, &log.TargetType, &log.Details, &log.CreatedAt); err != nil {
			return nil, err
		}
		logs = append(logs, &log)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}
	return logs, nil
}