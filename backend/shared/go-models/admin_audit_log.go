// backend/shared/go-models/admin_audit_log.go
package models

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

type AuditAction string

const (
	AuditCreate AuditAction = "CREATE"
	AuditUpdate AuditAction = "UPDATE"
	AuditDelete AuditAction = "DELETE"
	AuditRead   AuditAction = "READ"
)

type AuditTargetType string

const (
	TargetPropertyManager AuditTargetType = "PROPERTY_MANAGER"
	TargetProperty        AuditTargetType = "PROPERTY"
	TargetBuilding        AuditTargetType = "BUILDING"
	TargetUnit            AuditTargetType = "UNIT"
	TargetDumpster        AuditTargetType = "DUMPSTER"
	TargetJobDefinition   AuditTargetType = "JOB_DEFINITION"
)

type AdminAuditLog struct {
	ID         uuid.UUID        `json:"id"`
	AdminID    uuid.UUID        `json:"admin_id"`
	Action     AuditAction      `json:"action"`
	TargetID   uuid.UUID        `json:"target_id"`
	TargetType AuditTargetType  `json:"target_type"`
	Details    *json.RawMessage `json:"details,omitempty"` // JSONB field for before/after states
	CreatedAt  time.Time        `json:"created_at"`
}