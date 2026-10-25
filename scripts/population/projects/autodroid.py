"""AutoDroid sample data. Fields of `Job` in autodroid/lib/domain/models/job_model.py."""

from __future__ import annotations

import datetime as dt
import random

from .builder import build, chart, dim, measure
from .common import at, days, field, t, weighted

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


SRC = "job"
ADAPTER_FILTER = {"field": "adapter_name", "label": t("Adapter", "Adaptador", "อะแดปเตอร์"), "type": "category"}
F = [ADAPTER_FILTER]


def status(value: str) -> list:
    return [{"field": "status", "op": "eq", "value": value}]


RETRIED = [{"field": "attempt_count", "op": "gt", "value": 1}]
HIGH = [{"field": "priority", "op": "gte", "value": 100}]

DAY = dim("day", t("Day", "Dia", "วัน"), field="created_at", unit="day", per=t("Day", "Dia", "วัน"))
WEEK = dim("week", t("Week", "Semana", "สัปดาห์"), field="created_at", unit="week", per=t("Week", "Semana", "สัปดาห์"))
TYPE = dim("job_type", t("Job type", "Tipo de job", "ประเภทงาน"))
ADAPTER = dim("adapter_name", t("Adapter", "Adaptador", "อะแดปเตอร์"))
STATUS = dim("status", t("Status", "Status", "สถานะ"))
MESSAGE = dim("error_message", t("Error", "Erro", "ข้อผิดพลาด"))

JOB_COUNT = measure("jobs", t("Jobs", "Jobs", "งาน"), "count", about=t("Queued jobs", "Jobs na fila", "งานที่เข้าคิว"))
_ALL = measure("all_jobs", t("Jobs", "Jobs", "งาน"), "count")
_FAILED = measure("failed_jobs", t("Failed", "Com falha", "ล้มเหลว"), "count", where=status("failed"))
_DONE = measure("done_jobs", t("Done", "Concluídos", "เสร็จ"), "count", where=status("done"))
FAILED = measure("failed", t("Failed jobs", "Jobs com falha", "งานที่ล้มเหลว"), "count", where=status("failed"),
                 about=t("Jobs that used every attempt and failed", "Jobs que usaram todas as tentativas e falharam", "งานที่ใช้ความพยายามครบแล้วล้มเหลว"))
DONE = measure("done", t("Done jobs", "Jobs concluídos", "งานที่เสร็จ"), "count", where=status("done"))
PENDING = measure("pending", t("Pending jobs", "Jobs pendentes", "งานที่รอ"), "count", where=status("pending"))
CANCELLED = measure("cancelled", t("Cancelled jobs", "Jobs cancelados", "งานที่ยกเลิก"), "count", where=status("cancelled"))
FAILURE_RATE = measure("failure_rate", t("Failure rate", "Taxa de falha", "อัตราความล้มเหลว"), expr="failed_jobs / all_jobs * 100",
                       type_="percent", decimals=1, needs=(_ALL, _FAILED), about=t("Share of failed jobs", "Parcela de jobs com falha", "สัดส่วนงานที่ล้มเหลว"))
DONE_RATE = measure("done_rate", t("Completion rate", "Taxa de conclusão", "อัตราการเสร็จ"), expr="done_jobs / all_jobs * 100",
                    type_="percent", decimals=1, needs=(_ALL, _DONE), about=t("Share of done jobs", "Parcela de jobs concluídos", "สัดส่วนงานที่เสร็จ"))
RATE_7D = measure("rate_7d", t("7-day mean", "Média de 7 dias", "เฉลี่ย 7 วัน"), type_="percent", decimals=1,
                  window={"agg": "avg", "field": "failure_rate", "size": 7})
ATTEMPTS = measure("attempts", t("Attempts", "Tentativas", "ความพยายาม"), "sum", "attempt_count", about=t("Run attempts of all jobs", "Tentativas de execução de todos os jobs", "จำนวนครั้งที่รันของทุกงาน"))
MEAN_ATTEMPTS = measure("mean_attempts", t("Attempts per job", "Tentativas por job", "ความพยายามต่องาน"), "avg", "attempt_count", type_="float", decimals=2,
                        about=t("Mean run attempts per job", "Média de tentativas por job", "จำนวนครั้งที่รันเฉลี่ยต่องาน"))
RETRIED_JOBS = measure("retried", t("Retried jobs", "Jobs repetidos", "งานที่ลองใหม่"), "count", where=RETRIED,
                       about=t("Jobs that needed more than one attempt", "Jobs que precisaram de mais de uma tentativa", "งานที่ต้องรันมากกว่าหนึ่งครั้ง"))
