// meta-service/services/jobs-service/internal/controllers/jobs_controller.go

package controllers

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"strconv"
	"time"

	"github.com/bradfitz/latlong"
	"github.com/google/uuid"
	"github.com/poofware/go-middleware"
	"github.com/poofware/go-utils"
	"github.com/poofware/jobs-service/internal/dtos"
	"github.com/poofware/jobs-service/internal/services"
	internal_utils "github.com/poofware/jobs-service/internal/utils"
)

type JobsController struct {
	jobService *services.JobService
}

func NewJobsController(js *services.JobService) *JobsController {
	return &JobsController{jobService: js}
}

// ----------------------------------------------------------------
// GET /api/v1/jobs/open
// ----------------------------------------------------------------
func (c *JobsController) ListJobsHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	ctxUserID := ctx.Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusUnauthorized,
			utils.ErrCodeUnauthorized,
			"No userID in context",
			nil,
			nil,
		)
		return
	}

	q, loc, err := parseListQueryAndLocation(r)
	if err != nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusBadRequest,
			utils.ErrCodeInvalidPayload,
			err.Error(),
			nil,
			nil,
		)
		return
	}

	resp, svcErr := c.jobService.ListOpenJobs(ctx, ctxUserID.(string), q, loc)
	if svcErr != nil {
		utils.Logger.WithError(svcErr).Error("Failed to list open jobs")
		utils.RespondErrorWithCode(
			w,
			http.StatusInternalServerError,
			utils.ErrCodeInternal,
			"Failed to list jobs",
			nil,
			svcErr,
		)
		return
	}
	utils.RespondWithJSON(w, http.StatusOK, resp)
}

// ----------------------------------------------------------------
// GET /api/v1/jobs/my
// ----------------------------------------------------------------
func (c *JobsController) ListMyJobsHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	ctxUserID := ctx.Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusUnauthorized,
			utils.ErrCodeUnauthorized,
			"No userID in context",
			nil,
			nil,
		)
		return
	}

	q, loc, err := parseListQueryAndLocation(r)
	if err != nil {
		utils.RespondErrorWithCode(
			w,
			http.StatusBadRequest,
			utils.ErrCodeInvalidPayload,
			err.Error(),
			nil,
			nil,
		)
		return
	}

	resp, svcErr := c.jobService.ListMyJobs(ctx, ctxUserID.(string), q, loc)
	if svcErr != nil {
		utils.Logger.WithError(svcErr).Error("Failed to list my jobs")
		utils.RespondErrorWithCode(
			w,
			http.StatusInternalServerError,
			utils.ErrCodeInternal,
			"Failed to list your jobs",
			nil,
			svcErr,
		)
		return
	}
	utils.RespondWithJSON(w, http.StatusOK, resp)
}

