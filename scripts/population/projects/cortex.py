"""Cortex sample data. Fields of `TelemetryEvent` in cortex_api/lib/dal/models.py."""

from __future__ import annotations

import random

from .builder import build, chart, dim, measure
from .common import at, days, field, t, weighted

PROJECT = "cortex"

SCHEMA = {
    "schema_name": "telemetry_event",
    "description": "cortex_api TelemetryEvent: one LLM execution of the orchestration",
    "fields": [
        field("request_id", "string"), field("execution_id", "string"), field("strategy_id", "string"),
        field("tier_requested", "integer"), field("tier_executed", "integer"), field("task_type", "string"),
        field("provider", "string"), field("model", "string"), field("role", "string"),
        field("input_tokens", "integer"), field("output_tokens", "integer"), field("total_tokens", "integer"),
        field("started_at", "datetime"), field("latency_ms", "integer"), field("success", "boolean"),
        field("error_type", "string", required=False), field("retrieval_source", "string", required=False),
    ],
}

MODELS = {("ollama", "qwen2.5:7b"): 5, ("ollama", "llama3.1:8b"): 3, ("openai", "gpt-4o-mini"): 3, ("google", "gemini-2.0-flash"): 2}
TASKS = {"chat": 6, "code": 3, "summarize": 2, "research": 1}
ERRORS = {"timeout": 5, "rate_limited": 3, "context_overflow": 2}


def records(rng: random.Random) -> list[dict]:
    out_ = []
    n = 0
    for day in days():
        for _ in range(rng.randint(15, 40)):
            n += 1
            provider, model = weighted(rng, MODELS)
            tier = rng.choice([1, 2, 3])
            input_tokens = rng.randint(200, 3500)
            output_tokens = rng.randint(50, 1200)
            local = provider == "ollama"
            success = rng.random() > (0.12 if local else 0.05)
            started = at(day, rng)
            out_.append({
                "idempotency_key": f"cortex-req-{n:05d}",
                "event_time": started,
                "payload": {
                    "request_id": f"req-{n:05d}", "execution_id": f"exe-{n:05d}", "strategy_id": f"tier{tier}-default",
                    "tier_requested": tier, "tier_executed": tier if success else min(tier + 1, 3),
                    "task_type": weighted(rng, TASKS), "provider": provider, "model": model,
                    "role": "primary" if rng.random() > 0.1 else "fallback",
                    "input_tokens": input_tokens, "output_tokens": output_tokens, "total_tokens": input_tokens + output_tokens,
                    "started_at": started,
                    "latency_ms": rng.randint(900, 9000) if local else rng.randint(400, 4000),
                    "success": success,
                    "error_type": None if success else weighted(rng, ERRORS),
                    "retrieval_source": rng.choice(["hippocampus", "web", None]),
                },
            })
    return out_


SRC = "telemetry_event"
PROVIDER_FILTER = {"field": "provider", "label": t("Provider", "Provedor", "ผู้ให้บริการ"), "type": "category"}
F = [PROVIDER_FILTER]
OK = [{"field": "success", "op": "eq", "value": True}]
FAILED = [{"field": "success", "op": "eq", "value": False}]
RETRIEVAL = [{"field": "retrieval_source", "op": "in", "value": ["hippocampus", "web"]}]

DAY = dim("day", t("Day", "Dia", "วัน"), field="started_at", unit="day", per=t("Day", "Dia", "วัน"))
WEEK = dim("week", t("Week", "Semana", "สัปดาห์"), field="started_at", unit="week", per=t("Week", "Semana", "สัปดาห์"))
PROVIDER = dim("provider", t("Provider", "Provedor", "ผู้ให้บริการ"))
MODEL = dim("model", t("Model", "Modelo", "โมเดล"))
TASK = dim("task_type", t("Task", "Tarefa", "งาน"))
ROLE = dim("role", t("Role", "Papel", "บทบาท"))
STRATEGY = dim("strategy_id", t("Strategy", "Estratégia", "กลยุทธ์"))
ERROR = dim("error_type", t("Error", "Erro", "ข้อผิดพลาด"))
SOURCE = dim("retrieval_source", t("Retrieval source", "Fonte de recuperação", "แหล่งข้อมูลที่ดึง"))