HIGH_PRIORITY = measure("high_priority", t("High-priority jobs", "Jobs de alta prioridade", "งานความสำคัญสูง"), "count", where=HIGH,
                        about=t("Jobs with priority 100", "Jobs com prioridade 100", "งานที่มีความสำคัญ 100"))
MEAN_PRIORITY = measure("mean_priority", t("Mean priority", "Prioridade média", "ความสำคัญเฉลี่ย"), "avg", "priority", type_="float", decimals=0)
ADAPTERS = measure("adapters", t("Adapters in use", "Adaptadores em uso", "อะแดปเตอร์ที่ใช้"), "count_distinct", "adapter_name",
                   about=t("Distinct adapters", "Adaptadores distintos", "อะแดปเตอร์ที่ไม่ซ้ำ"))
TYPES_IN_USE = measure("types", t("Job types in use", "Tipos de job em uso", "ประเภทงานที่ใช้"), "count_distinct", "job_type",
                about=t("Distinct job types", "Tipos de job distintos", "ประเภทงานที่ไม่ซ้ำ"))
MESSAGES = measure("messages", t("Error messages", "Mensagens de erro", "ข้อความข้อผิดพลาด"), "count_distinct", "error_message",
                   about=t("Distinct error messages", "Mensagens de erro distintas", "ข้อความข้อผิดพลาดที่ไม่ซ้ำ"))
ERRORS_ = measure("errors", t("Errors", "Erros", "ข้อผิดพลาด"), "count", about=t("Failed jobs", "Jobs com falha", "งานที่ล้มเหลว"))
FAIL = status("failed")


def c(measures, dims=(), **kw):
    return chart(SRC, measures, dims, filters=kw.pop("filters", F), **kw)


