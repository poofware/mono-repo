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

