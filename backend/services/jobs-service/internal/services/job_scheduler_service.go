package services

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/go-models"
	"github.com/poofware/go-utils"
	"github.com/poofware/jobs-service/internal/config"
	"github.com/poofware/go-repositories"
)

type JobSchedulerService struct {
	cfg      *config.Config
	defRepo  repositories.JobDefinitionRepository
	instRepo repositories.JobInstanceRepository
	propRepo repositories.PropertyRepository
}

func NewJobSchedulerService(
	cfg *config.Config,
	defRepo repositories.JobDefinitionRepository,
	instRepo repositories.JobInstanceRepository,
	propRepo repositories.PropertyRepository,
) *JobSchedulerService {
	return &JobSchedulerService{
		cfg:     cfg,
		defRepo: defRepo,
		instRepo: instRepo,
		propRepo: propRepo,
	}
}

// RunDailyWindowMaintenance is triggered once per day (around 00:05 UTC).
// It loops over all properties, calculates the local date, 
// and retires old instances from "yesterday local" if open/assigned,
// then ensures day+7 is created, and ensures [today..today+6] are filled.
func (s *JobSchedulerService) RunDailyWindowMaintenance(ctx context.Context) error {
	utils.Logger.Info("Running daily job-service maintenance...")

	props, err := s.propRepo.ListAllProperties(ctx)
	if err != nil {
		return err
	}

	for _, p := range props {
		if p.TimeZone == "" {
			p.TimeZone = "America/Chicago"
		}
		loc, locErr := time.LoadLocation(p.TimeZone)
		if locErr != nil {
			loc = time.FixedZone("fallbackCST", -6*3600)
		}
		localNow := time.Now().In(loc)

		today := DateOnly(localNow)
		yesterday := today.AddDate(0,0,-1)
		// retire old instances from yesterday if they are OPEN or ASSIGNED
		oldStatuses := []models.InstanceStatusType{
			models.InstanceStatusOpen, models.InstanceStatusAssigned,
		}
		if err := s.instRepo.RetireInstancesForDate(ctx, yesterday, oldStatuses); err != nil {
			utils.Logger.WithError(err).Errorf("Failed to retire old instances for property=%s", p.ID)
		}

		// next day is today+7
		dayPlus7 := today.AddDate(0,0,7)

		// list all ACTIVE definitions for this property
		activeDefs, err := s.defRepo.ListByStatus(ctx, models.JobStatusActive)
		if err != nil {
			utils.Logger.WithError(err).Error("Failed to load active defs for daily maintenance")
			continue
		}
		// only keep ones that belong to this property
		var propDefs []*models.JobDefinition
		for _, d := range activeDefs {
			if d.PropertyID == p.ID {
				propDefs = append(propDefs, d)
			}
		}

		// generate day+7 if needed
		for _, d := range propDefs {
			if shouldCreateOnDate(d, dayPlus7) {
				dailyEstimate := d.GetDailyEstimate(dayPlus7.Weekday())
				var initialPay float64
				if dailyEstimate != nil {
					initialPay = dailyEstimate.BasePay
				}

				inst := &models.JobInstance{
					ID:           uuid.New(),
					DefinitionID: d.ID,
					ServiceDate:  dayPlus7,
					Status:       models.InstanceStatusOpen,
					EffectivePay: initialPay,
				}
				_ = s.instRepo.CreateIfNotExists(ctx, inst)
			}
		}

		// fill gaps for [today..today+6]
		for dayOffset := 0; dayOffset <= 6; dayOffset++ {
			day := today.AddDate(0,0,dayOffset)
			for _, d := range propDefs {
				if shouldCreateOnDate(d, day) {
					dailyEstimate := d.GetDailyEstimate(day.Weekday())
					var initialPay float64
					if dailyEstimate != nil {
						initialPay = dailyEstimate.BasePay
					}

					inst := &models.JobInstance{
						ID:           uuid.New(),
						DefinitionID: d.ID,
						ServiceDate:  day,
						Status:       models.InstanceStatusOpen,
						EffectivePay: initialPay,
					}
					_ = s.instRepo.CreateIfNotExists(ctx, inst)
				}
			}
		}
	}

	return nil
}

