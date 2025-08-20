package checkr

import "time"

// ErrorResponse is used if Checkr returns an error in JSON form
type ErrorResponse struct {
	Error string `json:"error,omitempty"`
}

// Candidate represents the Checkr candidate resource.
type Candidate struct {
	ID                          string            `json:"id,omitempty"`
	Object                      string            `json:"object,omitempty"`
	URI                         string            `json:"uri,omitempty"`
	FirstName                   string            `json:"first_name,omitempty"`
	MiddleName                  string            `json:"middle_name,omitempty"`
	LastName                    string            `json:"last_name,omitempty"`
	NoMiddleName                bool              `json:"no_middle_name,omitempty"`
	Email                       string            `json:"email,omitempty"`
	Phone                       string            `json:"phone,omitempty"`
	Zipcode                     string            `json:"zipcode,omitempty"`
	Dob                         string            `json:"dob,omitempty"` // "YYYY-MM-DD"
	SSN                         string            `json:"ssn,omitempty"`
	WorkLocations               []WorkLocation    `json:"work_locations,omitempty"`
	DriverLicenseNumber         string            `json:"driver_license_number,omitempty"`
	DriverLicenseState          string            `json:"driver_license_state,omitempty"`
	PreviousDriverLicenseNumber string            `json:"previous_driver_license_number,omitempty"`
	PreviousDriverLicenseState  string            `json:"previous_driver_license_state,omitempty"`
	CopyRequested               bool              `json:"copy_requested,omitempty"`
	CustomID                    string            `json:"custom_id,omitempty"`
	ReportIDs                   []string          `json:"report_ids,omitempty"`
	GeoIDs                      []string          `json:"geo_ids,omitempty"`
	Adjudication                string            `json:"adjudication,omitempty"`
	MotherMaidenName            string            `json:"mother_maiden_name,omitempty"`
	Metadata                    map[string]any    `json:"metadata,omitempty"`
}

// Invitation represents the Checkr invitation resource (hosted apply flow).
type Invitation struct {
	ID            string       `json:"id,omitempty"`
	Object        string       `json:"object,omitempty"`
	URI           string       `json:"uri,omitempty"`
	InvitationURL string       `json:"invitation_url,omitempty"`
	Status        string       `json:"status,omitempty"`
	CreatedAt     *time.Time   `json:"created_at,omitempty"`
	ExpiresAt     *time.Time   `json:"expires_at,omitempty"`
	CompletedAt   *time.Time   `json:"completed_at,omitempty"`
	DeletedAt     *time.Time   `json:"deleted_at,omitempty"`
	Package       string       `json:"package,omitempty"`
	CandidateID   string       `json:"candidate_id,omitempty"`
	ReportID      string       `json:"report_id,omitempty"`
	WorkLocations []WorkLocation `json:"work_locations,omitempty"`
}

// Package is a background-check package configuration returned by /packages.
type Package struct {
	ID         string     `json:"id,omitempty"`
	Object     string     `json:"object,omitempty"`
	Uri        string     `json:"uri,omitempty"`
	ApplyURL   string     `json:"apply_url,omitempty"`
	CreatedAt  *time.Time `json:"created_at,omitempty"`
	DeletedAt  *time.Time `json:"deleted_at,omitempty"`
	Name       string     `json:"name,omitempty"`
	Slug       string     `json:"slug,omitempty"`
	Price      int        `json:"price,omitempty"`
	Screenings []struct {
		Type    string `json:"type,omitempty"`
		Subtype string `json:"subtype,omitempty"`
	} `json:"screenings,omitempty"`
}

