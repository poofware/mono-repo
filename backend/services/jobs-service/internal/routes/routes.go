package routes

const (
	// Health
	Health = "/health"

	// Worker endpoints
	JobsBase     = "/api/v1/jobs"
	JobsOpen     = "/api/v1/jobs/open"
	JobsMy       = "/api/v1/jobs/my"
	JobsAccept   = "/api/v1/jobs/accept"
	JobsUnaccept = "/api/v1/jobs/unaccept"

	// NEW endpoints for unit verification workflow
	JobsVerifyUnitPhoto = "/api/v1/jobs/verify-unit-photo"
	JobsDumpBags        = "/api/v1/jobs/dump-bags"

	// NEW endpoint for “start job”
	JobsStart = "/api/v1/jobs/start"

	// NEW endpoint for “cancel job” (IN_PROGRESS → CANCELED)
	JobsCancel = "/api/v1/jobs/cancel"

	// Manager or system endpoint
	JobsDefinitionStatus = "/api/v1/jobs/definition/status"
	JobsDefinitionCreate = "/api/v1/manager/jobs/definition"
	JobsPMInstances      = "/api/v1/jobs/pm/instances"

	// Admin endpoints (NEW)
	AdminJobsBase       = "/api/v1/jobs/admin"
	AdminJobDefinitions = "/api/v1/jobs/admin/job-definitions"

	// Public agent completion endpoint
	JobsAgentComplete = "/api/v1/jobs/agent-complete/{token}"
)
