package utils

import (
	"context"
	"fmt"
	"sync"
	"time"

	routing "cloud.google.com/go/maps/routing/apiv2"
	"cloud.google.com/go/maps/routing/apiv2/routingpb"
	"github.com/poofware/go-utils" // Assuming your root go-utils for Logger
	"github.com/umahmood/haversine"
	"google.golang.org/api/option"
	"google.golang.org/genproto/googleapis/type/latlng"
	"google.golang.org/grpc/metadata"

	"github.com/poofware/jobs-service/internal/constants"
)

/*──────────── reusable, thread-safe Routes client ────────────*/

var (
	routesClientOnce sync.Once
	routesClient     *routing.RoutesClient
	routesClientErr  error
)

func getRoutesClient(ctx context.Context, apiKey string) (*routing.RoutesClient, error) {
	routesClientOnce.Do(func() {
		utils.Logger.Info("[GMapsClient] Initializing Google Maps Routes client...")
		routesClient, routesClientErr = routing.NewRoutesRESTClient(
			ctx,
			option.WithAPIKey(apiKey),
			option.WithEndpoint("https://routes.googleapis.com"),
		)
		if routesClientErr != nil {
			utils.Logger.WithError(routesClientErr).Error("[GMapsClient] Failed to initialize Google Maps Routes client")
		} else {
			// No log for successful initialization to reduce noise, error log is sufficient
		}
	})
	return routesClient, routesClientErr
}

/*────────────────────────────────────────────────────────────────────────────
  ComputeDriveDistanceTimeMiles returns (distanceMiles, durationMinutes, error).

  If the GMaps API key is empty, or if the GMaps request fails, we fall back
  to a simple Haversine distance, then estimate drive time as dist * constants.CrowFliesDriveTimeMultiplier.
────────────────────────────────────────────────────────────────────────────*/

func ComputeDriveDistanceTimeMiles(
	lat1, lng1, lat2, lng2 float64,
	apiKey string,
) (float64, int, error) {
	originStr := fmt.Sprintf("%.6f,%.6f", lat1, lng1)
	destStr := fmt.Sprintf("%.6f,%.6f", lat2, lng2)
	// Create logger with fields but defer logging until needed
	loggerWithFields := utils.Logger.WithField("origin", originStr).WithField("destination", destStr)

	if apiKey == "" {
		loggerWithFields.Warn("[GMapsClient] API key is empty. Falling back to Haversine.")
		dist := DistanceMiles(lat1, lng1, lat2, lng2)
		return dist, int(dist*constants.CrowFliesDriveTimeMultiplier + 0.5), nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	cli, err := getRoutesClient(ctx, apiKey)
	if err != nil {
		loggerWithFields.WithError(err).Error("[GMapsClient] Failed to get Routes client (initialization error). Falling back to Haversine.")
		dist := DistanceMiles(lat1, lng1, lat2, lng2)
		return dist, int(dist*constants.CrowFliesDriveTimeMultiplier + 0.5), nil
	}

	req := &routingpb.ComputeRoutesRequest{
		Origin: &routingpb.Waypoint{
			LocationType: &routingpb.Waypoint_Location{
				Location: &routingpb.Location{
					LatLng: &latlng.LatLng{Latitude: lat1, Longitude: lng1},
				},
			},
		},
		Destination: &routingpb.Waypoint{
			LocationType: &routingpb.Waypoint_Location{
				Location: &routingpb.Location{
					LatLng: &latlng.LatLng{Latitude: lat2, Longitude: lng2},
				},
			},
		},
		TravelMode:        routingpb.RouteTravelMode_DRIVE,
		RoutingPreference: routingpb.RoutingPreference_TRAFFIC_UNAWARE,
	}

	ctxWithFieldMask := metadata.AppendToOutgoingContext(
		ctx,
		"X-Goog-FieldMask",
		"routes.duration,routes.distanceMeters",
	)

	// utils.Logger.Debugf("[GMapsClient] Attempting Google Maps API call for %s to %s", originStr, destStr) // Changed to Debugf
	resp, err := cli.ComputeRoutes(ctxWithFieldMask, req)

	if err != nil {
		loggerWithFields.WithError(err).Warn("[GMapsClient] Google Maps API ComputeRoutes call failed. Falling back to Haversine.")
		dist := DistanceMiles(lat1, lng1, lat2, lng2)
		return dist, int(dist*constants.CrowFliesDriveTimeMultiplier + 0.5), nil
	}

	if len(resp.Routes) == 0 {
		loggerWithFields.Warn("[GMapsClient] Google Maps API returned no routes. Falling back to Haversine.")
		dist := DistanceMiles(lat1, lng1, lat2, lng2)
		return dist, int(dist*constants.CrowFliesDriveTimeMultiplier + 0.5), nil
	}

	route := resp.Routes[0]
	// Successful API call, no specific log here unless debugging verbosely
	// utils.Logger.Debugf("[GMapsClient] Google Maps API call successful for %s to %s.", originStr, destStr)


	var mins int
	if route.Duration != nil {
		mins = int(route.Duration.AsDuration().Minutes() + 0.5)
	} else {
		loggerWithFields.Warn("[GMapsClient] Google Maps API response missing duration. Estimating based on distance.")
		distMilesFromAPI := round1(float64(route.GetDistanceMeters()) / 1609.344)
		if distMilesFromAPI > 0 {
			mins = int(distMilesFromAPI*constants.CrowFliesDriveTimeMultiplier + 0.5)
		} else { // If distance is also zero/missing, use Haversine for everything
			dist := DistanceMiles(lat1, lng1, lat2, lng2)
			mins = int(dist*constants.CrowFliesDriveTimeMultiplier + 0.5)
		}
	}

	var distMiles float64
	if m := route.GetDistanceMeters(); m > 0 {
		distMiles = round1(float64(m) / 1609.344)
	} else {
		loggerWithFields.Warn("[GMapsClient] Google Maps API response missing distanceMeters or is zero. Using Haversine for distance.")
		distMiles = DistanceMiles(lat1, lng1, lat2, lng2)
	}
	
	// utils.Logger.Debugf("[GMapsClient] Calculated for %s to %s: DistanceMiles=%.2f, TravelMinutes=%d", originStr, destStr, distMiles, mins)
	return distMiles, mins, nil
}

func ComputeDistanceMeters(lat1, lng1, lat2, lng2 float64) float64 {
	distMiles := DistanceMiles(lat1, lng1, lat2, lng2)
	return distMiles * 1609.344
}

/*────────────────────────────────────────────────────────────────────────────
  DistanceMiles uses Haversine for a direct “as-the-crow-flies” distance.
────────────────────────────────────────────────────────────────────────────*/
func DistanceMiles(lat1, lon1, lat2, lon2 float64) float64 {
	p1 := haversine.Coord{Lat: lat1, Lon: lon1}
	p2 := haversine.Coord{Lat: lat2, Lon: lon2}
	mi, _ := haversine.Distance(p1, p2)
	return mi
}
