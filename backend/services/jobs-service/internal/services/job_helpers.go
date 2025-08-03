package services

import (
	"context"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/go-models"
	"github.com/poofware/go-utils"
	"github.com/poofware/jobs-service/internal/constants"
	"github.com/poofware/jobs-service/internal/dtos"
)

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
// tenant boost (-1 hour) and a reliability score delay (0-120 minutes).
// NOTE: Callers must decide which job dates this gate applies to (typically just the "next batch" date).
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
		verifMap := make(map[uuid.UUID]*models.JobUnitVerification)
		for _, v := range verifs {
			verifMap[v.UnitID] = v
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
				vf := verifMap[u.ID]
				st := models.UnitVerificationPending
				attempt := int16(0)
				var reasons []string
				permFail := false
				missingCan := false
				if vf != nil {
					st = vf.Status
					attempt = vf.AttemptCount
					reasons = vf.FailureReasons
					permFail = vf.PermanentFailure
					missingCan = vf.MissingTrashCan
				}
				udto := dtos.UnitVerificationDTO{
					UnitID:           u.ID,
					BuildingID:       grp.BuildingID,
					UnitNumber:       u.UnitNumber,
					Status:           string(st),
					AttemptCount:     attempt,
					FailureReasons:   reasons,
					PermanentFailure: permFail,
					MissingTrashCan:  missingCan,
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
