package services

import (
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/constants"
)

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

func (s *JobService) isJobReleasedToWorker(
	inst *models.JobInstance,
	prop *models.Property,
	propNow time.Time,
	baseMidnightForProp time.Time,
	workerScore int,
	workerTenantPropertyID *uuid.UUID,
) bool {
	standardReleaseDate := baseMidnightForProp.AddDate(0, 0, constants.DaysToListOpenJobsRange-2)

	instY, instM, instD := inst.ServiceDate.Date()
	stdY, stdM, stdD := standardReleaseDate.Date()

	isBefore := instY < stdY ||
		(instY == stdY && instM < stdM) ||
		(instY == stdY && instM == stdM && instD < stdD)

	if isBefore {
		return true
	}

	durationHours := inst.ServiceDate.Truncate(24 * time.Hour).Sub(baseMidnightForProp.Truncate(24 * time.Hour)).Hours()
	daysAhead := int(math.Round(durationHours / 24.0))

	baseDateForReleaseCalc := baseMidnightForProp.AddDate(0, 0, daysAhead-(constants.DaysToListOpenJobsRange-2))

	effectiveReleaseT := s.computeEffectiveReleaseTimeForBatch(baseDateForReleaseCalc, workerScore, workerTenantPropertyID, prop.ID)

	return !propNow.Before(effectiveReleaseT)
}
