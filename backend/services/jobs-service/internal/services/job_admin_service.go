package services

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/constants"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/dtos"
	internal_utils "github.com/poofware/mono-repo/backend/services/jobs-service/internal/utils"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

func (s *JobService) ForceReopenNoShow(
	ctx context.Context,
	instanceID uuid.UUID,
	oldWorkerID uuid.UUID,
) (*models.JobInstance, error) {
	// unchanged ...
	inst, err := s.instRepo.GetByID(ctx, instanceID)
	if err != nil {
		return nil, err
	}
	if inst == nil {
		return nil, nil
	}
	if inst.Status != models.InstanceStatusAssigned {
		return nil, nil
	}

	expectedVersion := inst.RowVersion
	newCount := inst.AssignUnassignCount + 1
	flagged := inst.FlaggedForReview
	if newCount > constants.MaxAssignUnassignCountForFlag {
		flagged = true
	}
	reopened, err := s.instRepo.UnassignInstanceAtomic(ctx, instanceID, expectedVersion, newCount, flagged)
	if err != nil {
		return nil, err
	}
	if reopened == nil {
		return nil, nil
	}
	_ = s.instRepo.AddExcludedWorker(ctx, instanceID, oldWorkerID)

	defn, err := s.defRepo.GetByID(ctx, reopened.DefinitionID)
	if err != nil || defn == nil {
		return reopened, nil
	}

	return reopened, nil
}

// ApplyManualSurge ...
func (s *JobService) ApplyManualSurge(
	ctx context.Context,
	inst *models.JobInstance,
	defn *models.JobDefinition,
	multiplier float64,
) {
	if inst.Status != models.InstanceStatusOpen {
		return
	}

	dayOfWeek := inst.ServiceDate.Weekday()
	dailyEstimate := defn.GetDailyEstimate(dayOfWeek)
	if dailyEstimate == nil {
		utils.Logger.Warnf("ApplyManualSurge: No daily estimate found for job_definition_id=%s, day_of_week=%s", defn.ID, dayOfWeek)
		return
	}

	basePay := dailyEstimate.BasePay
	if basePay <= 0 {
		return
	}
	if multiplier > constants.SurgeMultiplierStage4 {
		multiplier = constants.SurgeMultiplierStage4
	}
	newPay := basePay * multiplier
	if newPay <= inst.EffectivePay {
		return
	}

	latest, _ := s.instRepo.GetByID(ctx, inst.ID)
	if latest == nil || latest.Status != models.InstanceStatusOpen {
		return
	}
	_ = s.instRepo.UpdateEffectivePayAtomic(ctx, latest.ID, latest.RowVersion, newPay)
}

// SetDefinitionStatus ...
func (s *JobService) SetDefinitionStatus(ctx context.Context, defID uuid.UUID, newStatus string) error {
	// unchanged ...
	var st models.JobStatusType
	switch strings.ToUpper(newStatus) {
	case string(models.JobStatusActive):
		st = models.JobStatusActive
	case string(models.JobStatusPaused):
		st = models.JobStatusPaused
	case string(models.JobStatusArchived):
		st = models.JobStatusArchived
	case string(models.JobStatusDeleted):
		st = models.JobStatusDeleted
	default:
		return fmt.Errorf("unknown status: %s", newStatus)
	}

	defn, err := s.defRepo.GetByID(ctx, defID)
	if err != nil {
		return err
	}
	if defn == nil {
		return fmt.Errorf("job definition not found, id=%s", defID)
	}

	tag, err := s.defRepo.ChangeStatus(ctx, defn.ID, st, defn.RowVersion)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return utils.ErrRowVersionConflict
	}

	if st == models.JobStatusPaused || st == models.JobStatusArchived || st == models.JobStatusDeleted {
		today := time.Now().UTC()
		err = s.instRepo.DeleteFutureOpenInstances(ctx, defn.ID, DateOnly(today))
		if err != nil {
			return err
		}
	}
	return nil
}

