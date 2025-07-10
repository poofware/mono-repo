-- 000001_initial.up.sql
-- ----------------------------------------------------------------------
--  ENUM types
-- ----------------------------------------------------------------------
CREATE TYPE account_status_type AS ENUM (
    'INCOMPLETE',
    'BACKGROUND_CHECK_PENDING',
    'ACTIVE'
);
CREATE TYPE setup_progress_type AS ENUM (
    'AWAITING_PERSONAL_INFO',
    'ID_VERIFY',
    'ACH_PAYMENT_ACCOUNT_SETUP',
    'BACKGROUND_CHECK',
    'DONE'
);
CREATE TYPE report_outcome_type AS ENUM (
    'APPROVED',
    'REVIEW_CHARGES',
    'REVIEW_CANCELED_SCREENINGS',
    'REVIEW_CHARGES_AND_CANCELED_SCREENINGS',
    'DISPUTE_PENDING',
    'SUSPENDED',
    'UNSUSPENDED',
    'CANCELED',
    'PRE_ADVERSE_ACTION',
    'DISQUALIFIED',
    'UNKNOWN'
);
CREATE TYPE job_status_type AS ENUM (
    'ACTIVE',
    'PAUSED',
    'ARCHIVED',
    'DELETED'
);
CREATE TYPE job_frequency_type AS ENUM (
    'DAILY',
    'WEEKDAYS',
    'WEEKLY',
    'BIWEEKLY',
    'MONTHLY',
    'CUSTOM'
);
CREATE TYPE instance_status_type AS ENUM (
    'OPEN',
    'ASSIGNED',
    'IN_PROGRESS',
    'COMPLETED',
    'RETIRED',
    'CANCELED'
);
CREATE TYPE payout_status_type AS ENUM (
    'PENDING',
    'PROCESSING',
    'PAID',
    'FAILED'
);

-- Function to validate the daily_pay_estimates JSONB array
CREATE OR REPLACE FUNCTION validate_daily_pay_estimates_array(estimates JSONB)
RETURNS BOOLEAN AS $$
DECLARE
    estimate JSONB;
    base_pay NUMERIC;
    init_base_pay NUMERIC;
    est_time_min INT;
    init_est_time_min INT;
    day_of_week INT;
BEGIN
    -- Check if it's an array and not empty
    IF jsonb_typeof(estimates) != 'array' OR jsonb_array_length(estimates) = 0 THEN
        RETURN FALSE;
    END IF;

    FOR estimate IN SELECT * FROM jsonb_array_elements(estimates)
    LOOP
        -- Extract and validate fields for each element
        base_pay := (estimate ->> 'base_pay')::NUMERIC;
        init_base_pay := (estimate ->> 'initial_base_pay')::NUMERIC;
        est_time_min := (estimate ->> 'estimated_time_minutes')::INT;
        init_est_time_min := (estimate ->> 'initial_estimated_time_minutes')::INT;
        day_of_week := (estimate ->> 'day_of_week')::INT;

        IF NOT (base_pay > 0 AND init_base_pay > 0 AND est_time_min > 0 AND init_est_time_min > 0 AND day_of_week >= 0 AND day_of_week <= 6) THEN
            RETURN FALSE; -- One element failed validation
        END IF;
    END LOOP;
    RETURN TRUE; -- All elements passed
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ----------------------------------------------------------------------
--  admins
-- ----------------------------------------------------------------------
CREATE TABLE admins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    totp_secret VARCHAR(255),
    account_status ACCOUNT_STATUS_TYPE NOT NULL DEFAULT 'INCOMPLETE',
    setup_progress SETUP_PROGRESS_TYPE NOT NULL DEFAULT 'ID_VERIFY',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    row_version BIGINT NOT NULL DEFAULT 1
);
CREATE INDEX idx_admins_username ON admins (username);

