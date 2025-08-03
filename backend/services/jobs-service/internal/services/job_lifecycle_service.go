package services

import (
	"context"
	"fmt"
	"math"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/go-models"
	"github.com/poofware/go-utils"
	"github.com/poofware/jobs-service/internal/constants"
	"github.com/poofware/jobs-service/internal/dtos"
	internal_utils "github.com/poofware/jobs-service/internal/utils"
	logrus "github.com/sirupsen/logrus"
)

// AcceptJobInstanceWithLocation ...
func (s *JobService) AcceptJobInstanceWithLocation(
	ctx context.Context,
	workerID string,
	locReq dtos.JobLocationActionRequest,
) (*dtos.JobInstanceDTO, error) {
	inst, err := s.instRepo.GetByID(ctx, locReq.InstanceID)
	if err != nil {
		return nil, err
	}
	if inst == nil {
		return nil, nil
	}
	if inst.Status != models.InstanceStatusOpen {
		return nil, internal_utils.ErrWrongStatus
	}

	wUUID, parseErr := uuid.Parse(workerID)
	if parseErr != nil {
		return nil, fmt.Errorf("invalid worker ID format: %w", parseErr)
	}

	// Fetch worker and check account status first.
	worker, wErr := s.workerRepo.GetByID(ctx, wUUID)
	if wErr != nil {
		return nil, wErr // Pass up DB errors
	}
	if worker == nil {
		// This is a security anomaly - JWT for a non-existent worker.
		return nil, fmt.Errorf("authenticated worker with ID %s not found in database", workerID)
	}
	if worker.AccountStatus != models.AccountStatusActive {
		return nil, internal_utils.ErrWorkerNotActive
	}

	if ContainsUUID(inst.ExcludedWorkerIDs, wUUID) {
		return nil, internal_utils.ErrExcludedWorker
	}

	defn, dErr := s.defRepo.GetByID(ctx, inst.DefinitionID)
	if dErr != nil || defn == nil {
		return nil, fmt.Errorf("job definition not found")
	}
	prop, pErr := s.propRepo.GetByID(ctx, defn.PropertyID)
	if pErr != nil || prop == nil {
		return nil, fmt.Errorf("property not found")
	}

	// Continue with other validations after confirming worker is active.
	wScore := worker.ReliabilityScore
	var wTenantPropID *uuid.UUID
	if worker.TenantToken != nil && *worker.TenantToken != "" {
		propID, _ := s.lookupTenantPropertyID(ctx, *worker.TenantToken)
		wTenantPropID = propID
	}

	propLoc := loadPropertyLocation(prop.TimeZone)
	propNow := time.Now().In(propLoc)
	baseMidnightForProp := dateOnlyInLocation(propNow, propLoc)

	if !s.isJobReleasedToWorker(inst, prop, propNow, baseMidnightForProp, wScore, wTenantPropID) {
		return nil, internal_utils.ErrJobNotReleasedYet
	}

	// Gate job acceptance based on the no-show cutoff time.
	latestStartLocal := time.Date(inst.ServiceDate.Year(), inst.ServiceDate.Month(), inst.ServiceDate.Day(), defn.LatestStartTime.Hour(), defn.LatestStartTime.Minute(), 0, 0, propLoc)
	noShowCutoffTime := latestStartLocal.Add(-constants.NoShowCutoffBeforeLatestStart)
	acceptanceCutoffTime := noShowCutoffTime.Add(-constants.AcceptanceCutoffBeforeNoShow)
	if time.Now().After(acceptanceCutoffTime) {
		return nil, internal_utils.ErrNotWithinTimeWindow
	}

	distMiles := internal_utils.DistanceMiles(locReq.Lat, locReq.Lng, prop.Latitude, prop.Longitude)
	if distMiles > float64(constants.RadiusMiles) {
		return nil, internal_utils.ErrLocationOutOfBounds
	}

	newAssignCount := inst.AssignUnassignCount + 1
	flagged := inst.FlaggedForReview
	if newAssignCount > constants.MaxAssignUnassignCountForFlag {
		flagged = true
	}

	expectedVersion := inst.RowVersion
	updated, err2 := s.instRepo.AcceptInstanceAtomic(
		ctx,
		inst.ID,
		wUUID,
		expectedVersion,
		newAssignCount,
		flagged,
	)
	if err2 != nil {
		if strings.Contains(err2.Error(), utils.ErrRowVersionConflict.Error()) {
			latest, _ := s.instRepo.GetByID(ctx, inst.ID)
			if latest != nil {
				return nil, internal_utils.NewRowVersionConflictError(latest)
			}
			return nil, err2
		}
		return nil, err2
	}
	if updated == nil {
		return nil, utils.ErrNoRowsUpdated
	}

	dto, _ := s.buildInstanceDTO(ctx, updated, nil, nil)
	return dto, nil
}