// Report object
type Report struct {
	ID                          string            `json:"id,omitempty"`
	Object                      string            `json:"object,omitempty"`
	URI                         string            `json:"uri,omitempty"`
	Status                      ReportStatus      `json:"status,omitempty"`
	Result                      *ReportResult     `json:"result,omitempty"`
	IncludesCanceled            bool              `json:"includes_canceled,omitempty"`
	CreatedAt                   *time.Time        `json:"created_at,omitempty"`
	CompletedAt                 *time.Time        `json:"completed_at,omitempty"`
	RevisedAt                   *time.Time        `json:"revised_at,omitempty"`
	UpgradedAt                  *time.Time        `json:"upgraded_at,omitempty"`
	TurnaroundTime              int               `json:"turnaround_time,omitempty"`
	Package                     string            `json:"package,omitempty"`
	Adjudication                *ReportAdjudication `json:"adjudication,omitempty"`
	Assessment                  *ReportAssessment `json:"assessment,omitempty"`
	Source                      string            `json:"source,omitempty"`
	SegmentStamps               []string          `json:"segment_stamps,omitempty"`
	WorkLocations               []WorkLocation    `json:"work_locations,omitempty"`
	EstimatedTime               *time.Time        `json:"estimated_completion_time,omitempty"`
	CandidateStoryIDs           []string          `json:"candidate_story_ids,omitempty"`
	CandidateID                 string            `json:"candidate_id,omitempty"`

	DrugScreening *DrugScreening `json:"drug_screening,omitempty"`

	SSNTraceID                           string   `json:"ssn_trace_id,omitempty"`
	ArrestSearchID                       string   `json:"arrest_search_id,omitempty"`
	DrugScreeningID                      string   `json:"drug_screening_id,omitempty"`
	FacisSearchID                        string   `json:"facis_search_id,omitempty"`
	FederalCriminalSearchID              string   `json:"federal_criminal_search_id,omitempty"`
	GlobalWatchlistSearchID              string   `json:"global_watchlist_search_id,omitempty"`
	SexOffenderSearchID                  string   `json:"sex_offender_search_id,omitempty"`
	NationalCriminalSearchID             string   `json:"national_criminal_search_id,omitempty"`
	CountyCriminalSearchIDs              []string `json:"county_criminal_search_ids,omitempty"`
	PersonalReferenceVerificationIDs     []string `json:"personal_reference_verification_ids,omitempty"`
	ProfessionalReferenceVerificationIDs []string `json:"professional_reference_verification_ids,omitempty"`
	MotorVehicleReportID                 string   `json:"motor_vehicle_report_id,omitempty"`
	ProfessionalLicenseVerificationIDs   []string `json:"professional_license_verification_ids,omitempty"`
	StateCriminalSearches                []string `json:"state_criminal_searches,omitempty"`
	DocumentIDs                          []string `json:"document_ids,omitempty"`
	GeoIDs                               []string `json:"geo_ids,omitempty"`
	ProgramID                            string   `json:"program_id,omitempty"`
}

type ReportStatus string

const (
	ReportStatusPending   ReportStatus = "pending"
	ReportStatusComplete  ReportStatus = "complete"
	ReportStatusCanceled  ReportStatus = "canceled"
	ReportStatusDispute   ReportStatus = "dispute"
	ReportStatusSuspended ReportStatus = "suspended"
)

// Nullable
type ReportResult string

const (
	ReportResultClear    ReportResult = "clear"
	ReportResultConsider ReportResult = "consider"
)

// Nullable
type ReportAdjudication string

const (
	ReportAdjudicationEngaged           ReportAdjudication = "engaged"
	ReportAdjudicationPreAdverseAction  ReportAdjudication = "pre_adverse_action"
	ReportAdjudicationPostAdverseAction ReportAdjudication = "post_adverse_action"
)

// Nullable
type ReportAssessment string

const (
	ReportAssessmentEligible  ReportAssessment = "eligible"
	ReportAssessmentReview    ReportAssessment = "review"
	ReportAssessmentEscalated ReportAssessment = "escalated"
)

// WorkLocation is used within a Report or ContinuousCheck for "work_locations".
type WorkLocation struct {
	State   string `json:"state,omitempty"`
	Country string `json:"country,omitempty"`
	City    string `json:"city,omitempty"`
}

// DrugScreening describes the nested "drug_screening" field in a Report.
type DrugScreening struct {
	ID                     string        `json:"id,omitempty"`
	Status                 string        `json:"status,omitempty"`
	Result                 string        `json:"result,omitempty"`
	Disposition            string        `json:"disposition,omitempty"`
	MroNotes               string        `json:"mro_notes,omitempty"`
	Analytes               []DrugAnalyte `json:"analytes,omitempty"`
	Events                 []DrugEvent   `json:"events,omitempty"`
	ScreeningPassExpiresAt *time.Time    `json:"screening_pass_expires_at,omitempty"`
	AppointmentID          string        `json:"appointment_id,omitempty"`
}

