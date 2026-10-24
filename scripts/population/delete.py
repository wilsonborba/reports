"""Removes the sample data that populate.py wrote, and nothing else.

The engine deletes only entities owned by the fixture manifest `sample-v1-<project>`.
Manually edited entities, real records and the project catalog rows stay.

Usage: scripts/delete_fake_data.sh [--project <slug>] [--dry-run]
"""

from __future__ import annotations

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from client import Engine
from populate import MODULES, manifest_of


def main() -> int:
    parser = argparse.ArgumentParser(description="Remove the sample data of the launch projects")
    parser.add_argument("--project", choices=sorted(MODULES), help="only this project")
    parser.add_argument("--dry-run", action="store_true", help="print what would be called, send nothing")
    args = parser.parse_args()
    projects = [args.project] if args.project else list(MODULES)
    engine = Engine(dry_run=args.dry_run)
    for project in projects:
        result = engine.request("DELETE", f"/admin/fixtures/{manifest_of(project)}", fixture=False)
        if args.dry_run:
            continue
        print(f"{project}: removed {result['datasets']} cards, {result['reports']} reports, {result['calculations']} calculations, "
              f"{result['schemas']} schemas, {result['records']} records")
        for kept in result.get("kept", []):
            print(f"  kept {kept}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