// StartJobInstanceWithLocation ...
func (s *JobService) StartJobInstanceWithLocation(
	ctx context.Context,
	workerID string,
	locReq dtos.JobLocationActionRequest,
) (*dtos.JobInstanceDTO, error) {
	inst, err := s.instRepo.GetByID(ctx, locReq.InstanceID)
	if err != nil {
		return nil, err
	}
	if inst == nil {
		return nil, nil
	}

	if inst.AssignedWorkerID == nil || inst.AssignedWorkerID.String() != workerID {
		return nil, internal_utils.ErrNotAssignedWorker
	}

	if inst.Status != models.InstanceStatusAssigned {
		return nil, internal_utils.ErrWrongStatus
	}

	defn, dErr := s.defRepo.GetByID(ctx, inst.DefinitionID)
	if dErr != nil || defn == nil {
		return nil, fmt.Errorf("job definition not found")
	}
	prop, pErr := s.propRepo.GetByID(ctx, defn.PropertyID)
	if pErr != nil || prop == nil {
		return nil, fmt.Errorf("property not found")
	}

	// --- FIX: Construct the time window in the property's local timezone ---
	// 1. Load the property's location (timezone).
	propLoc := loadPropertyLocation(prop.TimeZone)

	// 2. Combine the service date with the definition's start/end times IN that timezone.
	// This creates the correct absolute moment in time for the window's start and end.
	serviceDate := inst.ServiceDate
	eStart := time.Date(serviceDate.Year(), serviceDate.Month(), serviceDate.Day(), defn.EarliestStartTime.Hour(), defn.EarliestStartTime.Minute(), 0, 0, propLoc)
	lStart := time.Date(serviceDate.Year(), serviceDate.Month(), serviceDate.Day(), defn.LatestStartTime.Hour(), defn.LatestStartTime.Minute(), 0, 0, propLoc)

	nowUTC := time.Now().UTC()
	// 3. The comparison now correctly uses absolute moments in time (UTC vs UTC).
	if nowUTC.Before(eStart) || nowUTC.After(lStart) {
		return nil, internal_utils.ErrNotWithinTimeWindow
	}

	distMeters := internal_utils.ComputeDistanceMeters(locReq.Lat, locReq.Lng, prop.Latitude, prop.Longitude)
	if distMeters > float64(constants.LocationRadiusMeters) {
		return nil, internal_utils.ErrLocationOutOfBounds
	}

	expectedVersion := inst.RowVersion
	updated, err2 := s.instRepo.UpdateStatusToInProgress(ctx, inst.ID, expectedVersion)
	if err2 != nil {
		if strings.Contains(err2.Error(), utils.ErrRowVersionConflict.Error()) {
			latest, _ := s.instRepo.GetByID(ctx, inst.ID)
			if latest != nil {
				return nil, internal_utils.NewRowVersionConflictError(latest)
			}
		}
		return nil, err2
	}
	if updated == nil {
		return nil, utils.ErrNoRowsUpdated
	}

	dto, _ := s.buildInstanceDTO(ctx, updated, nil, nil)
	return dto, nil
}

