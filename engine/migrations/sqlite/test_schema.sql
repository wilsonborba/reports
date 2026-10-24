-- SQLite mirror of the PostgreSQL schema after every migration in ../ (tests only).
-- Keep the table and column names equal to PostgreSQL. SQLite stores JSON, UUID and
-- times as TEXT and booleans as INTEGER (0 or 1).

CREATE TABLE IF NOT EXISTS catalog_projects (
    slug TEXT PRIMARY KEY,
    name TEXT NOT NULL DEFAULT '{}',
    description TEXT NOT NULL DEFAULT '{}',
    theme TEXT NOT NULL DEFAULT '{}',
    is_active INTEGER NOT NULL DEFAULT 1,
    tagline TEXT NOT NULL DEFAULT '{}',
    website_url TEXT,
    repository_url TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    domain_project_id TEXT UNIQUE,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS reports (
    project_slug TEXT NOT NULL REFERENCES catalog_projects(slug) ON DELETE CASCADE,
    slug TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '{}',
    description TEXT NOT NULL DEFAULT '{}',
    metadata TEXT NOT NULL DEFAULT '{}',
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    visibility TEXT NOT NULL DEFAULT 'restricted' CHECK (visibility IN ('public', 'signed_in', 'restricted')),
    discoverable INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (project_slug, slug)
);

CREATE TABLE IF NOT EXISTS datasets (
    project_slug TEXT NOT NULL,
    report_slug TEXT NOT NULL,
    dataset_id TEXT NOT NULL,
    data_tier TEXT NOT NULL DEFAULT 'sample' CHECK (data_tier IN ('real', 'hybrid', 'sample')),
    calculation_id TEXT,
    calculation_version INTEGER,
    visibility TEXT NOT NULL DEFAULT 'restricted' CHECK (visibility IN ('public', 'signed_in', 'restricted')),
    discoverable INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (project_slug, report_slug, dataset_id),
    FOREIGN KEY (project_slug, report_slug) REFERENCES reports(project_slug, slug) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS user_project_roles (
    user_uuid TEXT NOT NULL,
    app_name TEXT NOT NULL,
    is_project_admin INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (user_uuid, app_name)
);

CREATE TABLE IF NOT EXISTS resource_grants (
    id TEXT PRIMARY KEY,
    user_uuid TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    project_slug TEXT NOT NULL,
    report_slug TEXT NOT NULL,
    card_id TEXT NOT NULL DEFAULT '',
    granted_by TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_uuid, resource_type, project_slug, report_slug, card_id)
);

CREATE TABLE IF NOT EXISTS fixture_manifest (
    manifest_id TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (manifest_id, entity_type, entity_id)
);

CREATE TABLE IF NOT EXISTS schema_versions (
    project_slug TEXT NOT NULL REFERENCES catalog_projects(slug) ON DELETE CASCADE,
    schema_name TEXT NOT NULL,
    version INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'retired')),
    description TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at TEXT,
    PRIMARY KEY (project_slug, schema_name, version),
    CHECK (version > 0)
);

CREATE TABLE IF NOT EXISTS schema_fields (
    project_slug TEXT NOT NULL,
    schema_name TEXT NOT NULL,
    version INTEGER NOT NULL,
    field_path TEXT NOT NULL,
    field_type TEXT NOT NULL,
    is_required INTEGER NOT NULL DEFAULT 0,
    description TEXT,
    PRIMARY KEY (project_slug, schema_name, version, field_path),
    FOREIGN KEY (project_slug, schema_name, version)
        REFERENCES schema_versions(project_slug, schema_name, version) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_versions (
    project_slug TEXT NOT NULL REFERENCES catalog_projects(slug) ON DELETE CASCADE,
    calculation_id TEXT NOT NULL,
    version INTEGER NOT NULL CHECK (version > 0),
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'retired')),
    input_schema TEXT,
    input_schema_version INTEGER,
    inputs TEXT NOT NULL DEFAULT '[]',
    definition TEXT NOT NULL,
    needs_review INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at TEXT,
    PRIMARY KEY (project_slug, calculation_id, version)
);
