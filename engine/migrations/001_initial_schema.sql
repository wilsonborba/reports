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
