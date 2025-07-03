package utils

// Error codes specific to jobs-service only.
const (
    ErrCodeNotAssignedWorker   = "not_assigned_worker"
    ErrCodeWrongStatus         = "wrong_status"
    ErrCodeLocationOutOfBounds = "location_out_of_bounds"
    ErrCodeNoPhotosProvided    = "no_photos_provided"
    ErrCodeExcludedWorker      = "excluded_worker"
)
