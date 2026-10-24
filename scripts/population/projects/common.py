"""Helpers shared by the sample-data modules."""

from __future__ import annotations

import datetime as dt
import random

#: Fixed window of the sample data, so every run produces the same records.
FIRST_DAY = dt.date(2026, 9, 25)
DAYS = 30
TZ = dt.timezone(dt.timedelta(hours=7))


def t(en: str, pt: str, th: str) -> dict[str, str]:
    """Reports-owned text in the three UI languages."""
    return {"en": en, "pt-BR": pt, "th": th}


def field(path: str, type_: str, required: bool = True, description: str | None = None) -> dict:
    f = {"path": path, "type": type_, "required": required}
    if description:
        f["description"] = description
    return f


def out(name: str, label: dict, type_: str, role: str = "measure", unit: str | None = None, decimals: int | None = None) -> dict:
    o = {"name": name, "label": label, "type": type_, "role": role}
    if unit:
        o["unit"] = unit
    if decimals is not None:
        o["decimals"] = decimals
    return o


def days():
    for i in range(DAYS):
        yield FIRST_DAY + dt.timedelta(days=i)


def at(day: dt.date, rng: random.Random) -> str:
    """A random RFC 3339 time on that day (Asia/Bangkok offset)."""
    moment = dt.datetime.combine(day, dt.time(rng.randint(6, 23), rng.randint(0, 59), rng.randint(0, 59)), TZ)
    return moment.isoformat()


def weighted(rng: random.Random, options: dict):
    return rng.choices(list(options), weights=list(options.values()))[0]


SAMPLE_NOTE = t(
    "Generated sample data for demonstration. Not real usage.",
    "Dados de exemplo gerados para demonstração. Não é uso real.",
    "ข้อมูลตัวอย่างที่สร้างขึ้นเพื่อการสาธิต ไม่ใช่การใช้งานจริง",
)
