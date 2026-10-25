"""Asodya (domain) sample data. Fields of the `project_monthly_metrics` table in
domain_api/src/dal/migrations/versions/20260915_03_project_monthly_metrics.py."""

from __future__ import annotations

import datetime as dt
import random

from .builder import build, chart, dim, measure
from .common import TZ, field, t

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
METRICS = ["commits", "stars", "open_issues", "contributors", "forks", "open_pull_requests", "watchers"]


def records(rng: random.Random) -> list[dict]:
    out_ = []
    for pid, slug in DOMAIN_PROJECTS.items():
        stars = rng.randint(0, 3)
        forks = rng.randint(0, 1)
        watchers = rng.randint(0, 2)
        for period in PERIODS:
            year, month = map(int, period.split("-"))
            created = dt.datetime(year, month, 28, 2, 0, tzinfo=TZ).isoformat()
            stars += rng.randint(0, 2)
            values = {
                "commits": float(rng.randint(0, 60)), "stars": float(stars),
                "open_issues": float(rng.randint(0, 15)), "contributors": float(rng.choice([1, 1, 1, 2])),
            }
            forks += rng.choice([0, 0, 1])
            watchers += rng.choice([0, 0, 0, 1])
            values |= {"forks": float(forks), "open_pull_requests": float(rng.randint(0, 4)), "watchers": float(watchers)}
            for key in METRICS:
                out_.append({
                    "idempotency_key": f"domain-metric-{slug}-{period}-{key}",
                    "event_time": created,
                    "payload": {"project_id": pid, "period": period, "metric_key": key, "metric_value": values[key], "created_at": created},
                })
    return out_


SRC = "project_monthly_metric"
PROJECT_LABELS = {"project_id": {pid: {"en": slug, "pt-BR": slug, "th": slug} for pid, slug in DOMAIN_PROJECTS.items()}}
VL = PROJECT_LABELS
PROJECT_FILTER = {"field": "project_id", "label": t("Project", "Projeto", "โปรเจกต์"), "type": "category"}
F = [PROJECT_FILTER]
LATEST = [{"field": "period", "op": "eq", "value": PERIODS[-1]}]


def metric(key: str, *more) -> list[dict]:
    return [{"field": "metric_key", "op": "eq", "value": key}, *more]


MONTH = dim("month", t("Month", "Mês", "เดือน"), field="created_at", unit="day", per=t("Month", "Mês", "เดือน"))
PROJ = dim("project_id", t("Project", "Projeto", "โปรเจกต์"))
METRIC = dim("metric_key", t("Metric", "Métrica", "ตัวชี้วัด"))


def sums(name, label, key, about=None):
    return measure(name, label, "sum", "metric_value", where=metric(key), about=about)


def peak(name, label, key, about=None):
    return measure(name, label, "max", "metric_value", where=metric(key), about=about)


def mean(name, label, key, about=None):
    return measure(name, label, "avg", "metric_value", where=metric(key), type_="float", decimals=1, about=about)


COMMITS = sums("commits", t("Commits", "Commits", "คอมมิต"), "commits", t("Commits of the catalog projects", "Commits dos projetos do catálogo", "คอมมิตของโปรเจกต์ในแคตตาล็อก"))
MEAN_COMMITS = mean("mean_commits", t("Mean monthly commits", "Média mensal de commits", "คอมมิตเฉลี่ยต่อเดือน"), "commits")
MAX_COMMITS = peak("max_commits", t("Busiest month", "Mês mais ativo", "เดือนที่มีคอมมิตมากที่สุด"), "commits",
                   t("Highest monthly commits", "Maior número mensal de commits", "คอมมิตสูงสุดในหนึ่งเดือน"))
MIN_COMMITS = measure("min_commits", t("Quietest month", "Mês mais calmo", "เดือนที่มีคอมมิตน้อยที่สุด"), "min", "metric_value", where=metric("commits"),
                      about=t("Lowest monthly commits", "Menor número mensal de commits", "คอมมิตต่ำสุดในหนึ่งเดือน"))
