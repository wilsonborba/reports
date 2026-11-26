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
                    "unit": "percent",
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


def apply_bundle(engine: Engine, project: str) -> None:
    bundle = build_bundle()
    engine.request(
        "POST",
        f"/projects/{project}/admin/schemas",
        {"schema_name": SCHEMA_NAME, "fields": SCHEMA_FIELDS},
    )
    engine.request(
        "POST",
        f"/projects/{project}/admin/schemas/{SCHEMA_NAME}/versions/{SCHEMA_VERSION}/publish",
        {},
    )
    engine.request(
        "PUT",
        f"/projects/{project}/admin/reports/{REPORT_ID}",
        {
            "title": bundle["report"]["title"],
            "visibility": bundle["report"]["visibility"],
        },
    )
    for order, ds in enumerate(bundle["datasets"], start=1):
        ds_id = ds["id"]
        engine.request(
            "POST",
            f"/projects/{project}/admin/calculations",
            {"calculation_id": ds_id, "definition": ds["calculation"]},
        )
        engine.request(
            "POST",
            f"/projects/{project}/admin/calculations/{ds_id}/versions/1/publish",
            {},
        )
        engine.request(
            "PUT",
            f"/projects/{project}/admin/reports/{REPORT_ID}/datasets/{ds_id}",
            {
                "visibility": "public",
                "calculation_id": ds_id,
                "calculation_version": 1,
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