CALCULATIONS, REPORTS = build([
    {"slug": "job-queue", "title": t("Job Queue", "Fila de Jobs", "คิวงาน"),
     "description": t("Volume and status of the automation jobs per type and adapter.", "Volume e status dos jobs de automação por tipo e adaptador.", "ปริมาณและสถานะของงานอัตโนมัติตามประเภทและอะแดปเตอร์"),
     "tags": ["automation"], "period_field": "created_at",
     "access": {"cards": {"jobs-by-type-and-adapter": "signed_in", "high-priority-by-type": "signed_in"}},
     "sections": [
         [("total-jobs", c([JOB_COUNT], warm=True)), ("jobs-per-day", c([JOB_COUNT], [DAY], warm=True)),
          ("jobs-by-type", c([JOB_COUNT], [TYPE])), ("jobs-by-adapter", c([JOB_COUNT], [ADAPTER]))],
         [("jobs-by-status", c([JOB_COUNT], [STATUS])), ("jobs-per-day-by-status", c([JOB_COUNT], [DAY, STATUS])),
          ("jobs-per-day-by-adapter", c([JOB_COUNT], [DAY, ADAPTER])), ("jobs-by-type-and-adapter", c([JOB_COUNT, ATTEMPTS], [TYPE, ADAPTER]))],
         [("pending-jobs", c([PENDING])), ("pending-by-type", c([PENDING], [TYPE])),
          ("cancelled-jobs", c([CANCELLED])), ("cancelled-by-adapter", c([CANCELLED], [ADAPTER]))],
         [("jobs-per-week", c([JOB_COUNT], [WEEK])), ("jobs-per-week-by-type", c([JOB_COUNT], [WEEK, TYPE])),
          ("high-priority-jobs", c([HIGH_PRIORITY])), ("high-priority-by-type", c([HIGH_PRIORITY], [TYPE]))],
     ]},
    {"slug": "job-reliability", "title": t("Job Reliability", "Confiabilidade dos Jobs", "ความน่าเชื่อถือของงาน"),
     "description": t("Failures, error messages and completion of the jobs.", "Falhas, mensagens de erro e conclusão dos jobs.", "ความล้มเหลว ข้อความข้อผิดพลาด และการเสร็จของงาน"),
     "tags": ["automation", "quality"], "period_field": "created_at",
     "access": {"report": "signed_in", "cards": {"errors-by-adapter-and-message": "restricted"}},
     "sections": [
         [("failure-rate", c([FAILURE_RATE])), ("failure-rate-per-day", c([FAILURE_RATE, RATE_7D], [DAY])),
          ("failure-rate-by-adapter", c([FAILURE_RATE], [ADAPTER])), ("failure-rate-by-type", c([FAILURE_RATE], [TYPE]))],
         [("failed-jobs", c([FAILED])), ("failures-per-day", c([FAILED], [DAY])),
          ("failures-per-week", c([FAILED], [WEEK])), ("failures-per-day-by-adapter", c([FAILED], [DAY, ADAPTER]))],
         [("error-messages", c([MESSAGES], where=FAIL)), ("errors-by-message", c([ERRORS_], [MESSAGE], where=FAIL)),
          ("errors-by-adapter-and-message", c([ERRORS_], [ADAPTER, MESSAGE], where=FAIL)), ("errors-per-day-by-message", c([ERRORS_], [DAY, MESSAGE], where=FAIL))],
         [("completion-rate", c([DONE_RATE])), ("completion-rate-per-day", c([DONE_RATE], [DAY])),
          ("completion-rate-by-adapter", c([DONE_RATE], [ADAPTER])), ("done-by-type", c([DONE], [TYPE]))],
     ]},
    {"slug": "retries", "title": t("Retries", "Repetições", "การลองใหม่"),
     "description": t("Run attempts and the jobs that needed more than one.", "Tentativas de execução e os jobs que precisaram de mais de uma.", "จำนวนครั้งที่รันและงานที่ต้องรันมากกว่าหนึ่งครั้ง"),
     "tags": ["automation", "retries"], "period_field": "created_at",
     "sections": [
         [("total-attempts", c([ATTEMPTS])), ("attempts-per-day", c([ATTEMPTS], [DAY])),
          ("attempts-by-adapter", c([ATTEMPTS], [ADAPTER])), ("attempts-by-type", c([ATTEMPTS], [TYPE]))],
         [("attempts-per-job", c([MEAN_ATTEMPTS])), ("attempts-per-job-per-day", c([MEAN_ATTEMPTS], [DAY])),
          ("attempts-per-job-by-adapter", c([MEAN_ATTEMPTS], [ADAPTER])), ("attempts-per-job-by-type", c([MEAN_ATTEMPTS], [TYPE]))],
         [("retried-jobs", c([RETRIED_JOBS])), ("retried-per-day", c([RETRIED_JOBS], [DAY])),
          ("retried-by-adapter", c([RETRIED_JOBS], [ADAPTER])), ("retried-by-type", c([RETRIED_JOBS], [TYPE]))],
         [("attempts-per-week", c([ATTEMPTS], [WEEK])), ("retried-per-week", c([RETRIED_JOBS], [WEEK])),
          ("attempts-per-day-by-adapter", c([ATTEMPTS], [DAY, ADAPTER])), ("retries-by-adapter", c([JOB_COUNT, ATTEMPTS, MEAN_ATTEMPTS, RETRIED_JOBS], [ADAPTER]))],
     ]},
    {"slug": "adapters", "title": t("Adapters", "Adaptadores", "อะแดปเตอร์"),
     "description": t("What each adapter runs, finishes and cancels, and the priority of its jobs.", "O que cada adaptador executa, conclui e cancela, e a prioridade dos seus jobs.", "สิ่งที่แต่ละอะแดปเตอร์รัน ทำเสร็จ และยกเลิก รวมถึงความสำคัญของงาน"),
     "tags": ["automation", "adapters"], "period_field": "created_at",
     "access": {"cards": {"adapter-summary": "restricted"}, "hidden": ["adapter-summary"]},
     "sections": [
         [("adapters-in-use", c([ADAPTERS])), ("jobs-per-week-by-adapter", c([JOB_COUNT], [WEEK, ADAPTER])),
          ("done-by-adapter", c([DONE], [ADAPTER])), ("pending-by-adapter", c([PENDING], [ADAPTER]))],
         [("job-types-in-use", c([TYPES_IN_USE])), ("jobs-per-week-by-status", c([JOB_COUNT], [WEEK, STATUS])),
          ("done-per-day", c([DONE], [DAY])), ("done-per-week", c([DONE], [WEEK]))],
         [("mean-priority", c([MEAN_PRIORITY])), ("priority-by-type", c([MEAN_PRIORITY], [TYPE])),
          ("priority-by-adapter", c([MEAN_PRIORITY], [ADAPTER])), ("high-priority-per-day", c([HIGH_PRIORITY], [DAY]))],
         [("cancelled-per-day", c([CANCELLED], [DAY])), ("cancelled-by-type", c([CANCELLED], [TYPE])),
          ("type-summary", c([JOB_COUNT, DONE, FAILED, CANCELLED], [TYPE])), ("adapter-summary", c([JOB_COUNT, DONE, FAILED, CANCELLED], [ADAPTER]))],
     ]},
])
