package services

import (
	"context"
	"time"

	"github.com/poofware/go-models"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
	"github.com/poofware/jobs-service/internal/config"
	"github.com/poofware/jobs-service/internal/constants"
	"github.com/sendgrid/sendgrid-go"
	"github.com/twilio/twilio-go"
)

type JobEscalationService struct {
	cfg            *config.Config
	jobDefRepo     repositories.JobDefinitionRepository
	jobInstRepo    repositories.JobInstanceRepository
	workerRepo     repositories.WorkerRepository
	propRepo       repositories.PropertyRepository
	repRepo        repositories.AgentRepository
	twilioClient   *twilio.RestClient
	sendgridClient *sendgrid.Client
	jobService     *JobService
}

func NewJobEscalationService(
	cfg *config.Config,
	defRepo repositories.JobDefinitionRepository,
	instRepo repositories.JobInstanceRepository,
	workerRepo repositories.WorkerRepository,
	propRepo repositories.PropertyRepository,
	repRepo repositories.AgentRepository,
	jobService *JobService,
) *JobEscalationService {
	twClient := twilio.NewRestClientWithParams(twilio.ClientParams{
		Username: cfg.TwilioAccountSID,
		Password: cfg.TwilioAuthToken,
	})
	sgClient := sendgrid.NewSendClient(cfg.SendGridAPIKey)

	return &JobEscalationService{
		cfg:            cfg,
		jobDefRepo:     defRepo,
		jobInstRepo:    instRepo,
		workerRepo:     workerRepo,
		propRepo:       propRepo,
		repRepo:        repRepo,
		twilioClient:   twClient,
		sendgridClient: sgClient,
		jobService:     jobService,
	}
}

// RunEscalationCheck scans jobs for surges, no-shows, etc., including forcibly canceling an open job at T-20.
func (s *JobEscalationService) RunEscalationCheck(ctx context.Context) error {
	utils.Logger.Debug("Running JCAS escalation checks...")

	nowUTC := time.Now().UTC()
	// Query a 48-hour window to ensure we catch all jobs for any property's "today".
	startRange := nowUTC.Add(-24 * time.Hour)
	endRange := nowUTC.Add(24 * time.Hour)

	statuses := []models.InstanceStatusType{
		models.InstanceStatusOpen,
		models.InstanceStatusAssigned,
	}
	openOrAssigned, err := s.jobInstRepo.ListInstancesByDateRange(ctx, nil, statuses, startRange, endRange)
	if err != nil {
		return err
	}

	for _, inst := range openOrAssigned {
		defn, err := s.jobDefRepo.GetByID(ctx, inst.DefinitionID)
		if err != nil || defn == nil {
			continue
		}

		prop, pErr := s.propRepo.GetByID(ctx, defn.PropertyID)
		if pErr != nil || prop == nil {
			continue
		}

		propLoc, locErr := time.LoadLocation(prop.TimeZone)
		if locErr != nil {
			propLoc = time.UTC // Fallback
		}
		
		lStart := time.Date(inst.ServiceDate.Year(), inst.ServiceDate.Month(), inst.ServiceDate.Day(), defn.LatestStartTime.Hour(), defn.LatestStartTime.Minute(), 0, 0, propLoc)

		// Possibly apply surge multipliers to any open job, comparing against the consistent UTC `now`.
		s.applySurgeIfNeeded(ctx, inst, defn, lStart, nowUTC)

		// If assigned but not yet started, check the "no-show" cutoff
		if inst.Status == models.InstanceStatusAssigned && inst.CheckInAt == nil {
			cutoff := lStart.Add(-constants.NoShowCutoffBeforeLatestStart)
			if nowUTC.After(cutoff) {
				s.forceReopenNoShow(ctx, inst)
			}
		}

		// If still open at T-20 => forcibly cancel job
		if inst.Status == models.InstanceStatusOpen {
			cutoff20 := lStart.Add(-constants.OnCallEscalationBeforeLatest)
			if nowUTC.After(cutoff20) && nowUTC.Before(lStart) {
				s.forceCancelAtDispatchTime(ctx, inst, defn)
			}
		}
	}
	return nil
}