-- ----------------------------------------------------------------------
--  property_managers
-- ----------------------------------------------------------------------
CREATE TABLE property_managers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    phone_number VARCHAR(20) UNIQUE,
    totp_secret VARCHAR(255),
    business_name VARCHAR(255) NOT NULL,
    business_address VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(50) NOT NULL,
    zip_code VARCHAR(20) NOT NULL,
    account_status ACCOUNT_STATUS_TYPE NOT NULL DEFAULT 'INCOMPLETE',
    setup_progress SETUP_PROGRESS_TYPE NOT NULL DEFAULT 'ID_VERIFY',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    row_version BIGINT NOT NULL DEFAULT 1
);
CREATE INDEX idx_pm_email ON property_managers (email);
CREATE INDEX idx_pm_phone_number ON property_managers (phone_number);

-- ----------------------------------------------------------------------
--  workers
-- ----------------------------------------------------------------------
CREATE TABLE workers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    totp_secret VARCHAR(255),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    street_address VARCHAR(255) NOT NULL DEFAULT '',
    apt_suite VARCHAR(50),
    city VARCHAR(100) NOT NULL DEFAULT '',
    state VARCHAR(50) NOT NULL DEFAULT '',
    zip_code VARCHAR(20) NOT NULL DEFAULT '',
    vehicle_year INT NOT NULL DEFAULT 0,
    vehicle_make VARCHAR(100) NOT NULL DEFAULT '',
    vehicle_model VARCHAR(100) NOT NULL DEFAULT '',
    tenant_token VARCHAR(255) UNIQUE,
    account_status ACCOUNT_STATUS_TYPE NOT NULL DEFAULT 'INCOMPLETE',
    setup_progress SETUP_PROGRESS_TYPE
    NOT NULL DEFAULT 'AWAITING_PERSONAL_INFO',
    stripe_connect_account_id VARCHAR(255) UNIQUE,
    current_stripe_idv_session_id VARCHAR(255) UNIQUE,
    checkr_candidate_id VARCHAR(255) UNIQUE,
    checkr_invitation_id VARCHAR(255) UNIQUE,
    checkr_report_id VARCHAR(255) UNIQUE,
    checkr_report_outcome REPORT_OUTCOME_TYPE NOT NULL DEFAULT 'UNKNOWN',
    checkr_report_eta TIMESTAMP WITH TIME ZONE,
    reliability_score INT NOT NULL DEFAULT 100,
    is_banned BOOLEAN NOT NULL DEFAULT FALSE,
    suspended_until TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    row_version BIGINT NOT NULL DEFAULT 1
);
CREATE INDEX idx_worker_email ON workers (email);
CREATE INDEX idx_worker_phone_number ON workers (phone_number);

-- ----------------------------------------------------------------------
--  properties
-- ----------------------------------------------------------------------
CREATE TABLE properties (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_id UUID REFERENCES property_managers (id) ON DELETE CASCADE,
    property_name VARCHAR(255) NOT NULL,
    address VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(50) NOT NULL,
    zip_code VARCHAR(20) NOT NULL,
    time_zone VARCHAR(50) NOT NULL,
    latitude DECIMAL(9, 6) NOT NULL DEFAULT 0,
    longitude DECIMAL(9, 6) NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    row_version BIGINT NOT NULL DEFAULT 1
);
CREATE INDEX idx_properties_manager_id ON properties (manager_id);

-- ----------------------------------------------------------------------
--  property_buildings
-- ----------------------------------------------------------------------
CREATE TABLE property_buildings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID REFERENCES properties (id) ON DELETE CASCADE,
    building_name VARCHAR(100),
    address VARCHAR(255),
    latitude DECIMAL(9, 6),
    longitude DECIMAL(9, 6),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    row_version BIGINT NOT NULL DEFAULT 1
);
CREATE INDEX idx_property_buildings_property_id
ON property_buildings (property_id);

