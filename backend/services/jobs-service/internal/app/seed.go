// meta-service/services/jobs-service/internal/app/seed.go

package app

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/poofware/go-models"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
	"github.com/poofware/jobs-service/internal/dtos"
	"github.com/poofware/jobs-service/internal/services"
)

// Helper to check for unique violation error (PostgreSQL specific code)
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

// getPayPeriodStartForDate is a local copy of the earnings-service helper to ensure
// consistent date boundary calculations for seeding.
// The pay period is defined as Monday 4:00 AM to the following Monday 3:59 AM in America/New_York.
func getPayPeriodStartForDate(t time.Time) time.Time {
	loc, _ := time.LoadLocation("America/New_York") // Using the same business timezone as earnings-service

	// Convert the given time `t` into the business timezone.
	timeInLoc := t.In(loc)

	// A "day" for payouts starts at 4:00 AM. We subtract 4 hours to align any
	// time between midnight and 3:59 AM with the previous calendar day for accounting purposes.
	adjustedTime := timeInLoc.Add(-time.Duration(4) * time.Hour)

	// Now, find the Monday of that adjusted day's week.
	weekday := adjustedTime.Weekday()
	daysSinceMonday := (weekday - time.Monday + 7) % 7

	startOfWeek := adjustedTime.AddDate(0, 0, -int(daysSinceMonday))

	// Return the date part only, in UTC to ensure consistency when storing in a DATE field.
	return time.Date(startOfWeek.Year(), startOfWeek.Month(), startOfWeek.Day(), 0, 0, 0, 0, time.UTC)
}

/*
SeedAllTestData ...
*/
func SeedAllTestData(
	ctx context.Context,
	db repositories.DB,
	encryptionKey []byte,
	propRepo repositories.PropertyRepository,
	bldgRepo repositories.PropertyBuildingRepository,
	dumpRepo repositories.DumpsterRepository,
	defRepo repositories.JobDefinitionRepository,
	jobService *services.JobService,
) error {
	sentinelPropID := uuid.MustParse("33333333-3333-3333-3333-333333333333")
	if existing, err := propRepo.GetByID(ctx, sentinelPropID); err != nil {
		return fmt.Errorf("check existing seed property: %w", err)
	} else if existing != nil {
		utils.Logger.Info("jobs-service: seed data already present; skipping seeding")
		return nil
	}

	pmRepo := repositories.NewPropertyManagerRepository(db, encryptionKey)
	workerRepo := repositories.NewWorkerRepository(db, encryptionKey) // NEW: Worker Repo
	unitRepo := repositories.NewUnitRepository(db)
	// instRepo := repositories.NewJobInstanceRepository(db) // For manual seeding -- no longer needed here

	if err := seedDefaultPMIfNeeded(ctx, pmRepo); err != nil {
		return fmt.Errorf("seed default PM if needed: %w", err)
	}

	// NEW: Seed workers before properties and jobs
	if err := seedDefaultWorkersIfNeeded(ctx, workerRepo); err != nil {
		return fmt.Errorf("seed default workers if needed: %w", err)
	}

	propID, err := seedPropertyDataIfNeeded(ctx, propRepo, bldgRepo, dumpRepo, unitRepo)
	if err != nil {
		return fmt.Errorf("seed property data if needed: %w", err)
	}
	if propID == uuid.Nil {
		// This can happen if the property already exists, which is not an error state.
		// We can try to recover the ID to continue seeding jobs.
		propID = uuid.MustParse("33333333-3333-3333-3333-333333333333")
	}

	// Seed the active, ongoing job definitions for the property.
	if _, err := seedJobDefinitionsIfNeeded(ctx, propRepo, bldgRepo, defRepo, jobService, unitRepo, propID); err != nil {
		return fmt.Errorf("seed job definitions if needed: %w", err)
	}

	// NEW: Seed the small 3-unit demo job for Demo Property 1.
	if err := seedSmallDemoJobIfNeeded(ctx, defRepo, bldgRepo, unitRepo, jobService, propRepo, propID); err != nil {
		return fmt.Errorf("seed small demo job if needed: %w", err)
	}

	// Seed the new "The Station at Clift Farm" property and its associated data. [cite: 1929]
	if err := seedCliftFarmPropertyIfNeeded(ctx, propRepo, bldgRepo, dumpRepo, unitRepo, jobService, defRepo); err != nil {
		return fmt.Errorf("seed clift farm property if needed: %w", err)
	}

	// Seed a separate, inactive job definition to be the parent of historical jobs.
	historicalDefID, err := seedHistoricalDefinition(ctx, defRepo, jobService, propID)
	if err != nil {
		return fmt.Errorf("seed historical definition: %w", err)
	}

	// Seed completed job instances for past weeks using the historical definition ID.
	if historicalDefID != uuid.Nil {
		// FIX: Pass the raw `db` handle directly to the seeder function.
		if err := seedPastCompletedInstances(ctx, db, historicalDefID); err != nil {
			return fmt.Errorf("seed past completed instances: %w", err)
		}
	}

	utils.Logger.Info("jobs-service: seeding completed successfully (some or all items).")
	return nil
}

/*
------------------------------------------------------------------
 1. seedDefaultPMIfNeeded

------------------------------------------------------------------
*/
func seedDefaultPMIfNeeded(
	ctx context.Context,
	pmRepo repositories.PropertyManagerRepository,
) error {
	pmID := uuid.MustParse("22222222-2222-2222-2222-222222222222")

	pm := &models.PropertyManager{
		ID:              pmID,
		Email:           "team@thepoofapp.com",
		PhoneNumber:     utils.Ptr("+12565550000"),
		TOTPSecret:      "defaultpmstatusactivestotpsecret",
		BusinessName:    "Demo Property Management",
		BusinessAddress: "30 Gates Mill St NW",
		City:            "Huntsville",
		State:           "AL",
		ZipCode:         "35806",
	}
	if err := pmRepo.Create(ctx, pm); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Infof("jobs-service: PM (id=%s) already exists; skipping creation.", pmID)
			return nil
		}
		return fmt.Errorf("could not create PM (id=%s): %w", pmID, err)
	}

	utils.Logger.Infof("jobs-service: Created default PM (id=%s).", pmID)
	return nil
}