// ----------------------------------------------------------------
// POST /api/v1/jobs/accept
// *** device-attested + minimal location check
// ----------------------------------------------------------------
func (c *JobsController) AcceptJobHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	ctxUserID := ctx.Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(
			w, http.StatusUnauthorized, utils.ErrCodeUnauthorized,
			"No userID in context", nil, nil,
		)
		return
	}

	// Accept job now requires dtos.JobLocationActionRequest
	var body dtos.JobLocationActionRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload,
			"Invalid JSON for accept-job payload", nil, err,
		)
		return
	}

	// Basic checks
	if body.InstanceID == uuid.Nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload,
			"instance_id is required", nil, nil,
		)
		return
	}
	if body.Lat < -90 || body.Lat > 90 || body.Lng < -180 || body.Lng > 180 {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload,
			"lat/lng out of range", nil, nil,
		)
		return
	}
	if body.Accuracy > 30 {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeLocationInaccurate,
			"GPS accuracy is too low. Please move to an area with a clearer view of the sky.", nil, nil,
		)
		return
	}
	nowMS := time.Now().UnixMilli()
	if math.Abs(float64(nowMS-body.Timestamp)) > 30000 {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload,
			"location timestamp not within ±30s of server time", nil, nil,
		)
		return
	}
	if body.IsMock {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload,
			"is_mock must be false", nil, nil,
		)
		return
	}

	updated, err := c.jobService.AcceptJobInstanceWithLocation(
		ctx,
		ctxUserID.(string),
		body,
	)
	if err != nil {
		switch e := err.(type) {
		case *internal_utils.RowVersionConflictError:
			utils.RespondErrorWithCode(
				w,
				http.StatusConflict,
				utils.ErrCodeRowVersionConflict,
				"Another update occurred, please refresh",
				e.Current,
				err,
			)
			return
		default:
			if errors.Is(err, internal_utils.ErrWorkerNotActive) {
				utils.RespondErrorWithCode(
					w,
					http.StatusForbidden,
					internal_utils.ErrWorkerNotActive.Error(),
					"Your account is not active and cannot accept jobs.",
					nil,
					err,
				)
				return
			}
			if errors.Is(err, internal_utils.ErrJobNotReleasedYet) {
				// NEW: Worker is too early (shadow-ban or not tenant).
				utils.RespondErrorWithCode(
					w,
					http.StatusBadRequest,
					internal_utils.ErrJobNotReleasedYet.Error(),
					"Cannot accept job; not released to you yet",
					nil,
					err,
				)
				return
			}
			if errors.Is(err, internal_utils.ErrWrongStatus) ||
				errors.Is(err, internal_utils.ErrExcludedWorker) ||
				errors.Is(err, internal_utils.ErrLocationOutOfBounds) ||
				errors.Is(err, internal_utils.ErrNotWithinTimeWindow) {
				utils.RespondErrorWithCode(
					w,
					http.StatusBadRequest,
					err.Error(),
					"Cannot accept job",
					nil,
					err,
				)
				return
			}
			if errors.Is(err, utils.ErrNoRowsUpdated) {
				utils.RespondErrorWithCode(
					w, http.StatusConflict, utils.ErrCodeRowVersionConflict,
					"No rows updated, please refresh", nil, err,
				)
				return
			}
			utils.Logger.WithError(err).Error("Accept job error")
			utils.RespondErrorWithCode(
				w, http.StatusInternalServerError, utils.ErrCodeInternal,
				"Could not accept job", nil, err,
			)
			return
		}
	}
	if updated == nil {
		utils.RespondErrorWithCode(
			w, http.StatusNotFound, utils.ErrCodeNotFound,
			"Job instance not found or not open", nil, nil,
		)
		return
	}
	utils.RespondWithJSON(w, http.StatusOK, dtos.JobInstanceActionResponse{Updated: *updated})
}