// VerifyUnitPhoto processes a photo for a specific unit.
func (s *JobService) VerifyUnitPhoto(
	ctx context.Context,
	workerID string,
	instanceID uuid.UUID,
	unitID uuid.UUID,
	lat float64,
	lng float64,
	accuracy float64,
	timestampMS int64,
	isMock bool,
	missingTrashCan bool,
	photo []byte,
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

	defn, err := s.defRepo.GetByID(ctx, inst.DefinitionID)
	if err != nil || defn == nil {
		return nil, fmt.Errorf("job definition not found")
	}
	prop, err := s.propRepo.GetByID(ctx, defn.PropertyID)
	if err != nil || prop == nil {
		return nil, fmt.Errorf("property not found")
	}

	dist := internal_utils.ComputeDistanceMeters(lat, lng, prop.Latitude, prop.Longitude)
	if dist > float64(constants.LocationRadiusMeters) {
		return nil, internal_utils.ErrLocationOutOfBounds
	}

	// Ensure unit is part of the assignment
	allowed := false
	for _, grp := range defn.AssignedUnitsByBuilding {
		if slices.Contains(grp.UnitIDs, unitID) {
			allowed = true
		}
		if allowed {
			break
		}
	}
	if !allowed {
		return nil, internal_utils.ErrInvalidPayload
	}

	unit, err := s.unitRepo.GetByID(ctx, unitID)
	if err != nil || unit == nil {
		return nil, fmt.Errorf("unit not found")
	}

	status := models.UnitVerificationVerified
	var reasonCodes []string
	if s.cfg.LDFlag_OpenAIPhotoVerification {
		result, err := s.openai.VerifyPhoto(ctx, photo, unit.UnitNumber)
		if err != nil {
			return nil, err
		}
		utils.Logger.WithFields(logrus.Fields{
			"unit_id":              unitID,
			"trash_can_present":    result.TrashCanPresent,
			"no_trash_bag_visible": result.NoTrashBagVisible,
			"door_number_matches":  result.DoorNumberMatches,
			"door_number_detected": result.DoorNumberDetected,
		}).Debug("openai verification result")

		pass := false
		if missingTrashCan {
			pass = result.DoorNumberMatches
			if !result.DoorNumberMatches {
				if result.DoorNumberDetected != "" {
					reasonCodes = append(reasonCodes, "DOOR_NUMBER_MISMATCH")
				} else {
					reasonCodes = append(reasonCodes, "DOOR_NUMBER_MISSING")
				}
			}
		} else {
			pass = result.TrashCanPresent && result.NoTrashBagVisible && result.DoorNumberMatches
			if !result.TrashCanPresent {
				reasonCodes = append(reasonCodes, "TRASH_CAN_NOT_VISIBLE")
			}
			if !result.NoTrashBagVisible {
				reasonCodes = append(reasonCodes, "TRASH_BAG_VISIBLE")
			}
			if !result.DoorNumberMatches {
				if result.DoorNumberDetected != "" {
					reasonCodes = append(reasonCodes, "DOOR_NUMBER_MISMATCH")
				} else {
					reasonCodes = append(reasonCodes, "DOOR_NUMBER_MISSING")
				}
			}
		}
		if !pass {
			status = models.UnitVerificationFailed
		}
	}

	v, err := s.juvRepo.GetByInstanceAndUnit(ctx, instanceID, unitID)
	if err != nil {
		return nil, err
	}
	if v != nil && v.PermanentFailure {
		dto, _ := s.buildInstanceDTO(ctx, inst, nil, nil)
		return dto, nil
	}
	if v == nil {
		v = &models.JobUnitVerification{
			ID:                   uuid.New(),
			JobInstanceID:        instanceID,
			UnitID:               unitID,
			Status:               status,
			AttemptCount:         0,
			FailureReasons:       []string{},
			FailureReasonHistory: []string{},
			PermanentFailure:     false,
			MissingTrashCan:      missingTrashCan,
		}
	}

	if status == models.UnitVerificationFailed {
		v.AttemptCount++
		v.FailureReasons = reasonCodes
		v.FailureReasonHistory = append(v.FailureReasonHistory, reasonCodes...)
		if v.AttemptCount >= 3 {
			v.PermanentFailure = true
		}
	} else {
		v.AttemptCount = 0
		// Use an empty slice to satisfy the NOT NULL constraint on
		// job_unit_verifications.failure_reasons. Using nil would
		// result in a NULL value being written to the database and
		// violate the constraint.
		v.FailureReasons = []string{}
		v.PermanentFailure = false
	}

	v.Status = status
	v.MissingTrashCan = missingTrashCan

	if v.RowVersion == 0 {
		if err := s.juvRepo.Create(ctx, v); err != nil {
			return nil, err
		}
	} else {
		if _, err := s.juvRepo.UpdateIfVersion(ctx, v, v.RowVersion); err != nil {
			return nil, err
		}
	}

	dto, _ := s.buildInstanceDTO(ctx, inst, nil, nil)
	return dto, nil
}

