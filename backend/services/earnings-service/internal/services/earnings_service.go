// meta-service/services/earnings-service/internal/services/earnings_service.go

package services

import (
	"context"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/earnings-service/internal/config"
	"github.com/poofware/earnings-service/internal/constants"
	"github.com/poofware/earnings-service/internal/dtos"
	internal_models "github.com/poofware/earnings-service/internal/models"
	internal_repositories "github.com/poofware/earnings-service/internal/repositories"
	internal_utils "github.com/poofware/earnings-service/internal/utils"
	"github.com/poofware/go-models"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
)

const (
	// PayoutStatusCurrent indicates the week is the ongoing, not-yet-payout-eligible week.
	PayoutStatusCurrent = "CURRENT"
)

type EarningsService struct {
	jobInstRepo  repositories.JobInstanceRepository
	payoutRepo   internal_repositories.WorkerPayoutRepository
	defRepo      repositories.JobDefinitionRepository
	propRepo     repositories.PropertyRepository
	payoutSvc    *PayoutService // NEW: Dependency on PayoutService
	cfg          *config.Config
}

func NewEarningsService(cfg *config.Config, jobInstRepo repositories.JobInstanceRepository, payoutRepo internal_repositories.WorkerPayoutRepository, defRepo repositories.JobDefinitionRepository, propRepo repositories.PropertyRepository, payoutSvc *PayoutService) *EarningsService {
	return &EarningsService{
		jobInstRepo: jobInstRepo,
		payoutRepo:  payoutRepo,
		defRepo:     defRepo,
		propRepo:    propRepo,
		payoutSvc:   payoutSvc, // NEW
		cfg:         cfg,
	}
}

// GetEarningsSummary provides a unified view of earnings, adapting to both weekly and daily payout cycles.
func (s *EarningsService) GetEarningsSummary(ctx context.Context, workerIDStr string) (*dtos.EarningsSummaryResponse, error) {
	workerID, err := uuid.Parse(workerIDStr)
	if err != nil {
		return nil, err
	}

	loc, _ := time.LoadLocation(constants.BusinessTimezone)
	nowForLogic := time.Now().In(loc)
	nowForQuery := time.Now().UTC()
	endDate := nowForQuery.AddDate(0, 0, 1)
	startDate := nowForQuery.AddDate(0, 0, -constants.EarningsSummaryDays)

	// 1. Fetch all relevant data.
	completedJobs, err := s.jobInstRepo.ListInstancesByDateRange(ctx, &workerID, []models.InstanceStatusType{models.InstanceStatusCompleted}, startDate, endDate)
	if err != nil {
		return nil, err
	}
	payouts, err := s.payoutRepo.FindForWorkerByDateRange(ctx, workerID, startDate, endDate)
	if err != nil {
		return nil, err
	}

	// --- NEW: Reconcile stale payouts ---
	var reconciledPayouts []*internal_models.WorkerPayout
	for _, p := range payouts {
		// If payout is stuck in PROCESSING for more than 48 hours, poll Stripe for its status.
		if p.Status == internal_models.PayoutStatusProcessing && p.UpdatedAt.Before(time.Now().Add(-48*time.Hour)) {
			reconciled, reconcileErr := s.payoutSvc.ReconcileStalePayout(ctx, p)
			if reconcileErr != nil {
				utils.Logger.WithError(reconcileErr).Warnf("Failed to reconcile stale payout %s", p.ID)
				reconciledPayouts = append(reconciledPayouts, p) // Keep original if reconcile fails
			} else {
				reconciledPayouts = append(reconciledPayouts, reconciled)
			}
		} else {
			reconciledPayouts = append(reconciledPayouts, p)
		}
	}
	// --- End of New Logic ---

	// 2. Group jobs by ID for efficient lookup and calculate initial total.
	jobsByID, twoMonthTotal := s._groupJobsByIDAndCalcTotal(completedJobs)

	// Pre-fetch definitions and properties for efficiency.
	defMap, propMap, err := s._fetchJobMetadata(ctx, completedJobs)
	if err != nil {
		return nil, err
	}

	// 3. Process existing payouts to build the "Earnings History".
	pastWeeksDTOs, processedJobIDs := s._processPaidHistory(reconciledPayouts, jobsByID, defMap, propMap)

	// 4. Build the "Current Period" DTO from all jobs that have NOT been processed in a payout.
	currentPeriodDTO := s._buildCurrentPeriodDTO(completedJobs, processedJobIDs, defMap, propMap, nowForLogic)

	// 5. Sort all past entries from most recent to oldest.
	sort.Slice(pastWeeksDTOs, func(i, j int) bool {
		return pastWeeksDTOs[i].WeekStartDate > pastWeeksDTOs[j].WeekStartDate
	})

	// 6. Conditionally calculate the "Next Payout Date".
	var nextPayoutDate time.Time
	if s.cfg.LDFlag_UseShortPayPeriod {
		nextPayoutDate = nowForLogic.AddDate(0, 0, 1)
	} else {
		currentWeekStartForPayoutCalc := internal_utils.GetPayPeriodStartForDate(nowForLogic)
		nextPayoutDate = currentWeekStartForPayoutCalc.AddDate(0, 0, 8)
	}

	return &dtos.EarningsSummaryResponse{
		TwoMonthTotal:  twoMonthTotal,
		CurrentWeek:    currentPeriodDTO,
		PastWeeks:      pastWeeksDTOs,
		NextPayoutDate: nextPayoutDate.Format("2006-01-02"),
	}, nil
}

