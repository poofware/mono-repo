package dtos

import (
	"time" // Import time package
	"github.com/google/uuid"
)

/*
ListJobsQuery is the "request DTO" for GET /api/v1/jobs/open (and /my).
*/
type ListJobsQuery struct {
	Lat  float64
	Lng  float64
	Page int
	Size int
}

/*
JobInstanceDTO is used by responses listing or returning a single job instance.
*/
type JobInstanceDTO struct {
	InstanceID        uuid.UUID     `json:"instance_id"`
	DefinitionID      uuid.UUID     `json:"definition_id"`
	PropertyID        uuid.UUID     `json:"property_id"`
	ServiceDate       string        `json:"service_date"`
	Status            string        `json:"status"`
	Pay               float64       `json:"pay"`
	Property          PropertyDTO   `json:"property"`
	NumberOfBuildings int           `json:"number_of_buildings"`
	Buildings         []BuildingDTO `json:"buildings,omitempty"`
	NumberOfDumpsters int           `json:"number_of_dumpsters"`
	Dumpsters         []DumpsterDTO `json:"dumpsters,omitempty"`

	// Times are now provided in pairs for both worker and property timezones.

	// Recommended Start Time
	StartTimeHint       string `json:"start_time_hint,omitempty"` // Property Time
	WorkerStartTimeHint string `json:"worker_start_time_hint,omitempty"`

	// Actionable Service Window (Earliest Start to No-Show Cutoff)
	PropertyServiceWindowStart string `json:"property_service_window_start,omitempty"`
	WorkerServiceWindowStart   string `json:"worker_service_window_start,omitempty"`
	PropertyServiceWindowEnd   string `json:"property_service_window_end,omitempty"`
	WorkerServiceWindowEnd     string `json:"worker_service_window_end,omitempty"`

	// The distance & travel time from (lat, lng) to job's property
	DistanceMiles float64 `json:"distance_miles,omitempty"`
	TravelMinutes *int    `json:"travel_minutes,omitempty"`

	EstimatedTimeMinutes int        `json:"estimated_time_minutes"`
	CheckInAt            *time.Time `json:"check_in_at,omitempty"`
}

/*
JobInstancePMDTO is used by responses listing or returning a single job instance. Restricts info to PMs.
*/
type JobInstancePMDTO struct {
	InstanceID        uuid.UUID     `json:"instance_id"`
	DefinitionID      uuid.UUID     `json:"definition_id"`
	PropertyID        uuid.UUID     `json:"property_id"`
	ServiceDate       string        `json:"service_date"`
	Status            string        `json:"status"`
	Property          PropertyDTO   `json:"property"`
	Buildings         []BuildingDTO `json:"buildings,omitempty"`
}
/*
BuildingDTO and DumpsterDTO appear within JobInstanceDTO to give a
little more context about the assigned buildings/dumpsters for the job.
*/
type BuildingDTO struct {
	BuildingID uuid.UUID `json:"building_id"`
	Name       string    `json:"building_name"`
	Latitude   float64   `json:"latitude"`
	Longitude  float64   `json:"longitude"`
}

type DumpsterDTO struct {
	DumpsterID uuid.UUID `json:"dumpster_id"`
	Number     string    `json:"dumpster_number"`
	Latitude   float64   `json:"latitude"`
	Longitude  float64   `json:"longitude"`
}

type PropertyDTO struct {
	PropertyID   uuid.UUID `json:"property_id"`
	PropertyName string    `json:"property_name"`
	Address      string    `json:"address"`
	City         string    `json:"city"`
	State        string    `json:"state"`
	ZipCode      string    `json:"zip_code"`
	Latitude     float64   `json:"latitude"`
	Longitude    float64   `json:"longitude"`
}

/*
ListJobsResponse is the response for GET /api/v1/jobs/open or /api/v1/jobs/my.
*/
type ListJobsResponse struct {
	Results []JobInstanceDTO `json:"results"`
	Page    int              `json:"page"`
	Size    int              `json:"size"`
	Total   int              `json:"total"`
}

//ListJobsPMResponse is the response for manager-facing job list endpoints.

type ListJobsPMResponse struct {
	Results []JobInstancePMDTO `json:"results"`
	Total   int                `json:"total"`
}

/*
JobInstanceActionRequest is the simple "instance_id" payload for endpoints like
accept, unaccept, cancel, etc. that don’t require location data.
*/
type JobInstanceActionRequest struct {
	InstanceID uuid.UUID `json:"instance_id"`
}

/*
JobInstanceActionResponse includes the updated job instance in case it changed
(accept, unaccept, etc.).
*/
type JobInstanceActionResponse struct {
	Updated JobInstanceDTO `json:"updated"`
}

/*
NEW: JobLocationActionRequest is for device-attested job actions that
require location data (start or complete). This minimal structure
consists of:

  - instance_id: links the location fix to a specific job instance
  - lat, lng: WGS-84 coordinates (range-checked in the controller)
  - accuracy: 1-σ horizontal radius in meters
  - timestamp: Unix ms from the device
  - is_mock: OS-level location mocking/simulator flag
*/
type JobLocationActionRequest struct {
	InstanceID uuid.UUID `json:"instance_id"`
	Lat        float64   `json:"lat"`
	Lng        float64   `json:"lng"`
	Accuracy   float64   `json:"accuracy"`
	Timestamp  int64     `json:"timestamp"`
	IsMock     bool      `json:"is_mock"`
}