// CreateJobDefinition ...
func (s *JobService) CreateJobDefinition(
	ctx context.Context,
	pmUserID string,
	req dtos.CreateJobDefinitionRequest,
	status string,
) (uuid.UUID, error) {
	pmID, err := uuid.Parse(pmUserID)
	if err != nil {
		return uuid.Nil, fmt.Errorf("invalid PM user ID: %w", err)
	}
	prop, err := s.propRepo.GetByID(ctx, req.PropertyID)
	if err != nil || prop == nil {
		return uuid.Nil, fmt.Errorf("property_id not found: %s", req.PropertyID)
	}

	// --- Time Window Validations ---

	// Rule: EarliestStartTime and LatestStartTime must be on the same conceptual day (no midnight crossing)
	// This implies LatestStartTime must be strictly after EarliestStartTime.
	if !req.LatestStartTime.After(req.EarliestStartTime) {
		return uuid.Nil, fmt.Errorf("%w: latest_start_time (%v) must be after earliest_start_time (%v) and on the same day", internal_utils.ErrInvalidPayload, req.LatestStartTime.Format("15:04:05"), req.EarliestStartTime.Format("15:04:05"))
	}
	// Rule: Duration must be at least 90 minutes.
	if req.LatestStartTime.Sub(req.EarliestStartTime) < time.Duration(constants.MinJobDefinitionStartWindowMinutes)*time.Minute {
		return uuid.Nil, fmt.Errorf("%w: job duration (latest_start_time - earliest_start_time) must be at least %d minutes", internal_utils.ErrInvalidPayload, constants.MinJobDefinitionStartWindowMinutes)
	}

	var effectiveStartTimeHint time.Time
	if req.StartTimeHint != nil {
		// Rule: StartTimeHint validation
		// Hint must be on or after earliest_start_time
		if req.StartTimeHint.Before(req.EarliestStartTime) {
			return uuid.Nil, fmt.Errorf("%w: start_time_hint (%v) must be on or after earliest_start_time (%v)", internal_utils.ErrInvalidPayload, req.StartTimeHint.Format("15:04:05"), req.EarliestStartTime.Format("15:04:05"))
		}
		// Hint must be at least 50 minutes before latest_start_time
		cutoffForHint := req.LatestStartTime.Add(-time.Duration(constants.MinTimeBeforeLatestStartForHintMinutes) * time.Minute)
		if req.StartTimeHint.After(cutoffForHint) {
			return uuid.Nil, fmt.Errorf("%w: start_time_hint (%v) must be at least %d minutes before latest_start_time (latest: %v, hint cutoff: %v)", internal_utils.ErrInvalidPayload, req.StartTimeHint.Format("15:04:05"), constants.MinTimeBeforeLatestStartForHintMinutes, req.LatestStartTime.Format("15:04:05"), cutoffForHint.Format("15:04:05"))
		}
		effectiveStartTimeHint = *req.StartTimeHint
	} else {
		// If no hint is provided, we auto-calculate the midpoint. This midpoint must
		// satisfy the DB check constraint `hint <= latest_start_time - 50m`.
		// A midpoint is valid only if the total duration is at least 100 minutes.
		minDurationForMidpoint := 2 * time.Duration(constants.MinTimeBeforeLatestStartForHintMinutes) * time.Minute // 100 minutes
		if req.LatestStartTime.Sub(req.EarliestStartTime) < minDurationForMidpoint {
			return uuid.Nil, fmt.Errorf("%w: job window must be at least %d minutes when start_time_hint is not provided, to allow for automatic calculation", internal_utils.ErrInvalidPayload, int(minDurationForMidpoint.Minutes()))
		}

		duration := req.LatestStartTime.Sub(req.EarliestStartTime)
		effectiveStartTimeHint = req.EarliestStartTime.Add(duration / 2)
	}

	// --- End Time Window Validations ---

	var dailyEstimatesToUse []models.DailyPayEstimate

	if len(req.DailyPayEstimates) > 0 {
		if errVal := validateDailyPayEstimates(req.Frequency, req.Weekdays, req.DailyPayEstimates); errVal != nil {
			return uuid.Nil, fmt.Errorf("%w: %v", internal_utils.ErrMismatchedPayEstimatesFrequency, errVal)
		}
		dailyEstimatesToUse = make([]models.DailyPayEstimate, len(req.DailyPayEstimates))
		for i, dpeReq := range req.DailyPayEstimates {
			dailyEstimatesToUse[i] = models.DailyPayEstimate{
				DayOfWeek:                   time.Weekday(dpeReq.DayOfWeek),
				BasePay:                     dpeReq.BasePay,
				InitialBasePay:              dpeReq.BasePay,
				EstimatedTimeMinutes:        dpeReq.EstimatedTimeMinutes,
				InitialEstimatedTimeMinutes: dpeReq.EstimatedTimeMinutes,
			}
		}
	} else if req.GlobalBasePay != nil && req.GlobalEstimatedTimeMinutes != nil {
		if *req.GlobalBasePay <= 0 {
			return uuid.Nil, fmt.Errorf("%w: global_base_pay must be positive", internal_utils.ErrInvalidPayload)
		}
		if *req.GlobalEstimatedTimeMinutes <= 0 {
			return uuid.Nil, fmt.Errorf("%w: global_estimated_time_minutes must be positive", internal_utils.ErrInvalidPayload)
		}

		dailyEstimatesToUse = make([]models.DailyPayEstimate, 7)
		for i := range 7 {
			dailyEstimatesToUse[i] = models.DailyPayEstimate{
				DayOfWeek:                   time.Weekday(i),
				BasePay:                     *req.GlobalBasePay,
				InitialBasePay:              *req.GlobalBasePay,
				EstimatedTimeMinutes:        *req.GlobalEstimatedTimeMinutes,
				InitialEstimatedTimeMinutes: *req.GlobalEstimatedTimeMinutes,
			}
		}
		if req.Frequency == models.JobFreqCustom && len(req.Weekdays) == 0 {
			return uuid.Nil, fmt.Errorf("%w: weekdays must be specified for CUSTOM frequency even when using global pay/time estimates", internal_utils.ErrMismatchedPayEstimatesFrequency)
		}
	} else {
		return uuid.Nil, internal_utils.ErrMissingPayEstimateInput
	}

	floorSet := make(map[int16]struct{})
	totalUnits := 0
	for _, grp := range req.AssignedUnitsByBuilding {
		for _, f := range grp.Floors {
			floorSet[f] = struct{}{}
		}
		totalUnits += len(grp.UnitIDs)
	}
	floors := make([]int16, 0, len(floorSet))
	for f := range floorSet {
		floors = append(floors, f)
	}
	slices.Sort(floors)

	newDef := &models.JobDefinition{
		ID:                      uuid.New(),
		ManagerID:               pmID,
		PropertyID:              req.PropertyID,
		Title:                   req.Title,
		Description:             req.Description,
		AssignedUnitsByBuilding: req.AssignedUnitsByBuilding,
		Floors:                  floors,
		TotalUnits:              totalUnits,
		DumpsterIDs:             req.DumpsterIDs,
		Status:                  models.JobStatusType(strings.ToUpper(status)),
		Frequency:               req.Frequency,
		Weekdays:                req.Weekdays,
		IntervalWeeks:           req.IntervalWeeks,
		StartDate:               req.StartDate,
		EndDate:                 req.EndDate,
		EarliestStartTime:       req.EarliestStartTime,
		LatestStartTime:         req.LatestStartTime,
		StartTimeHint:           effectiveStartTimeHint,
		SkipHolidays:            req.SkipHolidays,
		HolidayExceptions:       req.HolidayExceptions,
		DailyPayEstimates:       dailyEstimatesToUse,
	}

	if req.Details != nil {
		newDef.Details = *req.Details
	}
	if req.Requirements != nil {
		newDef.Requirements = *req.Requirements
	}
	if req.CompletionRules != nil {
		newDef.CompletionRules = *req.CompletionRules
	}
	if req.SupportContact != nil {
		newDef.SupportContact = *req.SupportContact
	}

	err = s.defRepo.Create(ctx, newDef)
	if err != nil {
		if strings.Contains(err.Error(), "job_daily_pay_estimates_ck") {
			return uuid.Nil, fmt.Errorf("%w: database validation failed for daily_pay_estimates structure - %v", internal_utils.ErrMismatchedPayEstimatesFrequency, err)
		}
		// Check for job_time_window_ck or job_start_time_hint_ck
		if strings.Contains(err.Error(), "job_time_window_ck") || strings.Contains(err.Error(), "job_start_time_hint_ck") {
			// These should ideally be caught by service-level validation now,
			// but if they reach here, it indicates a potential logic mismatch or direct DB insertion attempt
			// that the service layer didn't vet.
			return uuid.Nil, fmt.Errorf("%w: database time constraint violation - %v", internal_utils.ErrInvalidPayload, err)
		}
		return uuid.Nil, err
	}

	if newDef.Status == models.JobStatusActive {
		loc := loadPropertyLocation(prop.TimeZone)
		nowLocal := time.Now().In(loc)
		baseDate := dateOnlyInLocation(nowLocal, loc)
		for i := range constants.DaysToSeedAhead {
			day := baseDate.AddDate(0, 0, i)
			if shouldCreateOnDate(newDef, day) {
				// NEW: Prevent creation if the no-show cutoff for today's job is already in the past.
				if time.Time.Equal(day, baseDate) {
					latestStartForToday := time.Date(day.Year(), day.Month(), day.Day(), newDef.LatestStartTime.Hour(), newDef.LatestStartTime.Minute(), 0, 0, loc)
					noShowCutoffForToday := latestStartForToday.Add(-constants.NoShowCutoffBeforeLatestStart)
					if nowLocal.After(noShowCutoffForToday) {
						utils.Logger.Infof("Skipping creation of job instance for today (def: %s) because its no-show cutoff time (%v) is in the past.", newDef.ID, noShowCutoffForToday)
						continue // Skip creating today's instance as it's already expired.
					}
				}

				dailyEstimate := newDef.GetDailyEstimate(day.Weekday())
				var initialPay float64
				if dailyEstimate != nil {
					initialPay = dailyEstimate.BasePay
				}

				inst := &models.JobInstance{
					ID:           uuid.New(),
					DefinitionID: newDef.ID,
					ServiceDate:  day,
					Status:       models.InstanceStatusOpen,
					EffectivePay: initialPay,
				}
				_ = s.instRepo.CreateIfNotExists(ctx, inst)
			}
		}
	}

	return newDef.ID, nil
}