STARS = sums("stars", t("Stars", "Estrelas", "ดาว"), "stars", t("GitHub stars", "Estrelas no GitHub", "ดาว GitHub"))
PEAK_STARS = peak("peak_stars", t("Stars", "Estrelas", "ดาว"), "stars", t("Highest GitHub star count", "Maior número de estrelas no GitHub", "จำนวนดาว GitHub สูงสุด"))
ISSUES = sums("open_issues", t("Open issues", "Issues abertas", "อิชชูที่เปิดอยู่"), "open_issues")
PEAK_ISSUES = peak("peak_issues", t("Open issues", "Issues abertas", "อิชชูที่เปิดอยู่"), "open_issues", t("Highest open issue count", "Maior número de issues abertas", "จำนวนอิชชูที่เปิดสูงสุด"))
MEAN_ISSUES = mean("mean_issues", t("Mean open issues", "Média de issues abertas", "อิชชูที่เปิดเฉลี่ย"), "open_issues")
CONTRIB = sums("contributors", t("Contributors", "Contribuidores", "ผู้ร่วมพัฒนา"), "contributors")
PEAK_CONTRIB = peak("peak_contributors", t("Contributors", "Contribuidores", "ผู้ร่วมพัฒนา"), "contributors", t("Highest contributor count", "Maior número de contribuidores", "จำนวนผู้ร่วมพัฒนาสูงสุด"))
MEAN_CONTRIB = mean("mean_contributors", t("Mean contributors", "Média de contribuidores", "ผู้ร่วมพัฒนาเฉลี่ย"), "contributors")
FORKS = sums("forks", t("Forks", "Forks", "ฟอร์ก"), "forks")
PEAK_FORKS = peak("peak_forks", t("Forks", "Forks", "ฟอร์ก"), "forks", t("Highest fork count", "Maior número de forks", "จำนวนฟอร์กสูงสุด"))
PRS = sums("open_prs", t("Open pull requests", "Pull requests abertos", "พูลรีเควสต์ที่เปิดอยู่"), "open_pull_requests")
PEAK_PRS = peak("peak_prs", t("Open pull requests", "Pull requests abertos", "พูลรีเควสต์ที่เปิดอยู่"), "open_pull_requests",
                t("Highest open pull request count", "Maior número de pull requests abertos", "จำนวนพูลรีเควสต์ที่เปิดสูงสุด"))
MEAN_PRS = mean("mean_prs", t("Mean open pull requests", "Média de pull requests abertos", "พูลรีเควสต์ที่เปิดเฉลี่ย"), "open_pull_requests")
WATCHERS = sums("watchers", t("Watchers", "Observadores", "ผู้ติดตาม"), "watchers")
PEAK_WATCHERS = peak("peak_watchers", t("Watchers", "Observadores", "ผู้ติดตาม"), "watchers", t("Highest watcher count", "Maior número de observadores", "จำนวนผู้ติดตามสูงสุด"))
ACTIVE = measure("active_projects", t("Active projects", "Projetos ativos", "โปรเจกต์ที่ใช้งาน"), "count_distinct", "project_id",
                 about=t("Projects with at least one commit", "Projetos com pelo menos um commit", "โปรเจกต์ที่มีคอมมิตอย่างน้อยหนึ่งครั้ง"))
ACTIVE_WHERE = metric("commits", {"field": "metric_value", "op": "gt", "value": 0})
_ACOMMITS = measure("all_commits", t("Commits", "Commits", "คอมมิต"), "sum", "metric_value", where=metric("commits"))
_APROJECTS = measure("projects_seen", t("Projects", "Projetos", "โปรเจกต์"), "count_distinct", "project_id")
PER_ACTIVE = measure("commits_per_project", t("Commits per project", "Commits por projeto", "คอมมิตต่อโปรเจกต์"), expr="all_commits / projects_seen",
                     type_="float", decimals=1, needs=(_ACOMMITS, _APROJECTS), about=t("Mean commits per catalog project", "Média de commits por projeto do catálogo", "คอมมิตเฉลี่ยต่อโปรเจกต์ในแคตตาล็อก"))
_ICOMMITS = measure("c_sum", t("Commits", "Commits", "คอมมิต"), "sum", "metric_value", where=metric("commits"))
_IISSUES = measure("i_sum", t("Open issues", "Issues abertas", "อิชชูที่เปิดอยู่"), "sum", "metric_value", where=metric("open_issues"))
COMMITS_PER_ISSUE = measure("commits_per_issue", t("Commits per open issue", "Commits por issue aberta", "คอมมิตต่ออิชชูที่เปิด"), expr="c_sum / i_sum",
                            type_="float", decimals=2, needs=(_ICOMMITS, _IISSUES), about=t("Commits over open issues", "Commits sobre issues abertas", "คอมมิตเทียบกับอิชชูที่เปิด"))