// DrugAnalyte defines each item in the "analytes" array of a DrugScreening.
type DrugAnalyte struct {
	Name         string `json:"name,omitempty"`
	Disposition  string `json:"disposition,omitempty"`
	SpecimenType string `json:"specimen_type,omitempty"`
}

// DrugEvent defines each item in the "events" array of a DrugScreening.
type DrugEvent struct {
	Type      string     `json:"type,omitempty"`
	Text      string     `json:"text,omitempty"`
	CreatedAt *time.Time `json:"created_at,omitempty"`
}

// ETAResponse is returned by GET /reports/{id}/eta
type ETAResponse struct {
	EstimateGeneratedAt     *time.Time `json:"estimate_generated_at,omitempty"`
	EstimatedCompletionTime *time.Time `json:"estimated_completion_time,omitempty"`
}

// AdverseItem is returned by GET /reports/{report_id}/adverse_items
type AdverseItem struct {
	ID         string            `json:"id,omitempty"`
	Object     string            `json:"object,omitempty"`
	Text       string            `json:"text,omitempty"`
	Assessment *AdverseAssessment `json:"assessment,omitempty"`
}

// AdverseAssessment holds the nested "value" / "rule" objects for an adverse_item.
type AdverseAssessment struct {
	Value *AdverseValue `json:"value,omitempty"`
	Rule  *AdverseValue `json:"rule,omitempty"`
}

// AdverseValue is the final nested field under "assessment".
type AdverseValue struct {
	Value string `json:"value,omitempty"`
}

// AdverseAction object
type AdverseAction struct {
	ID                            string         `json:"id,omitempty"`
	Object                        string         `json:"object,omitempty"`
	Uri                           string         `json:"uri,omitempty"`
	CreatedAt                     *time.Time     `json:"created_at,omitempty"`
	Status                        string         `json:"status,omitempty"`
	ReportID                      string         `json:"report_id,omitempty"`
	PostNoticeScheduledAt         *time.Time     `json:"post_notice_scheduled_at,omitempty"`
	PostNoticeReadyAt             *time.Time     `json:"post_notice_ready_at,omitempty"`
	CanceledAt                    *time.Time     `json:"canceled_at,omitempty"`
	AdverseItems                  []AdverseItem  `json:"adverse_items,omitempty"`
	IndividualizedAssessmentEngaged bool         `json:"individualized_assessment_engaged,omitempty"`
}

// ContinuousCheck object
type ContinuousCheck struct {
	ID            string         `json:"id,omitempty"`
	Object        string         `json:"object,omitempty"`
	Type          string         `json:"type,omitempty"`
	CreatedAt     *time.Time     `json:"created_at,omitempty"`
	CandidateID   string         `json:"candidate_id,omitempty"`
	Node          string         `json:"node,omitempty"`
	WorkLocations []WorkLocation `json:"work_locations,omitempty"`
}

// Webhook configuration
type Webhook struct {
	ID            string     `json:"id,omitempty"`
	Object        string     `json:"object,omitempty"`
	WebhookURL    string     `json:"webhook_url,omitempty"`
	Uri           string     `json:"uri,omitempty"`
	AccountID     string     `json:"account_id,omitempty"`
	ApplicationID string     `json:"application_id,omitempty"`
	IncludeObject bool       `json:"include_object,omitempty"`
	CreatedAt     *time.Time `json:"created_at,omitempty"`
	DeletedAt     *time.Time `json:"deleted_at,omitempty"`
}

// ListResponse[T] is a generic struct for listing endpoints if needed.
type ListResponse[T any] struct {
	Object   string `json:"object,omitempty"`
	Count    int    `json:"count,omitempty"`
	Data     []T    `json:"data,omitempty"`
	NextHref string `json:"next_href,omitempty"`
	PrevHref string `json:"previous_href,omitempty"`
}

// NEW: SessionToken for Web SDK Embeds
type SessionToken struct {
	Token string `json:"token"`
}
