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