/*
------------------------------------------------------------------

	1.5) seedDefaultWorkersIfNeeded (NEW)

------------------------------------------------------------------
*/
func seedDefaultWorkersIfNeeded(
	ctx context.Context,
	workerRepo repositories.WorkerRepository,
) error {
	defaultWorkerStatusIncompleteID := uuid.MustParse("1d30bfa5-e42f-457e-a21c-6b7e1aaa1111")
	defaultWorkerStatusActiveID := uuid.MustParse("1d30bfa5-e42f-457e-a21c-6b7e1aaa2222")

	// --- Worker 1: INCOMPLETE, at BACKGROUND_CHECK step ---
	wIncomplete := &models.Worker{
		ID:          defaultWorkerStatusIncompleteID,
		Email:       "jlmoors001@gmail.com",
		PhoneNumber: "+15551110000",
		TOTPSecret:  "defaultworkerstatusincompletestotpsecret",
		FirstName:   "DefaultWorker",
		LastName:    "SetupIncomplete",
	}
	if err := workerRepo.Create(ctx, wIncomplete); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Infof("jobs-service: Default Worker (incomplete) already present (id=%s); skipping.", wIncomplete.ID)
		} else {
			return fmt.Errorf("insert default worker (incomplete): %w", err)
		}
	} else {
		utils.Logger.Infof("jobs-service: Created default Worker (incomplete) id=%s, now updating status.", wIncomplete.ID)
		if err := workerRepo.UpdateWithRetry(ctx, wIncomplete.ID, func(stored *models.Worker) error {
			stored.StreetAddress = "123 Default Status Incomplete St"
			stored.City = "SeedCity"
			stored.State = "AL"
			stored.ZipCode = "90000"
			stored.VehicleYear = 2022
			stored.VehicleMake = "Toyota"
			stored.VehicleModel = "Corolla"
			stored.SetupProgress = models.SetupProgressBackgroundCheck
			return nil
		}); err != nil {
			return fmt.Errorf("update default worker (incomplete) status: %w", err)
		}
	}

	// --- Worker 2: ACTIVE, setup DONE ---
	wActive := &models.Worker{
		ID:          defaultWorkerStatusActiveID,
		Email:       "team@thepoofapp.com",
		PhoneNumber: "+15552220000",
		TOTPSecret:  "defaultworkerstatusactivestotpsecretokay",
		FirstName:   "DefaultWorker",
		LastName:    "SetupActive",
	}
	if err := workerRepo.Create(ctx, wActive); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Infof("jobs-service: Default Worker (active) already present (id=%s); skipping.", wActive.ID)
		} else {
			return fmt.Errorf("insert default worker (active): %w", err)
		}
	} else {
		utils.Logger.Infof("jobs-service: Created default Worker (active) id=%s, now updating status.", wActive.ID)
		if err := workerRepo.UpdateWithRetry(ctx, wActive.ID, func(stored *models.Worker) error {
			stored.StreetAddress = "123 Default Status Active St"
			stored.City = "SeedCity"
			stored.State = "AL"
			stored.ZipCode = "90000"
			stored.VehicleYear = 2022
			stored.VehicleMake = "Toyota"
			stored.VehicleModel = "Camry"
			stored.AccountStatus = models.AccountStatusActive
			stored.SetupProgress = models.SetupProgressDone
			stored.StripeConnectAccountID = utils.Ptr("acct_1RZHahCLd3ZjFFWN") // Happy Path Connect ID
			return nil
		}); err != nil {
			return fmt.Errorf("update default worker (active) status: %w", err)
		}
	}
	return nil
}

/*
------------------------------------------------------------------
 2. seedPropertyDataIfNeeded

------------------------------------------------------------------
*/
func seedPropertyDataIfNeeded(
	ctx context.Context,
	propRepo repositories.PropertyRepository,
	bldgRepo repositories.PropertyBuildingRepository,
	dumpRepo repositories.DumpsterRepository,
	unitRepo repositories.UnitRepository,
) (uuid.UUID, error) {
	propID := uuid.MustParse("33333333-3333-3333-3333-333333333333")

	p := &models.Property{
		ID:           propID,
		ManagerID:    uuid.MustParse("22222222-2222-2222-2222-222222222222"),
		PropertyName: "Demo Property 1",
		Address:      "30 Gates Mill St NW",
		City:         "Huntsville",
		State:        "AL",
		ZipCode:      "35806",
		TimeZone:     "America/Chicago",
		Latitude:     34.753042676669004,
		Longitude:    -86.6970825455451,
	}
	if err := propRepo.Create(ctx, p); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Infof("jobs-service: Property (id=%s) already exists; skipping property creation.", propID)
		} else {
			return uuid.Nil, fmt.Errorf("failed to create property id=%s: %w", propID, err)
		}
	} else {
		utils.Logger.Infof("jobs-service: Created property (id=%s).", propID)
	}

	if err := ensureBuildingsAndUnits(ctx, bldgRepo, unitRepo, propID); err != nil {
		return uuid.Nil, err
	}
	if err := ensureDumpster(ctx, dumpRepo, propID); err != nil {
		return uuid.Nil, err
	}
	return propID, nil
}

