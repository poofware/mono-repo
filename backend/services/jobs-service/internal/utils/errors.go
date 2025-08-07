// meta-service/services/jobs-service/internal/utils/errors.go

package utils

import (
	"errors"

	"github.com/poofware/mono-repo/backend/shared/go-models"
)

/*
    Sentinel errors for job-service domain logic.
   The controller can do: if errors.Is(err, ErrXYZ) { ... }
*/
var (
        ErrNotAssignedWorker     = errors.New("not_assigned_worker")
        ErrWrongStatus           = errors.New("wrong_status")
        ErrLocationOutOfBounds   = errors.New("location_out_of_bounds")
        ErrLocationInaccurate    = errors.New("location_inaccurate")
        ErrNoPhotosProvided      = errors.New("no_photos_provided")
        ErrExcludedWorker        = errors.New("excluded_worker")
        ErrNoRowsUpdated         = errors.New("no_rows_updated") // Can be used by repos

       ErrDumpLocationOutOfBounds = errors.New("dump_location_out_of_bounds")

	ErrNotWithinTimeWindow = errors.New("not_within_time_window")

	ErrJobNotReleasedYet = errors.New("job_not_released_yet")

	// NEW
	ErrWorkerNotActive = errors.New("worker_not_active")

	ErrMismatchedPayEstimatesFrequency = errors.New("mismatched_pay_estimates_frequency")
	ErrMissingPayEstimateInput         = errors.New("missing_pay_estimate_input")
	ErrInvalidPayload                  = errors.New("invalid_payload") // More generic for other payload issues
)

/*
   RowVersionConflictError is returned when there's a concurrency mismatch.
   It includes the "latest" JobInstance so the controller can return it
   to the client if desired.
*/
type RowVersionConflictError struct {
	Current *models.JobInstance
}

func (e *RowVersionConflictError) Error() string {
	return "row_version_conflict"
}

func NewRowVersionConflictError(current *models.JobInstance) error {
	return &RowVersionConflictError{Current: current}
}
