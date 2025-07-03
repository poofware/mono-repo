package utils

import (
	"time"

	"github.com/poofware/earnings-service/internal/constants"
)

// GetPayPeriodStartForDate returns the Monday that begins the pay period for a given time `t`.
// The pay period is defined as Monday 4:00 AM to the following Monday 3:59 AM in America/New_York.
// This is the single source of truth for pay period calculations.
func GetPayPeriodStartForDate(t time.Time) time.Time {
	loc, _ := time.LoadLocation(constants.BusinessTimezone)

	// CORRECTED: First, convert the given time `t` into the business timezone.
	timeInLoc := t.In(loc)

	// A "day" for payouts starts at 4:00 AM. We subtract 4 hours to align any
	// time between midnight and 3:59 AM with the previous calendar day for accounting purposes.
	adjustedTime := timeInLoc.Add(-time.Duration(constants.PayPeriodStartHourEST) * time.Hour)

	// Now, find the Monday of that adjusted day's week.
	weekday := adjustedTime.Weekday()
	daysSinceMonday := (weekday - time.Monday + 7) % 7

	startOfWeek := adjustedTime.AddDate(0, 0, -int(daysSinceMonday))

	// Return the date part only, in UTC to ensure consistency when storing in a DATE field.
	return time.Date(startOfWeek.Year(), startOfWeek.Month(), startOfWeek.Day(), 0, 0, 0, 0, time.UTC)
}
