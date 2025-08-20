package services

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/config"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/dtos"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
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
	cfg                    *config.Config
	defRepo                repositories.JobDefinitionRepository
	instRepo               repositories.JobInstanceRepository
	propRepo               repositories.PropertyRepository
	bldgRepo               repositories.PropertyBuildingRepository
	dumpRepo               repositories.DumpsterRepository
	workerRepo             repositories.WorkerRepository
	agentRepo              repositories.AgentRepository
	unitRepo               repositories.UnitRepository
	juvRepo                repositories.JobUnitVerificationRepository
	agentJobCompletionRepo repositories.AgentJobCompletionRepository
	openai                 *OpenAIService
	twilioClient           *twilio.RestClient
	sendgridClient         *sendgrid.Client
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
	ajcRepo repositories.AgentJobCompletionRepository,
	openai *OpenAIService,
	twilioClient *twilio.RestClient,
	sendgridClient *sendgrid.Client,
) *JobService {
	return &JobService{
		cfg:                    cfg,
		defRepo:                defRepo,
		instRepo:               instRepo,
		propRepo:               propRepo,
		bldgRepo:               bldgRepo,
		dumpRepo:               dumpRepo,
		workerRepo:             workerRepo,
		agentRepo:              agentRepo,
		unitRepo:               unitRepo,
		juvRepo:                juvRepo,
		agentJobCompletionRepo: ajcRepo,
		openai:                 openai,
		twilioClient:           twilioClient,
		sendgridClient:         sendgridClient,
	}
}

// ListJobsForPropertyByManager fetches job instances for a specific property,
// ensuring the requesting property manager has ownership.
func (s *JobService) ListJobsForPropertyByManager(
	ctx context.Context,
	pmID string,
	propID uuid.UUID,
) (*dtos.ListJobsPMResponse, error) {
	managerID, err := uuid.Parse(pmID)
	if err != nil {
		return nil, fmt.Errorf("invalid property manager ID format: %w", err)
	}

	// 1. Verify property ownership
	prop, err := s.propRepo.GetByID(ctx, propID)
	if err != nil {
		return nil, fmt.Errorf("could not retrieve property: %w", err)
	}
	if prop == nil {
		return nil, errors.New("property not found")
	}
	if prop.ManagerID != managerID {
		return nil, errors.New("unauthorized: property does not belong to this manager")
	}

	// 2. Get all job definitions for this property
	defs, err := s.defRepo.ListByPropertyID(ctx, propID)
	if err != nil {
		return nil, fmt.Errorf("could not list job definitions for property: %w", err)
	}

	if len(defs) == 0 {
		return &dtos.ListJobsPMResponse{Results: []dtos.JobInstancePMDTO{}, Total: 0}, nil
	}

	defIDs := make([]uuid.UUID, len(defs))
	for i, d := range defs {
		defIDs[i] = d.ID
	}

	// 3. Fetch all instances for these definitions within a wide date range
	now := time.Now().UTC()
	startDate := now.AddDate(0, -3, 0) // 90 days ago
	endDate := now.AddDate(0, 3, 0)    // 90 days from now
	instances, err := s.instRepo.ListInstancesByDefinitionIDs(ctx, defIDs, startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("could not list job instances: %w", err)
	}

	// 4. Build DTOs for the response
	var dtosList []dtos.JobInstancePMDTO
	for _, inst := range instances {
		dto, err := s.buildInstancePMDTO(ctx, inst)
		if err == nil && dto != nil {
			dtosList = append(dtosList, *dto)
		}
	}

	// 5. Return the full, unsorted list (frontend can sort/filter)
	return &dtos.ListJobsPMResponse{
		Results: dtosList,
		Total:   len(dtosList),
	}, nil
}

func (s *JobService) buildInstancePMDTO(
	ctx context.Context,
	inst *models.JobInstance,
) (*dtos.JobInstancePMDTO, error) {
	jdef, err := s.defRepo.GetByID(ctx, inst.DefinitionID)
	if err != nil || jdef == nil {
		return nil, fmt.Errorf("job definition not found for instance %s", inst.ID)
	}
	prop, err := s.propRepo.GetByID(ctx, jdef.PropertyID)
	if err != nil || prop == nil {
		return nil, fmt.Errorf("property not found for definition %s", jdef.ID)
	}

	var buildings []dtos.BuildingDTO
	if len(jdef.AssignedUnitsByBuilding) > 0 {
		allBldgs, bErr := s.bldgRepo.ListByPropertyID(ctx, prop.ID)
		if bErr != nil {
			return nil, bErr
		}
		bldgSet := make(map[uuid.UUID]bool)
		for _, grp := range jdef.AssignedUnitsByBuilding {
			bldgSet[grp.BuildingID] = true
		}
		for _, b := range allBldgs {
			if bldgSet[b.ID] {
				buildings = append(buildings, dtos.BuildingDTO{
					BuildingID: b.ID,
					Name:       b.BuildingName,
					Latitude:   b.Latitude,
					Longitude:  b.Longitude,
				})
			}
		}
	}

	dto := &dtos.JobInstancePMDTO{
		InstanceID:   inst.ID,
		DefinitionID: inst.DefinitionID,
		PropertyID:   prop.ID,
		ServiceDate:  inst.ServiceDate.Format("2006-01-02"),
		Status:       string(inst.Status),
		Property:     dtos.PropertyDTO{PropertyID: prop.ID, PropertyName: prop.PropertyName, Address: prop.Address, City: prop.City, State: prop.State, ZipCode: prop.ZipCode, Latitude: prop.Latitude, Longitude: prop.Longitude},
		Buildings:    buildings,
	}

	return dto, nil
}