func ensureBuildingsAndUnits(
	ctx context.Context,
	bldgRepo repositories.PropertyBuildingRepository,
	unitRepo repositories.UnitRepository,
	propID uuid.UUID,
) error {
	bldgs, err := bldgRepo.ListByPropertyID(ctx, propID)
	if err != nil {
		return err
	}
	if len(bldgs) >= 10 {
		utils.Logger.Infof("jobs-service: property (id=%s) already has %d buildings; skipping building creation.", propID, len(bldgs))
		return nil
	}

	type bldgConf struct {
		num int
		lat float64
		lng float64
	}
	list := []bldgConf{
		{0, 34.753042676669004, -86.6970825455451},
		{2, 34.75324101371002, -86.69770750024432},
		{3, 34.753939597063095, -86.69805350520186},
		{4, 34.75339086805018, -86.69827881075558},
		{5, 34.75409165385932, -86.6987025997801},
		{6, 34.75357598186378, -86.69891449428899},
		{7, 34.75424591409042, -86.69926318146175},
		{8, 34.75372803932841, -86.69947507597531},
		{9, 34.75443463669845, -86.69990063042995},
		{10, 34.75390354077383, -86.70011520714777},
	}

	var newBldgs []models.PropertyBuilding
	for _, bc := range list {
		bID := uuid.New()
		newBldgs = append(newBldgs, models.PropertyBuilding{
			ID:           bID,
			PropertyID:   propID,
			BuildingName: fmt.Sprintf("Building %d", bc.num),
			Latitude:     bc.lat,
			Longitude:    bc.lng,
		})
	}
	if err := bldgRepo.CreateMany(ctx, newBldgs); err != nil {
		// Since building IDs are random, this would likely be a foreign key error
		// which we should not ignore.
		return fmt.Errorf("failed to create buildings for prop=%s: %w", propID, err)
	}
	utils.Logger.Infof("jobs-service: Created %d buildings for property (id=%s).", len(newBldgs), propID)

	for idx, b := range newBldgs {
		for u := 1; u <= 30; u++ {
			unitNum := fmt.Sprintf("%d%02d", idx+1, u)
			un := &models.Unit{
				ID:          uuid.New(),
				PropertyID:  propID,
				BuildingID:  b.ID,
				UnitNumber:  unitNum,
				TenantToken: uuid.NewString(),
			}
			if cErr := unitRepo.Create(ctx, un); cErr != nil {
				return fmt.Errorf("create unit %s (bldg=%s) for prop=%s: %w", unitNum, b.BuildingName, propID, cErr)
			}
		}
	}
	utils.Logger.Infof("jobs-service: Created 30 units each for %d new buildings => %d new units total.", len(newBldgs), len(newBldgs)*30)
	return nil
}

func ensureDumpster(
	ctx context.Context,
	dumpRepo repositories.DumpsterRepository,
	propID uuid.UUID,
) error {
	dumpID := uuid.MustParse("44444444-4444-4444-4444-444444444444")

	d := &models.Dumpster{
		ID:             dumpID,
		PropertyID:     propID,
		DumpsterNumber: "1",
		Latitude:       34.75475287521528,
		Longitude:      -86.70042641169896,
	}
	if err := dumpRepo.Create(ctx, d); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Infof("jobs-service: Dumpster (id=%s) for property (id=%s) already exists; skipping creation.", dumpID, propID)
			return nil
		}
		return fmt.Errorf("create dumpster id=%s for prop=%s: %w", dumpID, propID, err)
	}

	utils.Logger.Infof("jobs-service: Created dumpster (id=%s) for property (id=%s).", dumpID, propID)
	return nil
}

// buildAssignedUnitGroups returns groups of unit IDs per building. If floor>0,
// only units on that floor are included. Units are generated with sequential
// numbers 01-30, so floors are derived by position: 1-10 => floor 1, 11-20 =>
// floor 2, 21-30 => floor 3.
// If maxUnits>0, the total number of units returned across all buildings is
// limited to maxUnits.

// buildAssignedUnitChunks retrieves units for the given building IDs and breaks
// them into slices where each slice contains at most maxUnits unit IDs total.
// Each returned slice represents units for a single job definition.
func buildAssignedUnitChunks(
	ctx context.Context,
	unitRepo repositories.UnitRepository,
	bldgIDs []uuid.UUID,
	floor int,
	maxUnits int,
) ([][]models.AssignedUnitGroup, error) {
	if maxUnits <= 0 {
		return nil, fmt.Errorf("maxUnits must be positive")
	}

	var all []*models.Unit
	for _, bID := range bldgIDs {
		units, err := unitRepo.ListByBuildingID(ctx, bID)
		if err != nil {
			return nil, err
		}
		for _, u := range units {
			num, _ := strconv.Atoi(u.UnitNumber)
			idx := num % 100
			fl := (idx-1)/10 + 1
			if floor == 0 || fl == floor {
				all = append(all, u)
			}
		}
	}

	var result [][]models.AssignedUnitGroup
	for i := 0; i < len(all); i += maxUnits {
		end := i + maxUnits
		if end > len(all) {
			end = len(all)
		}

		type grpInfo struct {
			ids    []uuid.UUID
			floors map[int16]struct{}
		}
		groupMap := map[uuid.UUID]*grpInfo{}
		for _, u := range all[i:end] {
			num, _ := strconv.Atoi(u.UnitNumber)
			idx := num % 100
			fl := int16((idx-1)/10 + 1)

			gi, ok := groupMap[u.BuildingID]
			if !ok {
				gi = &grpInfo{floors: make(map[int16]struct{})}
				groupMap[u.BuildingID] = gi
			}
			gi.ids = append(gi.ids, u.ID)
			gi.floors[fl] = struct{}{}
		}

		var groups []models.AssignedUnitGroup
		for bID, gi := range groupMap {
			floors := make([]int16, 0, len(gi.floors))
			for f := range gi.floors {
				floors = append(floors, f)
			}
			sort.Slice(floors, func(i, j int) bool { return floors[i] < floors[j] })
			groups = append(groups, models.AssignedUnitGroup{BuildingID: bID, UnitIDs: gi.ids, Floors: floors})
		}
		result = append(result, groups)
	}
	return result, nil
}

