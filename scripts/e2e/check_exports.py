#!/usr/bin/env python3
"""Structural checks of the export files that ui/test/real_api_export_test.dart writes.

PDF: the %PDF header, an %%EOF marker and at least one page object.
Markdown: UTF-8, a level 1 title and the project line.
CSV ZIP: a valid archive with index.csv and at least one card CSV with a header row.
Prints one line per file and a SHA-256 checksum; exits 1 on the first broken file.

Usage: scripts/e2e/check_exports.py <folder> [project/report ...]
"""

from __future__ import annotations

import csv
import hashlib
import io
import pathlib
import sys
import zipfile


def check_pdf(data: bytes) -> str | None:
    if not data.startswith(b"%PDF-"):
        return "no %PDF header"
    if b"%%EOF" not in data[-2048:]:
        return "no %%EOF marker"
    if b"/Type /Page" not in data and b"/Type/Page" not in data:
        return "no page object"
    return None


def check_md(data: bytes) -> str | None:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return "not UTF-8"
    if not text.startswith("# "):
        return "no level 1 title"
    if "\n- " not in text:
        return "no fact list (project, period, language)"
    return None


def check_zip(data: bytes) -> str | None:
    try:
        z = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        return "not a ZIP archive"
    if z.testzip() is not None:
        return "a member fails its CRC"
    names = z.namelist()
    if "index.csv" not in names:
        return f"no index.csv in {names}"
    cards = [n for n in names if n.endswith(".csv") and n != "index.csv"]
    if not cards:
        return "no card CSV"
    for n in ["index.csv", *cards]:
        rows = list(csv.reader(io.StringIO(z.read(n).decode("utf-8-sig"))))
        if not rows or not rows[0]:
            return f"{n} has no header row"
    return None


CHECKS = {".pdf": check_pdf, ".md": check_md, ".zip": check_zip}


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    folder = pathlib.Path(sys.argv[1])
    wanted = [r.replace("/", "_") for r in sys.argv[2:]]
    files = sorted(f for f in folder.iterdir() if f.suffix in CHECKS and (not wanted or any(f.name.startswith(w + "_") for w in wanted)))
    if not files:
        print(f"No export files in {folder}.")
        return 1
    seen = {f.suffix for f in files}
    failed = False
    for f in files:
        data = f.read_bytes()
        problem = CHECKS[f.suffix](data)
        print(f"[{'ok' if problem is None else 'FAIL'}] {f.name} {len(data)} bytes sha256={hashlib.sha256(data).hexdigest()[:16]}{'' if problem is None else ': ' + problem}")
        failed |= problem is not None
    missing = set(CHECKS) - seen
    if missing:
        print(f"Missing formats: {sorted(missing)}")
        failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
