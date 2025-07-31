// meta-service/services/jobs-service/internal/services/job_service.go

package services

import (
	"slices"
	"context"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/go-models"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
	"github.com/poofware/jobs-service/internal/config"
	"github.com/poofware/jobs-service/internal/constants"
	"github.com/poofware/jobs-service/internal/dtos"
	internal_utils "github.com/poofware/jobs-service/internal/utils"
	"github.com/sendgrid/sendgrid-go"
	"github.com/twilio/twilio-go"
)

const (
	jobTimeEmaAlpha          = 0.20 // for exponential moving average
	JobTimeEMAMinClipPercent = 0.4  // 40% of current estimate
	JobTimeEMAMaxClipPercent = 1.6  // 160% of current estimate
	MinJobTimeEstimateFloat  = 1.0  // Minimum float value for job time estimates
	MinJobTimeEstimateInt    = 1    // Minimum integer value for job time estimates
)

type JobService struct {
	cfg            *config.Config
	defRepo        repositories.JobDefinitionRepository
	instRepo       repositories.JobInstanceRepository
	propRepo       repositories.PropertyRepository
	bldgRepo       repositories.PropertyBuildingRepository
	dumpRepo       repositories.DumpsterRepository
	workerRepo     repositories.WorkerRepository
	agentRepo      repositories.AgentRepository
	unitRepo       repositories.UnitRepository
	juvRepo        repositories.JobUnitVerificationRepository
	openai         *OpenAIService
	twilioClient   *twilio.RestClient
	sendgridClient *sendgrid.Client
}

// routeInfo is a helper struct to cache the results of a single routing API call.
type routeInfo struct {
	DistanceMiles float64
	TravelMinutes *int
}

func NewJobService(
	cfg *config.Config,
	defRepo repositories.JobDefinitionRepository,
	instRepo repositories.JobInstanceRepository,
	propRepo repositories.PropertyRepository,
	bldgRepo repositories.PropertyBuildingRepository,
	dumpRepo repositories.DumpsterRepository,
	workerRepo repositories.WorkerRepository,
	agentRepo repositories.AgentRepository,
	unitRepo repositories.UnitRepository,
	juvRepo repositories.JobUnitVerificationRepository,
	openai *OpenAIService,
	twilioClient *twilio.RestClient,
	sendgridClient *sendgrid.Client,
) *JobService {
	return &JobService{
		cfg:            cfg,
		defRepo:        defRepo,
		instRepo:       instRepo,
		propRepo:       propRepo,
		bldgRepo:       bldgRepo,
		dumpRepo:       dumpRepo,
		workerRepo:     workerRepo,
		agentRepo:      agentRepo,
		unitRepo:       unitRepo,
		juvRepo:        juvRepo,
		openai:         openai,
		twilioClient:   twilioClient,
		sendgridClient: sendgridClient,
	}
}

