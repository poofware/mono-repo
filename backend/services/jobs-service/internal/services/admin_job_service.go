// backend/services/jobs-service/internal/services/admin_job_service.go
// NEW FILE
package services

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/go-models"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
	"github.com/poofware/jobs-service/internal/dtos"
	internal_utils "github.com/poofware/jobs-service/internal/utils"
)

type AdminJobService struct {
	adminRepo    repositories.AdminRepository
	auditRepo    repositories.AdminAuditLogRepository
	jobDefRepo   repositories.JobDefinitionRepository
	instRepo     repositories.JobInstanceRepository
	pmRepo       repositories.PropertyManagerRepository
	propRepo     repositories.PropertyRepository
	jobService   *JobService // Re-use creation logic
}

func NewAdminJobService(
	adminRepo repositories.AdminRepository,
	auditRepo repositories.AdminAuditLogRepository,
	jobDefRepo repositories.JobDefinitionRepository,
	instRepo repositories.JobInstanceRepository,
	pmRepo repositories.PropertyManagerRepository,
	propRepo repositories.PropertyRepository,
	jobService *JobService,
) *AdminJobService {
	return &AdminJobService{
		adminRepo:    adminRepo,
		auditRepo:    auditRepo,
		jobDefRepo:   jobDefRepo,
		instRepo:     instRepo,
		pmRepo:       pmRepo,
		propRepo:     propRepo,
		jobService:   jobService,
	}
}

func (s *AdminJobService) authorizeAdmin(ctx context.Context, adminID uuid.UUID) error {
	admin, err := s.adminRepo.GetByID(ctx, adminID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return &utils.AppError{StatusCode: http.StatusForbidden, Code: utils.ErrCodeUnauthorized, Message: "Access denied"}
		}
		return &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to verify admin status", Err: err}
	}
	if admin == nil || admin.AccountStatus != models.AccountStatusActive {
		return &utils.AppError{StatusCode: http.StatusForbidden, Code: utils.ErrCodeUnauthorized, Message: "Admin account is not active"}
	}
	return nil
}


func (s *AdminJobService) logAudit(ctx context.Context, adminID, targetID uuid.UUID, action models.AuditAction, targetType models.AuditTargetType, details any) {
	logEntry := &models.AdminAuditLog{
		ID:         uuid.New(),
		AdminID:    adminID,
		Action:     action,
		TargetID:   targetID,
		TargetType: targetType,
	}

	if details != nil {
		marshalled, _ := json.Marshal(details)
		raw := json.RawMessage(marshalled)
		logEntry.Details = &raw
	}

	_ = s.auditRepo.Create(ctx, logEntry)
}


func (s *AdminJobService) AdminCreateJobDefinition(ctx context.Context, adminID uuid.UUID, req dtos.AdminCreateJobDefinitionRequest) (*models.JobDefinition, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}

	// The jobService.CreateJobDefinition handles all the complex validation.
	// We just need to adapt the request.
	pmUserStr := req.ManagerID.String()

	// Convert admin DTO to the standard DTO
	createReq := dtos.CreateJobDefinitionRequest{
		PropertyID:                 req.PropertyID,
		Title:                      req.Title,
		Description:                req.Description,
		AssignedBuildingIDs:        req.AssignedBuildingIDs,
		DumpsterIDs:                req.DumpsterIDs,
		Frequency:                  req.Frequency,
		Weekdays:                   req.Weekdays,
		IntervalWeeks:              req.IntervalWeeks,
		StartDate:                  req.StartDate,
		EndDate:                    req.EndDate,
		EarliestStartTime:          req.EarliestStartTime,
		LatestStartTime:            req.LatestStartTime,
		StartTimeHint:              req.StartTimeHint,
		SkipHolidays:               req.SkipHolidays,
		HolidayExceptions:          req.HolidayExceptions,
		Details:                    req.Details,
		Requirements:               req.Requirements,
		CompletionRules:            req.CompletionRules,
		SupportContact:             req.SupportContact,
		DailyPayEstimates:          req.DailyPayEstimates,
		GlobalBasePay:              req.GlobalBasePay,
		GlobalEstimatedTimeMinutes: req.GlobalEstimatedTimeMinutes,
	}

	defID, err := s.jobService.CreateJobDefinition(ctx, pmUserStr, createReq, "ACTIVE")
	if err != nil {
		if errors.Is(err, internal_utils.ErrMismatchedPayEstimatesFrequency) || errors.Is(err, internal_utils.ErrMissingPayEstimateInput) || errors.Is(err, internal_utils.ErrInvalidPayload) {
			return nil, &utils.AppError{StatusCode: http.StatusBadRequest, Code: utils.ErrCodeInvalidPayload, Message: err.Error()}
		}
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to create job definition", Err: err}
	}

	createdDef, err := s.jobDefRepo.GetByID(ctx, defID)
	if err != nil {
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to retrieve created job definition", Err: err}
	}

	s.logAudit(ctx, adminID, createdDef.ID, models.AuditCreate, models.TargetJobDefinition, createdDef)
	return createdDef, nil
}