-- ----------------------------------------------------------------------
--  units
-- ----------------------------------------------------------------------
CREATE TABLE units (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID REFERENCES properties (id) ON DELETE CASCADE,
    building_id UUID REFERENCES property_buildings (id) ON DELETE CASCADE,
    unit_number VARCHAR(50) NOT NULL,
    tenant_token VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    row_version BIGINT NOT NULL DEFAULT 1,
    CONSTRAINT check_tenant_token_not_empty CHECK (tenant_token <> '')
);
CREATE INDEX idx_units_tenant_token ON units (tenant_token);
CREATE INDEX idx_units_property_id ON units (property_id);

-- ----------------------------------------------------------------------
--  dumpsters
-- ----------------------------------------------------------------------
CREATE TABLE dumpsters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID REFERENCES properties (id) ON DELETE CASCADE,
    dumpster_number VARCHAR(50) NOT NULL,
    latitude DECIMAL(9, 6) NOT NULL,
    longitude DECIMAL(9, 6) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    row_version BIGINT NOT NULL DEFAULT 1
);
CREATE INDEX idx_dumpsters_property_id ON dumpsters (property_id);

-- ----------------------------------------------------------------------
--  job_definitions
-- ----------------------------------------------------------------------
CREATE TABLE job_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    manager_id UUID NOT NULL
    REFERENCES property_managers (id) ON DELETE CASCADE,

    property_id UUID NOT NULL
    REFERENCES properties (id) ON DELETE CASCADE,

    title VARCHAR(255) NOT NULL,
    description TEXT,
    assigned_building_ids UUID [] NOT NULL,
    dumpster_ids UUID [] NOT NULL,
    status JOB_STATUS_TYPE NOT NULL DEFAULT 'ACTIVE',
    frequency JOB_FREQUENCY_TYPE NOT NULL DEFAULT 'DAILY',
    weekdays SMALLINT [], -- 0=Sunday, 1=Monday, ..., 6=Saturday
    interval_weeks INT,
    start_date DATE NOT NULL,
    end_date DATE,
    earliest_start_time TIME NOT NULL,
    latest_start_time TIME NOT NULL,
    start_time_hint TIME NOT NULL,
    skip_holidays BOOLEAN NOT NULL DEFAULT FALSE,
    holiday_exceptions DATE [],
    details JSONB,
    requirements JSONB,
    daily_pay_estimates JSONB NOT NULL,
    completion_rules JSONB,
    support_contact JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    row_version BIGINT NOT NULL DEFAULT 1,
    CONSTRAINT job_time_window_ck CHECK (
        latest_start_time > earliest_start_time
        AND
        (latest_start_time - earliest_start_time) >= INTERVAL '90 minute'
    ),
    CONSTRAINT job_start_time_hint_ck CHECK (
        start_time_hint >= earliest_start_time
        AND
        start_time_hint <= (latest_start_time - INTERVAL '50 minute')
    ),
    CONSTRAINT job_daily_pay_estimates_ck
    CHECK (validate_daily_pay_estimates_array(daily_pay_estimates)),
    CONSTRAINT check_assigned_building_ids_not_empty
    CHECK (array_length(assigned_building_ids, 1) >= 1),
    CONSTRAINT check_dumpster_ids_not_empty
    CHECK (array_length(dumpster_ids, 1) >= 1)
);
CREATE INDEX idx_job_definitions_manager_id ON job_definitions (manager_id);
CREATE INDEX idx_job_definitions_property_id ON job_definitions (property_id);