// CancelJobInstance allows a worker to cancel a job that is already IN_PROGRESS.
// This is a serious action and may result in penalties and exclusion.
func (s *JobService) CancelJobInstance(
	ctx context.Context,
	workerID string,
	instanceID uuid.UUID,
) (*dtos.JobInstanceDTO, error) {
	inst, err := s.instRepo.GetByID(ctx, instanceID)
	if err != nil {
		return nil, err
	}
	if inst == nil {
		return nil, nil
	}

	if inst.AssignedWorkerID == nil || inst.AssignedWorkerID.String() != workerID {
		return nil, internal_utils.ErrNotAssignedWorker
	}
	if inst.Status != models.InstanceStatusInProgress {
		return nil, internal_utils.ErrWrongStatus
	}

	defn, dErr := s.defRepo.GetByID(ctx, inst.DefinitionID)
	if dErr != nil || defn == nil {
		return nil, fmt.Errorf("job definition not found")
	}
	prop, propErr := s.propRepo.GetByID(ctx, defn.PropertyID)
	if propErr != nil || prop == nil {
		return nil, fmt.Errorf("property not found")
	}

	propLoc := loadPropertyLocation(prop.TimeZone)
	serviceDate := inst.ServiceDate
	eStart := time.Date(serviceDate.Year(), serviceDate.Month(), serviceDate.Day(), defn.EarliestStartTime.Hour(), defn.EarliestStartTime.Minute(), 0, 0, propLoc)
	lStart := time.Date(serviceDate.Year(), serviceDate.Month(), serviceDate.Day(), defn.LatestStartTime.Hour(), defn.LatestStartTime.Minute(), 0, 0, propLoc)
	noShowTime := lStart.Add(-constants.NoShowCutoffBeforeLatestStart)
	now := time.Now().UTC()
	wUUID := uuid.MustParse(workerID)

	if now.Before(lStart) {
		penaltyDelta, excludeWorker := CalculatePenaltyForUnassign(now, eStart, noShowTime)
		expectedVersion := inst.RowVersion
		assignCount := inst.AssignUnassignCount + 1
		flagged := inst.FlaggedForReview || (assignCount > constants.MaxAssignUnassignCountForFlag)

		rev, err2 := s.instRepo.RevertInProgressToOpenAtomic(ctx, instanceID, expectedVersion, assignCount, flagged)
		if err2 != nil {
			if strings.Contains(err2.Error(), utils.ErrRowVersionConflict.Error()) {
				latest, _ := s.instRepo.GetByID(ctx, instanceID)
				if latest != nil {
					return nil, internal_utils.NewRowVersionConflictError(latest)
				}
			}
			return nil, err2
		}
		if rev == nil {
			return nil, utils.ErrNoRowsUpdated
		}

		if excludeWorker {
			_ = s.instRepo.AddExcludedWorker(ctx, rev.ID, wUUID)
		}
		if penaltyDelta != 0 && s.workerRepo != nil {
			_ = s.workerRepo.AdjustWorkerScoreAtomic(ctx, wUUID, penaltyDelta, "CANCEL_IN_PROGRESS_REVERT")
		}

		// MODIFIED: More descriptive message body.
		messageBody := fmt.Sprintf(
			"The assigned worker canceled this in-progress job at %s before the latest start time (%s). The job has been reopened and may need coverage.",
			prop.PropertyName,
			lStart.Format("3:04 PM MST"),
		)
		// MODIFIED: Corrected the function call to match the updated signature.
		NotifyOnCallAgents(
			ctx,
			s.cfg.AppUrl,
			prop,
			defn,
			inst,
			"[Escalation] Worker Canceled In-Progress Job",
			messageBody,
			s.agentRepo,
			s.agentJobCompletionRepo,
			s.bldgRepo,
			s.unitRepo,
			s.twilioClient,
			s.sendgridClient,
			s.cfg,
		)

		dto, _ := s.buildInstanceDTO(ctx, rev, nil, nil, nil, nil, nil, nil, nil)
		return dto, nil
	}

	expectedVersion := inst.RowVersion
	cancelled, err2 := s.instRepo.UpdateStatusToCancelled(ctx, instanceID, expectedVersion)
	if err2 != nil {
		if strings.Contains(err2.Error(), utils.ErrRowVersionConflict.Error()) {
			latest, _ := s.instRepo.GetByID(ctx, instanceID)
			if latest != nil {
				return nil, internal_utils.NewRowVersionConflictError(latest)
			}
		}
		return nil, err2
	}
	if cancelled == nil {
		return nil, utils.ErrNoRowsUpdated
	}

	if s.workerRepo != nil {
		_ = s.instRepo.AddExcludedWorker(ctx, cancelled.ID, wUUID)
		_ = s.workerRepo.AdjustWorkerScoreAtomic(ctx, wUUID, constants.WorkerPenaltyNoShow, "CANCEL_IN_PROGRESS_LATE")
	}

	// MODIFIED: More descriptive message body.
	messageBody := fmt.Sprintf(
		"The assigned worker canceled this in-progress job at %s after the latest start time (%s). The job has been canceled and requires no further action.",
		prop.PropertyName,
		lStart.Format("3:04 PM MST"),
	)
	// MODIFIED: Corrected the function call to match the updated signature.
	NotifyInternalTeamOnly(
		ctx,
		prop,
		defn,
		cancelled,
		"[Alert] Worker Canceled In-Progress Job (Late)",
		messageBody,
		s.bldgRepo,
		s.unitRepo,
		s.sendgridClient,
		s.cfg,
	)

	dto, _ := s.buildInstanceDTO(ctx, cancelled, nil, nil, nil, nil, nil, nil, nil)
	return dto, nil
}

