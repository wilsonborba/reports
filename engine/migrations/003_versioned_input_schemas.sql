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
