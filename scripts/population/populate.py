"""Loads the sample (synthetic) data of the five launch projects through the admin API.

Every write carries `x-reports-fixture: sample-v1-<project>`, so the engine records the
ownership and `delete_fake_data.sh` can remove exactly this data later. A repeated run
reuses identical published schema and calculation versions, keeps the same visibility
(fixed seed) and writes no duplicate records (stable idempotency keys).

Usage: scripts/populate_fake_data.sh [--project <slug>] [--dry-run]
"""

from __future__ import annotations

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import random

from client import Engine, EngineError
from projects import autodroid, certifications, common, cortex, domain, fsm

MODULES = {m.PROJECT: m for m in (domain, certifications, cortex, autodroid, fsm)}
BATCH = 1000


def manifest_of(project: str) -> str:
    return f"sample-v1-{project}"


def subset(mine, theirs) -> bool:
    """True when every value of `mine` is in `theirs` (the engine adds defaults)."""
    if isinstance(mine, dict):
        return isinstance(theirs, dict) and all(k in theirs and subset(v, theirs[k]) for k, v in mine.items())
    if isinstance(mine, list):
        return isinstance(theirs, list) and len(mine) == len(theirs) and all(subset(a, b) for a, b in zip(mine, theirs))
    if isinstance(mine, (int, float)) and isinstance(theirs, (int, float)) and not isinstance(mine, bool):
        return float(mine) == float(theirs)
    return mine == theirs


def visibility_plan(module) -> dict:
    """Fixed-seed visibility of every report and card of one project."""
    rng = random.Random(f"reports-sample-v1-{module.PROJECT}")
    plan = {}
    for ri, report in enumerate(module.REPORTS):
        r_vis = "public" if ri == 0 else common.weighted(rng, {"public": 6, "signed_in": 3, "restricted": 1})
        cards = {}
        for ci, card in enumerate(report["cards"]):
            # The first card of the first report stays public, so every project has a guest chart.
            vis = "public" if ri == 0 and ci == 0 else common.weighted(rng, {"public": 5, "signed_in": 3, "restricted": 2})
            cards[card] = {"visibility": vis, "discoverable": vis != "public" and rng.random() < 0.7}
        plan[report["slug"]] = {"visibility": r_vis, "discoverable": r_vis != "public", "cards": cards}
    return plan


def same_fields(mine: list[dict], theirs: list[dict]) -> bool:
    """True when both lists hold the same fields. The engine returns fields ordered by
    path, so the order of the lists does not count."""
    by_path = {f["path"]: f for f in theirs}
    return len(mine) == len(theirs) and all(f["path"] in by_path and subset(f, by_path[f["path"]]) for f in mine)


def ensure_schema(engine: Engine, project: str, schema: dict) -> int:
    existing = engine.get(f"/admin/projects/{project}/schemas")
    for s in existing:
        if s["schema_name"] == schema["schema_name"] and s["status"] == "published" and same_fields(schema["fields"], s["fields"]):
            return s["version"]
    draft = engine.request("POST", f"/projects/{project}/admin/schemas", schema)
    version = draft.get("version", 1)
    engine.request("POST", f"/projects/{project}/admin/schemas/{schema['schema_name']}/versions/{version}/publish", {}, fixture=False)
    return version


def ensure_calculation(engine: Engine, project: str, calc_id: str, definition: dict, existing: list) -> int:
    for c in existing:
        if c["calculation_id"] == calc_id and c["status"] == "published" and subset(definition, c["definition"]):
            return c["version"]
    draft = engine.request("POST", f"/projects/{project}/admin/calculations", {"calculation_id": calc_id, "definition": definition})
    version = draft.get("version", 1)
    engine.request("POST", f"/projects/{project}/admin/calculations/{calc_id}/versions/{version}/publish", {}, fixture=False)
    return version


def populate(module, dry_run: bool) -> dict:
    project = module.PROJECT
    engine = Engine(fixture=manifest_of(project), dry_run=dry_run)
    try:
        engine.get(f"/projects/{project}")
    except EngineError as e:
        if e.status == 404:
            raise SystemExit(f"Project '{project}' is not in the catalog. Run scripts/catalog/populate.sh first.") from None
        raise
    version = ensure_schema(engine, project, module.SCHEMA)
    existing = [] if dry_run else engine.get(f"/admin/projects/{project}/calculations")
    versions = {cid: ensure_calculation(engine, project, cid, d, existing) for cid, d in module.CALCULATIONS.items()}
    plan = visibility_plan(module)
    for order, report in enumerate(module.REPORTS):
        p = plan[report["slug"]]
        engine.request("PUT", f"/projects/{project}/admin/reports/{report['slug']}", {
            "title": report["title"], "description": report["description"],
            "metadata": {"tags": report["tags"] + ["sample"], "sort_order": order,
                         "period_source": {"collection": module.SCHEMA["schema_name"], "field": report["period_field"]}},
            "visibility": p["visibility"], "discoverable": p["discoverable"],
        })
        for card in report["cards"]:
            c = p["cards"][card]
            engine.request("PUT", f"/projects/{project}/admin/reports/{report['slug']}/datasets/{card}", {
                "data_tier": "sample", "calculation_id": card, "calculation_version": versions.get(card, 1),
                "visibility": c["visibility"], "discoverable": c["discoverable"],
            })
    rows = module.records(random.Random(f"reports-sample-v1-{project}-records"))
    created = duplicates = 0
    for i in range(0, len(rows), BATCH):
        result = engine.request("POST", f"/projects/{project}/admin/ingest/{module.SCHEMA['schema_name']}",
                                {"schema_version": version, "records": rows[i:i + BATCH]})
        created += result.get("created", 0)
        duplicates += result.get("duplicates", 0)
    cards = sum(len(r["cards"]) for r in module.REPORTS)
    return {"project": project, "reports": len(module.REPORTS), "cards": cards, "records": len(rows),
            "created": created, "duplicates": duplicates, "plan": plan}


def main() -> int:
    parser = argparse.ArgumentParser(description="Load sample data for the launch projects")
    parser.add_argument("--project", choices=sorted(MODULES), help="only this project")
    parser.add_argument("--dry-run", action="store_true", help="print the plan, send nothing")
    parser.add_argument("--dump", metavar="FILE", help="write the requests as JSON to FILE, send nothing (tests)")
    args = parser.parse_args()
    if args.dump:
        Engine.recorder = []
    selected = [MODULES[args.project]] if args.project else list(MODULES.values())
    totals = {"public": 0, "signed_in": 0, "restricted": 0}
    for module in selected:
        summary = populate(module, args.dry_run)
        for report, p in summary["plan"].items():
            cards = ", ".join(f"{c}={v['visibility']}{'*' if v['discoverable'] else ''}" for c, v in p["cards"].items())
            print(f"  {summary['project']}/{report} ({p['visibility']}): {cards}")
            for v in p["cards"].values():
                totals[v["visibility"]] += 1
        print(f"{summary['project']}: {summary['reports']} reports, {summary['cards']} cards, "
              f"{summary['records']} records ({summary['created']} new, {summary['duplicates']} already stored)")
    print(f"Cards by visibility: {totals} (* = discoverable placeholder){' (dry run, nothing sent)' if args.dry_run else ''}")
    if args.dump:
        import json
        pathlib.Path(args.dump).write_text(json.dumps(Engine.recorder))
        print(f"Wrote {len(Engine.recorder)} requests to {args.dump}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