/*────────────────────────────────────────────────────────────────────────────
  Internal Helpers
───────────────────────────────────────────────────────────────────────────*/

// CalculatePenaltyForUnassign implements the tiered penalty logic for un-assigning or canceling a job.
// All windows are calculated relative to the no-show time.
func shouldCreateOnDate(d *models.JobDefinition, day time.Time) bool {
	if day.Before(DateOnly(d.StartDate)) {
		return false
	}
	if d.EndDate != nil && day.After(DateOnly(*d.EndDate)) {
		return false
	}
	if d.SkipHolidays && internal_utils.IsUSFedHoliday(day) &&
		!inExceptions(d.HolidayExceptions, day) {
		return false
	}

	if d.GetDailyEstimate(day.Weekday()) == nil {
		return false
	}

	switch d.Frequency {
	case models.JobFreqDaily:
		return true
	case models.JobFreqWeekdays:
		w := day.Weekday()
		return w >= time.Monday && w <= time.Friday
	case models.JobFreqWeekly:
		return day.Weekday() == d.StartDate.Weekday()
	case models.JobFreqBiWeekly:
		if day.Weekday() != d.StartDate.Weekday() {
			return false
		}
		startOfWeekForStartDate := d.StartDate.AddDate(0, 0, -int(d.StartDate.Weekday()))
		startOfWeekForDay := day.AddDate(0, 0, -int(day.Weekday()))
		weeks := int(startOfWeekForDay.Sub(startOfWeekForStartDate).Hours() / (24 * 7))
		return (weeks % 2) == 0
	case models.JobFreqMonthly:
		sd := d.StartDate.Day()
		if sd > 28 && day.Day() < sd {
			return day.Day() == lastDayOfMonth(day).Day()
		}
		return day.Day() == sd
	case models.JobFreqCustom:
		if d.IntervalWeeks == nil || len(d.Weekdays) == 0 {
			return false
		}
		wd := int16(day.Weekday())
		if !containsShort(d.Weekdays, wd) {
			return false
		}
		startOfWeekForStartDate := d.StartDate.AddDate(0, 0, -int(d.StartDate.Weekday()))
		startOfWeekForDay := day.AddDate(0, 0, -int(day.Weekday()))
		weeksSinceStart := int(startOfWeekForDay.Sub(startOfWeekForStartDate).Hours() / (24 * 7))
		return (weeksSinceStart >= 0) && (weeksSinceStart%*d.IntervalWeeks == 0)
	default:
		return false
	}
}