func (s *EarningsService) _fetchJobMetadata(ctx context.Context, jobs []*models.JobInstance) (map[uuid.UUID]*models.JobDefinition, map[uuid.UUID]*models.Property, error) {
	defIDs := make(map[uuid.UUID]struct{})
	for _, job := range jobs {
		defIDs[job.DefinitionID] = struct{}{}
	}

	defMap := make(map[uuid.UUID]*models.JobDefinition)
	propIDs := make(map[uuid.UUID]struct{})
	for id := range defIDs {
		def, err := s.defRepo.GetByID(ctx, id)
		if err != nil {
			utils.Logger.WithError(err).Warnf("Could not fetch definition %s", id)
			continue
		}
		if def != nil {
			defMap[id] = def
			propIDs[def.PropertyID] = struct{}{}
		}
	}

	propMap := make(map[uuid.UUID]*models.Property)
	for id := range propIDs {
		prop, err := s.propRepo.GetByID(ctx, id)
		if err != nil {
			utils.Logger.WithError(err).Warnf("Could not fetch property %s", id)
			continue
		}
		if prop != nil {
			propMap[id] = prop
		}
	}

	return defMap, propMap, nil
}

func (s *EarningsService) _groupJobsByIDAndCalcTotal(completedJobs []*models.JobInstance) (map[uuid.UUID]*models.JobInstance, float64) {
	jobsByID := make(map[uuid.UUID]*models.JobInstance, len(completedJobs))
	var total float64
	for _, job := range completedJobs {
		jobsByID[job.ID] = job
		total += job.EffectivePay
	}
	return jobsByID, total
}

func (s *EarningsService) _processPaidHistory(
	payouts []*internal_models.WorkerPayout,
	jobsByID map[uuid.UUID]*models.JobInstance,
	defMap map[uuid.UUID]*models.JobDefinition,
	propMap map[uuid.UUID]*models.Property,
) ([]dtos.WeeklyEarningsDTO, map[uuid.UUID]bool) {
	pastWeeksDTOs := make([]dtos.WeeklyEarningsDTO, 0, len(payouts))
	processedJobIDs := make(map[uuid.UUID]bool)
	jobsByDateForPayout := make(map[time.Time][]*models.JobInstance)

	for _, p := range payouts {
		// Clear map for this payout
		for k := range jobsByDateForPayout {
			delete(jobsByDateForPayout, k)
		}

		// Group jobs for this specific payout by their service date
		for _, jobID := range p.JobInstanceIDs {
			if job, ok := jobsByID[jobID]; ok {
				dateKey := job.ServiceDate.UTC().Truncate(24 * time.Hour)
				jobsByDateForPayout[dateKey] = append(jobsByDateForPayout[dateKey], job)
				processedJobIDs[job.ID] = true
			}
		}

		var dailyBreakdown []dtos.DailyEarningDTO
		var weeklyJobCount int
		for dateKey, jobsForDay := range jobsByDateForPayout {
			var dailyAmount float64
			var completedJobDTOs []dtos.CompletedJobDTO
			for _, job := range jobsForDay {
				dailyAmount += job.EffectivePay
				completedJobDTOs = append(completedJobDTOs, s._jobInstanceToCompletedDTO(job, defMap, propMap))
			}

			dailyBreakdown = append(dailyBreakdown, dtos.DailyEarningDTO{
				Date:        dateKey.Format("2006-01-02"),
				TotalAmount: dailyAmount,
				JobCount:    len(jobsForDay),
				Jobs:        completedJobDTOs,
			})
			weeklyJobCount += len(jobsForDay)
		}
		sort.Slice(dailyBreakdown, func(i, j int) bool {
			return dailyBreakdown[i].Date < dailyBreakdown[j].Date
		})

		var failureReason *string
		var requiresUserAction bool
		if p.Status == internal_models.PayoutStatusFailed && p.LastFailureReason != nil {
			failureReason = p.LastFailureReason
			_, reqUserAction := IsFailureRecoverable(*p.LastFailureReason)
			requiresUserAction = reqUserAction
		}

		pastWeeksDTOs = append(pastWeeksDTOs, dtos.WeeklyEarningsDTO{
			WeekStartDate:      p.WeekStartDate.UTC().Format("2006-01-02"),
			WeekEndDate:        p.WeekEndDate.UTC().Format("2006-01-02"),
			WeeklyTotal:        float64(p.AmountCents) / 100.0,
			JobCount:           weeklyJobCount,
			PayoutStatus:       string(p.Status),
			DailyBreakdown:     dailyBreakdown,
			FailureReason:      failureReason,
			RequiresUserAction: requiresUserAction,
		})
	}
	return pastWeeksDTOs, processedJobIDs
}