-- ----------------------------------------------------------------------
--  job_instances
-- ----------------------------------------------------------------------
CREATE TABLE job_instances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    definition_id UUID NOT NULL
    REFERENCES job_definitions (id) ON DELETE CASCADE,

    service_date DATE NOT NULL,
    status INSTANCE_STATUS_TYPE NOT NULL DEFAULT 'OPEN',
    assigned_worker_id UUID REFERENCES workers (id),
    effective_pay NUMERIC(10, 2) NOT NULL DEFAULT 0,
    check_in_at TIMESTAMP WITH TIME ZONE,
    check_out_at TIMESTAMP WITH TIME ZONE,
    excluded_worker_ids UUID [] NOT NULL DEFAULT '{}',
    assign_unassign_count INT NOT NULL DEFAULT 0,
    flagged_for_review BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    row_version BIGINT NOT NULL DEFAULT 1,
    UNIQUE (definition_id, service_date),
    CONSTRAINT assigned_worker_id_status_ck CHECK (
        (status = 'OPEN' AND assigned_worker_id IS NULL)
        OR
        (
            status IN ('ASSIGNED', 'IN_PROGRESS', 'COMPLETED')
            AND
            assigned_worker_id IS NOT NULL
        )
        OR
        (status IN ('RETIRED', 'CANCELED'))
    )
);
CREATE INDEX idx_job_instances_service_date ON job_instances (service_date);
CREATE INDEX idx_job_instances_status ON job_instances (status);
CREATE INDEX idx_job_instances_definition_id ON job_instances (definition_id);

-- ----------------------------------------------------------------------
--  admin_audit_logs
-- ----------------------------------------------------------------------
CREATE TYPE audit_action AS ENUM ('CREATE', 'UPDATE', 'DELETE', 'READ');
CREATE TYPE audit_target_type AS ENUM ('PROPERTY_MANAGER', 'PROPERTY', 'BUILDING', 'UNIT', 'DUMPSTER', 'JOB_DEFINITION');

CREATE TABLE admin_audit_logs (
    id UUID PRIMARY KEY,
    admin_id UUID NOT NULL REFERENCES admins(id),
    action audit_action NOT NULL,
    target_id UUID NOT NULL,
    target_type audit_target_type NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_admin_audit_logs_admin_id ON admin_audit_logs(admin_id);
CREATE INDEX idx_admin_audit_logs_target ON admin_audit_logs(target_type, target_id);

-- ----------------------------------------------------------------------
--  admin_refresh_tokens
-- ----------------------------------------------------------------------
CREATE TABLE admin_refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID REFERENCES admins (id) ON DELETE CASCADE,
    refresh_token VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    revoked BOOLEAN DEFAULT FALSE,
    ip_address VARCHAR(45),
    device_id VARCHAR(255)
);
CREATE INDEX idx_admin_refresh_tokens_token ON admin_refresh_tokens (refresh_token);

-- ----------------------------------------------------------------------
--  pm_refresh_tokens
-- ----------------------------------------------------------------------
CREATE TABLE pm_refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pm_id UUID REFERENCES property_managers (id) ON DELETE CASCADE,
    refresh_token VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    revoked BOOLEAN DEFAULT FALSE,
    ip_address VARCHAR(45),
    device_id VARCHAR(255)
);
CREATE INDEX idx_pm_refresh_tokens ON pm_refresh_tokens (refresh_token);

-- ----------------------------------------------------------------------
--  worker_refresh_tokens
-- ----------------------------------------------------------------------
CREATE TABLE worker_refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    worker_id UUID REFERENCES workers (id) ON DELETE CASCADE,
    refresh_token VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    revoked BOOLEAN DEFAULT FALSE,
    ip_address VARCHAR(45),
    device_id VARCHAR(255)
);
CREATE INDEX idx_worker_refresh_tokens ON worker_refresh_tokens (refresh_token);