// ProcessDumpTrip marks verified units as dumped and completes the job if all are dumped.
// It enforces that a worker must be near a dumpster if they have verified units.
// The location check is bypassed only if the job is being completed solely due to all units having permanently failed.
func (s *JobService) ProcessDumpTrip(
	ctx context.Context,
	workerID string,
	locReq dtos.JobLocationActionRequest,
) (*dtos.JobInstanceDTO, error) {
	inst, err := s.instRepo.GetByID(ctx, locReq.InstanceID)
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

	defn, err := s.defRepo.GetByID(ctx, inst.DefinitionID)
	if err != nil || defn == nil {
		return nil, fmt.Errorf("job definition not found")
	}
	prop, err := s.propRepo.GetByID(ctx, defn.PropertyID)
	if err != nil || prop == nil {
		return nil, fmt.Errorf("property not found")
	}

	verifs, err := s.juvRepo.ListByInstanceID(ctx, inst.ID)
	if err != nil {
		return nil, err
	}

	// --- START: Enhanced Validation Logic ---

	// Count the number of verified and permanently failed units.
	verifiedCount := 0
	permFailedCount := 0
	for _, v := range verifs {
		if v.Status == models.UnitVerificationVerified {
			verifiedCount++
		} else if v.Status == models.UnitVerificationFailed && v.PermanentFailure {
			permFailedCount++
		}
	}

	// Count the total number of units assigned to this job definition.
	totalUnits := 0
	for _, grp := range defn.AssignedUnitsByBuilding {
		totalUnits += len(grp.UnitIDs)
	}

	// This is the specific condition where a job can be completed without any verified bags.
	// It requires that all assigned units are accounted for as permanent failures.
	isCompletableViaFailure := verifiedCount == 0 && permFailedCount > 0 && permFailedCount >= totalUnits

	if verifiedCount > 0 {
		// Standard flow: Bags were collected, so location must be verified at a dumpster.
		dumps, err := s.dumpRepo.ListByPropertyID(ctx, prop.ID)
		if err != nil {
			return nil, err
		}
		within := false
		for _, d := range dumps {
			if ContainsUUID(defn.DumpsterIDs, d.ID) {
				dist := internal_utils.ComputeDistanceMeters(locReq.Lat, locReq.Lng, d.Latitude, d.Longitude)
				if dist <= float64(constants.LocationRadiusMeters) {
					within = true
					break
				}
			}
		}
		if !within {
			return nil, internal_utils.ErrDumpLocationOutOfBounds
		}
	} else if !isCompletableViaFailure {
		// Edge case: No bags were collected, AND the job is not completable due to permanent failures.
		// This is an invalid API call, as there is nothing to dump and the job is not finished.
		return nil, internal_utils.ErrDumpLocationOutOfBounds
	}
	// --- END: Enhanced Validation Logic ---

	for _, v := range verifs {
		if v.Status == models.UnitVerificationVerified {
			v.Status = models.UnitVerificationDumped
			_, _ = s.juvRepo.UpdateIfVersion(ctx, v, v.RowVersion)
		}
	}

	// check if all units are in a final state (dumped or permanently failed)
	total := 0
	completedUnits := 0
	for _, grp := range defn.AssignedUnitsByBuilding {
		total += len(grp.UnitIDs)
	}
	// Re-fetch verifications to get the latest status after updates
	verifsAfterUpdate, _ := s.juvRepo.ListByInstanceID(ctx, inst.ID)
	for _, v := range verifsAfterUpdate {
		if v.Status == models.UnitVerificationDumped || (v.Status == models.UnitVerificationFailed && v.PermanentFailure) {
			completedUnits++
		}
	}

	var updated *models.JobInstance
	if completedUnits >= total {
		rv := inst.RowVersion
		updated, err = s.instRepo.UpdateStatusToCompleted(ctx, inst.ID, rv)
		if err != nil {
			if strings.Contains(err.Error(), utils.ErrRowVersionConflict.Error()) {
				latest, _ := s.instRepo.GetByID(ctx, inst.ID)
				if latest != nil {
					return nil, internal_utils.NewRowVersionConflictError(latest)
				}
			}
			return nil, err
		}
		if updated != nil && updated.CheckInAt != nil && updated.CheckOutAt != nil {
			timeSpent := max(updated.CheckOutAt.Sub(*updated.CheckInAt).Minutes(), 1)
			actualMins := int(math.Round(timeSpent))
			_ = s.applyCompletionTimeEma(ctx, defn.ID, updated.ServiceDate.Weekday(), actualMins)
		}
	}

	if updated == nil {
		// If not completed, we need to re-fetch the instance to get the latest row_version
		// and updated unit statuses for the DTO.
		updated, _ = s.instRepo.GetByID(ctx, inst.ID)
		if updated == nil {
			updated = inst // fallback to original instance if re-fetch fails
		}
	}

	dto, _ := s.buildInstanceDTO(ctx, updated, nil, nil)
	return dto, nil
}

