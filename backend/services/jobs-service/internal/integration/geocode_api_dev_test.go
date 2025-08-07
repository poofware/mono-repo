//go:build dev && integration

package integration

import (
	"testing"

	"github.com/stretchr/testify/require"

	internal_utils "github.com/poofware/mono-repo/backend/services/jobs-service/internal/utils"
)

func TestGeocodeAddress(t *testing.T) {
	if h.GMapsRoutesAPIKey == "" {
		t.Skip("GMAPS_ROUTES_API_KEY secret not set")
	}

	lat, lng, err := internal_utils.GeocodeAddress("1600 Amphitheatre Parkway, Mountain View, CA", h.GMapsRoutesAPIKey)
	require.NoError(t, err)

	require.InEpsilon(t, 37.423021, lat, 0.001)
	require.InEpsilon(t, -122.083739, lng, 0.001)
}