-- ----------------------------------------------------------------------
--  admin_login_attempts
-- ----------------------------------------------------------------------
CREATE TABLE admin_login_attempts (
    admin_id UUID PRIMARY KEY REFERENCES admins (id) ON DELETE CASCADE,
    attempt_count INT NOT NULL DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- ----------------------------------------------------------------------
--  pm_login_attempts
-- ----------------------------------------------------------------------
CREATE TABLE pm_login_attempts (
    pm_id UUID PRIMARY KEY
    REFERENCES property_managers (id) ON DELETE CASCADE,

    attempt_count INT NOT NULL DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- ----------------------------------------------------------------------
--  worker_login_attempts
-- ----------------------------------------------------------------------
CREATE TABLE worker_login_attempts (
    worker_id UUID PRIMARY KEY REFERENCES workers (id) ON DELETE CASCADE,
    attempt_count INT NOT NULL DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- ----------------------------------------------------------------------
--  rate_limit_attempts (for SMS/email pump protection)
-- ----------------------------------------------------------------------
CREATE TABLE rate_limit_attempts (
    key TEXT PRIMARY KEY,
    attempt_count INT NOT NULL DEFAULT 1,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL
);
CREATE INDEX idx_rate_limit_attempts_expires_at
ON rate_limit_attempts (expires_at);

-- ----------------------------------------------------------------------
--  pm_email_verification_codes
-- ----------------------------------------------------------------------
CREATE TABLE pm_email_verification_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pm_id UUID,
    pm_email TEXT NOT NULL,
    verification_code TEXT NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    attempts INT DEFAULT 0,
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    verified_at TIMESTAMP,
    verified_by VARCHAR(64),
    created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_pm_email_verification_codes_email
ON pm_email_verification_codes (pm_email);

-- ----------------------------------------------------------------------
--  pm_sms_verification_codes
-- ----------------------------------------------------------------------
CREATE TABLE pm_sms_verification_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pm_id UUID,
    pm_phone VARCHAR(20) NOT NULL,
    verification_code VARCHAR(10) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    attempts INT DEFAULT 0,
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    verified_at TIMESTAMP,
    verified_by VARCHAR(64),
    created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_pm_sms_verification_codes_phone
ON pm_sms_verification_codes (pm_phone);

-- ----------------------------------------------------------------------
--  worker_email_verification_codes
-- ----------------------------------------------------------------------
CREATE TABLE worker_email_verification_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    worker_id UUID,
    worker_email TEXT NOT NULL,
    verification_code TEXT NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    attempts INT DEFAULT 0,
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    verified_at TIMESTAMP,
    verified_by VARCHAR(64),
    created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_worker_email_verification_codes_email
ON worker_email_verification_codes (worker_email);

-- ----------------------------------------------------------------------
--  worker_sms_verification_codes
-- ----------------------------------------------------------------------
CREATE TABLE worker_sms_verification_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    worker_id UUID,
    worker_phone VARCHAR(20) NOT NULL,
    verification_code VARCHAR(10) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    attempts INT DEFAULT 0,
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    verified_at TIMESTAMP,
    verified_by VARCHAR(64),
    created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_worker_sms_verification_codes_phone
ON worker_sms_verification_codes (worker_phone);

-- ----------------------------------------------------------------------
--  admin_blacklisted_tokens
-- ----------------------------------------------------------------------
CREATE TABLE admin_blacklisted_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_id VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
CREATE INDEX idx_admin_blacklisted_tokens_token_id ON admin_blacklisted_tokens (token_id);

-- ----------------------------------------------------------------------
--  pm_blacklisted_tokens
-- ----------------------------------------------------------------------
CREATE TABLE pm_blacklisted_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_id VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
CREATE INDEX idx_pm_blacklisted_tokens_token_id
ON pm_blacklisted_tokens (token_id);

-- ----------------------------------------------------------------------
--  worker_blacklisted_tokens
-- ----------------------------------------------------------------------
CREATE TABLE worker_blacklisted_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_id VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
CREATE INDEX idx_worker_blacklisted_tokens_token_id
ON worker_blacklisted_tokens (token_id);

-- ----------------------------------------------------------------------
--  worker_score_events (tracks reliability changes)
-- ----------------------------------------------------------------------
CREATE TABLE worker_score_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    worker_id UUID NOT NULL REFERENCES workers (id) ON DELETE CASCADE,
    event_type VARCHAR(50) NOT NULL,
    delta INT NOT NULL,
    old_score INT NOT NULL,
    new_score INT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- ----------------------------------------------------------------------
--  poof_representatives
-- ----------------------------------------------------------------------
CREATE TABLE poof_representatives (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    phone_number VARCHAR(20) NOT NULL UNIQUE,
    region VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- ----------------------------------------------------------------------
--  iOS App Attest keys
-- ----------------------------------------------------------------------
CREATE TABLE app_attest_keys (
    key_id BYTEA PRIMARY KEY,
    public_key BYTEA NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- ----------------------------------------------------------------------
--  Attestation Challenges
-- ----------------------------------------------------------------------
CREATE TABLE attestation_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    raw_challenge BYTEA NOT NULL,
    platform VARCHAR(10) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_attestation_challenges_expires_at
ON attestation_challenges (expires_at);

-- ----------------------------------------------------------------------
--  worker_payouts
-- ----------------------------------------------------------------------
CREATE TABLE worker_payouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    worker_id UUID NOT NULL REFERENCES workers (id),
    week_start_date TIMESTAMPTZ NOT NULL,
    week_end_date TIMESTAMPTZ NOT NULL,
    amount_cents BIGINT NOT NULL,
    status PAYOUT_STATUS_TYPE NOT NULL DEFAULT 'PENDING',
    stripe_transfer_id VARCHAR(255),
    stripe_payout_id VARCHAR(255),
    last_failure_reason TEXT,
    retry_count INT NOT NULL DEFAULT 0,
    last_attempt_at TIMESTAMPTZ,
    next_attempt_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    row_version BIGINT NOT NULL DEFAULT 1,
    UNIQUE (worker_id, week_start_date)
);
CREATE INDEX idx_worker_payouts_status ON worker_payouts (status);
CREATE INDEX idx_worker_payouts_worker_id ON worker_payouts (worker_id);

---- create above / drop below ----

-- 000001_initial.down.sql
DROP TABLE IF EXISTS worker_payouts;
DROP TABLE IF EXISTS attestation_challenges;
DROP TABLE IF EXISTS worker_score_events;
DROP TABLE IF EXISTS poof_representatives;
DROP TABLE IF EXISTS worker_blacklisted_tokens;
DROP TABLE IF EXISTS pm_blacklisted_tokens;
DROP TABLE IF EXISTS admin_blacklisted_tokens;
DROP TABLE IF EXISTS worker_sms_verification_codes;
DROP TABLE IF EXISTS worker_email_verification_codes;
DROP TABLE IF EXISTS pm_sms_verification_codes;
DROP TABLE IF EXISTS pm_email_verification_codes;
DROP TABLE IF EXISTS rate_limit_attempts;
DROP TABLE IF EXISTS worker_login_attempts;
DROP TABLE IF EXISTS pm_login_attempts;
DROP TABLE IF EXISTS admin_login_attempts;
DROP TABLE IF EXISTS worker_refresh_tokens;
DROP TABLE IF EXISTS pm_refresh_tokens;
DROP TABLE IF EXISTS admin_refresh_tokens;
DROP TABLE IF EXISTS job_instances;
DROP TABLE IF EXISTS job_definitions;
DROP TABLE IF EXISTS dumpsters;
DROP TABLE IF EXISTS units;
DROP TABLE IF EXISTS property_buildings;
DROP TABLE IF EXISTS properties;
DROP TABLE IF EXISTS workers;
DROP TABLE IF EXISTS property_managers;
DROP TABLE IF EXISTS admins;
DROP FUNCTION IF EXISTS validate_daily_pay_estimates_array(JSONB);
DROP TABLE IF EXISTS app_attest_keys;
DROP TABLE IF EXISTS admin_audit_logs;
DROP TYPE IF EXISTS audit_action;
DROP TYPE IF EXISTS audit_target_type;

DROP TYPE IF EXISTS PAYOUT_STATUS_TYPE;
DROP TYPE IF EXISTS JOB_FREQUENCY_TYPE;
DROP TYPE IF EXISTS JOB_STATUS_TYPE;
DROP TYPE IF EXISTS REPORT_OUTCOME_TYPE;
DROP TYPE IF EXISTS SETUP_PROGRESS_TYPE;
DROP TYPE IF EXISTS ACCOUNT_STATUS_TYPE;
DROP TYPE IF EXISTS INSTANCE_STATUS_TYPE;