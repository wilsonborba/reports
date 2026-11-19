-- Migration 012: normalized versioned visual templates and card bindings (RPT-8, #52).
CREATE TABLE IF NOT EXISTS visual_templates (
    template_id TEXT PRIMARY KEY CHECK(template_id <> ''),
    kind TEXT NOT NULL CHECK (kind IN ('chart', 'diagram')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS visual_template_versions (
    template_id TEXT NOT NULL REFERENCES visual_templates(template_id) ON DELETE CASCADE,
    version INTEGER NOT NULL CHECK (version >= 1),
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'retired')),
    visual TEXT NOT NULL CHECK(visual <> ''),
    published_at TIMESTAMPTZ,
    PRIMARY KEY (template_id, version)
);

CREATE TABLE IF NOT EXISTS visual_template_slots (
    template_id TEXT NOT NULL,
    version INTEGER NOT NULL,
    slot_name TEXT NOT NULL CHECK(slot_name <> ''),
    role TEXT NOT NULL CHECK (role IN ('dimension', 'measure', 'series', 'label', 'value', 'node_id', 'parent_id', 'edge_source', 'edge_target', 'group')),
    is_required BOOLEAN NOT NULL DEFAULT TRUE,
    min_count INTEGER NOT NULL DEFAULT 1 CHECK (min_count >= 0),
    max_count INTEGER NOT NULL DEFAULT 1 CHECK (max_count >= min_count),
    PRIMARY KEY (template_id, version, slot_name),
    FOREIGN KEY (template_id, version) REFERENCES visual_template_versions(template_id, version) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS visual_template_slot_types (
    template_id TEXT NOT NULL,
    version INTEGER NOT NULL,
    slot_name TEXT NOT NULL,
    field_type TEXT NOT NULL CHECK(field_type <> ''),
    PRIMARY KEY (template_id, version, slot_name, field_type),
    FOREIGN KEY (template_id, version, slot_name) REFERENCES visual_template_slots(template_id, version, slot_name) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS visual_template_options (
    template_id TEXT NOT NULL,
    version INTEGER NOT NULL,
    option_name TEXT NOT NULL CHECK(option_name <> ''),
    value_type TEXT NOT NULL CHECK (value_type IN ('bool', 'int', 'float', 'text', 'enum')),
    default_value TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (template_id, version, option_name),
    FOREIGN KEY (template_id, version) REFERENCES visual_template_versions(template_id, version) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS visual_template_option_values (
    template_id TEXT NOT NULL,
    version INTEGER NOT NULL,
    option_name TEXT NOT NULL,
    allowed_value TEXT NOT NULL,
    PRIMARY KEY (template_id, version, option_name, allowed_value),
    FOREIGN KEY (template_id, version, option_name) REFERENCES visual_template_options(template_id, version, option_name) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS localized_texts (
    owner_kind TEXT NOT NULL CHECK(owner_kind <> ''),
    owner_key TEXT NOT NULL CHECK(owner_key <> ''),
    text_key TEXT NOT NULL CHECK(text_key <> ''),
    lang TEXT NOT NULL CHECK (lang IN ('en', 'pt-BR', 'th')),
    text TEXT NOT NULL,
    PRIMARY KEY (owner_kind, owner_key, text_key, lang)
);

CREATE TABLE IF NOT EXISTS report_card_visuals (
    project_slug TEXT NOT NULL,
    report_slug TEXT NOT NULL,
    card_id TEXT NOT NULL,
    template_id TEXT NOT NULL,
    template_version INTEGER NOT NULL,
    PRIMARY KEY (project_slug, report_slug, card_id),
    FOREIGN KEY (project_slug, report_slug, card_id) REFERENCES datasets(project_slug, report_slug, dataset_id) ON DELETE CASCADE,
    FOREIGN KEY (template_id, template_version) REFERENCES visual_template_versions(template_id, version)
);

CREATE TABLE IF NOT EXISTS report_card_visual_fields (
    project_slug TEXT NOT NULL,
    report_slug TEXT NOT NULL,
    card_id TEXT NOT NULL,
    slot_name TEXT NOT NULL CHECK(slot_name <> ''),
    position INTEGER NOT NULL CHECK (position >= 0),
    field_name TEXT NOT NULL CHECK(field_name <> ''),
    PRIMARY KEY (project_slug, report_slug, card_id, slot_name, position),
    FOREIGN KEY (project_slug, report_slug, card_id) REFERENCES report_card_visuals(project_slug, report_slug, card_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS report_card_visual_options (
    project_slug TEXT NOT NULL,
    report_slug TEXT NOT NULL,
    card_id TEXT NOT NULL,
    option_name TEXT NOT NULL CHECK(option_name <> ''),
    value TEXT NOT NULL,
    PRIMARY KEY (project_slug, report_slug, card_id, option_name),
    FOREIGN KEY (project_slug, report_slug, card_id) REFERENCES report_card_visuals(project_slug, report_slug, card_id) ON DELETE CASCADE
);
