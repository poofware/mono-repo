-- ----------------------------------------------------------------------
--  admins
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admins (
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
CREATE INDEX IF NOT EXISTS idx_admins_username ON admins (username);

-- ----------------------------------------------------------------------
--  admin audit logging
-- ----------------------------------------------------------------------
DO $$ BEGIN
    CREATE TYPE AUDIT_ACTION AS ENUM ('CREATE', 'UPDATE', 'DELETE', 'READ');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE AUDIT_TARGET_TYPE AS ENUM ('PROPERTY_MANAGER', 'PROPERTY', 'BUILDING', 'UNIT', 'DUMPSTER', 'JOB_DEFINITION');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS admin_audit_logs (
    id UUID PRIMARY KEY,
    admin_id UUID NOT NULL REFERENCES admins (id),
    action AUDIT_ACTION NOT NULL,
    target_id UUID NOT NULL,
    target_type AUDIT_TARGET_TYPE NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_admin_id
ON admin_audit_logs (admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_target
ON admin_audit_logs (target_type, target_id);

-- ----------------------------------------------------------------------
--  admin_refresh_tokens
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID REFERENCES admins (id) ON DELETE CASCADE,
    refresh_token VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    revoked BOOLEAN DEFAULT FALSE,
    ip_address VARCHAR(45),
    device_id VARCHAR(255)
);
CREATE INDEX IF NOT EXISTS idx_admin_refresh_tokens_token
ON admin_refresh_tokens (refresh_token);

-- ----------------------------------------------------------------------
--  admin_login_attempts
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_login_attempts (
    admin_id UUID PRIMARY KEY REFERENCES admins (id) ON DELETE CASCADE,
    attempt_count INT NOT NULL DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- ----------------------------------------------------------------------
--  admin_blacklisted_tokens
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_blacklisted_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_id VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_admin_blacklisted_tokens_token_id
ON admin_blacklisted_tokens (token_id);

-- ----------------------------------------------------------------------
--  soft-delete/metadata columns
-- ----------------------------------------------------------------------
ALTER TABLE property_managers
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE properties
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT now();
ALTER TABLE properties
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE properties
ADD COLUMN IF NOT EXISTS row_version BIGINT NOT NULL DEFAULT 1;

ALTER TABLE property_buildings
ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT now();
ALTER TABLE property_buildings
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT now();
ALTER TABLE property_buildings
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE property_buildings
ADD COLUMN IF NOT EXISTS row_version BIGINT NOT NULL DEFAULT 1;

ALTER TABLE units
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT now();
ALTER TABLE units
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE units
ADD COLUMN IF NOT EXISTS row_version BIGINT NOT NULL DEFAULT 1;

ALTER TABLE dumpsters
ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT now();
ALTER TABLE dumpsters
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT now();
ALTER TABLE dumpsters
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE dumpsters
ADD COLUMN IF NOT EXISTS row_version BIGINT NOT NULL DEFAULT 1;

-- ----------------------------------------------------------------------
--  worker_payouts adjustments
-- ----------------------------------------------------------------------
ALTER TABLE worker_payouts
ALTER COLUMN job_instance_ids DROP DEFAULT;
ALTER TABLE worker_payouts
ALTER COLUMN job_instance_ids DROP NOT NULL;

---- create above / drop below ----

-- Revert soft-delete/metadata columns
ALTER TABLE dumpsters
DROP COLUMN IF EXISTS row_version,
DROP COLUMN IF EXISTS deleted_at,
DROP COLUMN IF EXISTS updated_at,
DROP COLUMN IF EXISTS created_at;

ALTER TABLE units
DROP COLUMN IF EXISTS row_version,
DROP COLUMN IF EXISTS deleted_at,
DROP COLUMN IF EXISTS updated_at;

ALTER TABLE property_buildings
DROP COLUMN IF EXISTS row_version,
DROP COLUMN IF EXISTS deleted_at,
DROP COLUMN IF EXISTS updated_at,
DROP COLUMN IF EXISTS created_at;

ALTER TABLE properties
DROP COLUMN IF EXISTS row_version,
DROP COLUMN IF EXISTS deleted_at,
DROP COLUMN IF EXISTS updated_at;

ALTER TABLE property_managers
DROP COLUMN IF EXISTS deleted_at;

-- Drop admin-related tables and types
DROP TABLE IF EXISTS admin_blacklisted_tokens;
DROP TABLE IF EXISTS admin_login_attempts;
DROP INDEX IF EXISTS idx_admin_refresh_tokens_token;
DROP TABLE IF EXISTS admin_refresh_tokens;
DROP INDEX IF EXISTS idx_admin_audit_logs_target;
DROP INDEX IF EXISTS idx_admin_audit_logs_admin_id;
DROP TABLE IF EXISTS admin_audit_logs;
DROP INDEX IF EXISTS idx_admins_username;
DROP TABLE IF EXISTS admins;
DROP TYPE IF EXISTS AUDIT_TARGET_TYPE;
DROP TYPE IF EXISTS AUDIT_ACTION;