// applySurgeIfNeeded checks if an open job is within a surge window and applies the
// corresponding pay multiplier. The windows are anchored to the job's no-show time.
func (s *JobEscalationService) applySurgeIfNeeded(
	ctx context.Context,
	inst *models.JobInstance,
	defn *models.JobDefinition,
	lStart, now time.Time,
) {
	if inst.Status != models.InstanceStatusOpen || lStart.IsZero() {
		return
	}

	noShowTime := lStart.Add(-constants.NoShowCutoffBeforeLatestStart)
	if now.After(noShowTime) {
		return // No surges after the no-show time has passed
	}

	timeLeft := noShowTime.Sub(now)
	var multiplier float64

	// Logic checks from highest surge (closest to no-show time) to lowest.
	// The first match is the one that applies.
	if timeLeft < constants.SurgeWindowStage4 { // T-30m -> no-show time
		multiplier = constants.SurgeMultiplierStage4
	} else if timeLeft < constants.SurgeWindowStage3 { // T-90m -> T-30m
		multiplier = constants.SurgeMultiplierStage3
	} else if timeLeft < constants.SurgeWindowStage2 { // T-3h -> T-90m
		multiplier = constants.SurgeMultiplierStage2
	} else if timeLeft < constants.SurgeWindowStage1 { // T-6h -> T-3h
		multiplier = constants.SurgeMultiplierStage1
	}

	if multiplier > 0 {
		s.jobService.ApplyManualSurge(ctx, inst, defn, multiplier)
	}
}

// forceReopenNoShow is invoked if assigned job not started by lStart - 30m
func (s *JobEscalationService) forceReopenNoShow(ctx context.Context, inst *models.JobInstance) {
	if inst.Status != models.InstanceStatusAssigned || inst.AssignedWorkerID == nil {
		return
	}
	err := s.workerRepo.AdjustWorkerScoreAtomic(ctx, *inst.AssignedWorkerID, constants.WorkerPenaltyNoShow, "NOSHOW")
	if err != nil {
		utils.Logger.WithError(err).Errorf("Failed to penalize no-show for worker=%s job=%s", inst.AssignedWorkerID, inst.ID)
	}
	_, err2 := s.jobService.ForceReopenNoShow(ctx, inst.ID, *inst.AssignedWorkerID)
	if err2 != nil {
		utils.Logger.WithError(err2).Error("forceReopenNoShow: Unassign failed")
	}
}

// forceCancelAtDispatchTime transitions the job from OPEN => CANCELED
// and notifies on-call staff that it was never claimed before T-20 cutoff.
func (s *JobEscalationService) forceCancelAtDispatchTime(
	ctx context.Context,
	inst *models.JobInstance,
	defn *models.JobDefinition,
) {
	rowVersion := inst.RowVersion
	canceled, err := s.jobInstRepo.UpdateStatusToCancelled(ctx, inst.ID, rowVersion)
	if err != nil {
		utils.Logger.WithError(err).Error("forceCancelAtDispatchTime: concurrency or DB error")
		return
	}
	if canceled == nil {
		utils.Logger.Warnf("forceCancelAtDispatchTime: no rows updated for job=%s", inst.ID)
		return
	}

	// There's no assigned worker => no penalty logic
	utils.Logger.Infof("forceCancelAtDispatchTime: forcibly canceled job=%s at T-20", inst.ID)

	// Notify on-call staff
	prop, pErr := s.propRepo.GetByID(ctx, defn.PropertyID)
	if pErr != nil || prop == nil {
		utils.Logger.WithError(pErr).Warn("forceCancelAtDispatchTime: property not found or nil")
	}
	msgBody := "Job was never claimed before T-20. It has been automatically canceled. No coverage found."
	s.notifyOnCallStaff(ctx, defn, "Open job auto-canceled at T-20", msgBody)
}

// notifyOnCallStaff uses the shared helpers.go method
func (s *JobEscalationService) notifyOnCallStaff(
	ctx context.Context,
	defn *models.JobDefinition,
	title string,
	msgBody string,
) {
	prop, err := s.propRepo.GetByID(ctx, defn.PropertyID)
	if err != nil || prop == nil {
		utils.Logger.WithError(err).Warn("notifyOnCallStaff: property not found or nil")
	}

	NotifyOnCallAgents(
		ctx,
		prop,
		defn.ID.String(),
		title,
		msgBody,
		s.repRepo,
		s.twilioClient,
		s.sendgridClient,
		s.cfg.LDFlag_TwilioFromPhone,
		s.cfg.LDFlag_SendgridFromEmail,
		s.cfg.OrganizationName,
		s.cfg.LDFlag_SendgridSandboxMode,
	)
}
