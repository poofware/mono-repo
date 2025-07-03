package utils

import (
	"math"
)

func round1(f float64) float64 {
	return math.Round(f*10) / 10
}
