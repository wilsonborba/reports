-- Migration 011: viewer-captured durable card snapshots (#43).
CREATE TABLE IF NOT EXISTS card_snapshots (
    id TEXT PRIMARY KEY CHECK(id <> ''),
    project_slug TEXT NOT NULL REFERENCES catalog_projects(slug) ON DELETE CASCADE,
    report_slug TEXT NOT NULL CHECK(report_slug <> ''),
    dataset_id TEXT NOT NULL CHECK(dataset_id <> ''),
    captured_by TEXT NOT NULL CHECK(captured_by <> ''),
    captured_at TEXT NOT NULL CHECK(captured_at <> ''),
    couch_doc_id TEXT NOT NULL CHECK(couch_doc_id <> ''),
    total_rows BIGINT NOT NULL DEFAULT 0 CHECK(total_rows >= 0)
);
CREATE INDEX IF NOT EXISTS card_snapshots_by_card ON card_snapshots(project_slug, report_slug, dataset_id, captured_at DESC);
