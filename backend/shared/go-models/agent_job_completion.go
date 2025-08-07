package models

import (
	"github.com/google/uuid"
	"time"
)

// AgentJobCompletion represents a single-use token that allows an agent
// to mark a job instance as completed outside the normal app workflow.
// Tokens are short-lived and pruned after expiration.
type AgentJobCompletion struct {
	ID            uuid.UUID  `json:"id"`
	JobInstanceID uuid.UUID  `json:"job_instance_id"`
	AgentID       uuid.UUID  `json:"agent_id"`
	Token         string     `json:"token"`
	ExpiresAt     time.Time  `json:"expires_at"`
	CompletedAt   *time.Time `json:"completed_at,omitempty"`
}

func (a *AgentJobCompletion) GetID() string {
	return a.ID.String()
}