// ----------------------------------------------------------------
// POST /api/v1/jobs/start
// device-attested + minimal location payload
// ...
// ----------------------------------------------------------------
func (c *JobsController) StartJobHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	ctxUserID := ctx.Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(
			w, http.StatusUnauthorized, utils.ErrCodeUnauthorized,
			"No userID in context", nil, nil,
		)
		return
	}

	var body dtos.JobLocationActionRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload,
			"Invalid JSON for start-job payload", nil, err,
		)
		return
	}

	// Basic checks
	if body.InstanceID == uuid.Nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload,
			"instance_id is required", nil, nil,
		)
		return
	}
	if body.Lat < -90 || body.Lat > 90 || body.Lng < -180 || body.Lng > 180 {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload,
			"lat/lng out of range", nil, nil,
		)
		return
	}
	if body.Accuracy > 30 {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeLocationInaccurate,
			"GPS accuracy is too low. Please move to an area with a clearer view of the sky.", nil, nil,
		)
		return
	}
	nowMS := time.Now().UnixMilli()
	if math.Abs(float64(nowMS-body.Timestamp)) > 30000 {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload,
			"location timestamp not within ±30s of server time", nil, nil,
		)
		return
	}
	if body.IsMock {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload,
			"is_mock must be false", nil, nil,
		)
		return
	}

	updated, err := c.jobService.StartJobInstanceWithLocation(
		ctx,
		ctxUserID.(string),
		body,
	)
	if err != nil {
		switch e := err.(type) {
		case *internal_utils.RowVersionConflictError:
			utils.RespondErrorWithCode(
				w,
				http.StatusConflict,
				utils.ErrCodeRowVersionConflict,
				"Row version conflict, please refresh",
				e.Current,
				err,
			)
			return
		default:
			if errors.Is(err, internal_utils.ErrNotAssignedWorker) ||
				errors.Is(err, internal_utils.ErrWrongStatus) ||
				errors.Is(err, internal_utils.ErrLocationOutOfBounds) ||
				errors.Is(err, internal_utils.ErrNotWithinTimeWindow) {
				utils.RespondErrorWithCode(
					w, http.StatusBadRequest,
					err.Error(),
					"Cannot start job",
					nil,
					err,
				)
				return
			}
			if errors.Is(err, utils.ErrNoRowsUpdated) {
				utils.RespondErrorWithCode(
					w, http.StatusConflict, utils.ErrCodeRowVersionConflict,
					"No rows updated, please refresh", nil, err,
				)
				return
			}
			utils.Logger.WithError(err).Error("Start job error")
			utils.RespondErrorWithCode(
				w, http.StatusInternalServerError, utils.ErrCodeInternal,
				"Could not start job", nil, err,
			)
			return
		}
	}
	if updated == nil {
		utils.RespondErrorWithCode(
			w, http.StatusNotFound, utils.ErrCodeNotFound,
			"Job instance not found or not assigned", nil, nil,
		)
		return
	}
	utils.RespondWithJSON(w, http.StatusOK, dtos.JobInstanceActionResponse{Updated: *updated})
}

// ----------------------------------------------------------------
// POST /api/v1/jobs/verify-unit-photo
// ----------------------------------------------------------------
func (c *JobsController) VerifyPhotoHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	ctxUserID := ctx.Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "No userID in context", nil, nil)
		return
	}

	if err := r.ParseMultipartForm(16 << 20); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Failed to parse form", nil, err)
		return
	}
	form := r.MultipartForm

	instIDStr := form.Value["instance_id"]
	unitIDStr := form.Value["unit_id"]
	latStr := form.Value["lat"]
	lngStr := form.Value["lng"]
	accStr := form.Value["accuracy"]
	tsStr := form.Value["timestamp"]
	mockStr := form.Value["is_mock"]

	if len(instIDStr) == 0 || len(unitIDStr) == 0 || len(latStr) == 0 || len(lngStr) == 0 || len(accStr) == 0 || len(tsStr) == 0 || len(mockStr) == 0 {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "missing required form fields", nil, nil)
		return
	}

	instID, err := uuid.Parse(instIDStr[0])
	if err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "invalid instance_id", nil, err)
		return
	}
	unitID, err := uuid.Parse(unitIDStr[0])
	if err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "invalid unit_id", nil, err)
		return
	}
	latVal, err := strconv.ParseFloat(latStr[0], 64)
	if err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "invalid lat", nil, err)
		return
	}
	lngVal, err := strconv.ParseFloat(lngStr[0], 64)
	if err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "invalid lng", nil, err)
		return
	}
	accVal, err := strconv.ParseFloat(accStr[0], 64)
	if err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "invalid accuracy", nil, err)
		return
	}
	tsVal, err := strconv.ParseInt(tsStr[0], 10, 64)
	if err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "invalid timestamp", nil, err)
		return
	}
	mockVal, err := strconv.ParseBool(mockStr[0])
	if err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "invalid is_mock", nil, err)
		return
	}
	if photoHeaders := form.File["photo"]; len(photoHeaders) == 0 {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "photo is required", nil, nil)
		return
	}
	file, err := form.File["photo"][0].Open()
	if err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "failed to open photo", nil, err)
		return
	}
	defer file.Close()
	imgData, _ := io.ReadAll(file)

	updated, svcErr := c.jobService.VerifyUnitPhoto(ctx, ctxUserID.(string), instID, unitID, latVal, lngVal, accVal, tsVal, mockVal, imgData)
	if svcErr != nil {
		utils.Logger.WithError(svcErr).Error("Verify photo error")
		utils.RespondErrorWithCode(w, http.StatusBadRequest, svcErr.Error(), "Could not verify photo", nil, svcErr)
		return
	}
	if updated == nil {
		utils.RespondErrorWithCode(w, http.StatusNotFound, utils.ErrCodeNotFound, "Job not found", nil, nil)
		return
	}
	utils.RespondWithJSON(w, http.StatusOK, dtos.JobInstanceActionResponse{Updated: *updated})
}

