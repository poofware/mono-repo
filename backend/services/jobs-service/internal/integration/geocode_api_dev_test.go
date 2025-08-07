//go:build dev && integration

package integration

import (
    "os"
    "testing"

    "github.com/stretchr/testify/require"

    internal_utils "github.com/poofware/mono-repo/backend/services/jobs-service/internal/utils"
)

func TestGeocodeAddress(t *testing.T) {
    apiKey := os.Getenv("GOOGLE_MAPS_API_KEY")
    if apiKey == "" {
        t.Skip("GOOGLE_MAPS_API_KEY not set")
    }

    lat, lng, err := internal_utils.GeocodeAddress("1600 Amphitheatre Parkway, Mountain View, CA", apiKey)
    require.NoError(t, err)

    require.InEpsilon(t, 37.423021, lat, 0.001)
    require.InEpsilon(t, -122.083739, lng, 0.001)
}
