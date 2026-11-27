#!/usr/bin/env python3
"""Inert fake-API regression tests for Reports catalog apply_bundle repeatability and recovery.

Faithfully exercises independent Rust-serde shapes and causal provenance cases:
1. Fresh project initialization (schema v1, report, calculations v1, dataset cards).
2. Second run idempotence against independently constructed Rust serde defaults (0 POSTs, 0 duplicate versions).
3. Exact calculation definition equality: extra limit1 or union fields fail match and create safe new versions.
4. Producer schema pin constraint: matching v1 + higher incompatible published v2 pins v1; missing v1 only v2 fails without POST.
5. Stale draft re-saving: wrong pin-only draft (input_schema_version != 1) or review flag-only draft (needs_review == True) is re-saved with selected pin.
6. Bug-state recovery: published v1 matching definition is reconciled even when leftover unhandled v2 draft exists.

Zero external network egress, zero real engine/database mutations.
"""

from __future__ import annotations

import copy
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import aggregates  # noqa: E402


class FakeEngineError(RuntimeError):
    def __init__(self, status: int, method: str, path: str, body: str):
        super().__init__(f"{method} {path} returned {status}: {body}")
        self.status = status


def _independent_rust_serde_spec(raw: dict) -> dict:
    """Independent simulation of Rust serde JSON serialization for DatasetSpec without using function under test."""
    return {
        "title": dict(raw.get("title") or {}),
        "description": dict(raw.get("description") or {}),
        "equation": raw.get("equation"),
        "source": raw.get("source"),
        "union": list(raw.get("union") or []),
        "lookups": list(raw.get("lookups") or []),
        "latest_snapshot": (
            {
                "order_field": raw["latest_snapshot"]["order_field"],
                "complete_field": raw["latest_snapshot"]["complete_field"],
                "id_field": raw["latest_snapshot"]["id_field"],
            }
            if raw.get("latest_snapshot")
            else None
        ),
        "buckets": list(raw.get("buckets") or []),
        "row_derived": [
            {
                "name": d.get("name", ""),
                "expr": d.get("expr"),
                "expr_field": d.get("expr_field"),
            }
            for d in (raw.get("row_derived") or [])
        ],
        "where": [
            {
                "field": c.get("field", ""),
                "op": c.get("op", ""),
                "value": c.get("value"),
            }
            for c in (raw.get("where") or [])
        ],
        "filters": list(raw.get("filters") or []),
        "stages": [
            {
                "group_by": list(st.get("group_by") or []),
                "measures": [
                    {
                        "name": m.get("name", ""),
                        "agg": m.get("agg", ""),
                        "field": m.get("field"),
                        "fields": list(m.get("fields") or []),
                        "by": m.get("by"),
                        "where": [
                            {
                                "field": c.get("field", ""),
                                "op": c.get("op", ""),
                                "value": c.get("value"),
                            }
                            for c in (m.get("where") or [])
                        ],
                        "n": m.get("n"),
                    }
                    for m in (st.get("measures") or [])
                ],
                "derived": [
                    {
                        "name": d.get("name", ""),
                        "expr": d.get("expr"),
                        "expr_field": d.get("expr_field"),
                    }
                    for d in (st.get("derived") or [])
                ],
                "partition_by": list(st.get("partition_by") or []),
                "having": [
                    {
                        "field": c.get("field", ""),
                        "op": c.get("op", ""),
                        "value": c.get("value"),
                    }
                    for c in (st.get("having") or [])
                ],
                "windows": list(st.get("windows") or []),
            }
            for st in (raw.get("stages") or [])
        ],
        "derived": [
            {
                "name": d.get("name", ""),
                "expr": d.get("expr"),
                "expr_field": d.get("expr_field"),
            }
            for d in (raw.get("derived") or [])
        ],
        "having": [
            {
                "field": c.get("field", ""),
                "op": c.get("op", ""),
                "value": c.get("value"),
            }
            for c in (raw.get("having") or [])
        ],
        "calculator": raw.get("calculator"),
        "params": dict(raw.get("params") or {}),
        "refs": dict(raw.get("refs") or {}),
        "sort": list(raw.get("sort") or []),
        "limit": raw.get("limit"),
        "fields": [
            {
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
            for f in (raw.get("fields") or [])
        ],
        "value_labels": dict(raw.get("value_labels") or {}),
        "warm": bool(raw.get("warm", False)),
    }


class FakeReportsEngine:
    """In-memory simulation of the Reports engine admin API adhering to exact engine rules."""

    def __init__(self):
        self.schemas: dict[tuple[str, str], list[dict]] = {}
        self.calculations: dict[tuple[str, str], list[dict]] = {}
        self.reports: dict[tuple[str, str], dict] = {}
        self.datasets: dict[tuple[str, str, str], dict] = {}
        self.dataset_meta: dict[tuple[str, str, str], dict] = {}
        self.call_log: list[tuple[str, str]] = []

    def request(self, method: str, path: str, body=None, fixture: bool = True):
        self.call_log.append((method, path))
        parts = path.strip("/").split("/")

        # GET /admin/projects/{project}/schemas
        if method == "GET" and len(parts) == 4 and parts[0] == "admin" and parts[1] == "projects" and parts[3] == "schemas":
            project = parts[2]
            res = []
            for (p, s), vers in self.schemas.items():
                if p == project:
                    res.extend(copy.deepcopy(vers))
            return res

        # GET /admin/projects/{project}/calculations
        if method == "GET" and len(parts) == 4 and parts[0] == "admin" and parts[1] == "projects" and parts[3] == "calculations":
            project = parts[2]
            res = []
            for (p, c), vers in self.calculations.items():
                if p == project:
                    res.extend(copy.deepcopy(vers))
            return res

        # POST /projects/{project}/admin/schemas
        if method == "POST" and len(parts) == 4 and parts[0] == "projects" and parts[2] == "admin" and parts[3] == "schemas":
            project = parts[1]
            schema_name = body["schema_name"]
            key = (project, schema_name)
            versions = self.schemas.setdefault(key, [])
            version = body.get("version")
            if version is None:
                latest = max([v["version"] for v in versions], default=0)
                version = latest + 1
            else:
                for existing in versions:
                    if existing["version"] == version and existing["status"] != "draft":
                        raise FakeEngineError(
                            409,
                            method,
                            path,
                            f"schema {project}:{schema_name} v{version} is {existing['status']} and cannot change; create version {version + 1}",
                        )
            draft = {
                "project": project,
                "schema_name": schema_name,
                "version": version,
                "status": "draft",
                "fields": copy.deepcopy(body.get("fields", [])),
            }
            for i, v in enumerate(versions):
                if v["version"] == version:
                    versions[i] = draft
                    return copy.deepcopy(draft)
            versions.append(draft)
            return copy.deepcopy(draft)

        # POST /projects/{project}/admin/schemas/{schema}/versions/{version}/publish
        if method == "POST" and len(parts) == 8 and parts[0] == "projects" and parts[2] == "admin" and parts[3] == "schemas" and parts[5] == "versions" and parts[7] == "publish":
            project, schema_name, version = parts[1], parts[4], int(parts[6])
            key = (project, schema_name)
            versions = self.schemas.get(key, [])
            for v in versions:
                if v["version"] == version:
                    if v["status"] != "draft":
                        raise FakeEngineError(409, method, path, "Not a draft")
                    v["status"] = "published"
                    return copy.deepcopy(v)
            raise FakeEngineError(404, method, path, "Schema version not found")

        # POST /projects/{project}/admin/calculations
        if method == "POST" and len(parts) == 4 and parts[0] == "projects" and parts[2] == "admin" and parts[3] == "calculations":
            project = parts[1]
            calc_id = body["calculation_id"]
            key = (project, calc_id)
            versions = self.calculations.setdefault(key, [])
            version = body.get("version")
            if version is None:
                latest = max([v["version"] for v in versions], default=0)
                version = latest + 1
            else:
                for existing in versions:
                    if existing["version"] == version and existing["status"] != "draft":
                        raise FakeEngineError(
                            409,
                            method,
                            path,
                            f"calculation {project}:{calc_id} v{version} is {existing['status']} and cannot change; create version {version + 1}",
                        )

            raw_def = copy.deepcopy(body.get("definition", {}))
            norm_def = _independent_rust_serde_spec(raw_def)
            source_schema = raw_def.get("source")
            input_ver = body.get("input_schema_version")
            if input_ver is None and source_schema:
                schema_vers = self.schemas.get((project, source_schema), [])
                pub_vers = [s["version"] for s in schema_vers if s["status"] == "published"]
                input_ver = max(pub_vers, default=None)

            draft = {
                "project": project,
                "calculation_id": calc_id,
                "version": version,
                "status": "draft",
                "input_schema": source_schema,
                "input_schema_version": input_ver,
                "inputs": [{"schema": source_schema, "version": input_ver}] if source_schema and input_ver else [],
                "needs_review": False,
                "definition": norm_def,
            }
            for i, v in enumerate(versions):
                if v["version"] == version:
                    versions[i] = draft
                    return copy.deepcopy(draft)
            versions.append(draft)
            return copy.deepcopy(draft)

        # POST /projects/{project}/admin/calculations/{calculation}/versions/{version}/publish
        if method == "POST" and len(parts) == 8 and parts[0] == "projects" and parts[2] == "admin" and parts[3] == "calculations" and parts[5] == "versions" and parts[7] == "publish":
            project, calc_id, version = parts[1], parts[4], int(parts[6])
            key = (project, calc_id)
            versions = self.calculations.get(key, [])
            for v in versions:
                if v["version"] == version:
                    if v["status"] != "draft":
                        raise FakeEngineError(409, method, path, "Not a draft")
                    v["status"] = "published"
                    return copy.deepcopy(v)
            raise FakeEngineError(404, method, path, "Calculation version not found")

        # PUT /projects/{project}/admin/reports/{report}
        if method == "PUT" and len(parts) == 5 and parts[2] == "admin" and parts[3] == "reports":
            project, report_id = parts[1], parts[4]
            self.reports[(project, report_id)] = copy.deepcopy(body)
            return {"status": "ok"}

        # PUT /projects/{project}/admin/reports/{report}/datasets/{dataset}
        if method == "PUT" and len(parts) == 7 and parts[2] == "admin" and parts[3] == "reports" and parts[5] == "datasets":
            project, report_id, ds_id = parts[1], parts[4], parts[6]
            self.datasets[(project, report_id, ds_id)] = copy.deepcopy(body)
            return {"status": "ok"}

        # PUT /projects/{project}/admin/reports/{report}/datasets/{dataset}/meta
        if method == "PUT" and len(parts) == 8 and parts[2] == "admin" and parts[3] == "reports" and parts[5] == "datasets" and parts[7] == "meta":
            project, report_id, ds_id = parts[1], parts[4], parts[6]
            self.dataset_meta[(project, report_id, ds_id)] = copy.deepcopy(body)
            return {"status": "ok"}

        raise FakeEngineError(404, method, path, f"Unhandled fake route: {method} {path}")

    def get(self, path: str):
        return self.request("GET", path)


class TestAggregatesRepeatability(unittest.TestCase):
    def setUp(self):
        self.engine = FakeReportsEngine()
        self.project = "test-project"

    def test_fresh_apply_bundle(self):
        """Initial run on empty catalog publishes schema v1 and 7 calculation v1s bound to schema v1."""
        aggregates.apply_bundle(self.engine, self.project)

        # Check schema v1
        schema_vers = self.engine.schemas.get((self.project, aggregates.SCHEMA_NAME), [])
        self.assertEqual(len(schema_vers), 1)
        self.assertEqual(schema_vers[0]["version"], 1)
        self.assertEqual(schema_vers[0]["status"], "published")

        # Check calculations
        for spec in aggregates.METRICS:
            calc_id = spec["id"]
            calc_vers = self.engine.calculations.get((self.project, calc_id), [])
            self.assertEqual(len(calc_vers), 1, f"Expected 1 version for {calc_id}")
            self.assertEqual(calc_vers[0]["version"], 1)
            self.assertEqual(calc_vers[0]["status"], "published")
            self.assertEqual(calc_vers[0]["input_schema"], aggregates.SCHEMA_NAME)
            self.assertEqual(calc_vers[0]["input_schema_version"], 1)

            # Check dataset wire
            ds = self.engine.datasets.get((self.project, aggregates.REPORT_ID, calc_id))
            self.assertIsNotNone(ds)
            self.assertEqual(ds["calculation_version"], 1)
            self.assertEqual(ds["visibility"], "public")

    def test_second_run_repeatability_with_independent_rust_serde_defaults(self):
        """Second run against independent Rust-serde shapes creates 0 versions and 0 POSTs."""
        aggregates.apply_bundle(self.engine, self.project)
        self.engine.call_log.clear()

        # Second run
        aggregates.apply_bundle(self.engine, self.project)

        schema_vers = self.engine.schemas.get((self.project, aggregates.SCHEMA_NAME), [])
        self.assertEqual(len(schema_vers), 1)

        for spec in aggregates.METRICS:
            calc_id = spec["id"]
            calc_vers = self.engine.calculations.get((self.project, calc_id), [])
            self.assertEqual(len(calc_vers), 1)
            self.assertEqual(calc_vers[0]["version"], 1)

            ds = self.engine.datasets.get((self.project, aggregates.REPORT_ID, calc_id))
            self.assertEqual(ds["calculation_version"], 1)

        schema_posts = [c for c in self.engine.call_log if "schemas" in c[1] and c[0] == "POST"]
        calc_posts = [c for c in self.engine.call_log if "calculations" in c[1] and c[0] == "POST"]
        self.assertEqual(schema_posts, [])
        self.assertEqual(calc_posts, [])

    def test_extra_limit_or_union_creates_safe_new_version(self):
        """A calculation with extra limit: 1 or union: ['other'] fails equality and creates v2."""
        bundle = aggregates.build_bundle()
        cid0 = bundle["datasets"][0]["id"]

        # Case A: target with extra limit: 1
        with_limit = copy.deepcopy(bundle["datasets"][0]["calculation"])
        with_limit["limit"] = 1
        self.assertFalse(
            aggregates.calculation_definitions_equal(with_limit, bundle["datasets"][0]["calculation"]),
            "realTarget+limit1 must not compare equal to realTarget",
        )

        # Case B: target with extra union
        with_union = copy.deepcopy(bundle["datasets"][0]["calculation"])
        with_union["union"] = ["other-input"]
        self.assertFalse(
            aggregates.calculation_definitions_equal(with_union, bundle["datasets"][0]["calculation"]),
            "realTarget+union must not compare equal to realTarget",
        )

        # Case C: seed published v1 with extra limit: 1 in fake engine
        self.engine.schemas[(self.project, aggregates.SCHEMA_NAME)] = [
            {"project": self.project, "schema_name": aggregates.SCHEMA_NAME, "version": 1, "status": "published", "fields": aggregates.SCHEMA_FIELDS}
        ]
        self.engine.calculations[(self.project, cid0)] = [
            {
                "project": self.project,
                "calculation_id": cid0,
                "version": 1,
                "status": "published",
                "input_schema": aggregates.SCHEMA_NAME,
                "input_schema_version": 1,
                "needs_review": False,
                "definition": _independent_rust_serde_spec(with_limit),
            }
        ]

        # Running apply_bundle must create safe version 2 for cid0
        aggregates.apply_bundle(self.engine, self.project)
        calc_vers = self.engine.calculations.get((self.project, cid0), [])
        self.assertEqual(len(calc_vers), 2)
        v2 = next(v for v in calc_vers if v["version"] == 2)
        self.assertEqual(v2["status"], "published")
        self.assertEqual(v2["input_schema_version"], 1)

    def test_matching_v1_with_higher_incompatible_published_v2_pins_v1(self):
        """When matching published v1 and higher incompatible published v2 both exist, pin v1."""
        incompatible_fields = [
            {"path": "snapshot_id", "type": "string", "required": True},
            {"path": "incompatible_extra", "type": "string", "required": True},
        ]
        self.engine.schemas[(self.project, aggregates.SCHEMA_NAME)] = [
            {
                "project": self.project,
                "schema_name": aggregates.SCHEMA_NAME,
                "version": 1,
                "status": "published",
                "fields": aggregates.SCHEMA_FIELDS,
            },
            {
                "project": self.project,
                "schema_name": aggregates.SCHEMA_NAME,
                "version": 2,
                "status": "published",
                "fields": incompatible_fields,
            },
        ]
        # Run apply_bundle
        aggregates.apply_bundle(self.engine, self.project)

        # Schema must be pinned to version 1
        for spec in aggregates.METRICS:
            cid = spec["id"]
            calc_vers = self.engine.calculations.get((self.project, cid), [])
            self.assertEqual(calc_vers[0]["input_schema_version"], 1)

    def test_missing_v1_only_v2_fails_clearly_without_post(self):
        """If v1 is missing and only v2 exists, fails with RuntimeError and sends zero POSTs."""
        self.engine.schemas[(self.project, aggregates.SCHEMA_NAME)] = [
            {
                "project": self.project,
                "schema_name": aggregates.SCHEMA_NAME,
                "version": 2,
                "status": "published",
                "fields": aggregates.SCHEMA_FIELDS,
            }
        ]
        self.engine.call_log.clear()

        with self.assertRaises(RuntimeError) as ctx:
            aggregates.apply_bundle(self.engine, self.project)
        self.assertIn("pinned v1 is absent", str(ctx.exception))

        # Must send zero POST requests
        posts = [c for c in self.engine.call_log if c[0] == "POST"]
        self.assertEqual(posts, [], f"Expected zero POSTs when v1 is absent, but got {posts}")

    def test_wrong_pin_only_stale_draft_resaves_correct_input(self):
        """A draft calculation with wrong pin (input_schema_version != 1) is re-saved with selected pin 1."""
        self.engine.schemas[(self.project, aggregates.SCHEMA_NAME)] = [
            {"project": self.project, "schema_name": aggregates.SCHEMA_NAME, "version": 1, "status": "published", "fields": aggregates.SCHEMA_FIELDS}
        ]
        bundle = aggregates.build_bundle()
        cid0 = bundle["datasets"][0]["id"]
        # Seed draft with input_schema_version: 99 and needs_review: False
        self.engine.calculations[(self.project, cid0)] = [
            {
                "project": self.project,
                "calculation_id": cid0,
                "version": 1,
                "status": "draft",
                "input_schema": aggregates.SCHEMA_NAME,
                "input_schema_version": 99,
                "needs_review": False,
                "definition": _independent_rust_serde_spec(bundle["datasets"][0]["calculation"]),
            }
        ]

        aggregates.apply_bundle(self.engine, self.project)

        calc_vers = self.engine.calculations.get((self.project, cid0), [])
        self.assertEqual(len(calc_vers), 1)
        self.assertEqual(calc_vers[0]["status"], "published")
        self.assertEqual(calc_vers[0]["input_schema_version"], 1)
        self.assertFalse(calc_vers[0]["needs_review"])

    def test_review_flag_only_stale_draft_resaves_correct_input(self):
        """A draft calculation with needs_review=True is re-saved to clear review flag and bind pin 1."""
        self.engine.schemas[(self.project, aggregates.SCHEMA_NAME)] = [
            {"project": self.project, "schema_name": aggregates.SCHEMA_NAME, "version": 1, "status": "published", "fields": aggregates.SCHEMA_FIELDS}
        ]
        bundle = aggregates.build_bundle()
        cid0 = bundle["datasets"][0]["id"]
        # Seed draft with input_schema_version: 1 and needs_review: True
        self.engine.calculations[(self.project, cid0)] = [
            {
                "project": self.project,
                "calculation_id": cid0,
                "version": 1,
                "status": "draft",
                "input_schema": aggregates.SCHEMA_NAME,
                "input_schema_version": 1,
                "needs_review": True,
                "definition": _independent_rust_serde_spec(bundle["datasets"][0]["calculation"]),
            }
        ]

        aggregates.apply_bundle(self.engine, self.project)

        calc_vers = self.engine.calculations.get((self.project, cid0), [])
        self.assertEqual(len(calc_vers), 1)
        self.assertEqual(calc_vers[0]["status"], "published")
        self.assertEqual(calc_vers[0]["input_schema_version"], 1)
        self.assertFalse(calc_vers[0]["needs_review"])

    def test_reconciliation_with_preexisting_buggy_v2_draft(self):
        """If v1 is published and an unhandled v2 draft exists, reconcile to published v1."""
        self.engine.schemas[(self.project, aggregates.SCHEMA_NAME)] = [
            {"project": self.project, "schema_name": aggregates.SCHEMA_NAME, "version": 1, "status": "published", "fields": aggregates.SCHEMA_FIELDS},
            {"project": self.project, "schema_name": aggregates.SCHEMA_NAME, "version": 2, "status": "draft", "fields": aggregates.SCHEMA_FIELDS},
        ]
        bundle = aggregates.build_bundle()
        cid0 = bundle["datasets"][0]["id"]
        self.engine.calculations[(self.project, cid0)] = [
            {
                "project": self.project,
                "calculation_id": cid0,
                "version": 1,
                "status": "published",
                "input_schema": aggregates.SCHEMA_NAME,
                "input_schema_version": 1,
                "needs_review": False,
                "definition": _independent_rust_serde_spec(bundle["datasets"][0]["calculation"]),
            },
            {
                "project": self.project,
                "calculation_id": cid0,
                "version": 2,
                "status": "draft",
                "input_schema": aggregates.SCHEMA_NAME,
                "input_schema_version": 1,
                "needs_review": False,
                "definition": _independent_rust_serde_spec(bundle["datasets"][0]["calculation"]),
            },
        ]

        aggregates.apply_bundle(self.engine, self.project)

        ds = self.engine.datasets.get((self.project, aggregates.REPORT_ID, cid0))
        self.assertEqual(ds["calculation_version"], 1)


if __name__ == "__main__":
    unittest.main()
