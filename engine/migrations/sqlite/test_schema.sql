-- SQLite mirror of the PostgreSQL schema after every migration in ../ (tests only).
-- Keep the table and column names equal to PostgreSQL. SQLite stores UUID and times as TEXT and booleans as INTEGER (0 or 1).

CREATE TABLE IF NOT EXISTS catalog_projects (
    slug TEXT PRIMARY KEY,
    is_active INTEGER NOT NULL DEFAULT 1,
    website_url TEXT,
    repository_url TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    domain_project_id TEXT UNIQUE,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS reports (
    project_slug TEXT NOT NULL REFERENCES catalog_projects(slug) ON DELETE CASCADE,
    slug TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    period_collection TEXT,
    period_field TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    visibility TEXT NOT NULL DEFAULT 'restricted' CHECK (visibility IN ('public', 'signed_in', 'restricted')),
    discoverable INTEGER NOT NULL DEFAULT 0,
    source_app TEXT NOT NULL DEFAULT 'reports',
    owner_id TEXT NOT NULL DEFAULT '',
    control_authority TEXT NOT NULL DEFAULT 'user_owned' CHECK (control_authority IN ('user_owned', 'app_controlled')),
    audience TEXT NOT NULL DEFAULT 'personal' CHECK (audience IN ('public', 'asodya', 'personal')),
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
    source_app TEXT NOT NULL DEFAULT 'reports',
    owner_id TEXT NOT NULL DEFAULT '',
    control_authority TEXT NOT NULL DEFAULT 'user_owned' CHECK (control_authority IN ('user_owned', 'app_controlled')),
    audience TEXT NOT NULL DEFAULT 'personal' CHECK (audience IN ('public', 'asodya', 'personal')),
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
    needs_review INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at TEXT,
    PRIMARY KEY (project_slug, calculation_id, version)
);

CREATE TABLE report_cards(project_slug TEXT NOT NULL,report_slug TEXT NOT NULL,card_id TEXT NOT NULL,is_visible INTEGER NOT NULL DEFAULT 1,visibility TEXT NOT NULL DEFAULT 'public',PRIMARY KEY(project_slug,report_slug,card_id));
CREATE TABLE site_settings(key TEXT PRIMARY KEY,updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);


CREATE TABLE IF NOT EXISTS project_texts (
 project_slug TEXT NOT NULL REFERENCES catalog_projects(slug) ON DELETE CASCADE,
 text_key TEXT NOT NULL CHECK (text_key IN ('name','tagline','description')),
 lang TEXT NOT NULL CHECK (length(lang)>0), text TEXT NOT NULL,
 PRIMARY KEY(project_slug,text_key,lang)
);
CREATE TABLE IF NOT EXISTS report_texts (
 project_slug TEXT NOT NULL, report_slug TEXT NOT NULL,
 text_key TEXT NOT NULL CHECK (text_key IN ('title','description')),
 lang TEXT NOT NULL CHECK (length(lang)>0), text TEXT NOT NULL,
 PRIMARY KEY(project_slug,report_slug,text_key,lang),
 FOREIGN KEY(project_slug,report_slug) REFERENCES reports(project_slug,slug) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS project_theme_modes (
 project_slug TEXT NOT NULL REFERENCES catalog_projects(slug) ON DELETE CASCADE,
 mode TEXT NOT NULL CHECK (mode IN ('light','dark')),PRIMARY KEY(project_slug,mode)
);
CREATE TABLE IF NOT EXISTS project_theme_colors (
 project_slug TEXT NOT NULL,mode TEXT NOT NULL,token TEXT NOT NULL,
 position BIGINT NOT NULL CHECK(position>=0),color TEXT NOT NULL,
 PRIMARY KEY(project_slug,mode,token,position),
 FOREIGN KEY(project_slug,mode) REFERENCES project_theme_modes(project_slug,mode) ON DELETE CASCADE,
 CHECK(token IN ('canvas','surface','surface_alt','border','text_primary','text_muted','accent','on_accent','positive','warning','negative','info','caution','other','series')),
 CHECK(token='series' OR position=0)
);
CREATE TABLE IF NOT EXISTS report_ordered_items (
 project_slug TEXT NOT NULL,report_slug TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('tag','card')),
 position BIGINT NOT NULL CHECK(position>=0),value TEXT NOT NULL,
 PRIMARY KEY(project_slug,report_slug,kind,position),
 FOREIGN KEY(project_slug,report_slug) REFERENCES reports(project_slug,slug) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS calculation_inputs (
 project_slug TEXT NOT NULL,calculation_id TEXT NOT NULL,version BIGINT NOT NULL,
 position BIGINT NOT NULL CHECK(position>=0),schema_name TEXT NOT NULL,schema_version BIGINT NOT NULL CHECK(schema_version>0),
 PRIMARY KEY(project_slug,calculation_id,version,position),
 FOREIGN KEY(project_slug,calculation_id,version) REFERENCES calculation_versions(project_slug,calculation_id,version) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS card_properties (
 project_slug TEXT NOT NULL,
 report_slug TEXT NOT NULL,
 card_id TEXT NOT NULL,
 node_id BIGINT NOT NULL CHECK(node_id>=0),
 parent_id BIGINT,
 position BIGINT NOT NULL CHECK(position>=0),
 property_name TEXT NOT NULL,
 value_kind TEXT NOT NULL CHECK(value_kind IN ('object','array','null','string','number','bool')),
 scalar_value TEXT,
 PRIMARY KEY(project_slug,report_slug,card_id,node_id),
 FOREIGN KEY(project_slug,report_slug,card_id) REFERENCES report_cards(project_slug,report_slug,card_id) ON DELETE CASCADE,
 FOREIGN KEY(project_slug,report_slug,card_id,parent_id) REFERENCES card_properties(project_slug,report_slug,card_id,node_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
 CHECK ((value_kind IN ('object','array','null') AND scalar_value IS NULL) OR (value_kind IN ('string','number','bool') AND scalar_value IS NOT NULL))
);
CREATE TABLE IF NOT EXISTS setting_properties (
 key TEXT NOT NULL,
 node_id BIGINT NOT NULL CHECK(node_id>=0),
 parent_id BIGINT,
 position BIGINT NOT NULL CHECK(position>=0),
 property_name TEXT NOT NULL,
 value_kind TEXT NOT NULL CHECK(value_kind IN ('object','array','null','string','number','bool')),
 scalar_value TEXT,
 PRIMARY KEY(key,node_id),
 FOREIGN KEY(key) REFERENCES site_settings(key) ON DELETE CASCADE,
 FOREIGN KEY(key,parent_id) REFERENCES setting_properties(key,node_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
 CHECK ((value_kind IN ('object','array','null') AND scalar_value IS NULL) OR (value_kind IN ('string','number','bool') AND scalar_value IS NOT NULL))
);
-- Normalize calculation definition components and their ordered children.
CREATE TABLE IF NOT EXISTS calculation_definitions (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "equation" TEXT,
    "source" TEXT,
    "limit" NUMERIC,
    "warm" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_titles (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "value" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_descriptions (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "value" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_unions (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "value" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_lookups (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "collection" TEXT NOT NULL,
    "prefix" TEXT,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_lookup_keys (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "value" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_lookups(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_lookup_matches (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "value" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_lookups(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_lookup_fields (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "value" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_lookups(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_buckets (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "field" TEXT NOT NULL,
    "unit" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "utc_offset_minutes" NUMERIC,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_row_derived (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "expr" TEXT,
    "expr_field" TEXT,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_conditions (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "field" TEXT NOT NULL,
    "op" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_conditions_values (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    node_kind TEXT NOT NULL CHECK (node_kind IN ('object','array','null','string','number','bool')),
    scalar_value TEXT,
    node_parent_key TEXT,
    FOREIGN KEY (project_slug, calculation_id, version, node_parent_key) REFERENCES calculation_conditions_values(project_slug, calculation_id, version, row_key) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_conditions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE IF NOT EXISTS calculation_filters (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "field" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "scope" TEXT,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_filter_labels (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "value" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_filters(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_stages (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_stage_groups (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "value" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_stages(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_stage_partitions (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "value" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_stages(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_measures (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "agg" TEXT NOT NULL,
    "field" TEXT,
    "by" TEXT,
    "n" NUMERIC,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_stages(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_measure_fields (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "value" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_measures(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_measure_conditions (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "field" TEXT NOT NULL,
    "op" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_measures(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_measure_conditions_values (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    node_kind TEXT NOT NULL CHECK (node_kind IN ('object','array','null','string','number','bool')),
    scalar_value TEXT,
    node_parent_key TEXT,
    FOREIGN KEY (project_slug, calculation_id, version, node_parent_key) REFERENCES calculation_measure_conditions_values(project_slug, calculation_id, version, row_key) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_measure_conditions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE IF NOT EXISTS calculation_stage_derived (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "expr" TEXT,
    "expr_field" TEXT,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_stages(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_stage_having (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "field" TEXT NOT NULL,
    "op" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_stages(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_stage_having_values (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    node_kind TEXT NOT NULL CHECK (node_kind IN ('object','array','null','string','number','bool')),
    scalar_value TEXT,
    node_parent_key TEXT,
    FOREIGN KEY (project_slug, calculation_id, version, node_parent_key) REFERENCES calculation_stage_having_values(project_slug, calculation_id, version, row_key) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_stage_having(project_slug, calculation_id, version, row_key) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE IF NOT EXISTS calculation_windows (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "agg" TEXT NOT NULL,
    "field" TEXT NOT NULL,
    "size" NUMERIC NOT NULL,
    "order_by" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_stages(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_window_partitions (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "value" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_windows(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_derived (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "expr" TEXT,
    "expr_field" TEXT,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_having (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "field" TEXT NOT NULL,
    "op" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_having_values (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    node_kind TEXT NOT NULL CHECK (node_kind IN ('object','array','null','string','number','bool')),
    scalar_value TEXT,
    node_parent_key TEXT,
    FOREIGN KEY (project_slug, calculation_id, version, node_parent_key) REFERENCES calculation_having_values(project_slug, calculation_id, version, row_key) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_having(project_slug, calculation_id, version, row_key) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE IF NOT EXISTS calculation_calculator_values (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    node_kind TEXT NOT NULL CHECK (node_kind IN ('object','array','null','string','number','bool')),
    scalar_value TEXT,
    node_parent_key TEXT,
    FOREIGN KEY (project_slug, calculation_id, version, node_parent_key) REFERENCES calculation_calculator_values(project_slug, calculation_id, version, row_key) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE IF NOT EXISTS calculation_parameters (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "value" NUMERIC NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_references (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "dataset" TEXT NOT NULL,
    "field" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_sort (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "field" TEXT NOT NULL,
    "desc" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_fields (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "role" TEXT NOT NULL,
    "unit" TEXT,
    "decimals" NUMERIC,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_field_labels (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "value" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_fields(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_value_fields (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_definitions(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_value_labels (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_value_fields(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS calculation_value_texts (
    project_slug TEXT NOT NULL,
    calculation_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    row_key TEXT NOT NULL,
    parent_key TEXT NOT NULL,
    position BIGINT NOT NULL CHECK (position >= 0),
    map_key TEXT NOT NULL,
    "value" TEXT NOT NULL,
    PRIMARY KEY (project_slug, calculation_id, version, row_key),
    FOREIGN KEY (project_slug, calculation_id, version) REFERENCES calculation_versions(project_slug, calculation_id, version) ON DELETE CASCADE,
    FOREIGN KEY (project_slug, calculation_id, version, parent_key) REFERENCES calculation_value_labels(project_slug, calculation_id, version, row_key) ON DELETE CASCADE
);


CREATE UNIQUE INDEX IF NOT EXISTS calculation_definitions_order ON calculation_definitions(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_titles_order ON calculation_titles(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_titles_name ON calculation_titles(project_slug,calculation_id,version,parent_key,map_key);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_descriptions_order ON calculation_descriptions(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_descriptions_name ON calculation_descriptions(project_slug,calculation_id,version,parent_key,map_key);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_unions_order ON calculation_unions(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_lookups_order ON calculation_lookups(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_lookup_keys_order ON calculation_lookup_keys(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_lookup_matches_order ON calculation_lookup_matches(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_lookup_fields_order ON calculation_lookup_fields(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_buckets_order ON calculation_buckets(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_row_derived_order ON calculation_row_derived(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_conditions_order ON calculation_conditions(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_conditions_values_root ON calculation_conditions_values(project_slug,calculation_id,version,parent_key) WHERE node_parent_key IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS calculation_conditions_values_order ON calculation_conditions_values(project_slug,calculation_id,version,node_parent_key,position) WHERE node_parent_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS calculation_filters_order ON calculation_filters(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_filter_labels_order ON calculation_filter_labels(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_filter_labels_name ON calculation_filter_labels(project_slug,calculation_id,version,parent_key,map_key);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_stages_order ON calculation_stages(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_stage_groups_order ON calculation_stage_groups(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_stage_partitions_order ON calculation_stage_partitions(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_measures_order ON calculation_measures(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_measure_fields_order ON calculation_measure_fields(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_measure_conditions_order ON calculation_measure_conditions(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_measure_conditions_values_root ON calculation_measure_conditions_values(project_slug,calculation_id,version,parent_key) WHERE node_parent_key IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS calculation_measure_conditions_values_order ON calculation_measure_conditions_values(project_slug,calculation_id,version,node_parent_key,position) WHERE node_parent_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS calculation_stage_derived_order ON calculation_stage_derived(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_stage_having_order ON calculation_stage_having(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_stage_having_values_root ON calculation_stage_having_values(project_slug,calculation_id,version,parent_key) WHERE node_parent_key IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS calculation_stage_having_values_order ON calculation_stage_having_values(project_slug,calculation_id,version,node_parent_key,position) WHERE node_parent_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS calculation_windows_order ON calculation_windows(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_window_partitions_order ON calculation_window_partitions(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_derived_order ON calculation_derived(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_having_order ON calculation_having(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_having_values_root ON calculation_having_values(project_slug,calculation_id,version,parent_key) WHERE node_parent_key IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS calculation_having_values_order ON calculation_having_values(project_slug,calculation_id,version,node_parent_key,position) WHERE node_parent_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS calculation_calculator_values_root ON calculation_calculator_values(project_slug,calculation_id,version,parent_key) WHERE node_parent_key IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS calculation_calculator_values_order ON calculation_calculator_values(project_slug,calculation_id,version,node_parent_key,position) WHERE node_parent_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS calculation_parameters_order ON calculation_parameters(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_parameters_name ON calculation_parameters(project_slug,calculation_id,version,parent_key,map_key);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_references_order ON calculation_references(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_references_name ON calculation_references(project_slug,calculation_id,version,parent_key,map_key);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_sort_order ON calculation_sort(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_fields_order ON calculation_fields(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_field_labels_order ON calculation_field_labels(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_field_labels_name ON calculation_field_labels(project_slug,calculation_id,version,parent_key,map_key);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_value_fields_order ON calculation_value_fields(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_value_fields_name ON calculation_value_fields(project_slug,calculation_id,version,parent_key,map_key);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_value_labels_order ON calculation_value_labels(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_value_labels_name ON calculation_value_labels(project_slug,calculation_id,version,parent_key,map_key);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_value_texts_order ON calculation_value_texts(project_slug,calculation_id,version,parent_key,position);
CREATE UNIQUE INDEX IF NOT EXISTS calculation_value_texts_name ON calculation_value_texts(project_slug,calculation_id,version,parent_key,map_key);