func (s *AdminJobService) AdminUpdateJobDefinition(ctx context.Context, adminID uuid.UUID, req dtos.AdminUpdateJobDefinitionRequest) (*models.JobDefinition, error) {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return nil, err
	}

	var updatedDef *models.JobDefinition
	err := s.jobDefRepo.UpdateWithRetry(ctx, req.DefinitionID, func(j *models.JobDefinition) error {
		// Apply updates from the request DTO if the fields are not nil
		if req.Title != nil {
			j.Title = *req.Title
		}
		if req.Description != nil {
			j.Description = req.Description
		}
		if req.AssignedBuildingIDs != nil {
			j.AssignedBuildingIDs = *req.AssignedBuildingIDs
		}
		if req.DumpsterIDs != nil {
			j.DumpsterIDs = *req.DumpsterIDs
		}
		if req.Frequency != nil {
			j.Frequency = *req.Frequency
		}
		if req.Weekdays != nil {
			j.Weekdays = *req.Weekdays
		}
		if req.IntervalWeeks != nil {
			j.IntervalWeeks = req.IntervalWeeks
		}
		if req.StartDate != nil {
			j.StartDate = *req.StartDate
		}
		if req.EndDate != nil {
			j.EndDate = req.EndDate
		}
		if req.EarliestStartTime != nil {
			j.EarliestStartTime = *req.EarliestStartTime
		}
		if req.LatestStartTime != nil {
			j.LatestStartTime = *req.LatestStartTime
		}
		if req.StartTimeHint != nil {
			j.StartTimeHint = *req.StartTimeHint
		}
		if req.SkipHolidays != nil {
			j.SkipHolidays = *req.SkipHolidays
		}
		if req.HolidayExceptions != nil {
			j.HolidayExceptions = *req.HolidayExceptions
		}
		if req.Details != nil {
			j.Details = *req.Details
		}
		if req.Requirements != nil {
			j.Requirements = *req.Requirements
		}
		if req.CompletionRules != nil {
			j.CompletionRules = *req.CompletionRules
		}
		if req.SupportContact != nil {
			j.SupportContact = *req.SupportContact
		}

		if req.DailyPayEstimates != nil {
			estimates := make([]models.DailyPayEstimate, len(*req.DailyPayEstimates))
			for i, estReq := range *req.DailyPayEstimates {
				estimates[i] = models.DailyPayEstimate{
					DayOfWeek:                   time.Weekday(estReq.DayOfWeek),
					BasePay:                     estReq.BasePay,
					InitialBasePay:              estReq.BasePay,
					EstimatedTimeMinutes:        estReq.EstimatedTimeMinutes,
					InitialEstimatedTimeMinutes: estReq.EstimatedTimeMinutes,
				}
			}
			j.DailyPayEstimates = estimates
		}

		updatedDef = j
		return nil
	})

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, &utils.AppError{StatusCode: http.StatusNotFound, Code: utils.ErrCodeNotFound, Message: "Job definition not found"}
		}
		return nil, &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to update job definition", Err: err}
	}

	s.logAudit(ctx, adminID, updatedDef.ID, models.AuditUpdate, models.TargetJobDefinition, updatedDef)
	return updatedDef, nil
}

func (s *AdminJobService) AdminSoftDeleteJobDefinition(ctx context.Context, adminID, defID uuid.UUID) error {
	if err := s.authorizeAdmin(ctx, adminID); err != nil {
		return err
	}

	// This reuses the logic from the existing JobService, which is good.
	// It changes status to DELETED and cleans up future instances.
	err := s.jobService.SetDefinitionStatus(ctx, defID, string(models.JobStatusDeleted))
	if err != nil {
		if errors.Is(err, utils.ErrRowVersionConflict) {
			return &utils.AppError{StatusCode: http.StatusConflict, Code: utils.ErrCodeRowVersionConflict, Message: "Job definition was modified by another process", Err: err}
		}
		return &utils.AppError{StatusCode: http.StatusInternalServerError, Code: utils.ErrCodeInternal, Message: "Failed to soft-delete job definition", Err: err}
	}

	s.logAudit(ctx, adminID, defID, models.AuditDelete, models.TargetJobDefinition, nil)
	return nil
}