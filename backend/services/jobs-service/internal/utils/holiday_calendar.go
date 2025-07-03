package utils

import (
	"time"

	cal "github.com/rickar/cal/v2"
	"github.com/rickar/cal/v2/us"
)

// create once at init
var usFed = cal.NewBusinessCalendar()

func init() {
	usFed.AddHoliday(
		us.NewYear,
		us.MlkDay,
		us.PresidentsDay,
		us.MemorialDay,
		us.Juneteenth,
		us.IndependenceDay,
		us.LaborDay,
		us.ThanksgivingDay,
		us.ChristmasDay,
	)
}

// drop-in replacement for the stub
func IsUSFedHoliday(t time.Time) bool {
	ok, _, _ := usFed.IsHoliday(t)
	return ok
}