REQUESTS = measure("requests", t("Requests", "Requisições", "คำขอ"), "count",
                   about=t("Executions", "Execuções", "จำนวนการทำงาน"))
TOKENS = measure("tokens", t("Tokens", "Tokens", "โทเค็น"), "sum", "total_tokens",
                 about=t("Input plus output tokens", "Tokens de entrada mais saída", "โทเค็นขาเข้ารวมขาออก"))
INPUT = measure("input_tokens", t("Input tokens", "Tokens de entrada", "โทเค็นขาเข้า"), "sum", "input_tokens", unit="tokens")
OUTPUT = measure("output_tokens", t("Output tokens", "Tokens de saída", "โทเค็นขาออก"), "sum", "output_tokens", unit="tokens")
MEAN_TOKENS = measure("mean_tokens", t("Mean tokens", "Média de tokens", "โทเค็นเฉลี่ย"), "avg", "total_tokens", type_="float", decimals=0,
                      about=t("Mean tokens per execution", "Média de tokens por execução", "โทเค็นเฉลี่ยต่อการทำงาน"))
SHARE = measure("share", t("Share", "Participação", "สัดส่วน"), expr="tokens / sum_tokens * 100", type_="percent", decimals=1)
MEAN_MS = measure("mean_ms", t("Mean latency", "Latência média", "เวลาแฝงเฉลี่ย"), "avg", "latency_ms", type_="float", unit="ms", decimals=0,
                  about=t("Mean response time", "Tempo médio de resposta", "เวลาตอบสนองเฉลี่ย"))
MAX_MS = measure("max_ms", t("Highest latency", "Latência máxima", "เวลาแฝงสูงสุด"), "max", "latency_ms", unit="ms")
MIN_MS = measure("min_ms", t("Lowest latency", "Latência mínima", "เวลาแฝงต่ำสุด"), "min", "latency_ms", unit="ms")
_ALL = measure("all_requests", t("Requests", "Requisições", "คำขอ"), "count")
_OK = measure("ok", t("Successful", "Com sucesso", "สำเร็จ"), "count", where=OK)
SUCCESS = measure("success_rate", t("Success rate", "Taxa de sucesso", "อัตราความสำเร็จ"), expr="ok / all_requests * 100",
                  type_="percent", decimals=1, needs=(_ALL, _OK),
                  about=t("Share of successful executions", "Parcela de execuções com sucesso", "สัดส่วนการทำงานที่สำเร็จ"))
RATE_7D = measure("rate_7d", t("7-day mean", "Média de 7 dias", "เฉลี่ย 7 วัน"), type_="percent", decimals=1,
                  window={"agg": "avg", "field": "success_rate", "size": 7})
FAILURES = measure("failures", t("Failures", "Falhas", "ความล้มเหลว"), "count", where=FAILED,
                   about=t("Failed executions", "Execuções com falha", "การทำงานที่ล้มเหลว"))
FALLBACKS = measure("fallbacks", t("Fallbacks", "Fallbacks", "การสำรอง"), "count", where=[{"field": "role", "op": "eq", "value": "fallback"}],
                    about=t("Executions of a fallback model", "Execuções de um modelo de fallback", "การทำงานด้วยโมเดลสำรอง"))
EXECUTIONS = measure("executions", t("Executions", "Execuções", "การทำงาน"), "count_distinct", "execution_id",
                     about=t("Distinct executions", "Execuções distintas", "การทำงานที่ไม่ซ้ำ"))
MODELS_IN_USE = measure("models", t("Models in use", "Modelos em uso", "โมเดลที่ใช้"), "count_distinct", "model",
                 about=t("Distinct models", "Modelos distintos", "โมเดลที่ไม่ซ้ำ"))
PROVIDERS = measure("providers", t("Providers in use", "Provedores em uso", "ผู้ให้บริการที่ใช้"), "count_distinct", "provider",
                    about=t("Distinct providers", "Provedores distintos", "ผู้ให้บริการที่ไม่ซ้ำ"))
STRATEGIES = measure("strategies", t("Strategies in use", "Estratégias em uso", "กลยุทธ์ที่ใช้"), "count_distinct", "strategy_id",
                     about=t("Distinct routing strategies", "Estratégias de roteamento distintas", "กลยุทธ์การกำหนดเส้นทางที่ไม่ซ้ำ"))
