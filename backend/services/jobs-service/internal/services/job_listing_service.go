package services

import (
	"context"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/go-models"
	"github.com/poofware/jobs-service/internal/constants"
	"github.com/poofware/jobs-service/internal/dtos"
	internal_utils "github.com/poofware/jobs-service/internal/utils"
)

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

	// 2. Precompute routes and preload property data once per property.
	routeCache := make(map[uuid.UUID]*routeInfo)
	bldgCache := make(map[uuid.UUID]map[uuid.UUID]*models.PropertyBuilding)
	unitCache := make(map[uuid.UUID]map[uuid.UUID][]*models.Unit)
	dumpCache := make(map[uuid.UUID][]*models.Dumpster)
	for propID := range instancesByPropID {
		prop := propsCache[propID]
		if prop == nil {
			continue
		}

		if q.Lat != 0 || q.Lng != 0 {
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
			routeCache[propID] = &routeInfo{DistanceMiles: distMiles, TravelMinutes: travelMins}
		}

		bldgs, _ := s.bldgRepo.ListByPropertyID(ctx, propID)
		bMap := make(map[uuid.UUID]*models.PropertyBuilding, len(bldgs))
		for _, b := range bldgs {
			bMap[b.ID] = b
		}
		bldgCache[propID] = bMap

		units, _ := s.unitRepo.ListByPropertyID(ctx, propID)
		uMap := make(map[uuid.UUID][]*models.Unit)
		for _, u := range units {
			if u.BuildingID != uuid.Nil {
				uMap[u.BuildingID] = append(uMap[u.BuildingID], u)
			}
		}
		unitCache[propID] = uMap

		dumps, _ := s.dumpRepo.ListByPropertyID(ctx, propID)
		dumpCache[propID] = dumps
	}

	// 3. Build DTOs using the cached data.
	var dtosList []dtos.JobInstanceDTO
	for propID, instancesInGroup := range instancesByPropID {
		route := routeCache[propID]
		if route != nil && route.DistanceMiles > float64(constants.RadiusMiles) {
			continue
		}
		bMap := bldgCache[propID]
		uMap := unitCache[propID]
		dumps := dumpCache[propID]
		prop := propsCache[propID]

		for _, inst := range instancesInGroup {
			defn := propDefs[inst.DefinitionID]
			dto, err := s.buildInstanceDTO(ctx, inst, route, workerLoc, defn, prop, bMap, uMap, dumps)
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
	bldgCache := make(map[uuid.UUID]map[uuid.UUID]*models.PropertyBuilding)
	unitCache := make(map[uuid.UUID]map[uuid.UUID][]*models.Unit)
	dumpCache := make(map[uuid.UUID][]*models.Dumpster)
	for propID := range instancesByPropID {
		prop := propsCache[propID]
		if prop == nil {
			continue
		}
		if q.Lat != 0 || q.Lng != 0 {
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
			routeCache[propID] = &routeInfo{DistanceMiles: distMiles, TravelMinutes: travelMins}
		}

		bldgs, _ := s.bldgRepo.ListByPropertyID(ctx, propID)
		bMap := make(map[uuid.UUID]*models.PropertyBuilding, len(bldgs))
		for _, b := range bldgs {
			bMap[b.ID] = b
		}
		bldgCache[propID] = bMap

		units, _ := s.unitRepo.ListByPropertyID(ctx, propID)
		uMap := make(map[uuid.UUID][]*models.Unit)
		for _, u := range units {
			if u.BuildingID != uuid.Nil {
				uMap[u.BuildingID] = append(uMap[u.BuildingID], u)
			}
		}
		unitCache[propID] = uMap

		dumps, _ := s.dumpRepo.ListByPropertyID(ctx, propID)
		dumpCache[propID] = dumps
	}

	var dtosList []dtos.JobInstanceDTO
	for propID, instancesInGroup := range instancesByPropID {
		route := routeCache[propID]
		bMap := bldgCache[propID]
		uMap := unitCache[propID]
		dumps := dumpCache[propID]
		prop := propsCache[propID]
		for _, inst := range instancesInGroup {
			defn := propDefs[inst.DefinitionID]
			dto, err := s.buildInstanceDTO(ctx, inst, route, workerLoc, defn, prop, bMap, uMap, dumps)
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
