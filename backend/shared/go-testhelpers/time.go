package testhelpers

import (
	"time"
)

// TestSameDayTimeWindow generates an earliest and latest time that is valid for an entire day.
// This makes tests robust against failures caused by the test execution time being
// outside a more narrow, dynamically-generated time window.
func (h *TestHelper) TestSameDayTimeWindow() (time.Time, time.Time) {
	now := time.Now().UTC()
	// Create a window that is the entirety of the current UTC day.
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	todayEnd := todayStart.Add(23*time.Hour + 59*time.Minute)
	return todayStart, todayEnd
}

// ActiveAcceptanceWindow returns an earliest and latest start time such that the
// acceptance cutoff (latest_start - 40 minutes) is guaranteed to be in the future
// relative to the current time. It also returns the corresponding serviceDate that
// tests should use when creating job instances.
//
// The window is constructed in UTC, which matches the default TimeZone used by
// CreateTestProperty in tests unless overridden explicitly.
func (h *TestHelper) ActiveAcceptanceWindow() (time.Time, time.Time, time.Time) {
    now := time.Now().UTC()
    todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
    todayEnd := todayStart.Add(23*time.Hour + 59*time.Minute)

    // Aim for a 2-hour window ending 2 hours from now.
    desiredLatest := now.Add(2 * time.Hour)
    desiredEarliest := desiredLatest.Add(-2 * time.Hour)

    // Clamp to stay within today if possible.
    if desiredLatest.Before(todayEnd) {
        // Ensure acceptance cutoff is in the future: latest - 40m > now
        acceptanceCutoff := desiredLatest.Add(-40 * time.Minute)
        if acceptanceCutoff.After(now) && desiredEarliest.After(todayStart) {
            serviceDate := todayStart
            return desiredEarliest, desiredLatest, serviceDate
        }
    }

    // If it's too late in the day (e.g., near/after acceptance cutoff), use tomorrow.
    tomorrowStart := todayStart.Add(24 * time.Hour)
    // Fixed safe window during tomorrow daytime: 10:00 - 12:00 UTC
    earliest := time.Date(tomorrowStart.Year(), tomorrowStart.Month(), tomorrowStart.Day(), 10, 0, 0, 0, time.UTC)
    latest := time.Date(tomorrowStart.Year(), tomorrowStart.Month(), tomorrowStart.Day(), 12, 0, 0, 0, time.UTC)
    serviceDate := tomorrowStart
    return earliest, latest, serviceDate
}

// WindowActiveNowInTZ returns (earliest, latest, serviceDate) such that in the given
// timezone tz, the current time is strictly within [earliest, latest], the window
// is at least 90 minutes long, and both times-of-day fall on the same local day.
// The returned serviceDate is the midnight instant for that local day expressed in UTC.
func (h *TestHelper) WindowActiveNowInTZ(tz string) (time.Time, time.Time, time.Time) {
    loc, err := time.LoadLocation(tz)
    if err != nil {
        loc = time.UTC
    }
    nowLocal := time.Now().In(loc)
    dayStart := time.Date(nowLocal.Year(), nowLocal.Month(), nowLocal.Day(), 0, 0, 0, 0, loc)
    dayEnd := dayStart.Add(24*time.Hour - time.Nanosecond)

    // Start 45 minutes before now to give room and ensure >=90m window
    earliestLocal := nowLocal.Add(-45 * time.Minute)
    latestLocal := earliestLocal.Add(2 * time.Hour)

    if earliestLocal.Before(dayStart) {
        earliestLocal = dayStart.Add(1 * time.Minute)
        latestLocal = earliestLocal.Add(2 * time.Hour)
    }
    if latestLocal.After(dayEnd) {
        // If too close to end of day, shift window earlier so now is still inside.
        latestLocal = dayEnd.Add(-1 * time.Minute)
        earliestLocal = latestLocal.Add(-2 * time.Hour)
        // Ensure nowLocal within [earliestLocal, latestLocal]; if not, center around now safely.
        if nowLocal.Before(earliestLocal) || nowLocal.After(latestLocal) {
            earliestLocal = nowLocal.Add(-1 * time.Hour)
            latestLocal = nowLocal.Add(1 * time.Hour)
            // Re-clamp to same day if needed
            if earliestLocal.Before(dayStart) {
                earliestLocal = dayStart.Add(1 * time.Minute)
            }
            if latestLocal.After(dayEnd) {
                latestLocal = dayEnd.Add(-1 * time.Minute)
            }
        }
    }

    // Convert to UTC while keeping the local times-of-day semantics by using the same absolute instants.
    earliest := earliestLocal.UTC()
    latest := latestLocal.UTC()
    serviceDate := time.Date(nowLocal.Year(), nowLocal.Month(), nowLocal.Day(), 0, 0, 0, 0, loc).UTC()
    // Guarantee at least 90 minutes window
    if latest.Sub(earliest) < 90*time.Minute {
        latest = earliest.Add(90 * time.Minute)
    }
    return earliest, latest, serviceDate
}

// WindowWithCutoffPassedInTZ returns (earliest, latest, serviceDate) such that in the
// given timezone tz, the acceptance cutoff time (latest - 40m) has already passed but
// the latest start is still in the near future. Both times-of-day are on the same local day.
func (h *TestHelper) WindowWithCutoffPassedInTZ(tz string) (time.Time, time.Time, time.Time) {
    loc, err := time.LoadLocation(tz)
    if err != nil {
        loc = time.UTC
    }
    nowLocal := time.Now().In(loc)
    dayStart := time.Date(nowLocal.Year(), nowLocal.Month(), nowLocal.Day(), 0, 0, 0, 0, loc)
    dayEnd := dayStart.Add(24*time.Hour - time.Nanosecond)

    latestLocal := nowLocal.Add(30 * time.Minute)
    earliestLocal := latestLocal.Add(-2 * time.Hour)

    // Clamp within the same local day
    if earliestLocal.Before(dayStart) {
        earliestLocal = dayStart.Add(1 * time.Minute)
        latestLocal = earliestLocal.Add(2 * time.Hour)
    }
    if latestLocal.After(dayEnd) {
        latestLocal = dayEnd.Add(-1 * time.Minute)
        earliestLocal = latestLocal.Add(-2 * time.Hour)
    }

    earliest := earliestLocal.UTC()
    latest := latestLocal.UTC()
    serviceDate := dayStart.UTC()
    return earliest, latest, serviceDate
}

