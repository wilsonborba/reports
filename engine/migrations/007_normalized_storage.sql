-- Stop engine writers before this explicit migration. Each migration runs atomically.
LOCK TABLE catalog_projects,reports,datasets,calculation_versions,report_cards,site_settings IN ACCESS EXCLUSIVE MODE;

ALTER TABLE reports ADD COLUMN IF NOT EXISTS sort_order BIGINT NOT NULL DEFAULT 0;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS period_collection TEXT;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS period_field TEXT;
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
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='calculation_definitions_warm_type') THEN ALTER TABLE calculation_definitions ADD CONSTRAINT calculation_definitions_warm_type CHECK("warm" IN ('true','false')); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='calculation_sort_desc_type') THEN ALTER TABLE calculation_sort ADD CONSTRAINT calculation_sort_desc_type CHECK("desc" IN ('true','false')); END IF; END $$;

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

-- Legacy data conversion runs in this migration transaction.
CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_titles(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_titles(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"value") VALUES(p,c,v,r,par,pos,m,j #>> '{}');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_descriptions(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_descriptions(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"value") VALUES(p,c,v,r,par,pos,m,j #>> '{}');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_unions(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_unions(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"value") VALUES(p,c,v,r,par,pos,m,j #>> '{}');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_lookup_keys(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_lookup_keys(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"value") VALUES(p,c,v,r,par,pos,m,j #>> '{}');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_lookup_matches(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_lookup_matches(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"value") VALUES(p,c,v,r,par,pos,m,j #>> '{}');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_lookup_fields(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_lookup_fields(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"value") VALUES(p,c,v,r,par,pos,m,j #>> '{}');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_lookups(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_lookups(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"collection","prefix") VALUES(p,c,v,r,par,pos,m,COALESCE(j->>'collection',''),j->>'prefix');
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'key','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_lookup_keys(p,c,v,r||'/key/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'match','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_lookup_matches(p,c,v,r||'/match/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'fields','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_lookup_fields(p,c,v,r||'/fields/'||item.n,r,item.n,'',item.value);END LOOP;
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_buckets(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_buckets(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"field","unit","name","utc_offset_minutes") VALUES(p,c,v,r,par,pos,m,COALESCE(j->>'field',''),COALESCE(j->>'unit',''),COALESCE(j->>'name',''),(j->>'utc_offset_minutes')::numeric);
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_row_derived(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_row_derived(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"name","expr","expr_field") VALUES(p,c,v,r,par,pos,m,COALESCE(j->>'name',''),j->>'expr',j->>'expr_field');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_conditions_values(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; pending jsonb; k text; n bigint; np text; payload jsonb;
BEGIN
 -- Walk containers as scalar/property rows. JSON values are function arguments only.
 pending=jsonb_build_array(jsonb_build_object('r',r,'np','','pos',pos,'m',m,'j',j));
 WHILE jsonb_array_length(pending)>0 LOOP
  payload=pending->0; pending=pending-0;
  r=payload->>'r';np=payload->>'np';pos=(payload->>'pos')::bigint;m=payload->>'m';j=payload->'j';
  INSERT INTO calculation_conditions_values(project_slug,calculation_id,version,row_key,parent_key,position,map_key,node_kind,scalar_value,node_parent_key) VALUES(p,c,v,r,par,pos,m,CASE jsonb_typeof(j) WHEN 'boolean' THEN 'bool' ELSE jsonb_typeof(j) END,CASE WHEN jsonb_typeof(j) IN ('string','number','boolean') THEN j #>> '{}' END,NULLIF(np,''));
  IF jsonb_typeof(j)='object' THEN
   n=0;FOR item IN SELECT key,value FROM jsonb_each(j) ORDER BY key LOOP pending=pending||jsonb_build_array(jsonb_build_object('r',r||'/'||n,'np',r,'pos',n,'m',item.key,'j',item.value));n=n+1; END LOOP;
  ELSIF jsonb_typeof(j)='array' THEN
   FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(j) WITH ORDINALITY LOOP pending=pending||jsonb_build_array(jsonb_build_object('r',r||'/'||item.n,'np',r,'pos',item.n,'m','','j',item.value));END LOOP;
  END IF;
 END LOOP;
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_conditions(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_conditions(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"field","op") VALUES(p,c,v,r,par,pos,m,COALESCE(j->>'field',''),COALESCE(j->>'op',''));
PERFORM pg_temp.normalize_calculation_conditions_values(p,c,v,r||'/value',r,0,'',COALESCE(j->'value','null'::jsonb));
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_filter_labels(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_filter_labels(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"value") VALUES(p,c,v,r,par,pos,m,j #>> '{}');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_filters(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_filters(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"field","type","scope") VALUES(p,c,v,r,par,pos,m,COALESCE(j->>'field',''),COALESCE(j->>'type',''),j->>'scope');
 FOR item IN SELECT key,value,row_number() OVER(ORDER BY key)-1 AS n FROM jsonb_each(COALESCE(NULLIF(j->'label','null'::jsonb),'{}'::jsonb)) LOOP PERFORM pg_temp.normalize_calculation_filter_labels(p,c,v,r||'/label/'||item.n,r,item.n,item.key,item.value);END LOOP;
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_stage_groups(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_stage_groups(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"value") VALUES(p,c,v,r,par,pos,m,j #>> '{}');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_stage_partitions(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_stage_partitions(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"value") VALUES(p,c,v,r,par,pos,m,j #>> '{}');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_measure_fields(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_measure_fields(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"value") VALUES(p,c,v,r,par,pos,m,j #>> '{}');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_measure_conditions_values(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; pending jsonb; k text; n bigint; np text; payload jsonb;
BEGIN
 -- Walk containers as scalar/property rows. JSON values are function arguments only.
 pending=jsonb_build_array(jsonb_build_object('r',r,'np','','pos',pos,'m',m,'j',j));
 WHILE jsonb_array_length(pending)>0 LOOP
  payload=pending->0; pending=pending-0;
  r=payload->>'r';np=payload->>'np';pos=(payload->>'pos')::bigint;m=payload->>'m';j=payload->'j';
  INSERT INTO calculation_measure_conditions_values(project_slug,calculation_id,version,row_key,parent_key,position,map_key,node_kind,scalar_value,node_parent_key) VALUES(p,c,v,r,par,pos,m,CASE jsonb_typeof(j) WHEN 'boolean' THEN 'bool' ELSE jsonb_typeof(j) END,CASE WHEN jsonb_typeof(j) IN ('string','number','boolean') THEN j #>> '{}' END,NULLIF(np,''));
  IF jsonb_typeof(j)='object' THEN
   n=0;FOR item IN SELECT key,value FROM jsonb_each(j) ORDER BY key LOOP pending=pending||jsonb_build_array(jsonb_build_object('r',r||'/'||n,'np',r,'pos',n,'m',item.key,'j',item.value));n=n+1; END LOOP;
  ELSIF jsonb_typeof(j)='array' THEN
   FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(j) WITH ORDINALITY LOOP pending=pending||jsonb_build_array(jsonb_build_object('r',r||'/'||item.n,'np',r,'pos',item.n,'m','','j',item.value));END LOOP;
  END IF;
 END LOOP;
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_measure_conditions(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_measure_conditions(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"field","op") VALUES(p,c,v,r,par,pos,m,COALESCE(j->>'field',''),COALESCE(j->>'op',''));
PERFORM pg_temp.normalize_calculation_measure_conditions_values(p,c,v,r||'/value',r,0,'',COALESCE(j->'value','null'::jsonb));
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_measures(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_measures(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"name","agg","field","by","n") VALUES(p,c,v,r,par,pos,m,COALESCE(j->>'name',''),COALESCE(j->>'agg',''),j->>'field',j->>'by',(j->>'n')::numeric);
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'fields','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_measure_fields(p,c,v,r||'/fields/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'where','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_measure_conditions(p,c,v,r||'/where/'||item.n,r,item.n,'',item.value);END LOOP;
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_stage_derived(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_stage_derived(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"name","expr","expr_field") VALUES(p,c,v,r,par,pos,m,COALESCE(j->>'name',''),j->>'expr',j->>'expr_field');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_stage_having_values(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; pending jsonb; k text; n bigint; np text; payload jsonb;
BEGIN
 -- Walk containers as scalar/property rows. JSON values are function arguments only.
 pending=jsonb_build_array(jsonb_build_object('r',r,'np','','pos',pos,'m',m,'j',j));
 WHILE jsonb_array_length(pending)>0 LOOP
  payload=pending->0; pending=pending-0;
  r=payload->>'r';np=payload->>'np';pos=(payload->>'pos')::bigint;m=payload->>'m';j=payload->'j';
  INSERT INTO calculation_stage_having_values(project_slug,calculation_id,version,row_key,parent_key,position,map_key,node_kind,scalar_value,node_parent_key) VALUES(p,c,v,r,par,pos,m,CASE jsonb_typeof(j) WHEN 'boolean' THEN 'bool' ELSE jsonb_typeof(j) END,CASE WHEN jsonb_typeof(j) IN ('string','number','boolean') THEN j #>> '{}' END,NULLIF(np,''));
  IF jsonb_typeof(j)='object' THEN
   n=0;FOR item IN SELECT key,value FROM jsonb_each(j) ORDER BY key LOOP pending=pending||jsonb_build_array(jsonb_build_object('r',r||'/'||n,'np',r,'pos',n,'m',item.key,'j',item.value));n=n+1; END LOOP;
  ELSIF jsonb_typeof(j)='array' THEN
   FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(j) WITH ORDINALITY LOOP pending=pending||jsonb_build_array(jsonb_build_object('r',r||'/'||item.n,'np',r,'pos',item.n,'m','','j',item.value));END LOOP;
  END IF;
 END LOOP;
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_stage_having(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_stage_having(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"field","op") VALUES(p,c,v,r,par,pos,m,COALESCE(j->>'field',''),COALESCE(j->>'op',''));
PERFORM pg_temp.normalize_calculation_stage_having_values(p,c,v,r||'/value',r,0,'',COALESCE(j->'value','null'::jsonb));
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_window_partitions(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_window_partitions(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"value") VALUES(p,c,v,r,par,pos,m,j #>> '{}');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_windows(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_windows(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"name","agg","field","size","order_by") VALUES(p,c,v,r,par,pos,m,COALESCE(j->>'name',''),COALESCE(j->>'agg',''),COALESCE(j->>'field',''),(COALESCE(j->>'size','0'))::numeric,COALESCE(j->>'order_by',''));
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'partition_by','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_window_partitions(p,c,v,r||'/partition_by/'||item.n,r,item.n,'',item.value);END LOOP;
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_stages(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_stages(project_slug,calculation_id,version,row_key,parent_key,position,map_key) VALUES(p,c,v,r,par,pos,m);
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'group_by','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_stage_groups(p,c,v,r||'/group_by/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'partition_by','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_stage_partitions(p,c,v,r||'/partition_by/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'measures','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_measures(p,c,v,r||'/measures/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'derived','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_stage_derived(p,c,v,r||'/derived/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'having','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_stage_having(p,c,v,r||'/having/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'windows','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_windows(p,c,v,r||'/windows/'||item.n,r,item.n,'',item.value);END LOOP;
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_derived(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_derived(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"name","expr","expr_field") VALUES(p,c,v,r,par,pos,m,COALESCE(j->>'name',''),j->>'expr',j->>'expr_field');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_having_values(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; pending jsonb; k text; n bigint; np text; payload jsonb;
BEGIN
 -- Walk containers as scalar/property rows. JSON values are function arguments only.
 pending=jsonb_build_array(jsonb_build_object('r',r,'np','','pos',pos,'m',m,'j',j));
 WHILE jsonb_array_length(pending)>0 LOOP
  payload=pending->0; pending=pending-0;
  r=payload->>'r';np=payload->>'np';pos=(payload->>'pos')::bigint;m=payload->>'m';j=payload->'j';
  INSERT INTO calculation_having_values(project_slug,calculation_id,version,row_key,parent_key,position,map_key,node_kind,scalar_value,node_parent_key) VALUES(p,c,v,r,par,pos,m,CASE jsonb_typeof(j) WHEN 'boolean' THEN 'bool' ELSE jsonb_typeof(j) END,CASE WHEN jsonb_typeof(j) IN ('string','number','boolean') THEN j #>> '{}' END,NULLIF(np,''));
  IF jsonb_typeof(j)='object' THEN
   n=0;FOR item IN SELECT key,value FROM jsonb_each(j) ORDER BY key LOOP pending=pending||jsonb_build_array(jsonb_build_object('r',r||'/'||n,'np',r,'pos',n,'m',item.key,'j',item.value));n=n+1; END LOOP;
  ELSIF jsonb_typeof(j)='array' THEN
   FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(j) WITH ORDINALITY LOOP pending=pending||jsonb_build_array(jsonb_build_object('r',r||'/'||item.n,'np',r,'pos',item.n,'m','','j',item.value));END LOOP;
  END IF;
 END LOOP;
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_having(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_having(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"field","op") VALUES(p,c,v,r,par,pos,m,COALESCE(j->>'field',''),COALESCE(j->>'op',''));
PERFORM pg_temp.normalize_calculation_having_values(p,c,v,r||'/value',r,0,'',COALESCE(j->'value','null'::jsonb));
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_calculator_values(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; pending jsonb; k text; n bigint; np text; payload jsonb;
BEGIN
 -- Walk containers as scalar/property rows. JSON values are function arguments only.
 pending=jsonb_build_array(jsonb_build_object('r',r,'np','','pos',pos,'m',m,'j',j));
 WHILE jsonb_array_length(pending)>0 LOOP
  payload=pending->0; pending=pending-0;
  r=payload->>'r';np=payload->>'np';pos=(payload->>'pos')::bigint;m=payload->>'m';j=payload->'j';
  INSERT INTO calculation_calculator_values(project_slug,calculation_id,version,row_key,parent_key,position,map_key,node_kind,scalar_value,node_parent_key) VALUES(p,c,v,r,par,pos,m,CASE jsonb_typeof(j) WHEN 'boolean' THEN 'bool' ELSE jsonb_typeof(j) END,CASE WHEN jsonb_typeof(j) IN ('string','number','boolean') THEN j #>> '{}' END,NULLIF(np,''));
  IF jsonb_typeof(j)='object' THEN
   n=0;FOR item IN SELECT key,value FROM jsonb_each(j) ORDER BY key LOOP pending=pending||jsonb_build_array(jsonb_build_object('r',r||'/'||n,'np',r,'pos',n,'m',item.key,'j',item.value));n=n+1; END LOOP;
  ELSIF jsonb_typeof(j)='array' THEN
   FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(j) WITH ORDINALITY LOOP pending=pending||jsonb_build_array(jsonb_build_object('r',r||'/'||item.n,'np',r,'pos',item.n,'m','','j',item.value));END LOOP;
  END IF;
 END LOOP;
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_parameters(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_parameters(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"value") VALUES(p,c,v,r,par,pos,m,(j #>> '{}')::numeric);
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_references(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_references(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"dataset","field") VALUES(p,c,v,r,par,pos,m,COALESCE(j->>'dataset',''),COALESCE(j->>'field',''));
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_sort(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_sort(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"field","desc") VALUES(p,c,v,r,par,pos,m,COALESCE(j->>'field',''),COALESCE(j->>'desc','false'));
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_field_labels(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_field_labels(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"value") VALUES(p,c,v,r,par,pos,m,j #>> '{}');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_fields(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_fields(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"name","type","role","unit","decimals") VALUES(p,c,v,r,par,pos,m,COALESCE(j->>'name',''),COALESCE(j->>'type',''),COALESCE(j->>'role','measure'),j->>'unit',(j->>'decimals')::numeric);
 FOR item IN SELECT key,value,row_number() OVER(ORDER BY key)-1 AS n FROM jsonb_each(COALESCE(NULLIF(j->'label','null'::jsonb),'{}'::jsonb)) LOOP PERFORM pg_temp.normalize_calculation_field_labels(p,c,v,r||'/label/'||item.n,r,item.n,item.key,item.value);END LOOP;
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_value_texts(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_value_texts(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"value") VALUES(p,c,v,r,par,pos,m,j #>> '{}');
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_value_labels(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_value_labels(project_slug,calculation_id,version,row_key,parent_key,position,map_key) VALUES(p,c,v,r,par,pos,m);
 FOR item IN SELECT key,value,row_number() OVER(ORDER BY key)-1 AS n FROM jsonb_each(COALESCE(NULLIF(j,'null'::jsonb),'{}'::jsonb)) LOOP PERFORM pg_temp.normalize_calculation_value_texts(p,c,v,r||'/*/'||item.n,r,item.n,item.key,item.value);END LOOP;
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_value_fields(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_value_fields(project_slug,calculation_id,version,row_key,parent_key,position,map_key) VALUES(p,c,v,r,par,pos,m);
 FOR item IN SELECT key,value,row_number() OVER(ORDER BY key)-1 AS n FROM jsonb_each(COALESCE(NULLIF(j,'null'::jsonb),'{}'::jsonb)) LOOP PERFORM pg_temp.normalize_calculation_value_labels(p,c,v,r||'/*/'||item.n,r,item.n,item.key,item.value);END LOOP;
END
$normalize$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_calculation_definitions(p text,c text,v bigint,r text,par text,pos bigint,m text,j jsonb) RETURNS void LANGUAGE plpgsql AS $normalize$
DECLARE item record; child jsonb;
BEGIN
 INSERT INTO calculation_definitions(project_slug,calculation_id,version,row_key,parent_key,position,map_key,"equation","source","limit","warm") VALUES(p,c,v,r,par,pos,m,j->>'equation',j->>'source',(j->>'limit')::numeric,COALESCE(j->>'warm','false'));
 FOR item IN SELECT key,value,row_number() OVER(ORDER BY key)-1 AS n FROM jsonb_each(COALESCE(NULLIF(j->'title','null'::jsonb),'{}'::jsonb)) LOOP PERFORM pg_temp.normalize_calculation_titles(p,c,v,r||'/title/'||item.n,r,item.n,item.key,item.value);END LOOP;
 FOR item IN SELECT key,value,row_number() OVER(ORDER BY key)-1 AS n FROM jsonb_each(COALESCE(NULLIF(j->'description','null'::jsonb),'{}'::jsonb)) LOOP PERFORM pg_temp.normalize_calculation_descriptions(p,c,v,r||'/description/'||item.n,r,item.n,item.key,item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'union','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_unions(p,c,v,r||'/union/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'lookups','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_lookups(p,c,v,r||'/lookups/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'buckets','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_buckets(p,c,v,r||'/buckets/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'row_derived','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_row_derived(p,c,v,r||'/row_derived/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'where','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_conditions(p,c,v,r||'/where/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'filters','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_filters(p,c,v,r||'/filters/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'stages','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_stages(p,c,v,r||'/stages/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'derived','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_derived(p,c,v,r||'/derived/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'having','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_having(p,c,v,r||'/having/'||item.n,r,item.n,'',item.value);END LOOP;
IF j->'calculator' IS NOT NULL AND j->'calculator'<>'null'::jsonb THEN PERFORM pg_temp.normalize_calculation_calculator_values(p,c,v,r||'/calculator',r,0,'',COALESCE(j->'calculator','null'::jsonb)); END IF;
 FOR item IN SELECT key,value,row_number() OVER(ORDER BY key)-1 AS n FROM jsonb_each(COALESCE(NULLIF(j->'params','null'::jsonb),'{}'::jsonb)) LOOP PERFORM pg_temp.normalize_calculation_parameters(p,c,v,r||'/params/'||item.n,r,item.n,item.key,item.value);END LOOP;
 FOR item IN SELECT key,value,row_number() OVER(ORDER BY key)-1 AS n FROM jsonb_each(COALESCE(NULLIF(j->'refs','null'::jsonb),'{}'::jsonb)) LOOP PERFORM pg_temp.normalize_calculation_references(p,c,v,r||'/refs/'||item.n,r,item.n,item.key,item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'sort','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_sort(p,c,v,r||'/sort/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(COALESCE(NULLIF(j->'fields','null'::jsonb),'[]'::jsonb)) WITH ORDINALITY LOOP PERFORM pg_temp.normalize_calculation_fields(p,c,v,r||'/fields/'||item.n,r,item.n,'',item.value);END LOOP;
 FOR item IN SELECT key,value,row_number() OVER(ORDER BY key)-1 AS n FROM jsonb_each(COALESCE(NULLIF(j->'value_labels','null'::jsonb),'{}'::jsonb)) LOOP PERFORM pg_temp.normalize_calculation_value_fields(p,c,v,r||'/value_labels/'||item.n,r,item.n,item.key,item.value);END LOOP;
END
$normalize$;

DO $upgrade$
DECLARE r record; j jsonb; k text; m record; token record; color record; item record; n bigint; calc text; raw jsonb;
BEGIN
 -- row_to_json reads both historical and current schemas without requiring old columns.
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='catalog_projects' AND column_name='name') THEN
 FOR r IN SELECT row_to_json(p)::jsonb AS data FROM catalog_projects p LOOP
  j=r.data;
  FOREACH k IN ARRAY ARRAY['name','tagline','description'] LOOP
   FOR item IN SELECT key,value FROM jsonb_each_text(COALESCE(j->k,'{}'::jsonb)) LOOP
    INSERT INTO project_texts VALUES(j->>'slug',k,item.key,item.value);
   END LOOP;
  END LOOP;
  FOR m IN SELECT key,value FROM jsonb_each(COALESCE(j->'theme','{}'::jsonb)) WHERE value<>'null'::jsonb LOOP
   INSERT INTO project_theme_modes VALUES(j->>'slug',m.key);
   FOR token IN SELECT key,value FROM jsonb_each(m.value) LOOP
    IF token.key='series' THEN
     FOR color IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements_text(token.value) WITH ORDINALITY LOOP
      INSERT INTO project_theme_colors VALUES(j->>'slug',m.key,token.key,color.n,color.value);
     END LOOP;
    ELSE INSERT INTO project_theme_colors VALUES(j->>'slug',m.key,token.key,0,token.value #>> '{}'); END IF;
   END LOOP;
  END LOOP;
 END LOOP;
 END IF;
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='reports' AND column_name='title') THEN
 FOR r IN SELECT row_to_json(p)::jsonb AS data FROM reports p LOOP
  j=r.data;
  FOREACH k IN ARRAY ARRAY['title','description'] LOOP
   FOR item IN SELECT key,value FROM jsonb_each_text(COALESCE(j->k,'{}'::jsonb)) LOOP
    INSERT INTO report_texts VALUES(j->>'project_slug',j->>'slug',k,item.key,item.value);
   END LOOP;
  END LOOP;
  UPDATE reports SET sort_order=COALESCE((j->'metadata'->>'sort_order')::bigint,0),period_collection=j->'metadata'->'period_source'->>'collection',period_field=j->'metadata'->'period_source'->>'field' WHERE project_slug=j->>'project_slug' AND slug=j->>'slug';
  FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements_text(COALESCE(j->'metadata'->'tags','[]'::jsonb)) WITH ORDINALITY LOOP
   INSERT INTO report_ordered_items VALUES(j->>'project_slug',j->>'slug','tag',item.n,item.value);
  END LOOP;
  FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements_text(COALESCE(j->'metadata'->'card_order','[]'::jsonb)) WITH ORDINALITY LOOP
   INSERT INTO report_ordered_items VALUES(j->>'project_slug',j->>'slug','card',item.n,item.value);
  END LOOP;
 END LOOP;
 END IF;
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='calculation_versions' AND column_name='definition') THEN
 FOR r IN SELECT row_to_json(p)::jsonb AS data FROM calculation_versions p LOOP
  j=r.data;
  PERFORM pg_temp.normalize_calculation_definitions(j->>'project_slug',j->>'calculation_id',(j->>'version')::bigint,'root','',0,'',j->'definition');
  FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(j->'inputs') WITH ORDINALITY LOOP
   INSERT INTO calculation_inputs VALUES(j->>'project_slug',j->>'calculation_id',(j->>'version')::bigint,item.n,item.value->>'schema',(item.value->>'version')::bigint);
  END LOOP;
 END LOOP;
 END IF;
 -- Pre-006 datasets retain their inline definition until this conversion succeeds.
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='datasets' AND column_name='spec') THEN
 FOR r IN SELECT row_to_json(p)::jsonb AS data FROM datasets p LOOP
  j=r.data;
  IF j->>'calculation_id' IS NULL THEN
   calc='legacy/'||length(j->>'report_slug')||'/'||(j->>'report_slug')||'/'||(j->>'dataset_id');
   INSERT INTO calculation_versions(project_slug,calculation_id,version,status,input_schema,published_at) VALUES(j->>'project_slug',calc,1,'published',j->'spec'->>'source',now());
   PERFORM pg_temp.normalize_calculation_definitions(j->>'project_slug',calc,1,'root','',0,'',j->'spec');
   UPDATE datasets SET calculation_id=calc,calculation_version=1 WHERE project_slug=j->>'project_slug' AND report_slug=j->>'report_slug' AND dataset_id=j->>'dataset_id';
  END IF;
 END LOOP;
 END IF;
END $upgrade$;
CREATE OR REPLACE FUNCTION pg_temp.normalize_card_properties(p0 text,p1 text,p2 text,j jsonb) RETURNS void LANGUAGE plpgsql AS $properties$
DECLARE pending jsonb; payload jsonb; item record; node bigint; par bigint; pos bigint; prop text; n bigint; next_id bigint:=1;
BEGIN
 pending=jsonb_build_array(jsonb_build_object('id',0,'parent',null,'position',0,'name','','j',j));
 WHILE jsonb_array_length(pending)>0 LOOP
  payload=pending->0;pending=pending-0;node=(payload->>'id')::bigint;par=(payload->>'parent')::bigint;pos=(payload->>'position')::bigint;prop=payload->>'name';j=payload->'j';
  INSERT INTO card_properties(project_slug,report_slug,card_id,node_id,parent_id,position,property_name,value_kind,scalar_value) VALUES(p0,p1,p2,node,par,pos,prop,CASE jsonb_typeof(j) WHEN 'boolean' THEN 'bool' ELSE jsonb_typeof(j) END,CASE WHEN jsonb_typeof(j) IN ('string','number','boolean') THEN j #>> '{}' END);
  IF jsonb_typeof(j)='object' THEN
   n=0;FOR item IN SELECT key,value FROM jsonb_each(j) ORDER BY key LOOP pending=pending||jsonb_build_array(jsonb_build_object('id',next_id,'parent',node,'position',n,'name',item.key,'j',item.value));next_id=next_id+1;n=n+1;END LOOP;
  ELSIF jsonb_typeof(j)='array' THEN
   FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(j) WITH ORDINALITY LOOP pending=pending||jsonb_build_array(jsonb_build_object('id',next_id,'parent',node,'position',item.n,'name','','j',item.value));next_id=next_id+1;END LOOP;
  END IF;
 END LOOP;
END $properties$;
DO $convert$
DECLARE r record;
BEGIN
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='report_cards' AND column_name='config') THEN
 FOR r IN SELECT row_to_json(p)::jsonb AS data FROM report_cards p LOOP
 PERFORM pg_temp.normalize_card_properties(r.data->>'project_slug',r.data->>'report_slug',r.data->>'card_id',r.data->'config');
 END LOOP;
 END IF;
END $convert$;
CREATE OR REPLACE FUNCTION pg_temp.normalize_setting_properties(p0 text,j jsonb) RETURNS void LANGUAGE plpgsql AS $properties$
DECLARE pending jsonb; payload jsonb; item record; node bigint; par bigint; pos bigint; prop text; n bigint; next_id bigint:=1;
BEGIN
 pending=jsonb_build_array(jsonb_build_object('id',0,'parent',null,'position',0,'name','','j',j));
 WHILE jsonb_array_length(pending)>0 LOOP
  payload=pending->0;pending=pending-0;node=(payload->>'id')::bigint;par=(payload->>'parent')::bigint;pos=(payload->>'position')::bigint;prop=payload->>'name';j=payload->'j';
  INSERT INTO setting_properties(key,node_id,parent_id,position,property_name,value_kind,scalar_value) VALUES(p0,node,par,pos,prop,CASE jsonb_typeof(j) WHEN 'boolean' THEN 'bool' ELSE jsonb_typeof(j) END,CASE WHEN jsonb_typeof(j) IN ('string','number','boolean') THEN j #>> '{}' END);
  IF jsonb_typeof(j)='object' THEN
   n=0;FOR item IN SELECT key,value FROM jsonb_each(j) ORDER BY key LOOP pending=pending||jsonb_build_array(jsonb_build_object('id',next_id,'parent',node,'position',n,'name',item.key,'j',item.value));next_id=next_id+1;n=n+1;END LOOP;
  ELSIF jsonb_typeof(j)='array' THEN
   FOR item IN SELECT value,ordinality-1 AS n FROM jsonb_array_elements(j) WITH ORDINALITY LOOP pending=pending||jsonb_build_array(jsonb_build_object('id',next_id,'parent',node,'position',item.n,'name','','j',item.value));next_id=next_id+1;END LOOP;
  END IF;
 END LOOP;
END $properties$;
DO $convert$
DECLARE r record;
BEGIN
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='site_settings' AND column_name='value') THEN
 FOR r IN SELECT row_to_json(p)::jsonb AS data FROM site_settings p LOOP
 PERFORM pg_temp.normalize_setting_properties(r.data->>'key',r.data->'value');
 END LOOP;
 END IF;
END $convert$;
ALTER TABLE catalog_projects DROP COLUMN IF EXISTS name;
ALTER TABLE catalog_projects DROP COLUMN IF EXISTS tagline;
ALTER TABLE catalog_projects DROP COLUMN IF EXISTS description;
ALTER TABLE catalog_projects DROP COLUMN IF EXISTS theme;
ALTER TABLE reports DROP COLUMN IF EXISTS title;
ALTER TABLE reports DROP COLUMN IF EXISTS description;
ALTER TABLE reports DROP COLUMN IF EXISTS metadata;
ALTER TABLE calculation_versions DROP COLUMN IF EXISTS inputs;
ALTER TABLE calculation_versions DROP COLUMN IF EXISTS definition;
ALTER TABLE datasets DROP COLUMN IF EXISTS spec;
ALTER TABLE report_cards DROP COLUMN IF EXISTS config;
ALTER TABLE site_settings DROP COLUMN IF EXISTS value;
DROP FUNCTION pg_temp.normalize_calculation_titles(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_descriptions(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_unions(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_lookup_keys(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_lookup_matches(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_lookup_fields(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_lookups(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_buckets(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_row_derived(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_conditions_values(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_conditions(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_filter_labels(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_filters(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_stage_groups(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_stage_partitions(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_measure_fields(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_measure_conditions_values(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_measure_conditions(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_measures(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_stage_derived(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_stage_having_values(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_stage_having(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_window_partitions(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_windows(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_stages(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_derived(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_having_values(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_having(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_calculator_values(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_parameters(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_references(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_sort(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_field_labels(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_fields(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_value_texts(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_value_labels(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_value_fields(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_calculation_definitions(text,text,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION pg_temp.normalize_card_properties(text,text,text,jsonb);
DROP FUNCTION pg_temp.normalize_setting_properties(text,jsonb);