// UnacceptJobInstance allows a worker to un-assign themselves from a job.
// Penalties are now applied based on a tiered model anchored to the no-show time.
func (s *JobService) UnacceptJobInstance(
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
		return nil, nil
	}
	if inst.Status != models.InstanceStatusAssigned {
		return nil, internal_utils.ErrWrongStatus
	}

	wUUID := uuid.MustParse(workerID)
	var penaltyDelta int
	var excludeWorker bool

	defn, _ := s.defRepo.GetByID(ctx, inst.DefinitionID)
	if defn != nil {
		prop, pErr := s.propRepo.GetByID(ctx, defn.PropertyID)
		if pErr == nil && prop != nil {
			now := time.Now().UTC()
			propLoc := loadPropertyLocation(prop.TimeZone)
			serviceDate := inst.ServiceDate
			eStart := time.Date(serviceDate.Year(), serviceDate.Month(), serviceDate.Day(), defn.EarliestStartTime.Hour(), defn.EarliestStartTime.Minute(), 0, 0, propLoc)
			lStart := time.Date(serviceDate.Year(), serviceDate.Month(), serviceDate.Day(), defn.LatestStartTime.Hour(), defn.LatestStartTime.Minute(), 0, 0, propLoc)
			noShowTime := lStart.Add(-constants.NoShowCutoffBeforeLatestStart)
			acceptanceCutoffTime := noShowTime.Add(-constants.AcceptanceCutoffBeforeNoShow)

			if now.After(acceptanceCutoffTime) {
				// Job is too close to start time to be reopened. It must be CANCELED.
				cancelled, err2 := s.instRepo.UpdateStatusToCancelled(ctx, instanceID, inst.RowVersion)
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

				// Apply no-show penalty and always exclude.
				if s.workerRepo != nil {
					_ = s.instRepo.AddExcludedWorker(ctx, cancelled.ID, wUUID)
					_ = s.workerRepo.AdjustWorkerScoreAtomic(ctx, wUUID, constants.WorkerPenaltyNoShow, "UNACCEPT_LATE_CANCEL")
				}

				messageBody := "Worker un-assigned from job after acceptance cutoff. It has been canceled and may need coverage."
				NotifyOnCallAgents(
					ctx, prop, defn.ID.String(), "[Escalation] Worker Unassigned Late", messageBody,
					s.agentRepo, s.twilioClient, s.sendgridClient,
					s.cfg.LDFlag_TwilioFromPhone, s.cfg.LDFlag_SendgridFromEmail,
					s.cfg.OrganizationName, s.cfg.LDFlag_SendgridSandboxMode,
				)

				dto, _ := s.buildInstanceDTO(ctx, cancelled, nil, nil)
				return dto, nil
			}

			penaltyDelta, excludeWorker = CalculatePenaltyForUnassign(now, eStart, noShowTime)
		}
	}

	assignCount := inst.AssignUnassignCount + 1
	flagged := inst.FlaggedForReview
	if assignCount > constants.MaxAssignUnassignCountForFlag {
		flagged = true
	}
	expectedVersion := inst.RowVersion
	updated, err2 := s.instRepo.UnassignInstanceAtomic(ctx, instanceID, expectedVersion, assignCount, flagged)
	if err2 != nil {
		if strings.Contains(err2.Error(), utils.ErrRowVersionConflict.Error()) {
			latest, _ := s.instRepo.GetByID(ctx, instanceID)
			if latest != nil {
				return nil, internal_utils.NewRowVersionConflictError(latest)
			}
		}
		return nil, err2
	}
	if updated == nil {
		return nil, utils.ErrNoRowsUpdated
	}

	if excludeWorker {
		_ = s.instRepo.AddExcludedWorker(ctx, updated.ID, wUUID)
	}
	if penaltyDelta != 0 && s.workerRepo != nil {
		_ = s.workerRepo.AdjustWorkerScoreAtomic(ctx, wUUID, penaltyDelta, "UNACCEPT")
	}

	dto, _ := s.buildInstanceDTO(ctx, updated, nil, nil)
	return dto, nil
}
