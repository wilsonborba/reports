-- Migration 002: Retire project-level data tier and establish report/dataset provenance and RBAC
-- Owner alignment: Provenance belongs to reports and datasets, never projects.

-- 1. Remove data_tier from catalog_projects
ALTER TABLE catalog_projects DROP COLUMN IF EXISTS data_tier;

-- 2. Add visibility column to reports and report_cards
ALTER TABLE reports ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'public';
ALTER TABLE report_cards ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'public';
ALTER TABLE datasets ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'public';

-- 3. Explicit resource grants for restricted reports and cards
CREATE TABLE IF NOT EXISTS resource_grants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_uuid UUID NOT NULL,
    resource_type TEXT NOT NULL, -- 'report' or 'card'
    project_slug TEXT NOT NULL,
    report_slug TEXT NOT NULL,
    card_id TEXT,
    granted_by TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_uuid, resource_type, project_slug, report_slug, card_id)
);
CREATE INDEX IF NOT EXISTS idx_grants_user ON resource_grants(user_uuid);

-- 4. Fixture manifest table to track seeded fixture entities for safe deletion
CREATE TABLE IF NOT EXISTS fixture_manifest (
    manifest_id TEXT NOT NULL,
    entity_type TEXT NOT NULL, -- 'schema', 'collection', 'report', 'dataset', 'card'
    entity_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (manifest_id, entity_type, entity_id)
);
CREATE INDEX IF NOT EXISTS idx_manifest_id ON fixture_manifest(manifest_id);


