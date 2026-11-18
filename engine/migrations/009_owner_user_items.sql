-- Migration 009: owner-submitted user chart/diagram items (#42).
CREATE TABLE IF NOT EXISTS user_chart_items (
    id TEXT PRIMARY KEY CHECK(id <> ''),
    project_slug TEXT NOT NULL REFERENCES catalog_projects(slug) ON DELETE CASCADE,
    report_slug TEXT NOT NULL CHECK(report_slug <> ''),
    dataset_id TEXT NOT NULL CHECK(dataset_id <> ''),
    owner_id TEXT NOT NULL CHECK(owner_id <> ''),
    source_app TEXT NOT NULL DEFAULT 'annotations',
    template_id TEXT NOT NULL CHECK(template_id <> ''),
    template_version INTEGER NOT NULL CHECK(template_version >= 1),
    audience TEXT NOT NULL DEFAULT 'personal' CHECK (audience IN ('public', 'asodya', 'personal')),
    control_authority TEXT NOT NULL DEFAULT 'user_owned' CHECK (control_authority IN ('user_owned', 'app_controlled')),
    couch_doc_id TEXT NOT NULL CHECK(couch_doc_id <> ''),
    etag TEXT NOT NULL CHECK(etag <> ''),
    idempotency_key TEXT NOT NULL DEFAULT '',
    reference_count INTEGER NOT NULL DEFAULT 0 CHECK(reference_count >= 0),
    created_at BIGINT NOT NULL CHECK(created_at >= 0),
    updated_at BIGINT NOT NULL CHECK(updated_at >= 0)
);
CREATE INDEX IF NOT EXISTS user_chart_items_by_owner ON user_chart_items(owner_id, updated_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS user_chart_items_idemp ON user_chart_items(owner_id, idempotency_key) WHERE idempotency_key <> '';
