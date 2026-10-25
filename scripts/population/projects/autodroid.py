"""AutoDroid sample data. Fields of `Job` in autodroid/lib/domain/models/job_model.py."""

from __future__ import annotations

import datetime as dt
import random

from .common import at, days, field, out, t, weighted

PROJECT = "autodroid"

SCHEMA = {
    "schema_name": "job",
    "description": "autodroid Job: one queued Android automation job",
    "fields": [
        field("job_type", "string"), field("adapter_name", "string"), field("status", "string"),
        field("priority", "integer"), field("attempt_count", "integer"), field("max_attempts", "integer"),
        field("error_message", "string", required=False), field("created_at", "datetime"), field("updated_at", "datetime"),
    ],
}

JOBS = {("instagram.post", "aiograpi"): 4, ("instagram.dm_read", "aiograpi"): 2, ("whatsapp.send", "evolution_go"): 4,
        ("screen.capture", "ui_mapper"): 2, ("app.flow", "ui_mapper"): 3}
FAIL_RATE = {"aiograpi": 0.15, "evolution_go": 0.06, "ui_mapper": 0.10}
ERRORS = ["login challenge", "element not found", "network timeout", "device offline"]


def records(rng: random.Random) -> list[dict]:
    out_ = []
    n = 0
    for day in days():
        for _ in range(rng.randint(10, 30)):
            n += 1
            job_type, adapter = weighted(rng, JOBS)
            created = at(day, rng)
            failed = rng.random() < FAIL_RATE[adapter]
            status = "failed" if failed else weighted(rng, {"done": 18, "cancelled": 1, "pending": 1})
            attempts = 3 if failed else (1 if rng.random() > 0.2 else 2)
            updated = (dt.datetime.fromisoformat(created) + dt.timedelta(seconds=rng.randint(20, 900))).isoformat()
            out_.append({
                "idempotency_key": f"autodroid-job-{n:05d}",
                "event_time": created,
                "payload": {
                    "job_type": job_type, "adapter_name": adapter, "status": status,
                    "priority": rng.choice([10, 50, 100, 100, 100]), "attempt_count": attempts, "max_attempts": 3,
                    "error_message": rng.choice(ERRORS) if failed else None,
                    "created_at": created, "updated_at": updated,
                },
            })
    return out_


ADAPTER = out("adapter_name", t("Adapter", "Adaptador", "อะแดปเตอร์"), "string", role="dimension")
ADAPTER_FILTER = {"field": "adapter_name", "label": t("Adapter", "Adaptador", "อะแดปเตอร์"), "type": "category"}

