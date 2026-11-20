-- Migration 010: dataset metadata and field semantics (RPT-5, #48).
CREATE TABLE IF NOT EXISTS dataset_meta (
    project_slug TEXT NOT NULL,
    report_slug TEXT NOT NULL,
    dataset_id TEXT NOT NULL,
    source_label TEXT NOT NULL DEFAULT '',
    source_url TEXT NOT NULL DEFAULT '',
    period_start TEXT NOT NULL DEFAULT '',
    period_end TEXT NOT NULL DEFAULT '',
    bucket_timezone TEXT NOT NULL DEFAULT 'UTC',
    freshness_mode TEXT NOT NULL DEFAULT 'live' CHECK (freshness_mode IN ('live', 'snapshot')),
    expected_refresh_minutes INTEGER NOT NULL DEFAULT 60 CHECK (expected_refresh_minutes >= 0),
    updated_at BIGINT NOT NULL DEFAULT 0 CHECK (updated_at >= 0),
    PRIMARY KEY (project_slug, report_slug, dataset_id),
    FOREIGN KEY (project_slug, report_slug, dataset_id)
        REFERENCES datasets(project_slug, report_slug, dataset_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS dataset_field_semantics (
    project_slug TEXT NOT NULL,
    report_slug TEXT NOT NULL,
    dataset_id TEXT NOT NULL,
    field_name TEXT NOT NULL CHECK(field_name <> ''),
    denominator_field TEXT NOT NULL DEFAULT '',
    denominator_text TEXT NOT NULL DEFAULT '',
    missing_means TEXT NOT NULL DEFAULT 'no_data' CHECK (missing_means IN ('no_data', 'zero')),
    PRIMARY KEY (project_slug, report_slug, dataset_id, field_name),
    FOREIGN KEY (project_slug, report_slug, dataset_id)
        REFERENCES datasets(project_slug, report_slug, dataset_id) ON DELETE CASCADE
);