// ListOpenJobs returns open jobs for the next several days.
// It queries a 9-day window from yesterday to today+7 days (relative to the worker's timezone).
// Jobs from yesterday through today+5 are always visible.
// Jobs on today+6 and today+7 are gated, becoming visible based on a release schedule
// that accounts for worker reliability score and tenancy status.
func (s *JobService) ListOpenJobs(
	ctx context.Context,
	userID string,
	q dtos.ListJobsQuery,
	workerLoc *time.Location,
) (*dtos.ListJobsResponse, error) {
	nowLocal := time.Now().In(workerLoc)
	// Query a 9-day window from yesterday to today+7 days to cover all scenarios.
	startUTC := dateOnlyInLocation(nowLocal.AddDate(0, 0, -1), workerLoc)
	endUTC := startUTC.AddDate(0, 0, constants.DaysToListOpenJobsRange)

	statuses := []models.InstanceStatusType{models.InstanceStatusOpen}
	// The repo query is inclusive on both start and end, so this covers the full 9 days.
	instances, err := s.instRepo.ListInstancesByDateRange(ctx, nil, statuses, startUTC, endUTC)
	if err != nil {
		return nil, err
	}

	var wScore int
	var wTenantPropID *uuid.UUID

	wID, parseErr := uuid.Parse(userID)
	if parseErr == nil {
		w, wErr := s.workerRepo.GetByID(ctx, wID)
		if wErr == nil && w != nil {
			wScore = w.ReliabilityScore
			if w.TenantToken != nil && *w.TenantToken != "" {
				propID, _ := s.lookupTenantPropertyID(ctx, *w.TenantToken)
				wTenantPropID = propID
			}
		}
	}

	// --- Start of Optimization ---

	// 1. Group instances by property ID after filtering.
	instancesByPropID := make(map[uuid.UUID][]*models.JobInstance)
	propDefs := make(map[uuid.UUID]*models.JobDefinition)
	propsCache := make(map[uuid.UUID]*models.Property)

	for _, inst := range instances {
		if parseErr == nil && ContainsUUID(inst.ExcludedWorkerIDs, wID) {
			continue
		}

		defn, ok := propDefs[inst.DefinitionID]
		if !ok {
			var dErr error
			defn, dErr = s.defRepo.GetByID(ctx, inst.DefinitionID)
			if dErr != nil || defn == nil {
				continue
			}
			propDefs[inst.DefinitionID] = defn
		}

		prop, ok := propsCache[defn.PropertyID]
		if !ok {
			var pErr error
			prop, pErr = s.propRepo.GetByID(ctx, defn.PropertyID)
			if pErr != nil || prop == nil {
				continue
			}
			propsCache[defn.PropertyID] = prop
		}

		propLoc := loadPropertyLocation(prop.TimeZone)
		propNow := time.Now().In(propLoc)
		baseMidnightForProp := dateOnlyInLocation(propNow, propLoc)

		if !s.isJobReleasedToWorker(inst, prop, propNow, baseMidnightForProp, wScore, wTenantPropID) {
			continue
		}

		latestStartLocal := time.Date(inst.ServiceDate.Year(), inst.ServiceDate.Month(), inst.ServiceDate.Day(), defn.LatestStartTime.Hour(), defn.LatestStartTime.Minute(), 0, 0, propLoc)
		noShowCutoffTime := latestStartLocal.Add(-constants.NoShowCutoffBeforeLatestStart)
		acceptanceCutoffTime := noShowCutoffTime.Add(-constants.AcceptanceCutoffBeforeNoShow)
		if time.Now().After(acceptanceCutoffTime) {
			continue
		}

		instancesByPropID[defn.PropertyID] = append(instancesByPropID[defn.PropertyID], inst)
	}

	// 2. Calculate routes once per property.
	routeCache := make(map[uuid.UUID]*routeInfo)
	if q.Lat != 0 || q.Lng != 0 {
		for propID := range instancesByPropID {
			prop, _ := propsCache[propID]
			if prop == nil {
				continue
			}

			var distMiles float64
			var travelMins *int
			if s.cfg.LDFlag_UseGMapsRoutesAPI && s.cfg.GMapsRoutesAPIKey != "" {
				dMiles, dMins, gErr := internal_utils.ComputeDriveDistanceTimeMiles(q.Lat, q.Lng, prop.Latitude, prop.Longitude, s.cfg.GMapsRoutesAPIKey)
				if gErr == nil {
					distMiles = dMiles
					travelMins = &dMins
				}
			}

			// Fallback if GMaps is disabled or failed
			if travelMins == nil {
				distMiles = internal_utils.DistanceMiles(q.Lat, q.Lng, prop.Latitude, prop.Longitude)
				estMins := int(distMiles * constants.CrowFliesDriveTimeMultiplier)
				travelMins = &estMins
			}

			routeCache[propID] = &routeInfo{
				DistanceMiles: distMiles,
				TravelMinutes: travelMins,
			}
		}
	}

	// 3. Build DTOs using the cached route info.
	var dtosList []dtos.JobInstanceDTO
	for propID, instancesInGroup := range instancesByPropID {
		route := routeCache[propID]
		if route != nil && route.DistanceMiles > float64(constants.RadiusMiles) {
			continue
		}

		for _, inst := range instancesInGroup {
			dto, err := s.buildInstanceDTO(ctx, inst, route, workerLoc)
			if err == nil && dto != nil {
				dtosList = append(dtosList, *dto)
			}
		}
	}

	// --- End of Optimization ---

	sort.Slice(dtosList, func(i, j int) bool {
		if dtosList[i].DistanceMiles < dtosList[j].DistanceMiles {
			return true
		} else if dtosList[i].DistanceMiles > dtosList[j].DistanceMiles {
			return false
		}
		return dtosList[i].ServiceDate < dtosList[j].ServiceDate
	})

	total := len(dtosList)
	startIdx := (q.Page - 1) * q.Size
	if startIdx >= total {
		return &dtos.ListJobsResponse{
			Results: []dtos.JobInstanceDTO{},
			Page:    q.Page,
			Size:    q.Size,
			Total:   total,
		}, nil
	}
	endIdx := min(startIdx+q.Size, total)
	paged := dtosList[startIdx:endIdx]

	return &dtos.ListJobsResponse{
		Results: paged,
		Page:    q.Page,
		Size:    q.Size,
		Total:   total,
	}, nil
}

