"""Reproducible schema, report, dataset, calculation, and card definitions for real
Asodya/Domain and Wilson current aggregate snapshots (`aggregate_snapshot` v1).

Requires an explicit non-secret project slug (`--project <slug>` or
`REPORTS_AGGREGATE_PROJECT`). Leaves the catalog untouched when unconfigured.

Usage:
  scripts/catalog/populate_aggregates.sh --project <slug> [--dry-run]
  python3 scripts/catalog/aggregates.py --dump-json
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "population"))
from client import Engine  # noqa: E402

SCHEMA_NAME = "aggregate_snapshot"
SCHEMA_VERSION = 1
REPORT_ID = "technical-aggregates"

SCHEMA_FIELDS = [
    {"path": "snapshot_id", "type": "string", "required": True},
    {"path": "snapshot_order", "type": "integer", "required": True},
    {"path": "snapshot_complete", "type": "boolean", "required": True},
    {"path": "availability", "type": "string", "required": True},
    {"path": "metric", "type": "string", "required": True},
    {"path": "group_key", "type": "string", "required": True},
    {"path": "key", "type": "string", "required": True},
    {"path": "value", "type": "integer", "required": True},
    {"path": "denominator", "type": "integer"},
]

LATEST_SNAPSHOT = {
    "order_field": "snapshot_order",
    "complete_field": "snapshot_complete",
    "id_field": "snapshot_id",
}

METRICS = [
    {
        "id": "projects-by-status",
        "metric": "projects_by_status",
        "title": {
            "en": "Projects by status",
            "pt-BR": "Projetos por status",
            "th": "โครงการตามสถานะ",
        },
        "source": "Domain aggregate snapshot",
        "visual": "horizontal_bar",
        "dimension_label": {"en": "Status", "pt-BR": "Status", "th": "สถานะ"},
        "measure_label": {"en": "Projects", "pt-BR": "Projetos", "th": "โครงการ"},
        "unit": "projects",
    },
    {
        "id": "categories-distribution",
        "metric": "categories_distribution",
        "title": {
            "en": "Categories distribution",
            "pt-BR": "Distribuição por categoria",
            "th": "การกระจายตามหมวดหมู่",
        },
        "source": "Domain aggregate snapshot",
        "visual": "horizontal_bar",
        "dimension_label": {"en": "Category", "pt-BR": "Categoria", "th": "หมวดหมู่"},
        "measure_label": {"en": "Projects", "pt-BR": "Projetos", "th": "โครงการ"},
        "unit": "projects",
    },
    {
        "id": "languages-distribution",
        "metric": "languages_distribution",
        "title": {
            "en": "Primary languages",
            "pt-BR": "Linguagens principais",
            "th": "ภาษาหลัก",
        },
        "source": "Domain aggregate snapshot",
        "visual": "horizontal_bar",
        "dimension_label": {"en": "Language", "pt-BR": "Linguagem", "th": "ภาษา"},
        "measure_label": {"en": "Projects", "pt-BR": "Projetos", "th": "โครงการ"},
        "unit": "projects",
    },
    {
        "id": "project-language-bytes",
        "metric": "project_language_bytes",
        "title": {
            "en": "Project language bytes",
            "pt-BR": "Bytes por linguagem do projeto",
            "th": "ไบต์ภาษาของโครงการ",
        },
        "source": "GitHub language byte rows",
        "visual": "stacked_bar",
        "unit": "bytes",
    },
    {
        "id": "skill-frequency",
        "metric": "skill_frequency",
        "title": {
            "en": "Skill frequency",
            "pt-BR": "Frequência de habilidades",
            "th": "ความถี่ของทักษะ",
        },
        "source": "Wilson aggregate snapshot",
        "visual": "horizontal_bar",
        "dimension_label": {"en": "Skill", "pt-BR": "Habilidade", "th": "ทักษะ"},
        "measure_label": {
            "en": "Occurrences",
            "pt-BR": "Ocorrências",
            "th": "จำนวนครั้ง",
        },
        "unit": "occurrences",
    },
    {
        "id": "issuer-counts",
        "metric": "issuer_counts",
        "title": {
            "en": "Credentials by issuer",
            "pt-BR": "Credenciais por emissor",
            "th": "ใบรับรองตามผู้ออก",
        },
        "source": "Wilson aggregate snapshot",
        "visual": "horizontal_bar",
        "dimension_label": {"en": "Issuer", "pt-BR": "Emissor", "th": "ผู้ออก"},
        "measure_label": {
            "en": "Credentials",
            "pt-BR": "Credenciais",
            "th": "ใบรับรอง",
        },
        "unit": "credentials",
    },
    {
        "id": "certification-type-counts",
        "metric": "certification_type_counts",
        "title": {
            "en": "Credentials by type",
            "pt-BR": "Credenciais por tipo",
            "th": "ใบรับรองตามประเภท",
        },
        "source": "Wilson aggregate snapshot",
        "visual": "horizontal_bar",
        "dimension_label": {"en": "Type", "pt-BR": "Tipo", "th": "ประเภท"},
        "measure_label": {
            "en": "Credentials",
            "pt-BR": "Credenciais",
            "th": "ใบรับรอง",
        },
        "unit": "credentials",
    },
]


def build_calculation(spec: dict) -> dict:
    metric = spec["metric"]
    if metric == "project_language_bytes":
        return {
            "title": spec["title"],
            "source": SCHEMA_NAME,
            "latest_snapshot": LATEST_SNAPSHOT,
            "where": [
                {"field": "metric", "op": "eq", "value": metric},
                {"field": "snapshot_complete", "op": "eq", "value": False},
                {"field": "denominator", "op": "gt", "value": 0},
            ],
            "stages": [
                {
                    "group_by": ["group_key", "key"],
                    "measures": [
                        {"name": "bytes", "agg": "sum", "field": "value"},
                        {"name": "total_bytes", "agg": "max", "field": "denominator"},
                    ],
                    "derived": [{"name": "percentage", "expr": "bytes / total_bytes * 100"}],
                }
            ],
            "fields": [
                {
                    "name": "group_key",
                    "label": {"en": "Project", "pt-BR": "Projeto", "th": "โครงการ"},
                    "type": "string",
                    "role": "dimension",
                },
                {
                    "name": "key",
                    "label": {"en": "Language", "pt-BR": "Linguagem", "th": "ภาษา"},
                    "type": "string",
                    "role": "dimension",
                },
                {
                    "name": "bytes",
                    "label": {"en": "Bytes", "pt-BR": "Bytes", "th": "ไบต์"},
                    "type": "integer",
                    "unit": "bytes",
                    "role": "measure",
                },
                {
                    "name": "total_bytes",
                    "label": {
                        "en": "Total bytes",
                        "pt-BR": "Total de bytes",
                        "th": "ไบต์ทั้งหมด",
                    },
                    "type": "integer",
                    "unit": "bytes",
                    "role": "measure",
                },
                {
                    "name": "percentage",
                    "label": {
                        "en": "Share (%)",
                        "pt-BR": "Participação (%)",
                        "th": "สัดส่วน (%)",
                    },
                    "type": "percent",
                    "unit": "%",
                    "role": "measure",
                },
            ],
        }

    return {
        "title": spec["title"],
        "source": SCHEMA_NAME,
        "latest_snapshot": LATEST_SNAPSHOT,
        "where": [
            {"field": "metric", "op": "eq", "value": metric},
            {"field": "snapshot_complete", "op": "eq", "value": False},
            {"field": "availability", "op": "eq", "value": "available"},
        ],
        "stages": [
            {
                "group_by": ["key"],
                "measures": [{"name": "count", "agg": "sum", "field": "value"}],
            }
        ],
        "fields": [
            {
                "name": "key",
                "label": spec["dimension_label"],
                "type": "string",
                "role": "dimension",
            },
            {
                "name": "count",
                "label": spec["measure_label"],
                "type": "integer",
                "unit": spec["unit"],
                "role": "measure",
            },
        ],
    }


def build_bundle() -> dict:
    return {
        "schema": {
            "schema_name": SCHEMA_NAME,
            "version": SCHEMA_VERSION,
            "fields": SCHEMA_FIELDS,
        },
        "report": {
            "id": REPORT_ID,
            "title": {
                "en": "Technical aggregates",
                "pt-BR": "Agregados técnicos",
                "th": "ข้อมูลสรุปทางเทคนิค",
            },
            "visibility": "public",
        },
        "datasets": [
            {
                "id": spec["id"],
                "metric": spec["metric"],
                "visual": spec["visual"],
                "calculation": build_calculation(spec),
                "meta": {
                    "source": spec["source"],
                    "timezone": "UTC",
                    "freshness_mode": "live",
                    "expected_refresh_minutes": 60,
                    "field_semantics": (
                        [
                            {
                                "field_name": "percentage",
                                "denominator_field": "total_bytes",
                                "denominator_text": "total language bytes",
                                "missing_means": "no_data",
                            }
                        ]
                        if spec["metric"] == "project_language_bytes"
                        else []
                    ),
                },
            }
            for spec in METRICS
        ],
    }


def schema_fields_equal(a_fields: list[dict], b_fields: list[dict]) -> bool:
    def normalize(fields: list[dict]):
        return sorted(
            [
                (
                    f.get("path"),
                    f.get("type") or f.get("field_type"),
                    bool(f.get("required", False)),
                )
                for f in fields
            ]
        )

    return normalize(a_fields) == normalize(b_fields)


def normalize_condition(c: dict) -> dict:
    return {
        "field": c.get("field", ""),
        "op": c.get("op", ""),
        "value": c.get("value"),
    }


def normalize_measure(m: dict) -> dict:
    return {
        "name": m.get("name", ""),
        "agg": m.get("agg", ""),
        "field": m.get("field"),
        "fields": list(m.get("fields") or []),
        "by": m.get("by"),
        "where": [normalize_condition(c) for c in (m.get("where") or [])],
        "n": m.get("n"),
    }


def normalize_derived(d: dict) -> dict:
    return {
        "name": d.get("name", ""),
        "expr": d.get("expr"),
        "expr_field": d.get("expr_field"),
    }


def normalize_stage(s: dict) -> dict:
    return {
        "group_by": list(s.get("group_by") or []),
        "measures": [normalize_measure(m) for m in (s.get("measures") or [])],
        "derived": [normalize_derived(d) for d in (s.get("derived") or [])],
        "partition_by": list(s.get("partition_by") or []),
        "having": [normalize_condition(c) for c in (s.get("having") or [])],
        "windows": list(s.get("windows") or []),
    }


def normalize_field(f: dict) -> dict:
    return {
        "name": f.get("name", ""),
        "label": dict(f.get("label") or {}),
        "type": f.get("type") or f.get("field_type") or "",
        "role": f.get("role") or "measure",
        "unit": f.get("unit"),
        "decimals": f.get("decimals"),
        "missing_means": f.get("missing_means") or "no_data",
        "denominator_field": f.get("denominator_field"),
        "denominator_text": f.get("denominator_text"),
    }


def normalize_spec(s: dict) -> dict:
    if not s:
        return {}
    return {
        "title": dict(s.get("title") or {}),
        "description": dict(s.get("description") or {}),
        "equation": s.get("equation"),
        "source": s.get("source"),
        "union": list(s.get("union") or []),
        "lookups": list(s.get("lookups") or []),
        "latest_snapshot": (
            {
                "order_field": s["latest_snapshot"].get("order_field", ""),
                "complete_field": s["latest_snapshot"].get("complete_field", ""),
                "id_field": s["latest_snapshot"].get("id_field", ""),
            }
            if s.get("latest_snapshot")
            else None
        ),
        "buckets": list(s.get("buckets") or []),
        "row_derived": [normalize_derived(d) for d in (s.get("row_derived") or [])],
        "where": [normalize_condition(c) for c in (s.get("where") or [])],
        "filters": list(s.get("filters") or []),
        "stages": [normalize_stage(st) for st in (s.get("stages") or [])],
        "derived": [normalize_derived(d) for d in (s.get("derived") or [])],
        "having": [normalize_condition(c) for c in (s.get("having") or [])],
        "calculator": s.get("calculator"),
        "params": dict(s.get("params") or {}),
        "refs": dict(s.get("refs") or {}),
        "sort": list(s.get("sort") or []),
        "limit": s.get("limit"),
        "fields": [normalize_field(f) for f in (s.get("fields") or [])],
        "value_labels": dict(s.get("value_labels") or {}),
        "warm": bool(s.get("warm", False)),
    }


def calculation_definitions_equal(existing: dict, target: dict) -> bool:
    return normalize_spec(existing) == normalize_spec(target)


def reconcile_schema(
    engine: Engine, project: str, schema_name: str, target_fields: list[dict]
) -> int:
    existing_schemas = engine.get(f"/admin/projects/{project}/schemas")
    versions = [s for s in existing_schemas if s.get("schema_name") == schema_name]
    v1_list = [s for s in versions if s.get("version") == SCHEMA_VERSION]

    if v1_list:
        v1 = v1_list[0]
        if v1.get("status") == "published":
            if schema_fields_equal(v1.get("fields", []), target_fields):
                return SCHEMA_VERSION
            raise RuntimeError(
                f"Schema {schema_name} v{SCHEMA_VERSION} is published with different immutable fields; "
                f"cannot mutate pinned producer schema version {SCHEMA_VERSION} without coordinated migration."
            )
        if v1.get("status") == "draft":
            if not schema_fields_equal(v1.get("fields", []), target_fields):
                engine.request(
                    "POST",
                    f"/projects/{project}/admin/schemas",
                    {
                        "schema_name": schema_name,
                        "version": SCHEMA_VERSION,
                        "fields": target_fields,
                    },
                )
            engine.request(
                "POST",
                f"/projects/{project}/admin/schemas/{schema_name}/versions/{SCHEMA_VERSION}/publish",
                {},
            )
            return SCHEMA_VERSION

    if versions and not v1_list:
        raise RuntimeError(
            f"Schema {schema_name} has existing versions {[s.get('version') for s in versions]} "
            f"but pinned v{SCHEMA_VERSION} is absent; coordinated migration required."
        )

    # Clean catalog: create draft v1 and publish.
    saved = engine.request(
        "POST",
        f"/projects/{project}/admin/schemas",
        {"schema_name": schema_name, "version": SCHEMA_VERSION, "fields": target_fields},
    )
    v = saved.get("version", SCHEMA_VERSION)
    engine.request(
        "POST",
        f"/projects/{project}/admin/schemas/{schema_name}/versions/{v}/publish",
        {},
    )
    return v


def reconcile_calculation(
    engine: Engine,
    project: str,
    calc_id: str,
    target_def: dict,
    schema_version: int,
    existing_calcs: list[dict],
) -> int:
    versions = [c for c in existing_calcs if c.get("calculation_id") == calc_id]
    versions.sort(key=lambda x: x.get("version", 0))

    # 1. Exact matching published version: definition, schema pin, and no pending review.
    for c in versions:
        if (
            c.get("status") == "published"
            and calculation_definitions_equal(c.get("definition", {}), target_def)
            and c.get("input_schema") == SCHEMA_NAME
            and c.get("input_schema_version") == schema_version
            and not c.get("needs_review")
        ):
            return c["version"]

    # 2. Existing draft version: if definition, schema pin, and needs_review are clean, publish.
    drafts = [c for c in versions if c.get("status") == "draft"]
    if drafts:
        draft = drafts[-1]
        v = draft["version"]
        is_exact = (
            calculation_definitions_equal(draft.get("definition", {}), target_def)
            and draft.get("input_schema_version") == schema_version
            and not draft.get("needs_review")
        )
        if not is_exact:
            # Re-save draft with exact selected schema pin and definition.
            engine.request(
                "POST",
                f"/projects/{project}/admin/calculations",
                {
                    "calculation_id": calc_id,
                    "version": v,
                    "input_schema_version": schema_version,
                    "definition": target_def,
                },
            )
        engine.request(
            "POST",
            f"/projects/{project}/admin/calculations/{calc_id}/versions/{v}/publish",
            {},
        )
        return v

    # 3. No matching version and no draft: create next draft with explicit input_schema_version and publish.
    req_body: dict = {
        "calculation_id": calc_id,
        "input_schema_version": schema_version,
        "definition": target_def,
    }
    if not versions:
        req_body["version"] = 1
    saved = engine.request("POST", f"/projects/{project}/admin/calculations", req_body)
    v = saved.get("version", 1)
    engine.request(
        "POST",
        f"/projects/{project}/admin/calculations/{calc_id}/versions/{v}/publish",
        {},
    )
    return v


def apply_bundle(engine: Engine, project: str) -> None:
    bundle = build_bundle()
    schema_version = reconcile_schema(engine, project, SCHEMA_NAME, SCHEMA_FIELDS)
    engine.request(
        "PUT",
        f"/projects/{project}/admin/reports/{REPORT_ID}",
        {
            "title": bundle["report"]["title"],
            "visibility": bundle["report"]["visibility"],
        },
    )
    existing_calcs = engine.get(f"/admin/projects/{project}/calculations")
    for order, ds in enumerate(bundle["datasets"], start=1):
        ds_id = ds["id"]
        calc_version = reconcile_calculation(
            engine,
            project,
            ds_id,
            ds["calculation"],
            schema_version,
            existing_calcs,
        )
        engine.request(
            "PUT",
            f"/projects/{project}/admin/reports/{REPORT_ID}/datasets/{ds_id}",
            {
                "visibility": "public",
                "calculation_id": ds_id,
                "calculation_version": calc_version,
                "visual": ds["visual"],
                "card_order": order,
            },
        )
        engine.request(
            "PUT",
            f"/projects/{project}/admin/reports/{REPORT_ID}/datasets/{ds_id}/meta",
            ds["meta"],
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Initialize aggregate_snapshot catalog definitions.")
    parser.add_argument("--project", default=os.environ.get("REPORTS_AGGREGATE_PROJECT", ""))
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--dump-json", action="store_true")
    args = parser.parse_args()

    if args.dump_json:
        print(json.dumps(build_bundle(), indent=2, ensure_ascii=False))
        return 0

    project = args.project.strip()
    if not project:
        print(
            "Unconfigured: set --project <slug> or REPORTS_AGGREGATE_PROJECT (no live project slug assumed)."
        )
        return 0 if args.dry_run else 2

    if args.dry_run:
        bundle = build_bundle()
        print(
            f"Dry run: would publish schema {SCHEMA_NAME} v{SCHEMA_VERSION}, "
            f"report '{REPORT_ID}', and {len(bundle['datasets'])} datasets/cards for '{project}'"
        )
        return 0

    engine = Engine(dry_run=False)
    apply_bundle(engine, project)
    print(
        f"Prepared {len(METRICS)} aggregate datasets/cards under report '{REPORT_ID}' for '{project}'"
        + (" (dry run)" if args.dry_run else "")
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
