-- Migration 008: per-user ownership, source app, control authority, and audience (#41).
ALTER TABLE reports ADD COLUMN IF NOT EXISTS source_app TEXT NOT NULL DEFAULT 'reports';
ALTER TABLE reports ADD COLUMN IF NOT EXISTS owner_id TEXT NOT NULL DEFAULT '';
ALTER TABLE reports ADD COLUMN IF NOT EXISTS control_authority TEXT NOT NULL DEFAULT 'user_owned';
ALTER TABLE reports ADD COLUMN IF NOT EXISTS audience TEXT NOT NULL DEFAULT 'personal';

ALTER TABLE datasets ADD COLUMN IF NOT EXISTS source_app TEXT NOT NULL DEFAULT 'reports';
ALTER TABLE datasets ADD COLUMN IF NOT EXISTS owner_id TEXT NOT NULL DEFAULT '';
ALTER TABLE datasets ADD COLUMN IF NOT EXISTS control_authority TEXT NOT NULL DEFAULT 'user_owned';
ALTER TABLE datasets ADD COLUMN IF NOT EXISTS audience TEXT NOT NULL DEFAULT 'personal';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reports_control_authority_check') THEN
        ALTER TABLE reports ADD CONSTRAINT reports_control_authority_check
            CHECK (control_authority IN ('user_owned', 'app_controlled')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reports_audience_check') THEN
        ALTER TABLE reports ADD CONSTRAINT reports_audience_check
            CHECK (audience IN ('public', 'asodya', 'personal')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'datasets_control_authority_check') THEN
        ALTER TABLE datasets ADD CONSTRAINT datasets_control_authority_check
            CHECK (control_authority IN ('user_owned', 'app_controlled')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'datasets_audience_check') THEN
        ALTER TABLE datasets ADD CONSTRAINT datasets_audience_check
            CHECK (audience IN ('public', 'asodya', 'personal')) NOT VALID;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS reports_by_owner_audience ON reports(owner_id, audience);
CREATE INDEX IF NOT EXISTS datasets_by_owner_audience ON datasets(owner_id, audience);
