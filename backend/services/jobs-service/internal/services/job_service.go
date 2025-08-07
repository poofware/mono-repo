package services

import (
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/config"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
	"github.com/twilio/twilio-go"
	"github.com/sendgrid/sendgrid-go"
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

