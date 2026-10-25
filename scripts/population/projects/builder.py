"""Sample calculations built from named dimensions and measures.

A project declares its dimensions and measures once, with labels in the three UI languages;
each chart names the ones it uses. Titles and descriptions come from those labels, so the 64
charts of a project stay consistent and complete in en, pt-BR and th.

A report has 4 sections of 4 charts. The frontend groups cards into sections of at most 4 in
the order of the API, and the populate script sends that order as the report `card_order`.
"""

from __future__ import annotations

from .common import out, t

LANGS = ("en", "pt-BR", "th")
WHOLE_PERIOD = t("over the whole period", "em todo o período", "ตลอดช่วงเวลา")


def dim(name: str, label: dict, *, field: str | None = None, unit: str | None = None, per: dict | None = None) -> dict:
    """A grouping. With `unit` (day or week) it buckets the time `field` and `per` names the unit."""
    return {"name": name, "label": label, "field": field, "unit": unit, "per": per}


def measure(name: str, label: dict, agg: str | None = None, field: str | None = None, *, type_: str = "integer",
            unit: str | None = None, decimals: int | None = None, where: list | None = None, expr: str | None = None,
            window: dict | None = None, about: dict | None = None, needs: tuple = ()) -> dict:
    """A value. `agg` aggregates rows, `expr` derives from other measures (named in `needs`,
    computed but not shown), `window` is a moving aggregate over the time dimension."""
    return {"name": name, "label": label, "agg": agg, "field": field, "type": type_, "unit": unit, "decimals": decimals,
            "where": where, "expr": expr, "window": window, "about": about or label, "needs": needs}


def _lower(text: str) -> str:
    """Lowercases the first letter of an en or pt-BR label, keeping acronyms (PDF, LLM)."""
    return text[:1].lower() + text[1:] if len(text) > 1 and text[1].islower() else text


def _join(items: list[str], lang: str) -> str:
    word = {"en": " and ", "pt-BR": " e ", "th": "และ"}[lang]
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + word + items[-1]


def _caps(text: str) -> str:
    """Title case of an en label: every word capitalized, acronyms and short words kept."""
    small = {"a", "an", "and", "by", "of", "per", "the", "to", "in", "on"}
    return " ".join(w if w.lower() in small and i else w[:1].upper() + w[1:] for i, w in enumerate(text.split(" ")))


SUMMARY = t("Summary", "Resumo", "สรุป")


def _title(measures: list, time: list, cats: list) -> dict:
    """Measure names, then the grouping. The engine allows one name per title (no "and"), so
    two names join with "×" and three or more measures read "Summary". Share and moving
    columns stay out of the title."""
    named = [m for m in measures if not m["window"] and "sum_" not in (m["expr"] or "")]
    out_ = {}
    for lang in LANGS:
        fix = _caps if lang == "en" else (lambda s: s)
        m = SUMMARY[lang] if len(named) > 2 else " × ".join(fix(x["label"][lang]) for x in named)
        per = fix(time[0]["per"][lang]) if time else None
        names = " × ".join(fix(c["label"][lang]) for c in cats)
        if lang == "th":
            s = m + (f"ต่อ{per}" if per else "") + (f"ตาม{names}" if names else "")
        else:
            word_per, word_by = ("per", "by") if lang == "en" else ("por", "por")
            s = m
            if per:
                s += f" {word_per} {per}"
            if names:
                s += (" e " if lang == "pt-BR" and per else f" {word_by} ") + names
        out_[lang] = s
    return out_


def _description(main: dict, extra: list, time: list, cats: list) -> dict:
    out_ = {}
    for lang in LANGS:
        about = main["about"][lang]
        lc = (lambda s: s) if lang == "th" else _lower
        per = lc(time[0]["per"][lang]) if time else None
        names = [lc(c["label"][lang]) for c in cats]
        if lang == "th":
            group = (f" ต่อ{per}" if per else "") + (f" ตาม{_join(names, lang)}" if names else "")
        elif lang == "en":
            group = (f" per {per}" if per else "") + ((" and " if per else " by ") + _join(names, lang) if names else "")
        else:
            group = (f" por {per}" if per else "") + ((" e " if per else " por ") + _join(names, lang) if names else "")
        text = about + (group or " " + WHOLE_PERIOD[lang])
        if extra:
            others = _join([lc(m["label"][lang]) for m in extra], lang)
            text += {"en": f", with {others}", "pt-BR": f", com {others}", "th": f" พร้อม{others}"}[lang]
        out_[lang] = text + ("" if lang == "th" else ".")
    return out_


def chart(source: str, measures: list, dims: tuple | list = (), *, where: list | None = None, filters: list | None = None,
          value_labels: dict | None = None, sort: list | None = None, limit: int | None = None, warm: bool = False,
          title: dict | None = None, description: dict | None = None) -> dict:
    """One calculation definition. Sort: time ascending, else the first measure descending."""
    time = [d for d in dims if d["unit"]]
    cats = [d for d in dims if not d["unit"]]
    hidden = [n for m in measures for n in m["needs"]]
    stage: dict = {"group_by": [d["name"] for d in dims], "measures": []}
    for m in [*hidden, *measures]:
        if m["agg"]:
            spec = {"name": m["name"], "agg": m["agg"]}
            if m["field"]:
                spec["field"] = m["field"]
            if m["where"]:
                spec["where"] = m["where"]
            if spec not in stage["measures"]:
                stage["measures"].append(spec)
    derived = [{"name": m["name"], "expr": m["expr"]} for m in measures if m["expr"]]
    windows = [{"name": m["name"], **m["window"], "order_by": time[0]["name"]} for m in measures if m["window"]]
    if derived:
        stage["derived"] = derived
    if windows:
        stage["windows"] = windows
    spec = {
        "title": title or _title(measures, time, cats),
        "description": description or _description(measures[0], measures[1:], time, cats),
        "source": source,
        "stages": [stage],
        "sort": sort or ([{"field": time[0]["name"]}] if time else ([{"field": measures[0]["name"], "desc": True}] if dims else [])),
        "fields": [
            *[out(d["name"], d["label"], "date" if d["unit"] else "string", role="dimension") for d in dims],
            *[out(m["name"], m["label"], m["type"], unit=m["unit"], decimals=m["decimals"]) for m in measures],
        ],
    }
    if time:
        spec["buckets"] = [{"field": d["field"], "unit": d["unit"], "name": d["name"]} for d in time]
    if where:
        spec["where"] = where
    if filters:
        spec["filters"] = filters
    if value_labels:
        spec["value_labels"] = value_labels
    if limit:
        spec["limit"] = limit
    if warm:
        spec["warm"] = True
    if not spec["sort"]:
        del spec["sort"]
    return spec


def build(reports: list[dict]) -> tuple[dict, list[dict]]:
    """CALCULATIONS and REPORTS of a project from reports with `sections` of (card id, chart)."""
    calculations: dict = {}
    out_reports = []
    for r in reports:
        assert len(r["sections"]) == 4 and all(len(s) == 4 for s in r["sections"]), r["slug"]
        cards = []
        for section in r["sections"]:
            for card_id, spec in section:
                assert card_id not in calculations, card_id
                calculations[card_id] = spec
                cards.append(card_id)
        out_reports.append({k: v for k, v in r.items() if k != "sections"} | {"cards": cards})
    return calculations, out_reports