CALCULATIONS = {
    "jobs-per-day": {
        "title": t("Jobs per Day", "Jobs por Dia", "งานต่อวัน"),
        "description": t("Queued jobs per day and how many finished.", "Jobs na fila por dia e quantos terminaram.", "งานในคิวต่อวันและจำนวนที่เสร็จ"),
        "source": "job", "filters": [ADAPTER_FILTER], "warm": True,
        "buckets": [{"field": "created_at", "unit": "day", "name": "day"}],
        "stages": [{"group_by": ["day"], "measures": [
            {"name": "jobs", "agg": "count"},
            {"name": "done", "agg": "count", "where": [{"field": "status", "op": "eq", "value": "done"}]}]}],
        "sort": [{"field": "day"}],
        "fields": [out("day", t("Day", "Dia", "วัน"), "date", role="dimension"),
                   out("jobs", t("Jobs", "Jobs", "งาน"), "integer"), out("done", t("Done", "Concluídos", "เสร็จแล้ว"), "integer")],
    },
    "jobs-by-type": {
        "title": t("Jobs by Type", "Jobs por Tipo", "งานตามประเภท"),
        "description": t("Jobs per job type.", "Jobs por tipo de job.", "จำนวนงานตามประเภทงาน"),
        "source": "job", "filters": [ADAPTER_FILTER],
        "stages": [{"group_by": ["job_type"], "measures": [{"name": "jobs", "agg": "count"}]}],
        "sort": [{"field": "jobs", "desc": True}],
        "fields": [out("job_type", t("Job type", "Tipo de job", "ประเภทงาน"), "string", role="dimension"),
                   out("jobs", t("Jobs", "Jobs", "งาน"), "integer")],
    },
    "attempts-by-adapter": {
        "title": t("Attempts by Adapter", "Tentativas por Adaptador", "จำนวนครั้งที่ลองตามอะแดปเตอร์"),
        "description": t("Mean attempts per job of each adapter.", "Média de tentativas por job de cada adaptador.", "จำนวนครั้งที่ลองเฉลี่ยต่องานของแต่ละอะแดปเตอร์"),
        "source": "job",
        "stages": [{"group_by": ["adapter_name"], "measures": [{"name": "attempts", "agg": "avg", "field": "attempt_count"}]}],
        "sort": [{"field": "adapter_name"}],
        "fields": [ADAPTER, out("attempts", t("Mean attempts", "Média de tentativas", "เฉลี่ยครั้งที่ลอง"), "float", decimals=2)],
    },
    "failure-by-adapter": {
        "title": t("Failure Rate", "Taxa de Falha", "อัตราความล้มเหลว"),
        "description": t("Failed jobs as a share of all jobs, per adapter.", "Jobs com falha sobre o total, por adaptador.", "สัดส่วนงานที่ล้มเหลวจากงานทั้งหมด ตามอะแดปเตอร์"),
        "source": "job",
        "stages": [{"group_by": ["adapter_name"], "measures": [
            {"name": "jobs", "agg": "count"},
            {"name": "failed", "agg": "count", "where": [{"field": "status", "op": "eq", "value": "failed"}]}],
            "derived": [{"name": "failure_rate", "expr": "failed / jobs * 100"}]}],
        "sort": [{"field": "failure_rate", "desc": True}],
        "fields": [ADAPTER, out("failure_rate", t("Failure rate", "Taxa de falha", "อัตราความล้มเหลว"), "percent", decimals=1)],
    },
    "failures-per-week": {
        "title": t("Failures per Week", "Falhas por Semana", "ความล้มเหลวต่อสัปดาห์"),
        "description": t("Failed jobs per ISO week.", "Jobs com falha por semana ISO.", "งานที่ล้มเหลวต่อสัปดาห์"),
        "source": "job", "filters": [ADAPTER_FILTER],
        "where": [{"field": "status", "op": "eq", "value": "failed"}],
        "buckets": [{"field": "created_at", "unit": "week", "name": "week"}],
        "stages": [{"group_by": ["week"], "measures": [{"name": "failed", "agg": "count"}]}],
        "sort": [{"field": "week"}],
        "fields": [out("week", t("Week", "Semana", "สัปดาห์"), "date", role="dimension"),
                   out("failed", t("Failed", "Com falha", "ล้มเหลว"), "integer")],
    },
    "errors-by-message": {
        "title": t("Errors by Message", "Erros por Mensagem", "ข้อผิดพลาดตามข้อความ"),
        "description": t("Failed jobs per error message.", "Jobs com falha por mensagem de erro.", "งานที่ล้มเหลวตามข้อความข้อผิดพลาด"),
        "source": "job",
        "where": [{"field": "status", "op": "eq", "value": "failed"}],
        "stages": [{"group_by": ["error_message"], "measures": [{"name": "jobs", "agg": "count"}]}],
        "sort": [{"field": "jobs", "desc": True}],
        "fields": [out("error_message", t("Error", "Erro", "ข้อผิดพลาด"), "string", role="dimension"),
                   out("jobs", t("Jobs", "Jobs", "งาน"), "integer")],
    },
}

REPORTS = [
    {"slug": "job-queue", "title": t("Job Queue", "Fila de Jobs", "คิวงาน"),
     "description": t("What the automation queue receives and finishes.", "O que a fila de automação recebe e conclui.", "งานที่คิวอัตโนมัติได้รับและทำเสร็จ"),
     "tags": ["automation"], "period_field": "created_at", "cards": ["jobs-per-day", "jobs-by-type", "attempts-by-adapter"], "access": {"cards": {"attempts-by-adapter": "signed_in"}}},
    {"slug": "job-reliability", "title": t("Job Reliability", "Confiabilidade dos Jobs", "ความน่าเชื่อถือของงาน"),
     "description": t("Where and why jobs fail.", "Onde e por que os jobs falham.", "งานล้มเหลวที่ไหนและเพราะอะไร"),
     "tags": ["automation", "quality"], "period_field": "created_at", "cards": ["failure-by-adapter", "failures-per-week", "errors-by-message"], "access": {"report": "signed_in", "cards": {"failure-by-adapter": "restricted"}}},
]