/*
	------------------------------------------------------------------
	  3) seedJobDefinitionsIfNeeded

------------------------------------------------------------------
*/
func seedJobDefinitionsIfNeeded(
	ctx context.Context,
	propRepo repositories.PropertyRepository,
	bldgRepo repositories.PropertyBuildingRepository,
	defRepo repositories.JobDefinitionRepository,
	jobSvc *services.JobService,
	unitRepo repositories.UnitRepository,
	propID uuid.UUID,
) (uuid.UUID, error) {
	// First, fetch the property to get its timezone for seeding.
	prop, err := propRepo.GetByID(ctx, propID)
	if err != nil || prop == nil {
		return uuid.Nil, fmt.Errorf("could not fetch property %s for timezone info: %w", propID, err)
	}
	timeZone := prop.TimeZone
	dumpsterID := uuid.MustParse("44444444-4444-4444-4444-444444444444")

	existingDefs, err := defRepo.ListByPropertyID(ctx, propID)
	if err != nil {
		return uuid.Nil, err
	}

	titles := map[string]uuid.UUID{}
	for _, d := range existingDefs {
		titles[d.Title] = d.ID
	}

	allBldgs, err := bldgRepo.ListByPropertyID(ctx, propID)
	if err != nil {
		return uuid.Nil, err
	}

	var defID uuid.UUID
	for _, bldg := range allBldgs {
		num, err := strconv.Atoi(strings.TrimPrefix(bldg.BuildingName, "Building "))
		if err != nil {
			utils.Logger.Warnf("Could not parse building number from name: %s", bldg.BuildingName)
			continue
		}

		for floor := 1; floor <= 3; floor++ {
			title := fmt.Sprintf("Service Building %d Floor %d", num, floor)
			if existingID, ok := titles[title]; ok {
				utils.Logger.Infof("jobs-service: JobDefinition '%s' already exists; skipping.", title)
				if defID == uuid.Nil {
					defID = existingID
				}
				continue
			}

			createdID, err := createDailyDefinition(ctx, jobSvc, propID, title, []uuid.UUID{bldg.ID}, timeZone, dumpsterID, unitRepo, floor)
			if err != nil {
				return uuid.Nil, err
			}
			if defID == uuid.Nil {
				defID = createdID
			}
		}
	}

	return defID, nil
}

/*
------------------------------------------------------------------
  NEW) seedSmallDemoJobIfNeeded
------------------------------------------------------------------
*/
// seedSmallDemoJobIfNeeded creates a small, specific job for demonstration purposes.
func seedSmallDemoJobIfNeeded(
	ctx context.Context,
	defRepo repositories.JobDefinitionRepository,
	bldgRepo repositories.PropertyBuildingRepository,
	unitRepo repositories.UnitRepository,
	jobSvc *services.JobService,
	propRepo repositories.PropertyRepository,
	propID uuid.UUID,
) error {
	title := "Small Demo Job (Bldg 0, Fl 2)"

	// 1. Check if it already exists to make seeding idempotent.
	existingDefs, err := defRepo.ListByPropertyID(ctx, propID)
	if err != nil {
		return fmt.Errorf("listing definitions for prop %s: %w", propID, err)
	}
	for _, d := range existingDefs {
		if d.Title == title {
			utils.Logger.Infof("jobs-service: Small demo job definition '%s' already exists; skipping.", title)
			return nil
		}
	}

	// 2. Find Building 0.
	allBldgs, err := bldgRepo.ListByPropertyID(ctx, propID)
	if err != nil {
		return fmt.Errorf("listing buildings for prop %s: %w", propID, err)
	}

	var bldg0 *models.PropertyBuilding
	for _, b := range allBldgs {
		if b.BuildingName == "Building 0" {
			bldg0 = b
			break
		}
	}
	if bldg0 == nil {
		utils.Logger.Warnf("jobs-service: Could not find 'Building 0' for prop %s to seed small demo job. Skipping.", propID)
		return nil // Not an error, just can't proceed.
	}

	// 3. Find units 115, 116, 117 within that building.
	bldgUnits, err := unitRepo.ListByBuildingID(ctx, bldg0.ID)
	if err != nil {
		return fmt.Errorf("listing units for building %s: %w", bldg0.ID, err)
	}

	var targetUnitIDs []uuid.UUID
	targetUnitNumbers := map[string]bool{"115": true, "116": true, "117": true}
	for _, u := range bldgUnits {
		if _, ok := targetUnitNumbers[u.UnitNumber]; ok {
			targetUnitIDs = append(targetUnitIDs, u.ID)
		}
	}

	if len(targetUnitIDs) != 3 {
		utils.Logger.Warnf("jobs-service: Did not find all required units (115, 116, 117) for 'Building 0' on prop %s. Found %d. Skipping small demo job.", propID, len(targetUnitIDs))
		return nil
	}

	// 4. Construct the job definition request.
	assignedGroup := []models.AssignedUnitGroup{
		{
			BuildingID: bldg0.ID,
			UnitIDs:    targetUnitIDs,
			Floors:     []int16{2},
		},
	}

	prop, err := propRepo.GetByID(ctx, propID)
	if err != nil || prop == nil {
		return fmt.Errorf("could not fetch property %s for timezone info: %w", propID, err)
	}
	timeZone := prop.TimeZone
	dumpsterID := uuid.MustParse("44444444-4444-4444-4444-444444444444") // Dumpster for Demo Property 1
	pmID := uuid.MustParse("22222222-2222-2222-2222-222222222222")

	loc, err := time.LoadLocation(timeZone)
	if err != nil {
		loc = time.UTC
	}
	earliest := time.Date(0, 1, 1, 0, 0, 0, 0, loc)
	latest := earliest.Add(23*time.Hour + 59*time.Minute)

	dailyEstimates := make([]dtos.DailyPayEstimateRequest, 7)
	for i := range 7 {
		dailyEstimates[i] = dtos.DailyPayEstimateRequest{
			DayOfWeek:            i,
			BasePay:              5.00, // smaller job, smaller pay
			EstimatedTimeMinutes: 10,
		}
	}

	req := dtos.CreateJobDefinitionRequest{
		PropertyID:              propID,
		Title:                   title,
		Description:             utils.Ptr("A small, specific demo job with only 3 units."),
		AssignedUnitsByBuilding: assignedGroup,
		DumpsterIDs:             []uuid.UUID{dumpsterID},
		Frequency:               models.JobFreqDaily,
		StartDate:               time.Now().UTC().AddDate(0, 0, -1),
		EarliestStartTime:       earliest,
		LatestStartTime:         latest,
		SkipHolidays:            false,
		DailyPayEstimates:       dailyEstimates,
		CompletionRules: &models.JobCompletionRules{
			ProofPhotosRequired: true,
		},
	}

	// 5. Create the job definition.
	defID, err := jobSvc.CreateJobDefinition(ctx, pmID.String(), req, "ACTIVE")
	if err != nil {
		return fmt.Errorf("failed to create small demo job definition '%s' for prop=%s: %w", title, propID, err)
	}

	utils.Logger.Infof("jobs-service: Created small demo job definition '%s' (id=%s).", title, defID)
	return nil
}

