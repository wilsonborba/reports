CREATE TABLE IF NOT EXISTS calculation_latest_snapshots (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    order_field TEXT NOT NULL,
    complete_field TEXT NOT NULL,
    id_field TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version, parent_key)
        REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key)
        ON DELETE CASCADE
);