// ListMyJobs returns assigned or in-progress jobs ...
func (s *JobService) ListMyJobs(
	ctx context.Context,
	userID string,
	q dtos.ListJobsQuery,
	workerLoc *time.Location,
) (*dtos.ListJobsResponse, error) {
	wID, errParse := uuid.Parse(userID)
	if errParse != nil {
		return &dtos.ListJobsResponse{
			Results: []dtos.JobInstanceDTO{},
			Page:    q.Page,
			Size:    q.Size,
			Total:   0,
		}, nil
	}

	nowLocal := time.Now().In(workerLoc)
	// Query an 9-day window from yesterday to today+7 days to cover all scenarios.
	startUTC := dateOnlyInLocation(nowLocal.AddDate(0, 0, -1), workerLoc)
	endUTC := startUTC.AddDate(0, 0, constants.DaysToListOpenJobsRange)

	statuses := []models.InstanceStatusType{
		models.InstanceStatusAssigned,
		models.InstanceStatusInProgress,
	}
	instances, err := s.instRepo.ListInstancesByDateRange(ctx, &wID, statuses, startUTC, endUTC)
	if err != nil {
		return nil, err
	}

	// --- Start of Optimization (mirrors ListOpenJobs) ---

	instancesByPropID := make(map[uuid.UUID][]*models.JobInstance)
	propDefs := make(map[uuid.UUID]*models.JobDefinition)
	propsCache := make(map[uuid.UUID]*models.Property)

	for _, inst := range instances {
		defn, ok := propDefs[inst.DefinitionID]
		if !ok {
			var dErr error
			defn, dErr = s.defRepo.GetByID(ctx, inst.DefinitionID)
			if dErr != nil || defn == nil {
				continue
			}
			propDefs[inst.DefinitionID] = defn
		}
		if _, ok := propsCache[defn.PropertyID]; !ok {
			prop, pErr := s.propRepo.GetByID(ctx, defn.PropertyID)
			if pErr != nil || prop == nil {
				continue
			}
			propsCache[defn.PropertyID] = prop
		}
		instancesByPropID[defn.PropertyID] = append(instancesByPropID[defn.PropertyID], inst)
	}

	routeCache := make(map[uuid.UUID]*routeInfo)
	if q.Lat != 0 || q.Lng != 0 {
		for propID := range instancesByPropID {
			prop, _ := propsCache[propID]
			if prop == nil {
				continue
			}
			var distMiles float64
			var travelMins *int
			if s.cfg.LDFlag_UseGMapsRoutesAPI && s.cfg.GMapsRoutesAPIKey != "" {
				dMiles, dMins, gErr := internal_utils.ComputeDriveDistanceTimeMiles(q.Lat, q.Lng, prop.Latitude, prop.Longitude, s.cfg.GMapsRoutesAPIKey)
				if gErr == nil {
					distMiles = dMiles
					travelMins = &dMins
				}
			}
			if travelMins == nil {
				distMiles = internal_utils.DistanceMiles(q.Lat, q.Lng, prop.Latitude, prop.Longitude)
				estMins := int(distMiles * constants.CrowFliesDriveTimeMultiplier)
				travelMins = &estMins
			}
			routeCache[propID] = &routeInfo{
				DistanceMiles: distMiles,
				TravelMinutes: travelMins,
			}
		}
	}

	var dtosList []dtos.JobInstanceDTO
	for propID, instancesInGroup := range instancesByPropID {
		route := routeCache[propID]
		for _, inst := range instancesInGroup {
			dto, err := s.buildInstanceDTO(ctx, inst, route, workerLoc)
			if err == nil && dto != nil {
				dtosList = append(dtosList, *dto)
			}
		}
	}

	// --- End of Optimization ---

	sort.Slice(dtosList, func(i, j int) bool {
		if dtosList[i].DistanceMiles < dtosList[j].DistanceMiles {
			return true
		} else if dtosList[i].DistanceMiles > dtosList[j].DistanceMiles {
			return false
		}
		return dtosList[i].ServiceDate < dtosList[j].ServiceDate
	})

	total := len(dtosList)
	startIdx := (q.Page - 1) * q.Size
	if startIdx >= total {
		return &dtos.ListJobsResponse{
			Results: []dtos.JobInstanceDTO{},
			Page:    q.Page,
			Size:    q.Size,
			Total:   total,
		}, nil
	}
	endIdx := min(startIdx+q.Size, total)
	paged := dtosList[startIdx:endIdx]

	return &dtos.ListJobsResponse{
		Results: paged,
		Page:    q.Page,
		Size:    q.Size,
		Total:   total,
	}, nil
}

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

	result, err := s.openai.VerifyPhoto(ctx, photo, unit.UnitNumber)
	if err != nil {
		return nil, err
	}

	status := models.UnitVerificationFailed
	if result.TrashCanPresent && result.NoTrashBagVisible && result.DoorNumberMatches {
		status = models.UnitVerificationVerified
	}

	v, err := s.juvRepo.GetByInstanceAndUnit(ctx, instanceID, unitID)
	if err != nil {
		return nil, err
	}
	if v == nil {
		v = &models.JobUnitVerification{
			ID:            uuid.New(),
			JobInstanceID: instanceID,
			UnitID:        unitID,
			Status:        status,
		}
		if err := s.juvRepo.Create(ctx, v); err != nil {
			return nil, err
		}
	} else {
		v.Status = status
		if _, err := s.juvRepo.UpdateIfVersion(ctx, v, v.RowVersion); err != nil {
			return nil, err
		}
	}

	dto, _ := s.buildInstanceDTO(ctx, inst, nil, nil)
	return dto, nil
}

