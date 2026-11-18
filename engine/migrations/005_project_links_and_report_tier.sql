-- Migration 005: project links and Domain link (issues #10 and #19), report provenance
-- computed from datasets only (issue #9). Structure only. Idempotent.

ALTER TABLE catalog_projects ADD COLUMN IF NOT EXISTS tagline JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE catalog_projects ADD COLUMN IF NOT EXISTS website_url TEXT;
ALTER TABLE catalog_projects ADD COLUMN IF NOT EXISTS repository_url TEXT;
ALTER TABLE catalog_projects ADD COLUMN IF NOT EXISTS sort_order BIGINT NOT NULL DEFAULT 0;
-- Stable link to the domain_api project (its slug may change; this UUID does not).
ALTER TABLE catalog_projects ADD COLUMN IF NOT EXISTS domain_project_id UUID;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_projects_domain_project ON catalog_projects(domain_project_id);

-- A report tier is the aggregate of its datasets; a stored copy could disagree.
ALTER TABLE reports DROP COLUMN IF EXISTS data_tier;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'datasets_data_tier_check') THEN
        ALTER TABLE datasets ADD CONSTRAINT datasets_data_tier_check
            CHECK (data_tier IN ('real', 'hybrid', 'sample')) NOT VALID;
    END IF;
END $$;