func (s *EarningsService) _buildCurrentPeriodDTO(
	allCompletedJobs []*models.JobInstance,
	processedJobIDs map[uuid.UUID]bool,
	defMap map[uuid.UUID]*models.JobDefinition,
	propMap map[uuid.UUID]*models.Property,
	nowForLogic time.Time,
) *dtos.WeeklyEarningsDTO {
	dailyTallies := make(map[time.Time]struct {
		amount float64
		jobs   []dtos.CompletedJobDTO
	})

	var periodTotal float64
	var periodJobCount int

	// This ensures the UI always shows a full 7-day week for the "This Week" section,
	// regardless of whether the pay cycle is daily or weekly.
	currentPeriodStart := internal_utils.GetPayPeriodStartForDate(nowForLogic)
	currentPeriodEnd := currentPeriodStart.AddDate(0, 0, 6)

	for _, job := range allCompletedJobs {
		if processedJobIDs[job.ID] {
			continue // Skip jobs already part of a past payout
		}

		serviceDateOnly := job.ServiceDate.Truncate(24 * time.Hour)
		if serviceDateOnly.Before(currentPeriodStart) || serviceDateOnly.After(currentPeriodEnd) {
			continue // This job is from a past, unpaid week. Ignore it for the "current" total.
		}

		// All remaining jobs are part of the "current" period's earnings.
		periodTotal += job.EffectivePay
		periodJobCount++

		tally := dailyTallies[serviceDateOnly]
		tally.amount += job.EffectivePay
		tally.jobs = append(tally.jobs, s._jobInstanceToCompletedDTO(job, defMap, propMap))
		dailyTallies[serviceDateOnly] = tally
	}

	var dailyBreakdown []dtos.DailyEarningDTO
	for day, tally := range dailyTallies {
		dailyBreakdown = append(dailyBreakdown, dtos.DailyEarningDTO{
			Date:        day.Format("2006-01-02"),
			TotalAmount: tally.amount,
			JobCount:    len(tally.jobs),
			Jobs:        tally.jobs,
		})
	}
	sort.Slice(dailyBreakdown, func(i, j int) bool { return dailyBreakdown[i].Date < dailyBreakdown[j].Date })

	return &dtos.WeeklyEarningsDTO{
		WeekStartDate:  currentPeriodStart.Format("2006-01-02"),
		WeekEndDate:    currentPeriodEnd.Format("2006-01-02"),
		WeeklyTotal:    periodTotal,
		JobCount:       periodJobCount,
		PayoutStatus:   PayoutStatusCurrent,
		DailyBreakdown: dailyBreakdown,
	}
}

func (s *EarningsService) _jobInstanceToCompletedDTO(job *models.JobInstance, defMap map[uuid.UUID]*models.JobDefinition, propMap map[uuid.UUID]*models.Property) dtos.CompletedJobDTO {
	dto := dtos.CompletedJobDTO{
		InstanceID:  job.ID,
		Pay:         job.EffectivePay,
		CompletedAt: job.CheckOutAt,
	}

	if def, ok := defMap[job.DefinitionID]; ok {
		if prop, ok := propMap[def.PropertyID]; ok {
			dto.PropertyName = prop.PropertyName
		}
	}

	if job.CheckInAt != nil && job.CheckOutAt != nil {
		duration := int(job.CheckOutAt.Sub(*job.CheckInAt).Minutes())
		dto.DurationMinutes = &duration
	}

	return dto
}