// ----------------------------------------------------------------
// POST /api/v1/jobs/dump-bags
// ----------------------------------------------------------------
func (c *JobsController) DumpBagsHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	ctxUserID := ctx.Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "No userID in context", nil, nil)
		return
	}
	var body dtos.JobLocationActionRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "Invalid JSON", nil, err)
		return
	}
	if body.InstanceID == uuid.Nil {
		utils.RespondErrorWithCode(w, http.StatusBadRequest, utils.ErrCodeInvalidPayload, "instance_id is required", nil, nil)
		return
	}

	updated, svcErr := c.jobService.ProcessDumpTrip(ctx, ctxUserID.(string), body)
	if svcErr != nil {
		utils.Logger.WithError(svcErr).Error("Dump bags error")
		utils.RespondErrorWithCode(w, http.StatusBadRequest, svcErr.Error(), "Could not dump bags", nil, svcErr)
		return
	}
	if updated == nil {
		utils.RespondErrorWithCode(w, http.StatusNotFound, utils.ErrCodeNotFound, "Job not found", nil, nil)
		return
	}
	utils.RespondWithJSON(w, http.StatusOK, dtos.JobInstanceActionResponse{Updated: *updated})
}

// POST /api/v1/jobs/unaccept
// ...
// ----------------------------------------------------------------
func (c *JobsController) UnacceptJobHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	ctxUserID := ctx.Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(
			w, http.StatusUnauthorized, utils.ErrCodeUnauthorized,
			"No userID in context", nil, nil,
		)
		return
	}
	var req dtos.JobInstanceActionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload,
			"Invalid JSON", nil, err,
		)
		return
	}
	if req.InstanceID == uuid.Nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload,
			"instance_id is required", nil, nil,
		)
		return
	}
	updated, err := c.jobService.UnacceptJobInstance(ctx, ctxUserID.(string), req.InstanceID)
	if err != nil {
		switch e := err.(type) {
		case *internal_utils.RowVersionConflictError:
			utils.RespondErrorWithCode(
				w, http.StatusConflict, utils.ErrCodeRowVersionConflict,
				"Row version conflict, please refresh",
				e.Current,
				err,
			)
			return
		default:
			if errors.Is(err, internal_utils.ErrWrongStatus) {
				utils.RespondErrorWithCode(
					w, http.StatusBadRequest, err.Error(),
					"Cannot unaccept job", nil, err,
				)
				return
			}
			if errors.Is(err, utils.ErrNoRowsUpdated) {
				utils.RespondErrorWithCode(
					w, http.StatusConflict, utils.ErrCodeRowVersionConflict,
					"No rows updated, please refresh", nil, err,
				)
				return
			}
			utils.Logger.WithError(err).Error("Unaccept job error")
			utils.RespondErrorWithCode(
				w, http.StatusInternalServerError, utils.ErrCodeInternal,
				"Could not unaccept job", nil, err,
			)
			return
		}
	}
	if updated == nil {
		utils.RespondErrorWithCode(
			w, http.StatusNotFound, utils.ErrCodeNotFound,
			"Job instance not found or not assigned to you", nil, nil,
		)
		return
	}
	utils.RespondWithJSON(w, http.StatusOK, dtos.JobInstanceActionResponse{Updated: *updated})
}

