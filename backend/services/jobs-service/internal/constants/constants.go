package constants

import (
	"time"
)

// General job settings
const (
	RadiusMiles                    = 75
	LocationRadiusMeters           = 200
	RadiusMilesToNotifyAgents      = 50
	MaxAssignUnassignCountForFlag  = 2
	DaysToListOpenJobsRange        = 8 // Query window is [yesterday...today+7] = 9 days total
	DaysToSeedAhead                = 7 // How many days ahead to seed new instances
	MinJobDefinitionStartWindowMinutes       = 90 // Min duration between earliest/latest start
	MinTimeBeforeLatestStartForHintMinutes = 50 // Hint must be at least this many mins before latest start
)

// Time windows relative to a job's LATEST_START_TIME
const (
	NoShowCutoffBeforeLatestStart = 20 * time.Minute
	// A worker cannot accept a job if it's within 20 minutes of the no-show cutoff time.
	AcceptanceCutoffBeforeNoShow = 20 * time.Minute
	OnCallEscalationBeforeLatest = 20 * time.Minute
	Warning90MinBeforeLatestStart = 90 * time.Minute
	Warning40MinBeforeLatestStart = 40 * time.Minute
)

// Worker Penalty Tiers (negative values)
const (
	WorkerPenaltyNoShow          = -20 // Assigned worker does not start job by no-show time
	WorkerPenaltyLate            = -10 // Un-assigns or cancels within the "late" window
	WorkerPenaltyMid             = -6  // Un-assigns or cancels within the "mid" window
	WorkerPenaltyEarly           = -3  // Un-assigns or cancels within the "early" window
	WorkerPenaltyExclusionWindow = -2  // Un-assigns or cancels within the "exclusion" window
	WorkerPenalty24h             = -1  // Un-assigns more than 7h before no-show, but < 24h before earliest_start
)

// Time windows for penalties, all relative to the NO_SHOW_TIME (LatestStartTime - 20m)
const (
	LateUnassignCutoff         = 90 * time.Minute // T-90m before no-show
	MidUnassignCutoff          = 3 * time.Hour    // T-3h before no-show
	EarlyUnassignCutoff        = 6 * time.Hour    // T-6h before no-show
	ExclusionWindowStartCutoff = 7 * time.Hour    // T-7h before no-show
)

// Surge Pay Multipliers (4-Stage Model)
const (
	SurgeMultiplierStage1 = 1.10
	SurgeMultiplierStage2 = 1.20
	SurgeMultiplierStage3 = 1.35
	SurgeMultiplierStage4 = 1.50
)

// Time windows for surges, all relative to the NO_SHOW_TIME
const (
	SurgeWindowStage1 = 6 * time.Hour    // T-6h -> T-3h
	SurgeWindowStage2 = 3 * time.Hour    // T-3h -> T-90m
	SurgeWindowStage3 = 90 * time.Minute // T-90m -> T-45m
	SurgeWindowStage4 = 45 * time.Minute // T-45m -> no-show time (SURGE STOPS HERE)
)

// Common concurrency conflict / row-version conflict messages
const (
	ErrMsgNoRowsUpdated                    = "No rows updated"
	ErrMsgRowVersionConflictRefresh        = "The job has changed, please refresh"
	ErrMsgRowVersionConflictAnotherUpdated = "Another update occurred, please refresh"
)