// createDailyDefinition now seeds earliest_start_time=00:00, latest=23:59 => "all day long"
// It also seeds DailyPayEstimates for all 7 days of the week.
func createDailyDefinition(
	ctx context.Context,
	jobSvc *services.JobService,
	propID uuid.UUID,
	title string,
	assignedBuildingIDs []uuid.UUID,
	timeZone string, // <-- NEW
	dumpsterID uuid.UUID, // <-- NEW
	unitRepo repositories.UnitRepository,
	floor int,
) (uuid.UUID, error) {
	loc, err := time.LoadLocation(timeZone)
	if err != nil {
		utils.Logger.Warnf("Invalid timezone '%s', falling back to UTC for job def '%s'", timeZone, title)
		loc = time.UTC
	}

	// A dummy date is used because the DB column is TIME-only. Year/Month/Day are ignored,
	// but the Location is preserved.
	earliest := time.Date(0, 1, 1, 0, 0, 0, 0, loc)
	latest := earliest.Add(23*time.Hour + 59*time.Minute)

	// Seed DailyPayEstimates - for a DAILY job, we need all 7 days.
	// Adjust pay/time slightly for Monday/Wednesday for demonstration.
	dailyEstimates := make([]dtos.DailyPayEstimateRequest, 7)
	basePay := 22.50
	baseTime := 60

	for i := range 7 {
		day := time.Weekday(i)
		currentPay := basePay
		currentTime := baseTime
		if day == time.Monday { // After weekend
			currentPay = basePay * 1.1                  // 10% more pay
			currentTime = int(float64(baseTime) * 1.15) // 15% more time
		} else if day == time.Wednesday { // Mid-week
			currentPay = basePay * 1.05                // 5% more pay
			currentTime = int(float64(baseTime) * 1.1) // 10% more time
		}
		dailyEstimates[i] = dtos.DailyPayEstimateRequest{
			DayOfWeek:            int(day),
			BasePay:              currentPay,
			EstimatedTimeMinutes: currentTime,
		}
	}

	chunks, err := buildAssignedUnitChunks(ctx, unitRepo, assignedBuildingIDs, floor, 20)
	if err != nil {
		return uuid.Nil, err
	}

	pmID := uuid.MustParse("22222222-2222-2222-2222-222222222222")

	var firstID uuid.UUID
	for i, groups := range chunks {
		t := title
		if len(chunks) > 1 {
			t = fmt.Sprintf("%s Part %d", title, i+1)
		}
		req := dtos.CreateJobDefinitionRequest{
			PropertyID:              propID,
			Title:                   t,
			Description:             utils.Ptr("automatic seed job"),
			AssignedUnitsByBuilding: groups,
			DumpsterIDs:             []uuid.UUID{dumpsterID},
			Frequency:               models.JobFreqDaily,
			// Set StartDate to "yesterday" in UTC to avoid time-zone
			// off-by-one issues when seeding job instances. This ensures
			// today's instance is eligible even if seeding occurs after
			// a job's local cutoff time.
			StartDate:         time.Now().UTC().AddDate(0, 0, -1),
			EarliestStartTime: earliest,
			LatestStartTime:   latest,
			SkipHolidays:      false,
			DailyPayEstimates: dailyEstimates,
			CompletionRules: &models.JobCompletionRules{
				ProofPhotosRequired: true,
			},
		}
		defID, err := jobSvc.CreateJobDefinition(ctx, pmID.String(), req, "ACTIVE")
		if err != nil {
			return uuid.Nil, fmt.Errorf("failed to create job definition '%s' for prop=%s: %w", t, propID, err)
		}
		utils.Logger.Infof("jobs-service: Created job definition '%s' (id=%s).", t, defID)
		if firstID == uuid.Nil {
			firstID = defID
		}
	}
	return firstID, nil
}

// createRealisticTimeWindowDefinition seeds a job with a specific local time window (e.g., 6 AM - 9 AM).
func createRealisticTimeWindowDefinition(
	ctx context.Context,
	jobSvc *services.JobService,
	propID uuid.UUID,
	title string,
	assignedBuildingIDs []uuid.UUID,
	startHour, endHour int,
	timeZone string, // <-- NEW
	dumpsterID uuid.UUID, // <-- NEW
	unitRepo repositories.UnitRepository,
	floor int,
) (uuid.UUID, error) {
	loc, err := time.LoadLocation(timeZone)
	if err != nil {
		utils.Logger.Warnf("Invalid timezone '%s', falling back to UTC for job def '%s'", timeZone, title)
		loc = time.UTC
	}

	// A dummy date is used because the DB column is TIME-only. Year/Month/Day are ignored.
	// We now use the property's local timezone.
	earliest := time.Date(0, 1, 1, startHour, 0, 0, 0, loc)
	latest := time.Date(0, 1, 1, endHour, 0, 0, 0, loc)

	// Seed DailyPayEstimates - for a DAILY job, we need all 7 days.
	// Adjust pay/time slightly for Monday/Wednesday for demonstration.
	dailyEstimates := make([]dtos.DailyPayEstimateRequest, 7)
	basePay := 22.50
	baseTime := 60

	for i := range 7 {
		day := time.Weekday(i)
		currentPay := basePay
		currentTime := baseTime
		if day == time.Monday { // After weekend
			currentPay = basePay * 1.1                  // 10% more pay
			currentTime = int(float64(baseTime) * 1.15) // 15% more time
		} else if day == time.Wednesday { // Mid-week
			currentPay = basePay * 1.05                // 5% more pay
			currentTime = int(float64(baseTime) * 1.1) // 10% more time
		}
		dailyEstimates[i] = dtos.DailyPayEstimateRequest{
			DayOfWeek:            int(day),
			BasePay:              currentPay,
			EstimatedTimeMinutes: currentTime,
		}
	}

	chunks, err := buildAssignedUnitChunks(ctx, unitRepo, assignedBuildingIDs, floor, 20)
	if err != nil {
		return uuid.Nil, err
	}

	pmID := uuid.MustParse("22222222-2222-2222-2222-222222222222")
	var firstID uuid.UUID
	for i, groups := range chunks {
		t := title
		if len(chunks) > 1 {
			t = fmt.Sprintf("%s Part %d", title, i+1)
		}
		req := dtos.CreateJobDefinitionRequest{
			PropertyID:              propID,
			Title:                   t,
			Description:             utils.Ptr("automatic seed job with realistic time window"),
			AssignedUnitsByBuilding: groups,
			DumpsterIDs:             []uuid.UUID{dumpsterID},
			Frequency:               models.JobFreqDaily,
			// Use "yesterday" in UTC to guarantee the seeding logic
			// creates a full 7-day window of instances regardless of
			// when the backend boots relative to local cutoff times.
			StartDate:         time.Now().UTC().AddDate(0, 0, -1),
			EarliestStartTime: earliest,
			LatestStartTime:   latest,
			SkipHolidays:      false,
			DailyPayEstimates: dailyEstimates,
			CompletionRules: &models.JobCompletionRules{
				ProofPhotosRequired: true,
			},
		}
		defID, err := jobSvc.CreateJobDefinition(ctx, pmID.String(), req, "ACTIVE")
		if err != nil {
			return uuid.Nil, fmt.Errorf("failed to create job definition '%s' for prop=%s: %w", t, propID, err)
		}
		utils.Logger.Infof("jobs-service: Created job definition '%s' (id=%s) with realistic window.", t, defID)
		if firstID == uuid.Nil {
			firstID = defID
		}
	}
	return firstID, nil
}