// ----------------------------------------------------------------
// POST /api/v1/jobs/cancel
// ...
// ----------------------------------------------------------------
func (c *JobsController) CancelJobHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	ctxUserID := ctx.Value(middleware.ContextKeyUserID)
	if ctxUserID == nil {
		utils.RespondErrorWithCode(
			w, http.StatusUnauthorized, utils.ErrCodeUnauthorized,
			"No userID in context", nil, nil,
		)
		return
	}
	var req dtos.JobInstanceActionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload,
			"Invalid JSON body", nil, err,
		)
		return
	}
	if req.InstanceID == uuid.Nil {
		utils.RespondErrorWithCode(
			w, http.StatusBadRequest, utils.ErrCodeInvalidPayload,
			"instance_id is required", nil, nil,
		)
		return
	}
	updated, svcErr := c.jobService.CancelJobInstance(ctx, ctxUserID.(string), req.InstanceID)
	if svcErr != nil {
		switch e := svcErr.(type) {
		case *internal_utils.RowVersionConflictError:
			utils.RespondErrorWithCode(
				w, http.StatusConflict, utils.ErrCodeRowVersionConflict,
				"Row version conflict, please refresh",
				e.Current,
				svcErr,
			)
			return
		default:
			if errors.Is(svcErr, internal_utils.ErrNotAssignedWorker) ||
				errors.Is(svcErr, internal_utils.ErrWrongStatus) {
				utils.RespondErrorWithCode(
					w, http.StatusBadRequest, svcErr.Error(),
					"Could not cancel job", nil, svcErr,
				)
				return
			}
			if errors.Is(svcErr, utils.ErrNoRowsUpdated) {
				utils.RespondErrorWithCode(
					w, http.StatusConflict, utils.ErrCodeRowVersionConflict,
					"No rows updated, please refresh", nil, svcErr,
				)
				return
			}
			utils.Logger.WithError(svcErr).Error("Cancel job error")
			utils.RespondErrorWithCode(
				w, http.StatusInternalServerError, utils.ErrCodeInternal,
				"Could not cancel job", nil, svcErr,
			)
			return
		}
	}
	if updated == nil {
		utils.RespondErrorWithCode(
			w, http.StatusNotFound, utils.ErrCodeNotFound,
			"Job instance not found or not in progress", nil, nil,
		)
		return
	}
	utils.RespondWithJSON(w, http.StatusOK, dtos.JobInstanceActionResponse{Updated: *updated})
}

// ----------------------------------------------------------------
// parseListQueryAndLocation ...
// ----------------------------------------------------------------
func parseListQueryAndLocation(r *http.Request) (dtos.ListJobsQuery, *time.Location, error) {
	latStr := r.URL.Query().Get("lat")
	lngStr := r.URL.Query().Get("lng")
	if latStr == "" || lngStr == "" {
		return dtos.ListJobsQuery{}, nil,
			fmt.Errorf("lat and lng are required query params")
	}
	lat, err := strconv.ParseFloat(latStr, 64)
	if err != nil {
		return dtos.ListJobsQuery{}, nil,
			fmt.Errorf("invalid lat param: %w", err)
	}
	lng, err := strconv.ParseFloat(lngStr, 64)
	if err != nil {
		return dtos.ListJobsQuery{}, nil,
			fmt.Errorf("invalid lng param: %w", err)
	}

	pageStr := r.URL.Query().Get("page")
	if pageStr == "" {
		pageStr = "1"
	}
	sizeStr := r.URL.Query().Get("size")
	if sizeStr == "" {
		sizeStr = "50"
	}
	page, e1 := strconv.Atoi(pageStr)
	if e1 != nil || page < 1 {
		page = 1
	}
	size, e2 := strconv.Atoi(sizeStr)
	if e2 != nil || size < 1 {
		size = 50
	}

	tzName := latlong.LookupZoneName(lat, lng)
	if tzName == "" {
		tzName = "UTC"
	}
	loc, err := time.LoadLocation(tzName)
	if err != nil {
		loc = time.UTC
	}

	q := dtos.ListJobsQuery{
		Lat:  lat,
		Lng:  lng,
		Page: page,
		Size: size,
	}
	return q, loc, nil
}
