-- Historical schema from release before storage normalization. Test evidence only.
CREATE TABLE IF NOT EXISTS catalog_projects (
    slug TEXT PRIMARY KEY, name JSONB NOT NULL DEFAULT '{}'::jsonb, description JSONB NOT NULL DEFAULT '{}'::jsonb,
    data_tier TEXT NOT NULL DEFAULT 'sample', theme JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT TRUE, updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS reports (
    project_slug TEXT NOT NULL REFERENCES catalog_projects(slug) ON DELETE CASCADE, slug TEXT NOT NULL,
    title JSONB NOT NULL DEFAULT '{}'::jsonb, description JSONB NOT NULL DEFAULT '{}'::jsonb,
    data_tier TEXT NOT NULL DEFAULT 'sample', metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (project_slug, slug)
);
CREATE TABLE IF NOT EXISTS datasets (
    project_slug TEXT NOT NULL, report_slug TEXT NOT NULL, dataset_id TEXT NOT NULL,
    data_tier TEXT NOT NULL DEFAULT 'sample', spec JSONB NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (project_slug, report_slug, dataset_id),
    FOREIGN KEY (project_slug, report_slug) REFERENCES reports(project_slug, slug) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS user_project_roles (
    user_uuid UUID NOT NULL, app_name TEXT NOT NULL, is_project_admin BOOLEAN NOT NULL DEFAULT FALSE,
    can_view_sample BOOLEAN NOT NULL DEFAULT FALSE, PRIMARY KEY (user_uuid, app_name)
);
CREATE TABLE IF NOT EXISTS report_cards (
    project_slug TEXT NOT NULL, report_slug TEXT NOT NULL, card_id TEXT NOT NULL,
    config JSONB NOT NULL DEFAULT '{}'::jsonb, is_visible BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (project_slug, report_slug, card_id)
);
CREATE TABLE IF NOT EXISTS site_settings (key TEXT PRIMARY KEY, value JSONB NOT NULL DEFAULT '{}'::jsonb, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS idx_reports_project ON reports(project_slug);
CREATE INDEX IF NOT EXISTS idx_roles_user ON user_project_roles(user_uuid);

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



-- Migration 003: durable, versioned input schemas (issues #1 and #21).
-- Structure only. scripts/migrate.sh applies it; the engine never runs DDL.
-- Idempotent: every statement can run again on an already migrated database.

CREATE TABLE IF NOT EXISTS schema_versions (
    project_slug TEXT NOT NULL REFERENCES catalog_projects(slug) ON DELETE CASCADE,
    schema_name TEXT NOT NULL,
    version BIGINT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft',
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ,
    PRIMARY KEY (project_slug, schema_name, version),
    CONSTRAINT schema_versions_status_check CHECK (status IN ('draft', 'published', 'retired')),
    CONSTRAINT schema_versions_version_check CHECK (version > 0)
);

CREATE TABLE IF NOT EXISTS schema_fields (
    project_slug TEXT NOT NULL,
    schema_name TEXT NOT NULL,
    version BIGINT NOT NULL,
    field_path TEXT NOT NULL,
    field_type TEXT NOT NULL,
    is_required BOOLEAN NOT NULL DEFAULT FALSE,
    description TEXT,
    PRIMARY KEY (project_slug, schema_name, version, field_path),
    FOREIGN KEY (project_slug, schema_name, version)
        REFERENCES schema_versions(project_slug, schema_name, version) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_schema_versions_status ON schema_versions(project_slug, schema_name, status);

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

-- Migration 006: immutable calculation versions bound to input schema versions (issue #22).
-- Structure only. Idempotent.

CREATE TABLE IF NOT EXISTS calculation_versions (
    project_slug TEXT NOT NULL REFERENCES catalog_projects(slug) ON DELETE CASCADE,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft',
    -- Main input schema and its version; every other input is listed in `inputs`.
    input_schema TEXT,
    input_schema_version BIGINT,
    inputs JSONB NOT NULL DEFAULT '[]'::jsonb,
    definition JSONB NOT NULL,
    -- A newer input schema version was published after this draft was written.
    needs_review BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ,
    PRIMARY KEY (project_slug, calculation_id, version),
    CONSTRAINT calculation_versions_status_check CHECK (status IN ('draft', 'published', 'retired')),
    CONSTRAINT calculation_versions_version_check CHECK (version > 0)
);

CREATE INDEX IF NOT EXISTS idx_calculation_versions_input
    ON calculation_versions(project_slug, input_schema, status);

-- A dataset shows one published calculation version. The inline spec is retired.
ALTER TABLE datasets ADD COLUMN IF NOT EXISTS calculation_id TEXT;
ALTER TABLE datasets ADD COLUMN IF NOT EXISTS calculation_version BIGINT;
ALTER TABLE datasets DROP COLUMN IF EXISTS spec;