/*
	------------------------------------------------------------------
	  4) seedHistoricalDefinition
------------------------------------------------------------------
*/
// seedHistoricalDefinition creates a special, inactive job definition to house historical job instances.
// This separates historical data from the active, ongoing job definitions.
func seedHistoricalDefinition(
	ctx context.Context,
	defRepo repositories.JobDefinitionRepository,
	jobSvc *services.JobService,
	propID uuid.UUID,
) (uuid.UUID, error) {
	title := "Legacy Valet Trash (Historical)"

	// 1. Check if it already exists to make seeding idempotent.
	existingDefs, err := defRepo.ListByPropertyID(ctx, propID)
	if err != nil {
		return uuid.Nil, fmt.Errorf("listing definitions for prop %s: %w", propID, err)
	}
	for _, d := range existingDefs {
		if d.Title == title {
			utils.Logger.Infof("jobs-service: Historical job definition '%s' already exists; skipping.", title)
			return d.ID, nil
		}
	}

	// 2. If not, create it.
	// For historical data, using UTC is acceptable as it's not for live display.
	loc := time.UTC
	earliest := time.Date(0, 1, 1, 0, 0, 0, 0, loc)
	latest := earliest.Add(23*time.Hour + 59*time.Minute)
	dumpID := uuid.MustParse("44444444-4444-4444-4444-444444444444")

	// Use a simple, flat pay rate for all days for this historical job.
	dailyEstimates := make([]dtos.DailyPayEstimateRequest, 7)
	for i := range 7 {
		dailyEstimates[i] = dtos.DailyPayEstimateRequest{
			DayOfWeek:            i,
			BasePay:              20.00,
			EstimatedTimeMinutes: 50,
		}
	}

	req := dtos.CreateJobDefinitionRequest{
		PropertyID:              propID,
		Title:                   title,
		Description:             utils.Ptr("Historical job data for demonstration purposes."),
		AssignedUnitsByBuilding: []models.AssignedUnitGroup{},
		DumpsterIDs:             []uuid.UUID{dumpID},
		Frequency:               models.JobFreqDaily,
		StartDate:               time.Now().UTC().AddDate(-1, 0, 0), // Start date a year ago
		EarliestStartTime:       earliest,
		LatestStartTime:         latest,
		SkipHolidays:            true,
		DailyPayEstimates:       dailyEstimates,
		CompletionRules: &models.JobCompletionRules{
			ProofPhotosRequired: true,
		},
	}

	pmID := uuid.MustParse("22222222-2222-2222-2222-222222222222")

	// Create this definition as INACTIVE so it doesn't generate future jobs.
	defID, err := jobSvc.CreateJobDefinition(ctx, pmID.String(), req, string(models.JobStatusArchived))
	if err != nil {
		// It's possible for a unique violation if another process runs this simultaneously.
		// The check at the top should prevent this, but we handle the error just in case.
		if isUniqueViolation(err) {
			utils.Logger.Warnf("jobs-service: Unique violation on creating historical def, likely a race condition. Attempting to recover ID.")
			// Re-fetch to get the ID created by the other process.
			return seedHistoricalDefinition(ctx, defRepo, jobSvc, propID)
		}
		return uuid.Nil, fmt.Errorf("failed to create historical job definition '%s' for prop=%s: %w", title, propID, err)
	}

	utils.Logger.Infof("jobs-service: Created historical job definition '%s' (id=%s).", title, defID)
	return defID, nil
}