_HIPPO = measure("hippocampus", t("Hippocampus", "Hippocampus", "Hippocampus"), "count",
                 where=[{"field": "retrieval_source", "op": "eq", "value": "hippocampus"}])
HIPPO_SHARE = measure("hippocampus_share", t("Hippocampus share", "Parcela do Hippocampus", "สัดส่วน Hippocampus"),
                      expr="hippocampus / all_requests * 100", type_="percent", decimals=1, needs=(_ALL, _HIPPO),
                      about=t("Share of retrievals from Hippocampus", "Parcela das recuperações vindas do Hippocampus", "สัดส่วนการดึงข้อมูลจาก Hippocampus"))


def c(measures, dims=(), **kw):
    return chart(SRC, measures, dims, filters=kw.pop("filters", F), **kw)


CALCULATIONS, REPORTS = build([
    {"slug": "model-usage", "title": t("Model Usage", "Uso de Modelos", "การใช้โมเดล"),
     "description": t("How Cortex spends tokens across providers, models and tasks.", "Como o Cortex usa tokens entre provedores, modelos e tarefas.", "Cortex ใช้โทเค็นอย่างไรในแต่ละผู้ให้บริการ โมเดล และงาน"),
     "tags": ["llm", "tokens"], "period_field": "started_at",
     "access": {"cards": {"tokens-by-model": "signed_in", "requests-per-day-by-provider": "signed_in", "tokens-by-provider-and-model": "signed_in"}},
     "sections": [
         [("total-tokens", c([TOKENS], warm=True)), ("tokens-per-day", c([INPUT, OUTPUT], [DAY], warm=True)),
          ("tokens-by-provider", c([TOKENS, SHARE], [PROVIDER])), ("tokens-by-model", c([TOKENS], [MODEL]))],
         [("total-requests", c([REQUESTS])), ("requests-per-day", c([REQUESTS], [DAY])),
          ("requests-by-task", c([REQUESTS, MEAN_TOKENS], [TASK])), ("requests-per-day-by-provider", c([REQUESTS], [DAY, PROVIDER]))],
         [("mean-tokens", c([MEAN_TOKENS])), ("mean-tokens-per-day", c([MEAN_TOKENS], [DAY])),
          ("tokens-by-task", c([INPUT, OUTPUT], [TASK])), ("tokens-by-provider-and-model", c([TOKENS, REQUESTS], [PROVIDER, MODEL]))],
         [("tokens-per-week", c([TOKENS], [WEEK])), ("requests-per-week", c([REQUESTS], [WEEK])),
          ("tokens-per-week-by-task", c([TOKENS], [WEEK, TASK])), ("weekly-summary", c([REQUESTS, TOKENS, MEAN_TOKENS, MEAN_MS], [WEEK]))],
     ]},
    {"slug": "reliability", "title": t("Reliability", "Confiabilidade", "ความน่าเชื่อถือ"),
     "description": t("Success rate, latency, errors and fallbacks of the orchestration.", "Taxa de sucesso, latência, erros e fallbacks da orquestração.", "อัตราความสำเร็จ เวลาแฝง ข้อผิดพลาด และการสำรองของระบบ"),
     "tags": ["llm", "quality"], "period_field": "started_at", "access": {"report": "restricted"},
     "sections": [
         [("success-rate", c([SUCCESS])), ("success-rate-per-day", c([SUCCESS, RATE_7D], [DAY])),
          ("failures-by-provider", c([FAILURES], [PROVIDER])), ("success-rate-by-model", c([SUCCESS], [MODEL]))],
         [("mean-latency", c([MEAN_MS])), ("latency-per-day", c([MEAN_MS], [DAY])),
          ("latency-by-model", c([MEAN_MS, MAX_MS], [MODEL])), ("latency-by-task", c([MEAN_MS, MIN_MS, MAX_MS], [TASK]))],
         [("total-failures", c([FAILURES])), ("failures-per-day", c([FAILURES], [DAY])),
          ("errors-by-type", c([FAILURES], [ERROR], where=FAILED)), ("failures-per-day-by-error", c([FAILURES], [DAY, ERROR], where=FAILED))],
         [("total-fallbacks", c([FALLBACKS])), ("fallbacks-per-day", c([FALLBACKS], [DAY])),
          ("fallbacks-by-provider", c([FALLBACKS], [PROVIDER])), ("errors-by-provider-and-type", c([FAILURES], [PROVIDER, ERROR], where=FAILED))],
     ]},
    {"slug": "routing", "title": t("Routing", "Roteamento", "การกำหนดเส้นทาง"),
     "description": t("Strategies, roles and tasks that route each request to a model.", "Estratégias, papéis e tarefas que levam cada requisição a um modelo.", "กลยุทธ์ บทบาท และงานที่ส่งคำขอแต่ละรายการไปยังโมเดล"),
     "tags": ["llm", "routing"], "period_field": "started_at",
     "sections": [
         [("strategies-in-use", c([STRATEGIES])), ("requests-by-strategy", c([REQUESTS], [STRATEGY])),
          ("tokens-by-strategy", c([TOKENS], [STRATEGY])), ("latency-by-strategy", c([MEAN_MS], [STRATEGY]))],
         [("requests-by-role", c([REQUESTS], [ROLE])), ("tokens-by-role", c([TOKENS, MEAN_TOKENS], [ROLE])),
          ("latency-by-role", c([MEAN_MS, MAX_MS], [ROLE])), ("requests-per-day-by-role", c([REQUESTS], [DAY, ROLE]))],
         [("requests-by-task-and-provider", c([REQUESTS, TOKENS], [TASK, PROVIDER])), ("tokens-per-day-by-task", c([TOKENS], [DAY, TASK])),
          ("latency-of-tasks", c([MEAN_MS], [TASK])), ("success-rate-by-task", c([SUCCESS], [TASK]))],
         [("distinct-executions", c([EXECUTIONS])), ("executions-per-day", c([EXECUTIONS], [DAY])),
          ("models-per-day", c([MODELS_IN_USE], [DAY])), ("providers-in-use", c([PROVIDERS]))],
     ]},
    {"slug": "retrieval", "title": t("Memory Retrieval", "Recuperação de Memória", "การดึงหน่วยความจำ"),
     "description": t("Requests that read Hippocampus memories or the web before answering.", "Requisições que leem memórias do Hippocampus ou a web antes de responder.", "คำขอที่อ่านหน่วยความจำ Hippocampus หรือเว็บก่อนตอบ"),
     "tags": ["llm", "memory"], "period_field": "started_at",
     "access": {"report": "signed_in", "cards": {"retrieval-by-task-and-source": "restricted"}},
     "sections": [
         [("retrieval-requests", c([REQUESTS], where=RETRIEVAL)), ("requests-by-source", c([REQUESTS], [SOURCE], where=RETRIEVAL)),
          ("tokens-by-source", c([TOKENS, MEAN_TOKENS], [SOURCE], where=RETRIEVAL)), ("latency-by-source", c([MEAN_MS, MAX_MS], [SOURCE], where=RETRIEVAL))],
         [("hippocampus-share", c([HIPPO_SHARE], where=RETRIEVAL)), ("retrieval-per-day", c([REQUESTS], [DAY], where=RETRIEVAL)),
          ("retrieval-per-day-by-source", c([REQUESTS], [DAY, SOURCE], where=RETRIEVAL)), ("hippocampus-share-per-day", c([HIPPO_SHARE], [DAY], where=RETRIEVAL))],
         [("retrieval-tokens-per-day", c([TOKENS], [DAY], where=RETRIEVAL)), ("retrieval-by-task-and-source", c([REQUESTS], [TASK, SOURCE], where=RETRIEVAL)),
          ("retrieval-by-model", c([REQUESTS], [MODEL], where=RETRIEVAL)), ("retrieval-success-by-source", c([SUCCESS], [SOURCE], where=RETRIEVAL))],
         [("retrieval-per-week", c([REQUESTS], [WEEK], where=RETRIEVAL)), ("retrieval-tokens-per-week", c([TOKENS], [WEEK], where=RETRIEVAL)),
          ("retrieval-latency-per-week", c([MEAN_MS], [WEEK], where=RETRIEVAL)), ("retrieval-mean-latency", c([MEAN_MS], where=RETRIEVAL))],
     ]},
])
