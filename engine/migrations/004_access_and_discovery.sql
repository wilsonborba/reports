-- Migration 004: access defaults, discoverability and grants (issues #8 and #28).
-- Structure only. Idempotent.

-- New reports and datasets are restricted until a publisher opens them.
ALTER TABLE reports ALTER COLUMN visibility SET DEFAULT 'restricted';
ALTER TABLE datasets ALTER COLUMN visibility SET DEFAULT 'restricted';

-- A gated resource may appear to guests as a safe placeholder only when it is discoverable.
ALTER TABLE reports ADD COLUMN IF NOT EXISTS discoverable BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE datasets ADD COLUMN IF NOT EXISTS discoverable BOOLEAN NOT NULL DEFAULT FALSE;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reports_visibility_check') THEN
        ALTER TABLE reports ADD CONSTRAINT reports_visibility_check
            CHECK (visibility IN ('public', 'signed_in', 'restricted')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'datasets_visibility_check') THEN
        ALTER TABLE datasets ADD CONSTRAINT datasets_visibility_check
            CHECK (visibility IN ('public', 'signed_in', 'restricted')) NOT VALID;
    END IF;
END $$;

-- A report grant has card_id ''; NULL would let the unique key accept duplicates.
UPDATE resource_grants SET card_id = '' WHERE card_id IS NULL;
ALTER TABLE resource_grants ALTER COLUMN card_id SET DEFAULT '';
ALTER TABLE resource_grants ALTER COLUMN card_id SET NOT NULL;
CREATE INDEX IF NOT EXISTS idx_grants_resource ON resource_grants(project_slug, report_slug);

-- Project data tier is gone (migration 002); the sample-view flag belonged to it.
ALTER TABLE user_project_roles DROP COLUMN IF EXISTS can_view_sample;