/*
	------------------------------------------------------------------
	  5) seedPastCompletedInstances
------------------------------------------------------------------
*/
// seedPastCompletedInstances creates COMPLETED job instances for the two most recent
// completed pay periods to ensure consistent and predictable historical data.
func seedPastCompletedInstances(ctx context.Context, db repositories.DB, defID uuid.UUID) error {
	loc, _ := time.LoadLocation("America/New_York")
	nowInBusinessTZ := time.Now().In(loc)
	todayInBusinessTZ := time.Date(nowInBusinessTZ.Year(), nowInBusinessTZ.Month(), nowInBusinessTZ.Day(), 0, 0, 0, 0, time.UTC)

	// Calculate the start of the two most recent completed pay periods.
	thisWeekStart := getPayPeriodStartForDate(nowInBusinessTZ)
	lastWeekStart := thisWeekStart.AddDate(0, 0, -7)
	weekBeforeLastStart := lastWeekStart.AddDate(0, 0, -7)

	// --- Jobs for the week *before* last week ---
	// Total pay: 20 + 25 + 22 = $67.00
	jobsForWeekBeforeLast := []*models.JobInstance{
		{
			// UPDATED: Use a hardcoded, predictable UUID
			ID:           uuid.MustParse("aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaa1"),
			ServiceDate:  weekBeforeLastStart.AddDate(0, 0, 1),
			EffectivePay: 20.00,
			CheckInAt:    utils.Ptr(weekBeforeLastStart.AddDate(0, 0, 1).Add(17 * time.Hour)),
			CheckOutAt:   utils.Ptr(weekBeforeLastStart.AddDate(0, 0, 1).Add(17 * time.Hour).Add(50 * time.Minute)),
		},
		{
			// UPDATED: Use a hardcoded, predictable UUID
			ID:           uuid.MustParse("aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaa2"),
			ServiceDate:  weekBeforeLastStart.AddDate(0, 0, 3),
			EffectivePay: 25.00,
			CheckInAt:    utils.Ptr(weekBeforeLastStart.AddDate(0, 0, 3).Add(18 * time.Hour)),
			CheckOutAt:   utils.Ptr(weekBeforeLastStart.AddDate(0, 0, 3).Add(18 * time.Hour).Add(60 * time.Minute)),
		},
		{
			// UPDATED: Use a hardcoded, predictable UUID
			ID:           uuid.MustParse("aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaa3"),
			ServiceDate:  weekBeforeLastStart.AddDate(0, 0, 5),
			EffectivePay: 22.00,
			CheckInAt:    utils.Ptr(weekBeforeLastStart.AddDate(0, 0, 5).Add(19 * time.Hour)),
			CheckOutAt:   utils.Ptr(weekBeforeLastStart.AddDate(0, 0, 5).Add(19 * time.Hour).Add(55 * time.Minute)),
		},
	}

	// --- Jobs for *last* week ---
	// Total pay: 30 + 28 = $58.00
	jobsForLastWeek := []*models.JobInstance{
		{
			// UPDATED: Use a hardcoded, predictable UUID
			ID:           uuid.MustParse("bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbb1"),
			ServiceDate:  lastWeekStart.AddDate(0, 0, 0),
			EffectivePay: 30.00,
			CheckInAt:    utils.Ptr(lastWeekStart.AddDate(0, 0, 0).Add(16 * time.Hour)),
			CheckOutAt:   utils.Ptr(lastWeekStart.AddDate(0, 0, 0).Add(16 * time.Hour).Add(65 * time.Minute)),
		},
		{
			// UPDATED: Use a hardcoded, predictable UUID
			ID:           uuid.MustParse("bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbb2"),
			ServiceDate:  lastWeekStart.AddDate(0, 0, 2),
			EffectivePay: 28.00,
			CheckInAt:    utils.Ptr(lastWeekStart.AddDate(0, 0, 2).Add(20 * time.Hour)),
			CheckOutAt:   utils.Ptr(lastWeekStart.AddDate(0, 0, 2).Add(20 * time.Hour).Add(62 * time.Minute)),
		},
	}

	// --- NEW: A completed job for today ---
	todayJob := &models.JobInstance{
		// UPDATED: Use a hardcoded, predictable UUID
		ID:           uuid.MustParse("cccccccc-cccc-4ccc-cccc-cccccccccccc"),
		ServiceDate:  todayInBusinessTZ,
		EffectivePay: 25.00,
		CheckInAt:    utils.Ptr(nowInBusinessTZ.Add(-45 * time.Minute)),
		CheckOutAt:   utils.Ptr(nowInBusinessTZ.Add(-5 * time.Minute)),
	}

	allJobsToSeed := append(
		append(jobsForWeekBeforeLast, jobsForLastWeek...),
		todayJob,
	)

	// This is the default active worker ID seeded in seedDefaultWorkersIfNeeded
	workerID := uuid.MustParse("1d30bfa5-e42f-457e-a21c-6b7e1aaa2222")

	for _, job := range allJobsToSeed {
		// Set common properties for all seeded historical/completed jobs
		job.DefinitionID = defID
		job.Status = models.InstanceStatusCompleted
		job.AssignedWorkerID = &workerID

		// Use raw SQL to insert, avoiding ON CONFLICT issues with existing active jobs.
		_, err := db.Exec(ctx, `
            INSERT INTO job_instances (
                id, definition_id, service_date, status,
                assigned_worker_id, effective_pay, check_in_at, check_out_at,
                excluded_worker_ids, assign_unassign_count, flagged_for_review,
                created_at, updated_at, row_version
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, '{}', 0, FALSE, NOW(), NOW(), 1)
        `,
			job.ID, job.DefinitionID, job.ServiceDate, job.Status,
			job.AssignedWorkerID, job.EffectivePay, job.CheckInAt, job.CheckOutAt,
		)
		if err != nil {
			// It's possible an active job for this day already exists. Log as a warning and continue.
			if isUniqueViolation(err) {
				utils.Logger.WithError(err).Warnf("Could not seed historical job for date %s (likely already exists), continuing.", job.ServiceDate.Format("2006-01-02"))
				continue
			}
			utils.Logger.WithError(err).Errorf("Failed to seed past completed job instance for date %s", job.ServiceDate)
			// Return the error to halt seeding if it's not a unique violation.
			return err
		} else {
			utils.Logger.Infof("Seeded COMPLETED job instance for date %s with pay $%.2f", job.ServiceDate.Format("2006-01-02"), job.EffectivePay)
		}
	}

	return nil
}