// ProcessDumpTrip marks verified units as dumped and completes the job if all are dumped.
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

	// Verify location is near one of the dumpsters
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
		return nil, internal_utils.ErrLocationOutOfBounds
	}

	verifs, err := s.juvRepo.ListByInstanceID(ctx, inst.ID)
	if err != nil {
		return nil, err
	}
	for _, v := range verifs {
		if v.Status == models.UnitVerificationVerified {
			v.Status = models.UnitVerificationDumped
			_, _ = s.juvRepo.UpdateIfVersion(ctx, v, v.RowVersion)
		}
	}

	// check if all units dumped
	total := 0
	dumped := 0
	for _, grp := range defn.AssignedUnitsByBuilding {
		total += len(grp.UnitIDs)
	}
	for _, v := range verifs {
		if v.Status == models.UnitVerificationDumped {
			dumped++
		}
	}

	var updated *models.JobInstance
	if dumped >= total {
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
		updated = inst
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

// ForceReopenNoShow ...
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
	s.ApplyManualSurge(ctx, reopened, defn, constants.SurgeMultiplierStage4)

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

	newDef := &models.JobDefinition{
		ID:                      uuid.New(),
		ManagerID:               pmID,
		PropertyID:              req.PropertyID,
		Title:                   req.Title,
		Description:             req.Description,
		AssignedUnitsByBuilding: req.AssignedUnitsByBuilding,
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

	// Case 1: Canceled before the no-show cutoff.
	if now.Before(noShowTime) {
		acceptanceCutoffTime := noShowTime.Add(-constants.AcceptanceCutoffBeforeNoShow)
		// Nested check: if cancellation is after the acceptance cutoff, it's treated as a late cancellation.
		if now.After(acceptanceCutoffTime) {
			// This is effectively a late cancellation, treated with the same severity as a no-show.
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

			// Apply no-show penalty and always exclude.
			if s.workerRepo != nil {
				_ = s.instRepo.AddExcludedWorker(ctx, cancelled.ID, wUUID)
				_ = s.workerRepo.AdjustWorkerScoreAtomic(ctx, wUUID, constants.WorkerPenaltyNoShow, "CANCEL_IN_PROGRESS_LATE")
			}
			messageBody := fmt.Sprintf(
				"Worker canceled in-progress job after acceptance cutoff time. The job's latest start time was %s. Coverage is likely required.",
				lStart.Format("15:04"),
			)
			NotifyOnCallAgents(
				ctx, prop, defn.ID.String(), "[Escalation] Worker Canceled In-Progress Job (Late)", messageBody,
				s.agentRepo, s.twilioClient, s.sendgridClient,
				s.cfg.LDFlag_TwilioFromPhone, s.cfg.LDFlag_SendgridFromEmail,
				s.cfg.OrganizationName, s.cfg.LDFlag_SendgridSandboxMode,
			)
			dto, _ := s.buildInstanceDTO(ctx, cancelled, nil, nil)
			return dto, nil
		}

		// Revert job to OPEN.
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

		dto, _ := s.buildInstanceDTO(ctx, rev, nil, nil)
		return dto, nil
	}

	// Case 2: Canceled after the no-show cutoff. Job is fully CANCELED.
	// This is treated with the same severity as a no-show.
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

	// Apply no-show penalty and always exclude.
	if s.workerRepo != nil {
		_ = s.instRepo.AddExcludedWorker(ctx, cancelled.ID, wUUID)
		_ = s.workerRepo.AdjustWorkerScoreAtomic(ctx, wUUID, constants.WorkerPenaltyNoShow, "CANCEL_IN_PROGRESS_LATE")
	}

	messageBody := fmt.Sprintf(
		"Worker canceled in-progress job after no-show time. The job's latest start time was %s. Coverage is likely required.",
		lStart.Format("15:04"),
	)
	NotifyOnCallAgents(
		ctx,
		prop,
		defn.ID.String(),
		"[Escalation] Worker Canceled In-Progress Job (Late)",
		messageBody,
		s.agentRepo,
		s.twilioClient,
		s.sendgridClient,
		s.cfg.LDFlag_TwilioFromPhone,
		s.cfg.LDFlag_SendgridFromEmail,
		s.cfg.OrganizationName,
		s.cfg.LDFlag_SendgridSandboxMode,
	)

	dto, _ := s.buildInstanceDTO(ctx, cancelled, nil, nil)
	return dto, nil
}

/*────────────────────────────────────────────────────────────────────────────
  Internal Helpers
───────────────────────────────────────────────────────────────────────────*/

// CalculatePenaltyForUnassign implements the tiered penalty logic for un-assigning or canceling a job.
// All windows are calculated relative to the no-show time.
func CalculatePenaltyForUnassign(now, eStart, noShowTime time.Time) (int, bool) {
	// Highest urgency: past the no-show time.
	if noShowTime.IsZero() || now.After(noShowTime) {
		return constants.WorkerPenaltyLate, true
	}

	timeLeftUntilNoShow := noShowTime.Sub(now)

	// Tiered penalties based on proximity to the no-show time (highest to lowest urgency).
	if timeLeftUntilNoShow < constants.LateUnassignCutoff { // T-90m before no-show
		return constants.WorkerPenaltyLate, true
	}
	if timeLeftUntilNoShow < constants.MidUnassignCutoff { // T-3h before no-show
		return constants.WorkerPenaltyMid, true
	}
	if timeLeftUntilNoShow < constants.EarlyUnassignCutoff { // T-6h before no-show
		return constants.WorkerPenaltyEarly, true
	}
	if timeLeftUntilNoShow < constants.ExclusionWindowStartCutoff { // T-7h before no-show
		return constants.WorkerPenaltyExclusionWindow, true
	}

	// Lower urgency: Not close to no-show, but un-assigning within 24 hours of when the job could start.
	// This only applies if none of the more severe penalties above were triggered.
	if !eStart.IsZero() {
		timeUntilEarliestStart := eStart.Sub(now)
		if timeUntilEarliestStart > 0 && timeUntilEarliestStart < 24*time.Hour {
			return constants.WorkerPenalty24h, false
		}
	}

	// Default: Ample notice given, no penalty.
	return 0, false
}

// computeEffectiveReleaseTimeForBatch calculates the exact time a worker can see
// the next batch of jobs. This is based on a midnight base time, adjusted by a
// tenant boost (-1 hour) and a reliability score delay (0-120 minutes).
// NOTE: Callers must decide which job dates this gate applies to (typically just the "next batch" date).
func (s *JobService) computeEffectiveReleaseTimeForBatch(
	baseTimeForRelease time.Time,
	workerScore int,
	workerTenantPropertyID *uuid.UUID,
	jobPropertyID uuid.UUID,
) time.Time {
	effectiveBase := baseTimeForRelease
	if workerTenantPropertyID != nil && *workerTenantPropertyID == jobPropertyID {
		effectiveBase = effectiveBase.Add(-1 * time.Hour)
	}
	delay := ComputeShadowDelay(workerScore)
	return effectiveBase.Add(delay)
}

func ComputeShadowDelay(score int) time.Duration {
	if score < 0 {
		score = 0
	}
	if score > 100 {
		score = 100
	}
	delayMinutes := 120 * (100 - score) / 100
	return time.Duration(delayMinutes) * time.Minute
}

func (s *JobService) buildInstanceDTO(
	ctx context.Context,
	inst *models.JobInstance,
	route *routeInfo, // Route info is now passed in
	workerLoc *time.Location,
) (*dtos.JobInstanceDTO, error) {
	jdef, err := s.defRepo.GetByID(ctx, inst.DefinitionID)
	if err != nil || jdef == nil {
		return nil, fmt.Errorf("job definition not found")
	}
	prop, err := s.propRepo.GetByID(ctx, jdef.PropertyID)
	if err != nil || prop == nil {
		return nil, fmt.Errorf("property not found")
	}

	var buildings []dtos.BuildingDTO
	var unitDTOs []dtos.UnitVerificationDTO
	if len(jdef.AssignedUnitsByBuilding) > 0 {
		// cache buildings by ID
		bCache := make(map[uuid.UUID]*models.PropertyBuilding)
		// Preload existing verifications
		verifs, _ := s.juvRepo.ListByInstanceID(ctx, inst.ID)
		statusMap := make(map[uuid.UUID]models.UnitVerificationStatus)
		for _, v := range verifs {
			statusMap[v.UnitID] = v.Status
		}

		for _, grp := range jdef.AssignedUnitsByBuilding {
			b, ok := bCache[grp.BuildingID]
			if !ok {
				b, _ = s.bldgRepo.GetByID(ctx, grp.BuildingID)
				if b == nil {
					continue
				}
				bCache[grp.BuildingID] = b
			}

			// build unit set for quick lookup
			uidSet := make(map[uuid.UUID]struct{}, len(grp.UnitIDs))
			for _, uid := range grp.UnitIDs {
				uidSet[uid] = struct{}{}
			}

			units, _ := s.unitRepo.ListByBuildingID(ctx, grp.BuildingID)
			var bUnits []dtos.UnitVerificationDTO
			for _, u := range units {
				if _, ok := uidSet[u.ID]; !ok {
					continue
				}
				st := statusMap[u.ID]
				if st == "" {
					st = models.UnitVerificationPending
				}
				udto := dtos.UnitVerificationDTO{
					UnitID:     u.ID,
					BuildingID: grp.BuildingID,
					UnitNumber: u.UnitNumber,
					Status:     string(st),
				}
				bUnits = append(bUnits, udto)
				unitDTOs = append(unitDTOs, udto)
			}

			buildings = append(buildings, dtos.BuildingDTO{
				BuildingID: b.ID,
				Name:       b.BuildingName,
				Latitude:   b.Latitude,
				Longitude:  b.Longitude,
				Units:      bUnits,
			})
		}
	}

	var dumpsters []dtos.DumpsterDTO
	if len(jdef.DumpsterIDs) > 0 {
		all, err := s.dumpRepo.ListByPropertyID(ctx, prop.ID)
		if err != nil {
			return nil, err
		}
		include := make(map[uuid.UUID]struct{}, len(jdef.DumpsterIDs))
		for _, id := range jdef.DumpsterIDs {
			include[id] = struct{}{}
		}
		for _, d := range all {
			if _, ok := include[d.ID]; ok {
				dumpsters = append(dumpsters, dtos.DumpsterDTO{
					DumpsterID: d.ID,
					Number:     d.DumpsterNumber,
					Latitude:   d.Latitude,
					Longitude:  d.Longitude,
				})
			}
		}
	}

	var distMiles float64
	var travelMins *int
	if route != nil {
		distMiles = route.DistanceMiles
		travelMins = route.TravelMinutes
	}

	propLoc := loadPropertyLocation(prop.TimeZone)

	// -- TIME WINDOW FIX ---
	// 1. Combine the service date with the time-of-day values, explicitly in the property's timezone.
	serviceDate := inst.ServiceDate
	earliestStartLocal := time.Date(serviceDate.Year(), serviceDate.Month(), serviceDate.Day(), jdef.EarliestStartTime.Hour(), jdef.EarliestStartTime.Minute(), 0, 0, propLoc)
	latestStartLocal := time.Date(serviceDate.Year(), serviceDate.Month(), serviceDate.Day(), jdef.LatestStartTime.Hour(), jdef.LatestStartTime.Minute(), 0, 0, propLoc)
	hintLocal := time.Date(serviceDate.Year(), serviceDate.Month(), serviceDate.Day(), jdef.StartTimeHint.Hour(), jdef.StartTimeHint.Minute(), 0, 0, propLoc)
	noShowCutoffLocal := latestStartLocal.Add(-constants.NoShowCutoffBeforeLatestStart)

	// 2. Format these correct absolute times for the different display timezones.
	pwws := formatTimeInLocation(earliestStartLocal, propLoc)
	pwwe := formatTimeInLocation(noShowCutoffLocal, propLoc)
	sthProp := formatTimeInLocation(hintLocal, propLoc)

	var sthWorker, wws, wwe string
	if workerLoc != nil {
		sthWorker = formatTimeInLocation(hintLocal, workerLoc)
		wws = formatTimeInLocation(earliestStartLocal, workerLoc)
		wwe = formatTimeInLocation(noShowCutoffLocal, workerLoc)
	}

	effectivePay := inst.EffectivePay
	estimatedTimeMins := MinJobTimeEstimateInt
	dailyEstimate := jdef.GetDailyEstimate(inst.ServiceDate.Weekday())
	if dailyEstimate != nil {
		estimatedTimeMins = dailyEstimate.EstimatedTimeMinutes
	}

	dto := &dtos.JobInstanceDTO{
		InstanceID:   inst.ID,
		DefinitionID: inst.DefinitionID,
		PropertyID:   prop.ID,
		ServiceDate:  inst.ServiceDate.Format("2006-01-02"),
		Status:       string(inst.Status),
		Pay:          effectivePay,
		Property: dtos.PropertyDTO{
			PropertyID:   prop.ID,
			PropertyName: prop.PropertyName,
			Address:      prop.Address,
			City:         prop.City,
			State:        prop.State,
			ZipCode:      prop.ZipCode,
			Latitude:     prop.Latitude,
			Longitude:    prop.Longitude,
		},
		NumberOfBuildings:          len(buildings),
		Buildings:                  buildings,
		NumberOfDumpsters:          len(dumpsters),
		Dumpsters:                  dumpsters,
		UnitVerifications:          unitDTOs,
		StartTimeHint:              sthProp,
		WorkerStartTimeHint:        sthWorker,
		PropertyServiceWindowStart: pwws,
		WorkerServiceWindowStart:   wws,
		PropertyServiceWindowEnd:   pwwe,
		WorkerServiceWindowEnd:     wwe,
		DistanceMiles:              distMiles,
		TravelMinutes:              travelMins,
		EstimatedTimeMinutes:       estimatedTimeMins,
		CheckInAt:                  inst.CheckInAt,
	}

	return dto, nil
}

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

func (s *JobService) lookupTenantPropertyID(ctx context.Context, token string) (*uuid.UUID, error) {
	unit, err := s.unitRepo.FindByTenantToken(ctx, token)
	if err != nil {
		return nil, err
	}
	if unit == nil {
		return nil, nil
	}
	return &unit.PropertyID, nil
}

func (s *JobService) applyCompletionTimeEma(ctx context.Context, defID uuid.UUID, dayOfWeek time.Weekday, actualMins int) error {
	return s.defRepo.UpdateWithRetry(ctx, defID, func(d *models.JobDefinition) error {
		dailyEstimate := d.GetDailyEstimate(dayOfWeek)
		if dailyEstimate == nil {
			utils.Logger.Warnf("applyCompletionTimeEma: No daily estimate found for job_definition_id=%s, day_of_week=%s. Cannot update EMA.", d.ID, dayOfWeek)
			return fmt.Errorf("no daily estimate found for day %s in job definition %s", dayOfWeek, d.ID)
		}

		oldEstimateFloat := float64(dailyEstimate.EstimatedTimeMinutes)
		actualMinsFloat := float64(actualMins)

		if oldEstimateFloat < MinJobTimeEstimateFloat {
			oldEstimateFloat = MinJobTimeEstimateFloat
		}

		clippedActualMinsFloat := actualMinsFloat
		relativeLowerBound := oldEstimateFloat * JobTimeEMAMinClipPercent
		relativeUpperBound := oldEstimateFloat * JobTimeEMAMaxClipPercent

		if clippedActualMinsFloat < relativeLowerBound {
			clippedActualMinsFloat = relativeLowerBound
		}
		if clippedActualMinsFloat > relativeUpperBound {
			clippedActualMinsFloat = relativeUpperBound
		}

		if clippedActualMinsFloat < MinJobTimeEstimateFloat {
			clippedActualMinsFloat = MinJobTimeEstimateFloat
		}

		diff := clippedActualMinsFloat - oldEstimateFloat
		newEstimate := oldEstimateFloat + jobTimeEmaAlpha*diff
		newEstimateInt := max(int(math.Round(newEstimate)), MinJobTimeEstimateInt)

		// Also update base_pay proportionally
		initialBasePay := dailyEstimate.InitialBasePay
		initialEstTime := float64(dailyEstimate.InitialEstimatedTimeMinutes)
		if initialEstTime <= 0 {
			initialEstTime = MinJobTimeEstimateFloat
		}

		proportionalPay := (float64(newEstimateInt) / initialEstTime) * initialBasePay
		newBasePay := math.Round(proportionalPay*100) / 100 // round to 2 decimal places

		// Update the values on the definition object
		dailyEstimate.EstimatedTimeMinutes = newEstimateInt
		dailyEstimate.BasePay = newBasePay
		return nil
	})
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

// isJobReleasedToWorker checks if a potentially gated job is visible to a worker.
// Ungated jobs (service date before the standard "next batch" day) are always visible.
// Gated jobs (on or after "next batch" day) are visible only if the current time
// is after their calculated release time, which depends on worker score and tenancy.
func (s *JobService) isJobReleasedToWorker(
	inst *models.JobInstance,
	prop *models.Property,
	propNow time.Time,
	baseMidnightForProp time.Time,
	workerScore int,
	workerTenantPropertyID *uuid.UUID,
) bool {
	// Ungated jobs are always released.
	// Ungated means service date is before the standard "next batch" date.
	// DaysToListOpenJobsRange is 8, so standard release is for jobs on day_of_prop_today + 6.
	standardReleaseDate := baseMidnightForProp.AddDate(0, 0, constants.DaysToListOpenJobsRange-2)

	// Compare dates without regard to time or timezone.
	// This corrects the bug where a UTC date was compared to a local date.
	inst_y, inst_m, inst_d := inst.ServiceDate.Date()
	std_y, std_m, std_d := standardReleaseDate.Date()

	isBefore := inst_y < std_y ||
		(inst_y == std_y && inst_m < std_m) ||
		(inst_y == std_y && inst_m == std_m && inst_d < std_d)

	if isBefore {
		// The job's calendar date is before the release calendar date, so it's always visible.
		return true
	}

	// This is a "gated" job. Check if it's released for this worker.
	// The release of a batch is tied to the midnight that is 6 days *before* its service date.
	// e.g., the batch for today+6 is released relative to today's midnight.
	// The batch for today+7 is released relative to today+1's midnight.
	// --- BUGFIX: Use math.Round for a robust day calculation ---
	// The original int(...) truncation could cause off-by-one errors due to floating point inaccuracies
	// when calculating durations across timezones or DST changes.
	durationHours := inst.ServiceDate.Truncate(24 * time.Hour).Sub(baseMidnightForProp.Truncate(24 * time.Hour)).Hours()
	daysAhead := int(math.Round(durationHours / 24.0))

	baseDateForReleaseCalc := baseMidnightForProp.AddDate(0, 0, daysAhead-(constants.DaysToListOpenJobsRange-2))

	effectiveReleaseT := s.computeEffectiveReleaseTimeForBatch(baseDateForReleaseCalc, workerScore, workerTenantPropertyID, prop.ID)

	return !propNow.Before(effectiveReleaseT)
}