COMMIT_SHARE = measure("commit_share", t("Share", "Participação", "สัดส่วน"), expr="commits / sum_commits * 100", type_="percent", decimals=1)
STAR_SHARE = measure("star_share", t("Share", "Participação", "สัดส่วน"), expr="peak_stars / sum_peak_stars * 100", type_="percent", decimals=1)
ISSUE_SHARE = measure("issue_share", t("Share", "Participação", "สัดส่วน"), expr="peak_issues / sum_peak_issues * 100", type_="percent", decimals=1)
FORK_SHARE = measure("fork_share", t("Share", "Participação", "สัดส่วน"), expr="peak_forks / sum_peak_forks * 100", type_="percent", decimals=1)
RECORDS = measure("records", t("Metric records", "Registros de métricas", "บันทึกตัวชี้วัด"), "count",
                  about=t("Monthly metric records", "Registros mensais de métricas", "บันทึกตัวชี้วัดรายเดือน"))
VALUE = measure("value", t("Total value", "Valor total", "ค่ารวม"), "sum", "metric_value", type_="float", decimals=0)
MEAN_VALUE = measure("mean_value", t("Mean value", "Valor médio", "ค่าเฉลี่ย"), "avg", "metric_value", type_="float", decimals=1)
MAX_VALUE = measure("max_value", t("Highest value", "Maior valor", "ค่าสูงสุด"), "max", "metric_value", type_="float", decimals=0)
TRACKED = measure("tracked", t("Projects tracked", "Projetos acompanhados", "โปรเจกต์ที่ติดตาม"), "count_distinct", "project_id",
                  about=t("Catalog projects with metrics", "Projetos do catálogo com métricas", "โปรเจกต์ในแคตตาล็อกที่มีตัวชี้วัด"))
METRICS_SEEN = measure("metrics_seen", t("Metrics tracked", "Métricas acompanhadas", "ตัวชี้วัดที่ติดตาม"), "count_distinct", "metric_key",
                       about=t("Distinct metric keys", "Chaves de métrica distintas", "คีย์ตัวชี้วัดที่ไม่ซ้ำ"))


def c(measures, dims=(), **kw):
    return chart(SRC, measures, dims, filters=kw.pop("filters", F), value_labels=VL, **kw)