/*
	------------------------------------------------------------------
	  6) seedCliftFarmPropertyIfNeeded (NEW)

------------------------------------------------------------------
*/
func seedCliftFarmPropertyIfNeeded(
	ctx context.Context,
	propRepo repositories.PropertyRepository,
	bldgRepo repositories.PropertyBuildingRepository,
	dumpRepo repositories.DumpsterRepository,
	unitRepo repositories.UnitRepository,
	jobSvc *services.JobService,
	defRepo repositories.JobDefinitionRepository,
) error {
	propID := uuid.MustParse("55555555-5555-5555-5555-555555555555")

	p := &models.Property{
		ID:           propID,
		ManagerID:    uuid.MustParse("22222222-2222-2222-2222-222222222222"),
		PropertyName: "The Station at Clift Farm",
		Address:      "165 John Thomas Dr",
		City:         "Madison",
		State:        "AL",
		ZipCode:      "35758",
		TimeZone:     "America/Chicago",
		Latitude:     34.752931141531086,
		Longitude:    -86.75920658648279,
	}

	if err := propRepo.Create(ctx, p); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Infof("jobs-service: Clift Farm Property (id=%s) already exists; continuing with seeding.", propID)
		} else {
			return fmt.Errorf("failed to create Clift Farm property id=%s: %w", propID, err)
		}
	} else {
		utils.Logger.Infof("jobs-service: Created Clift Farm property (id=%s).", propID)
	}

	// -- Seed Buildings & Units for Clift Farm --
	existingBldgs, err := bldgRepo.ListByPropertyID(ctx, propID)
	if err != nil {
		return fmt.Errorf("list clift farm buildings: %w", err)
	}

	type bldgConf struct {
		num int
		lat float64
		lng float64
	}
	bldgList := []bldgConf{
		{1, 34.753499865723214, -86.76060923898977},
		{2, 34.7538260179232, -86.75883898104533},
		{3, 34.75301788853227, -86.75992709822535},
		{4, 34.75337268653752, -86.75804126871314},
	}

	existingMap := make(map[int]*models.PropertyBuilding)
	for _, b := range existingBldgs {
		var num int
		fmt.Sscanf(b.BuildingName, "Building %d", &num)
		existingMap[num] = b
	}

	var allBldgIDs []uuid.UUID
	for _, bc := range bldgList {
		b, ok := existingMap[bc.num]
		if !ok {
			b = &models.PropertyBuilding{
				ID:           uuid.New(),
				PropertyID:   propID,
				BuildingName: fmt.Sprintf("Building %d", bc.num),
				Latitude:     bc.lat,
				Longitude:    bc.lng,
			}
			if err := bldgRepo.Create(ctx, b); err != nil {
				return fmt.Errorf("create building %d for clift farm: %w", bc.num, err)
			}
			utils.Logger.Infof("jobs-service: Created building %s for Clift Farm property (id=%s).", b.BuildingName, propID)
		}
		allBldgIDs = append(allBldgIDs, b.ID)

		units, err := unitRepo.ListByBuildingID(ctx, b.ID)
		if err != nil {
			return fmt.Errorf("list units for bldg %s: %w", b.ID, err)
		}
		for u := len(units) + 1; u <= 30; u++ {
			unitNum := fmt.Sprintf("%d%02d", bc.num, u)
			un := &models.Unit{
				ID:          uuid.New(),
				PropertyID:  propID,
				BuildingID:  b.ID,
				UnitNumber:  unitNum,
				TenantToken: uuid.NewString(),
			}
			if cErr := unitRepo.Create(ctx, un); cErr != nil {
				return fmt.Errorf("create unit %s for Clift Farm prop=%s: %w", unitNum, propID, cErr)
			}
		}
		if len(units) < 30 {
			utils.Logger.Infof("jobs-service: Created %d units for building %s at Clift Farm", 30-len(units), b.BuildingName)
		}
	}

	// -- Seed Dumpster for Clift Farm --
	dumpsterID := uuid.MustParse("66666666-6666-6666-6666-666666666666")
	d := &models.Dumpster{
		ID:             dumpsterID,
		PropertyID:     propID,
		DumpsterNumber: "1",
		Latitude:       34.75320015716651,
		Longitude:      -86.7606387432878,
	}
	if err := dumpRepo.Create(ctx, d); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Infof("jobs-service: Clift Farm dumpster (id=%s) for property (id=%s) already exists; skipping creation.", dumpsterID, propID)
		} else {
			return fmt.Errorf("create dumpster id=%s for Clift Farm prop=%s: %w", dumpsterID, propID, err)
		}
	} else {
		utils.Logger.Infof("jobs-service: Created dumpster (id=%s) for Clift Farm property (id=%s).", dumpsterID, propID)
	}

	// -- Seed Job Definitions for Clift Farm --
	defTitleAM := "Service The Station at Clift Farm (AM)"
	defTitlePM := "Service The Station at Clift Farm (PM)"

	existingDefs, err := defRepo.ListByPropertyID(ctx, propID)
	if err != nil {
		return fmt.Errorf("listing existing defs for clift farm: %w", err)
	}

	var amDefExists bool
	var pmDefExists bool
	for _, def := range existingDefs {
		if def.Title == defTitleAM {
			amDefExists = true
		}
		if def.Title == defTitlePM {
			pmDefExists = true
		}
	}

	// Morning Job Definition (4 AM - 9 AM)
	if !amDefExists {
		if _, err := createRealisticTimeWindowDefinition(ctx, jobSvc, propID, defTitleAM, allBldgIDs, 4, 9, p.TimeZone, dumpsterID, unitRepo, 0); err != nil {
			return fmt.Errorf("seed AM job definition for clift farm: %w", err)
		}
	} else {
		utils.Logger.Infof("jobs-service: JobDefinition '%s' already exists for Clift Farm; skipping.", defTitleAM)
	}

	// Evening Job Definition (4 PM - 11 PM)
	if !pmDefExists {
		if _, err := createRealisticTimeWindowDefinition(ctx, jobSvc, propID, defTitlePM, allBldgIDs, 16, 23, p.TimeZone, dumpsterID, unitRepo, 0); err != nil {
			return fmt.Errorf("seed PM job definition for clift farm: %w", err)
		}
	} else {
		utils.Logger.Infof("jobs-service: JobDefinition '%s' already exists for Clift Farm; skipping.", defTitlePM)
	}

	// Single floor definitions
	existingDefs, err = defRepo.ListByPropertyID(ctx, propID)
	if err != nil {
		return fmt.Errorf("listing existing defs for clift farm: %w", err)
	}
	for f := 1; f <= 3; f++ {
		title := fmt.Sprintf("Clift Farm Floor %d", f)
		exists := false
		for _, d := range existingDefs {
			if d.Title == title {
				exists = true
				break
			}
		}
		if !exists {
			if _, ferr := createDailyDefinition(ctx, jobSvc, propID, title, allBldgIDs, p.TimeZone, dumpsterID, unitRepo, f); ferr != nil {
				return ferr
			}
		}
	}

	return nil
}
