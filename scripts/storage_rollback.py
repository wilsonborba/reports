#!/usr/bin/env python3
"""Export normalized storage or restore it into an empty prior-release database.

Stop writers before export. Set REPORTS_STORAGE_DATABASE_URL explicitly; this tool
never loads .env. Restore into a separate empty database using the schema supplied
by the prior release, verify it, then switch the previous engine to that database.
The original database remains available for retry. Keep the export private.
The supported restoration target is the prior-release schema through migration006;
schema005 cannot represent standalone drafts or versioned calculations.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TABLES = (
    "catalog_projects", "reports", "datasets", "user_project_roles", "report_cards",
    "site_settings", "resource_grants", "fixture_manifest", "schema_versions",
    "schema_fields", "calculation_versions",
)


def psql(sql):
    url = os.environ.get("REPORTS_STORAGE_DATABASE_URL")
    if not url:
        raise ValueError("Set REPORTS_STORAGE_DATABASE_URL to the explicit source or empty restoration target")
    result = subprocess.run(
        ["psql", "--dbname", url, "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1"],
        input=sql, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if result.returncode:
        # Do not print target credentials or row contents in an error.
        raise ValueError("Storage export/restoration SQL failed; verify the schema and database target")
    return result.stdout.strip()


def export_sql():
    projects = """SELECT to_jsonb(p) || jsonb_build_object(
      'name',COALESCE((SELECT jsonb_object_agg(lang,text) FROM project_texts WHERE project_slug=p.slug AND text_key='name'),'{}'::jsonb),
      'tagline',COALESCE((SELECT jsonb_object_agg(lang,text) FROM project_texts WHERE project_slug=p.slug AND text_key='tagline'),'{}'::jsonb),
      'description',COALESCE((SELECT jsonb_object_agg(lang,text) FROM project_texts WHERE project_slug=p.slug AND text_key='description'),'{}'::jsonb),
      'theme',COALESCE((SELECT jsonb_object_agg(mode,
        COALESCE((SELECT jsonb_object_agg(token,color) FROM project_theme_colors c WHERE c.project_slug=p.slug AND c.mode=m.mode AND token<>'series'),'{}'::jsonb)
        ||jsonb_build_object('series',COALESCE((SELECT jsonb_agg(color ORDER BY position) FROM project_theme_colors c WHERE c.project_slug=p.slug AND c.mode=m.mode AND token='series'),'[]'::jsonb))) FROM project_theme_modes m WHERE m.project_slug=p.slug),'{}'::jsonb)) AS row FROM catalog_projects p"""
    reports = """SELECT (to_jsonb(r)-'sort_order'-'period_collection'-'period_field') || jsonb_build_object(
      'title',COALESCE((SELECT jsonb_object_agg(lang,text) FROM report_texts WHERE project_slug=r.project_slug AND report_slug=r.slug AND text_key='title'),'{}'::jsonb),
      'description',COALESCE((SELECT jsonb_object_agg(lang,text) FROM report_texts WHERE project_slug=r.project_slug AND report_slug=r.slug AND text_key='description'),'{}'::jsonb),
      'metadata',jsonb_build_object('sort_order',r.sort_order,'period_source',CASE WHEN period_collection IS NULL THEN 'null'::jsonb ELSE jsonb_build_object('collection',period_collection,'field',period_field) END,
       'tags',COALESCE((SELECT jsonb_agg(value ORDER BY position) FROM report_ordered_items WHERE project_slug=r.project_slug AND report_slug=r.slug AND kind='tag'),'[]'::jsonb))
       ||CASE WHEN EXISTS(SELECT 1 FROM report_ordered_items WHERE project_slug=r.project_slug AND report_slug=r.slug AND kind='card') THEN jsonb_build_object('card_order',(SELECT jsonb_agg(value ORDER BY position) FROM report_ordered_items WHERE project_slug=r.project_slug AND report_slug=r.slug AND kind='card')) ELSE '{}'::jsonb END) AS row FROM reports r"""
    calculations = """SELECT to_jsonb(c) || jsonb_build_object(
       'inputs',COALESCE((SELECT jsonb_agg(jsonb_build_object('schema',schema_name,'version',schema_version) ORDER BY position) FROM calculation_inputs i WHERE i.project_slug=c.project_slug AND i.calculation_id=c.calculation_id AND i.version=c.version),'[]'::jsonb),
       'definition',pg_temp.export_calculation_definitions(project_slug,calculation_id,version,'')) AS row FROM calculation_versions c"""
    special = {
        "catalog_projects": projects, "reports": reports, "calculation_versions": calculations,
        "report_cards": "SELECT to_jsonb(c)||jsonb_build_object('config',pg_temp.export_card_properties(project_slug,report_slug,card_id)) AS row FROM report_cards c",
        "site_settings": "SELECT to_jsonb(s)||jsonb_build_object('value',pg_temp.export_setting_properties(key)) AS row FROM site_settings s",
    }
    values = []
    for table in TABLES:
        query = special.get(table, f"SELECT to_jsonb(t) AS row FROM {table} t")
        values.append(f"'{table}',COALESCE((SELECT jsonb_agg(row) FROM ({query}) exported),'[]'::jsonb)")
    return (
        "BEGIN ISOLATION LEVEL REPEATABLE READ;\n"
        + (ROOT / "engine/storage/export_legacy.sql").read_text()
        + "\nSELECT jsonb_build_object('format',1,'tables',jsonb_build_object("
        + ",".join(values) + "));\nROLLBACK;\n"
    )


def literal(value):
    if value is None:
        return "NULL"
    if isinstance(value, (dict, list)):
        value = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    elif isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    elif isinstance(value, (int, float)):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def restore_sql(snapshot, historical_schema):
    if snapshot.get("format") != 1 or set(snapshot.get("tables", {})) != set(TABLES):
        raise ValueError("Unsupported or incomplete storage export")
    # Every table identifier comes from the allowlist. Field identifiers come from
    # the old schema, checked inside the same transaction before inserting data.
    sql = """BEGIN;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema=current_schema() AND table_type='BASE TABLE') THEN
  RAISE EXCEPTION 'Restoration requires an empty database schema';
 END IF;
END $$;
""" + historical_schema + "\nSET standard_conforming_strings=on;\n"
    for table in TABLES:
        for row in snapshot["tables"][table]:
            # json_populate_record performs prior-release type conversion. Its JSON
            # argument is transient; the prior release owns its historical schema.
            payload = literal(json.dumps(row, ensure_ascii=False))
            sql += f"INSERT INTO {table} SELECT (json_populate_record(NULL::{table}, {payload}::json)).*;\n"
    return sql + "COMMIT;\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--export", type=Path, dest="export_path")
    action.add_argument("--restore", type=Path, dest="restore_path")
    parser.add_argument("--historical-schema", type=Path)
    args = parser.parse_args()
    if args.export_path:
        snapshot = psql(export_sql())
        json.loads(snapshot)
        fd = os.open(args.export_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as output:
            output.write(snapshot + "\n")
        print("Storage export saved. Keep it private.")
    else:
        if not args.historical_schema:
            parser.error("--restore requires --historical-schema from the prior release")
        snapshot = json.loads(args.restore_path.read_text())
        psql(restore_sql(snapshot, args.historical_schema.read_text()))
        print("Storage restored into the empty prior-release database.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