CALCULATIONS, REPORTS = build([
    {"slug": "repository-activity", "title": t("Repository Activity", "Atividade dos Repositórios", "กิจกรรมของรีโพสิทอรี"),
     "description": t("Commits, active projects, pull requests and forks of the Asodya catalog.", "Commits, projetos ativos, pull requests e forks do catálogo Asodya.", "คอมมิต โปรเจกต์ที่ใช้งาน พูลรีเควสต์ และฟอร์กของแคตตาล็อก Asodya"),
     "tags": ["catalog"], "period_field": "created_at",
     "sections": [
         [("total-commits", c([COMMITS], warm=True)), ("commits-per-month", c([COMMITS], [MONTH], warm=True)),
          ("commits-by-project", c([COMMITS], [PROJ])), ("active-projects", c([ACTIVE], where=ACTIVE_WHERE))],
         [("active-projects-per-month", c([ACTIVE], [MONTH], where=ACTIVE_WHERE)), ("commits-per-project", c([PER_ACTIVE])),
          ("commits-per-month-by-project", c([COMMITS], [MONTH, PROJ])), ("mean-commits-by-project", c([MEAN_COMMITS], [PROJ]))],
         [("mean-open-prs", c([MEAN_PRS])), ("open-prs-per-month", c([PRS], [MONTH])),
          ("open-prs-by-project", c([PEAK_PRS], [PROJ])), ("open-prs-per-month-by-project", c([PRS], [MONTH, PROJ]))],
         [("highest-forks", c([PEAK_FORKS])), ("forks-per-month", c([FORKS], [MONTH])),
          ("forks-by-project", c([PEAK_FORKS], [PROJ])), ("activity-by-project", c([COMMITS, PEAK_STARS, PEAK_FORKS, PEAK_ISSUES], [PROJ]))],
     ]},
    {"slug": "repository-health", "title": t("Repository Health", "Saúde dos Repositórios", "สุขภาพของรีโพสิทอรี"),
     "description": t("Open issues, stars, contributors and watchers per project and month.", "Issues abertas, estrelas, contribuidores e observadores por projeto e mês.", "อิชชูที่เปิด ดาว ผู้ร่วมพัฒนา และผู้ติดตาม ตามโปรเจกต์และเดือน"),
     "tags": ["catalog", "health"], "period_field": "created_at",
     "access": {"cards": {"stars-per-month": "signed_in", "contributors-by-project": "signed_in", "health-by-project": "signed_in"}},
     "sections": [
         [("mean-open-issues", c([MEAN_ISSUES])), ("open-issues-per-month", c([ISSUES], [MONTH])),
          ("open-issues-by-project", c([PEAK_ISSUES], [PROJ])), ("open-issues-per-month-by-project", c([ISSUES], [MONTH, PROJ]))],
         [("highest-stars", c([PEAK_STARS])), ("stars-per-month", c([STARS], [MONTH])),
          ("stars-by-project", c([PEAK_STARS], [PROJ])), ("stars-per-month-by-project", c([STARS], [MONTH, PROJ]))],
         [("largest-team", c([PEAK_CONTRIB])), ("contributors-per-month", c([CONTRIB], [MONTH])),
          ("contributors-by-project", c([PEAK_CONTRIB], [PROJ])), ("mean-contributors-by-project", c([MEAN_CONTRIB], [PROJ]))],
         [("highest-watchers", c([PEAK_WATCHERS])), ("watchers-per-month", c([WATCHERS], [MONTH])),
          ("watchers-by-project", c([PEAK_WATCHERS], [PROJ])), ("health-by-project", c([PEAK_ISSUES, PEAK_PRS, PEAK_CONTRIB, PEAK_WATCHERS], [PROJ]))],
     ]},
    {"slug": "portfolio", "title": t("Portfolio", "Portfólio", "พอร์ตโฟลิโอ"),
     "description": t("Coverage of the catalog metrics and each project's share of them.", "Cobertura das métricas do catálogo e a participação de cada projeto.", "ความครอบคลุมของตัวชี้วัดในแคตตาล็อกและสัดส่วนของแต่ละโปรเจกต์"),
     "tags": ["catalog", "portfolio"], "period_field": "created_at", "access": {"report": "signed_in"},
     "sections": [
         [("metric-records", c([RECORDS])), ("records-per-month", c([RECORDS], [MONTH])),
          ("records-by-metric", c([RECORDS], [METRIC])), ("projects-tracked", c([TRACKED]))],
         [("value-by-metric", c([VALUE], [METRIC])), ("mean-value-by-metric", c([MEAN_VALUE], [METRIC])),
          ("highest-value-by-metric", c([MAX_VALUE], [METRIC])), ("value-per-month-by-metric", c([VALUE], [MONTH, METRIC]))],
         [("commit-share-by-project", c([COMMITS, COMMIT_SHARE], [PROJ])), ("star-share-by-project", c([PEAK_STARS, STAR_SHARE], [PROJ])),
          ("issue-share-by-project", c([PEAK_ISSUES, ISSUE_SHARE], [PROJ])), ("fork-share-by-project", c([PEAK_FORKS, FORK_SHARE], [PROJ]))],
         [("projects-per-month", c([TRACKED], [MONTH])), ("metrics-tracked", c([METRICS_SEEN])),
          ("records-per-month-by-metric", c([RECORDS], [MONTH, METRIC])), ("records-by-project", c([RECORDS], [PROJ]))],
     ]},
    {"slug": "delivery", "title": t("Delivery", "Entrega", "การส่งมอบ"),
     "description": t("The latest month, commits against open issues, and monthly ranges per project.", "O último mês, commits contra issues abertas e faixas mensais por projeto.", "เดือนล่าสุด คอมมิตเทียบกับอิชชูที่เปิด และช่วงรายเดือนตามโปรเจกต์"),
     "tags": ["catalog", "delivery"], "period_field": "created_at",
     "access": {"cards": {"commits-per-issue-by-project": "restricted"}},
     "sections": [
         [("latest-month-commits", c([COMMITS], where=LATEST)), ("latest-commits-by-project", c([COMMITS], [PROJ], where=LATEST)),
          ("latest-issues-by-project", c([ISSUES], [PROJ], where=LATEST)), ("latest-prs-by-project", c([PRS], [PROJ], where=LATEST))],
         [("commits-per-issue", c([COMMITS_PER_ISSUE])), ("commits-per-issue-by-project", c([COMMITS_PER_ISSUE], [PROJ])),
          ("commits-per-issue-per-month", c([COMMITS_PER_ISSUE], [MONTH])), ("commits-and-issues-per-month", c([COMMITS, ISSUES], [MONTH]))],
         [("mean-monthly-commits", c([MEAN_COMMITS])), ("busiest-month-by-project", c([MAX_COMMITS], [PROJ])),
          ("quietest-month-by-project", c([MIN_COMMITS], [PROJ])), ("commit-range-by-project", c([MIN_COMMITS, MEAN_COMMITS, MAX_COMMITS], [PROJ]))],
         [("stars-and-forks-per-month", c([STARS, FORKS], [MONTH])), ("stars-and-forks-by-project", c([PEAK_STARS, PEAK_FORKS], [PROJ])),
          ("contributors-and-commits-by-project", c([PEAK_CONTRIB, COMMITS], [PROJ])), ("monthly-summary", c([COMMITS, ISSUES, PRS, STARS], [MONTH]))],
     ]},
])
