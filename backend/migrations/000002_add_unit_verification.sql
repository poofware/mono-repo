-- 000002_add_unit_verification.up.sql
CREATE TYPE unit_verification_status AS ENUM (
    'PENDING',
    'VERIFIED',
    'DUMPED',
    'FAILED'
);

CREATE TABLE job_unit_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_instance_id UUID NOT NULL REFERENCES job_instances (id)
    ON DELETE CASCADE,
    unit_id UUID NOT NULL REFERENCES units (id) ON DELETE CASCADE,
    status UNIT_VERIFICATION_STATUS NOT NULL DEFAULT 'PENDING',
    attempt_count SMALLINT NOT NULL DEFAULT 0,
    failure_reasons TEXT [] NOT NULL DEFAULT '{}',
    failure_reason_history TEXT [] NOT NULL DEFAULT '{}',
    permanent_failure BOOLEAN NOT NULL DEFAULT FALSE,
    missing_trash_can BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    row_version BIGINT NOT NULL DEFAULT 1,
    UNIQUE (job_instance_id, unit_id)
);

ALTER TABLE job_definitions
DROP COLUMN assigned_building_ids,
ADD COLUMN assigned_units_by_building JSONB NOT NULL,
ADD COLUMN floors SMALLINT [] NOT NULL DEFAULT '{}',
ADD COLUMN total_units INT NOT NULL DEFAULT 0;

ALTER TABLE workers
ADD COLUMN on_waitlist BOOLEAN NOT NULL DEFAULT TRUE,
ADD COLUMN waitlisted_at TIMESTAMPTZ NULL;

---- create above / drop below ----

ALTER TABLE job_definitions
ADD COLUMN assigned_building_ids UUID [] NOT NULL,
DROP COLUMN assigned_units_by_building,
DROP COLUMN floors,
DROP COLUMN total_units;

ALTER TABLE workers
DROP COLUMN on_waitlist,
DROP COLUMN waitlisted_at;

DROP TABLE IF EXISTS job_unit_verifications;
DROP TYPE IF EXISTS UNIT_VERIFICATION_STATUS;
