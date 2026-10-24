"""Asodya (domain) sample data. Fields of the `project_monthly_metrics` table in
domain_api/src/dal/migrations/versions/20260915_03_project_monthly_metrics.py."""

from __future__ import annotations

import datetime as dt
import random

from .common import TZ, field, out, t

PROJECT = "domain"

SCHEMA = {
    "schema_name": "project_monthly_metric",
    "description": "domain_api project_monthly_metrics: one metric of one catalog project in one month",
    "fields": [
        field("project_id", "string", description="domain_api project UUID"), field("period", "string", description="YYYY-MM"),
        field("metric_key", "string"), field("metric_value", "float"), field("created_at", "datetime"),
    ],
}

#: domain_api project UUIDs and slugs (the slugs label the charts).
DOMAIN_PROJECTS = {
    "4ef82613-e51e-42fa-9f3e-93809fdff54b": "cortex",
    "3f734b2e-c44a-413c-9395-1cd2e3c9b061": "certifications",
    "55e5dd94-8854-4edb-8f08-3431b3a0eb4f": "autodroid",
    "203321df-c74d-4725-afdf-370d1d41a522": "fsm",
    "fc582b4a-9503-45b5-b0d3-9533be8ec9c7": "asodya-home",
    "34f3ddb8-b613-497b-b60c-c1cf35e100ba": "hippocampus",
    "52c32ea7-ca52-4a09-a540-817a3722fd7f": "api-for-apps",
    "b2b8a2a2-58d3-4ace-8272-9b24b899a4cd": "domain-api",
}
PERIODS = ["2026-05", "2026-06", "2026-07", "2026-08", "2026-09", "2026-10"]
METRICS = ["commits", "stars", "open_issues", "contributors"]


def records(rng: random.Random) -> list[dict]:
    out_ = []
    for pid, slug in DOMAIN_PROJECTS.items():
        stars = rng.randint(0, 3)
        for period in PERIODS:
            year, month = map(int, period.split("-"))
            created = dt.datetime(year, month, 28, 2, 0, tzinfo=TZ).isoformat()
            stars += rng.randint(0, 2)
            values = {
                "commits": float(rng.randint(0, 60)), "stars": float(stars),
                "open_issues": float(rng.randint(0, 15)), "contributors": float(rng.choice([1, 1, 1, 2])),
            }
            for key in METRICS:
                out_.append({
                    "idempotency_key": f"domain-metric-{slug}-{period}-{key}",
                    "event_time": created,
                    "payload": {"project_id": pid, "period": period, "metric_key": key, "metric_value": values[key], "created_at": created},
                })
    return out_


PROJECT_LABELS = {"project_id": {pid: {"en": slug, "pt-BR": slug, "th": slug} for pid, slug in DOMAIN_PROJECTS.items()}}
PROJ = out("project_id", t("Project", "Projeto", "โปรเจกต์"), "string", role="dimension")
MONTH = out("period", t("Month", "Mês", "เดือน"), "string", role="dimension")
KEY_FILTER = {"field": "project_id", "label": t("Project", "Projeto", "โปรเจกต์"), "type": "category"}


def metric(key: str) -> list[dict]:
    return [{"field": "metric_key", "op": "eq", "value": key}]