func validateDailyPayEstimates(
	freq models.JobFrequencyType,
	weekdaysInDef []int16,
	estimatesReq []dtos.DailyPayEstimateRequest,
) error {
	if len(estimatesReq) == 0 {
		return fmt.Errorf("internal error: validateDailyPayEstimates called with empty estimatesReq")
	}

	providedDaysMap := make(map[time.Weekday]bool)
	for _, est := range estimatesReq {
		if est.DayOfWeek < int(time.Sunday) || est.DayOfWeek > int(time.Saturday) {
			return fmt.Errorf("invalid day_of_week %d in daily_pay_estimates; must be 0 (Sunday) to 6 (Saturday)", est.DayOfWeek)
		}
		dayEnum := time.Weekday(est.DayOfWeek)
		if _, exists := providedDaysMap[dayEnum]; exists {
			return fmt.Errorf("duplicate day_of_week %s in daily_pay_estimates", dayEnum)
		}
		if est.BasePay <= 0 {
			return fmt.Errorf("base_pay must be positive for day %s", dayEnum)
		}
		if est.EstimatedTimeMinutes <= 0 {
			return fmt.Errorf("estimated_time_minutes must be positive for day %s", dayEnum)
		}
		providedDaysMap[dayEnum] = true
	}

	requiredDaysMap := make(map[time.Weekday]bool)
	switch freq {
	case models.JobFreqDaily, models.JobFreqMonthly, models.JobFreqWeekly, models.JobFreqBiWeekly:
		for d := time.Sunday; d <= time.Saturday; d++ {
			requiredDaysMap[d] = true
		}
	case models.JobFreqWeekdays:
		for d := time.Monday; d <= time.Friday; d++ {
			requiredDaysMap[d] = true
		}
	case models.JobFreqCustom:
		if len(weekdaysInDef) == 0 {
			return fmt.Errorf("weekdays must be specified in the definition for CUSTOM frequency when providing specific daily_pay_estimates")
		}
		for _, wdInt := range weekdaysInDef {
			if wdInt < int16(time.Sunday) || wdInt > int16(time.Saturday) {
				return fmt.Errorf("invalid weekday value %d in definition's weekdays for CUSTOM frequency", wdInt)
			}
			requiredDaysMap[time.Weekday(wdInt)] = true
		}
	default:
		return fmt.Errorf("unknown job frequency for daily_pay_estimates validation: %s", freq)
	}

	for day := range requiredDaysMap {
		if !providedDaysMap[day] {
			return fmt.Errorf("missing daily_pay_estimate for required day: %s (based on frequency %s and/or custom weekdays)", day, freq)
		}
	}

	return nil
}
