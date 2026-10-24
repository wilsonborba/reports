"""Writes the five selected Reports projects through the protected admin API.

Only Reports-owned fields are set: name, links, Domain UUID and order. The tagline,
description, categories and statistics come from domain_api through the engine's Domain
composition, so Reports keeps no copy that could go out of sync.

Usage: scripts/catalog/populate.sh [--dry-run]
"""

from __future__ import annotations

import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "population"))
from client import Engine  # noqa: E402

PROJECTS = [
    {"slug": "domain", "name": "Asodya", "website_url": "https://asodya.com",
     "repository_url": "https://github.com/wilsonborba/domain", "domain_project_id": "fc582b4a-9503-45b5-b0d3-9533be8ec9c7"},
    {"slug": "certifications", "name": "Certifications", "website_url": "https://certifications.asodya.com",
     "repository_url": "https://github.com/wilsonborba/certifications", "domain_project_id": "3f734b2e-c44a-413c-9395-1cd2e3c9b061"},
    {"slug": "cortex", "name": "Cortex", "website_url": "https://cortex.asodya.com",
     "repository_url": "https://github.com/wilsonborba/cortex", "domain_project_id": "4ef82613-e51e-42fa-9f3e-93809fdff54b"},
    {"slug": "autodroid", "name": "AutoDroid", "website_url": "https://github.com/wilsonborba/autodroid",
     "repository_url": "https://github.com/wilsonborba/autodroid", "domain_project_id": "55e5dd94-8854-4edb-8f08-3431b3a0eb4f"},
    {"slug": "fsm", "name": "FSM", "website_url": "https://github.com/wilsonborba/fsm",
     "repository_url": "https://github.com/wilsonborba/fsm", "domain_project_id": "203321df-c74d-4725-afdf-370d1d41a522"},
]


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    engine = Engine(dry_run=dry_run)
    print(f"Engine: {engine.base}")
    for order, p in enumerate(PROJECTS, start=1):
        body = {
            # A product name is the same in every language.
            "name": {"en": p["name"], "pt-BR": p["name"], "th": p["name"]},
            "website_url": p["website_url"],
            "repository_url": p["repository_url"],
            "domain_project_id": p["domain_project_id"],
            "sort_order": order,
        }
        engine.request("PUT", f"/projects/{p['slug']}/admin/project", body)
        print(f"  project {p['slug']}: saved")
    print(f"Done: {len(PROJECTS)} projects{' (dry run, nothing sent)' if dry_run else ''}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
