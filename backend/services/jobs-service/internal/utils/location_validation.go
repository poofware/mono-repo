package utils

import (
	"math"
	"time"

	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

// validateLocationData checks lat/lng range, accuracy, timestamp proximity, and
// is_mock=false. It returns empty strings if valid, otherwise an error code and
// message suitable for RespondErrorWithCode.
func ValidateLocationData(lat, lng, accuracy float64, timestamp int64, isMock bool) (string, string) {
	if lat < -90 || lat > 90 || lng < -180 || lng > 180 {
		return utils.ErrCodeInvalidPayload, "lat/lng out of range"
	}
	if accuracy > 30 {
		return utils.ErrCodeLocationInaccurate, "GPS accuracy is too low. Please move to an area with a clearer view of the sky."
	}
	nowMS := time.Now().UnixMilli()
	if math.Abs(float64(nowMS-timestamp)) > 30000 {
		return utils.ErrCodeInvalidPayload, "location timestamp not within ±30s of server time"
	}
	if isMock {
		return utils.ErrCodeInvalidPayload, "is_mock must be false"
	}
	return "", ""
}
