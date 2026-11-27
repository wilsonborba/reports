#!/usr/bin/env python3
"""Inert fake-API regression tests for Reports catalog apply_bundle repeatability and recovery.

Exercises:
1. Fresh project initialization (schema v1, report, calculations v1, dataset cards).
2. Second run idempotence/repeatability (no 409 conflict, no redundant v2 drafts, no duplicate publish).
3. Interrupted partial run recovery (matches existing drafts without bumping versions unnecessarily).
4. Bug-state recovery (v1 published and leftover unhandled v2 draft).
5. Changed definition evolution (creates draft v2, publishes v2, wires v2 to dataset card).

Zero external network egress, zero real engine/database mutations.
"""

from __future__ import annotations

import copy
import sys
import pathlib
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import aggregates  # noqa: E402


class FakeEngineError(RuntimeError):
    def __init__(self, status: int, method: str, path: str, body: str):
        super().__init__(f"{method} {path} returned {status}: {body}")
        self.status = status


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
            # update existing draft or append
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
            draft = {
                "project": project,
                "calculation_id": calc_id,
                "version": version,
                "status": "draft",
                "definition": copy.deepcopy(body.get("definition", {})),
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
        """Initial run on empty catalog publishes schema v1 and 7 calculation v1s."""
        aggregates.apply_bundle(self.engine, self.project)

        # Check schema
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

            # Check dataset wire
            ds = self.engine.datasets.get((self.project, aggregates.REPORT_ID, calc_id))
            self.assertIsNotNone(ds)
            self.assertEqual(ds["calculation_version"], 1)
            self.assertEqual(ds["visibility"], "public")

    def test_second_run_repeatability(self):
        """Second run reconciles existing published versions without 409 or v2 creation."""
        # Initial run
        aggregates.apply_bundle(self.engine, self.project)
        calls_run1 = len(self.engine.call_log)

        # Clear call log to trace only run 2
        self.engine.call_log.clear()

        # Second run must succeed idempotently
        aggregates.apply_bundle(self.engine, self.project)

        # Ensure no new versions were created
        schema_vers = self.engine.schemas.get((self.project, aggregates.SCHEMA_NAME), [])
        self.assertEqual(len(schema_vers), 1, "Schema should still have exactly 1 version")
        self.assertEqual(schema_vers[0]["version"], 1)

        for spec in aggregates.METRICS:
            calc_id = spec["id"]
            calc_vers = self.engine.calculations.get((self.project, calc_id), [])
            self.assertEqual(len(calc_vers), 1, f"Calculation {calc_id} should have exactly 1 version")
            self.assertEqual(calc_vers[0]["version"], 1)

            # Ensure dataset wiring intact
            ds = self.engine.datasets.get((self.project, aggregates.REPORT_ID, calc_id))
            self.assertEqual(ds["calculation_version"], 1)

        # Ensure zero draft posts and zero publish posts occurred in run 2
        schema_posts = [c for c in self.engine.call_log if "schemas" in c[1] and c[0] == "POST"]
        calc_posts = [c for c in self.engine.call_log if "calculations" in c[1] and c[0] == "POST"]
        self.assertEqual(schema_posts, [], f"Expected no schema POSTs on run 2: {schema_posts}")
        self.assertEqual(calc_posts, [], f"Expected no calculation POSTs on run 2: {calc_posts}")

    def test_interrupted_run_recovery(self):
        """Interrupted run with existing draft publishes the draft without bumping version."""
        # Setup: Schema published v1, calculations 0..2 published v1, calculation 3 has draft v1 (unbudgeted crash), 4..6 missing.
        self.engine.schemas[(self.project, aggregates.SCHEMA_NAME)] = [
            {"project": self.project, "schema_name": aggregates.SCHEMA_NAME, "version": 1, "status": "published", "fields": aggregates.SCHEMA_FIELDS}
        ]
        bundle = aggregates.build_bundle()
        # Calcs 0..2 published
        for ds in bundle["datasets"][:3]:
            cid = ds["id"]
            self.engine.calculations[(self.project, cid)] = [
                {"project": self.project, "calculation_id": cid, "version": 1, "status": "published", "definition": ds["calculation"]}
            ]
        # Calc 3 draft
        ds3 = bundle["datasets"][3]
        cid3 = ds3["id"]
        self.engine.calculations[(self.project, cid3)] = [
            {"project": self.project, "calculation_id": cid3, "version": 1, "status": "draft", "definition": ds3["calculation"]}
        ]

        # Run apply_bundle: should recover cleanly
        aggregates.apply_bundle(self.engine, self.project)

        # Calc 3 draft should now be published as v1 (not bumped to v2)
        calc3_vers = self.engine.calculations.get((self.project, cid3), [])
        self.assertEqual(len(calc3_vers), 1)
        self.assertEqual(calc3_vers[0]["version"], 1)
        self.assertEqual(calc3_vers[0]["status"], "published")

        # All 7 metrics should now have 1 published version
        for spec in aggregates.METRICS:
            cid = spec["id"]
            calc_vers = self.engine.calculations.get((self.project, cid), [])
            self.assertEqual(len(calc_vers), 1)
            self.assertEqual(calc_vers[0]["status"], "published")

    def test_reconciliation_with_preexisting_buggy_v2_draft(self):
        """If v1 is published and an unhandled v2 draft exists from earlier bug, reconcile to published v1."""
        # Schema has published v1 AND draft v2
        self.engine.schemas[(self.project, aggregates.SCHEMA_NAME)] = [
            {"project": self.project, "schema_name": aggregates.SCHEMA_NAME, "version": 1, "status": "published", "fields": aggregates.SCHEMA_FIELDS},
            {"project": self.project, "schema_name": aggregates.SCHEMA_NAME, "version": 2, "status": "draft", "fields": aggregates.SCHEMA_FIELDS},
        ]
        # First calculation has published v1 AND draft v2
        bundle = aggregates.build_bundle()
        cid0 = bundle["datasets"][0]["id"]
        self.engine.calculations[(self.project, cid0)] = [
            {"project": self.project, "calculation_id": cid0, "version": 1, "status": "published", "definition": bundle["datasets"][0]["calculation"]},
            {"project": self.project, "calculation_id": cid0, "version": 2, "status": "draft", "definition": bundle["datasets"][0]["calculation"]},
        ]

        # Run apply_bundle
        aggregates.apply_bundle(self.engine, self.project)

        # Dataset for cid0 must bind to reconciled published version 1
        ds = self.engine.datasets.get((self.project, aggregates.REPORT_ID, cid0))
        self.assertEqual(ds["calculation_version"], 1)

    def test_changed_definition_evolution(self):
        """If calculation definition has changed, safe evolution creates and publishes v2."""
        bundle = aggregates.build_bundle()
        cid0 = bundle["datasets"][0]["id"]
        # Old definition in v1
        old_def = copy.deepcopy(bundle["datasets"][0]["calculation"])
        old_def["title"] = {"en": "Old Title"}
        self.engine.calculations[(self.project, cid0)] = [
            {"project": self.project, "calculation_id": cid0, "version": 1, "status": "published", "definition": old_def}
        ]

        # Run apply_bundle
        aggregates.apply_bundle(self.engine, self.project)

        # Calculation cid0 should now have version 2 published with new definition
        calc_vers = self.engine.calculations.get((self.project, cid0), [])
        self.assertEqual(len(calc_vers), 2)
        v2 = next(v for v in calc_vers if v["version"] == 2)
        self.assertEqual(v2["status"], "published")

        # Dataset card must point to version 2
        ds = self.engine.datasets.get((self.project, aggregates.REPORT_ID, cid0))
        self.assertEqual(ds["calculation_version"], 2)


if __name__ == "__main__":
    unittest.main()