CALCULATIONS = {
    "commits-per-month": {
        "title": t("Commits per Month", "Commits por Mês", "คอมมิตต่อเดือน"),
        "description": t("Commits of every catalog project, per month.", "Commits de todos os projetos do catálogo, por mês.", "คอมมิตของทุกโปรเจกต์ในแคตตาล็อก ต่อเดือน"),
        "source": "project_monthly_metric", "where": metric("commits"), "filters": [KEY_FILTER], "value_labels": PROJECT_LABELS, "warm": True,
        "stages": [{"group_by": ["period"], "measures": [{"name": "commits", "agg": "sum", "field": "metric_value"}]}],
        "sort": [{"field": "period"}],
        "fields": [MONTH, out("commits", t("Commits", "Commits", "คอมมิต"), "integer")],
    },
    "commits-by-project": {
        "title": t("Commits by Project", "Commits por Projeto", "คอมมิตตามโปรเจกต์"),
        "description": t("Commits of the last six months, per project.", "Commits dos últimos seis meses, por projeto.", "คอมมิตในหกเดือนล่าสุด ตามโปรเจกต์"),
        "source": "project_monthly_metric", "where": metric("commits"), "value_labels": PROJECT_LABELS,
        "stages": [{"group_by": ["project_id"], "measures": [{"name": "commits", "agg": "sum", "field": "metric_value"}]}],
        "sort": [{"field": "commits", "desc": True}],
        "fields": [PROJ, out("commits", t("Commits", "Commits", "คอมมิต"), "integer")],
    },
    "active-projects-per-month": {
        "title": t("Active Projects", "Projetos Ativos", "โปรเจกต์ที่ใช้งาน"),
        "description": t("Projects with at least one commit, per month.", "Projetos com pelo menos um commit, por mês.", "โปรเจกต์ที่มีคอมมิตอย่างน้อยหนึ่งครั้ง ต่อเดือน"),
        "source": "project_monthly_metric",
        "where": metric("commits") + [{"field": "metric_value", "op": "gt", "value": 0}],
        "stages": [{"group_by": ["period"], "measures": [{"name": "projects", "agg": "count_distinct", "field": "project_id"}]}],
        "sort": [{"field": "period"}],
        "fields": [MONTH, out("projects", t("Projects", "Projetos", "โปรเจกต์"), "integer")],
    },
    "open-issues-by-project": {
        "title": t("Open Issues", "Issues Abertas", "อิชชูที่เปิดอยู่"),
        "description": t("Open issues in the latest month, per project.", "Issues abertas no último mês, por projeto.", "อิชชูที่เปิดอยู่ในเดือนล่าสุด ตามโปรเจกต์"),
        "source": "project_monthly_metric", "value_labels": PROJECT_LABELS,
        "where": metric("open_issues") + [{"field": "period", "op": "eq", "value": PERIODS[-1]}],
        "stages": [{"group_by": ["project_id"], "measures": [{"name": "open_issues", "agg": "max", "field": "metric_value"}]}],
        "sort": [{"field": "open_issues", "desc": True}],
        "fields": [PROJ, out("open_issues", t("Open issues", "Issues abertas", "อิชชูที่เปิดอยู่"), "integer")],
    },
    "stars-per-month": {
        "title": t("Stars per Month", "Estrelas por Mês", "ดาวต่อเดือน"),
        "description": t("GitHub stars of all catalog projects, per month.", "Estrelas no GitHub de todos os projetos, por mês.", "ดาว GitHub ของทุกโปรเจกต์ ต่อเดือน"),
        "source": "project_monthly_metric", "where": metric("stars"), "filters": [KEY_FILTER], "value_labels": PROJECT_LABELS,
        "stages": [{"group_by": ["period"], "measures": [{"name": "stars", "agg": "sum", "field": "metric_value"}]}],
        "sort": [{"field": "period"}],
        "fields": [MONTH, out("stars", t("Stars", "Estrelas", "ดาว"), "integer")],
    },
    "contributors-by-project": {
        "title": t("Contributors", "Contribuidores", "ผู้ร่วมพัฒนา"),
        "description": t("Highest contributor count of each project.", "Maior número de contribuidores de cada projeto.", "จำนวนผู้ร่วมพัฒนาสูงสุดของแต่ละโปรเจกต์"),
        "source": "project_monthly_metric", "where": metric("contributors"), "value_labels": PROJECT_LABELS,
        "stages": [{"group_by": ["project_id"], "measures": [{"name": "contributors", "agg": "max", "field": "metric_value"}]}],
        "sort": [{"field": "contributors", "desc": True}],
        "fields": [PROJ, out("contributors", t("Contributors", "Contribuidores", "ผู้ร่วมพัฒนา"), "integer")],
    },
}

REPORTS = [
    {"slug": "repository-activity", "title": t("Repository Activity", "Atividade dos Repositórios", "กิจกรรมของรีโพสิทอรี"),
     "description": t("Commits and active projects of the Asodya catalog.", "Commits e projetos ativos do catálogo Asodya.", "คอมมิตและโปรเจกต์ที่ใช้งานในแคตตาล็อก Asodya"),
     "tags": ["catalog"], "period_field": "period", "cards": ["commits-per-month", "commits-by-project", "active-projects-per-month"]},
    {"slug": "repository-health", "title": t("Repository Health", "Saúde dos Repositórios", "สุขภาพของรีโพสิทอรี"),
     "description": t("Open issues, stars and contributors per project.", "Issues abertas, estrelas e contribuidores por projeto.", "อิชชูที่เปิดอยู่ ดาว และผู้ร่วมพัฒนาตามโปรเจกต์"),
     "tags": ["catalog"], "period_field": "period", "cards": ["open-issues-by-project", "stars-per-month", "contributors-by-project"]},
]
