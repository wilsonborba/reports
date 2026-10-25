"""Cortex sample data. Fields of `TelemetryEvent` in cortex_api/lib/dal/models.py."""

from __future__ import annotations

import random

from .common import at, days, field, out, t, weighted

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


PROVIDER_FILTER = {"field": "provider", "label": t("Provider", "Provedor", "ผู้ให้บริการ"), "type": "category"}
DAY = out("day", t("Day", "Dia", "วัน"), "date", role="dimension")

CALCULATIONS = {
    "tokens-per-day": {
        "title": t("Tokens per Day", "Tokens por Dia", "โทเค็นต่อวัน"),
        "description": t("Input and output tokens of every execution, per day.", "Tokens de entrada e saída de cada execução, por dia.", "โทเค็นขาเข้าและขาออกของทุกการทำงาน ต่อวัน"),
        "source": "telemetry_event", "filters": [PROVIDER_FILTER], "warm": True,
        "buckets": [{"field": "started_at", "unit": "day", "name": "day"}],
        "stages": [{"group_by": ["day"], "measures": [
            {"name": "input_tokens", "agg": "sum", "field": "input_tokens"},
            {"name": "output_tokens", "agg": "sum", "field": "output_tokens"}]}],
        "sort": [{"field": "day"}],
        "fields": [DAY, out("input_tokens", t("Input", "Entrada", "ขาเข้า"), "integer", unit="tokens"),
                   out("output_tokens", t("Output", "Saída", "ขาออก"), "integer", unit="tokens")],
    },
    "tokens-by-provider": {
        "title": t("Tokens by Provider", "Tokens por Provedor", "โทเค็นตามผู้ให้บริการ"),
        "description": t("Share of all tokens per model provider.", "Participação de cada provedor no total de tokens.", "สัดส่วนโทเค็นทั้งหมดของแต่ละผู้ให้บริการ"),
        "source": "telemetry_event",
        "stages": [{"group_by": ["provider"], "measures": [{"name": "tokens", "agg": "sum", "field": "total_tokens"}],
                    "derived": [{"name": "share", "expr": "tokens / sum_tokens * 100"}]}],
        "sort": [{"field": "tokens", "desc": True}],
        "fields": [out("provider", t("Provider", "Provedor", "ผู้ให้บริการ"), "string", role="dimension"),
                   out("tokens", t("Tokens", "Tokens", "โทเค็น"), "integer"), out("share", t("Share", "Participação", "สัดส่วน"), "percent", decimals=1)],
    },
    "requests-by-task": {
        "title": t("Requests by Task", "Requisições por Tarefa", "คำขอตามประเภทงาน"),
        "description": t("Executions and mean tokens per task type.", "Execuções e média de tokens por tipo de tarefa.", "จำนวนการทำงานและโทเค็นเฉลี่ยตามประเภทงาน"),
        "source": "telemetry_event", "filters": [PROVIDER_FILTER],
        "stages": [{"group_by": ["task_type"], "measures": [
            {"name": "requests", "agg": "count"}, {"name": "mean_tokens", "agg": "avg", "field": "total_tokens"}]}],
        "sort": [{"field": "requests", "desc": True}],
        "fields": [out("task_type", t("Task", "Tarefa", "งาน"), "string", role="dimension"),
                   out("requests", t("Requests", "Requisições", "คำขอ"), "integer"),
                   out("mean_tokens", t("Mean tokens", "Média de tokens", "โทเค็นเฉลี่ย"), "float", decimals=0)],
    },
    "success-rate-per-day": {
        "title": t("Success Rate", "Taxa de Sucesso", "อัตราความสำเร็จ"),
        "description": t("Successful executions per day, with a 7-day moving mean.", "Execuções com sucesso por dia, com média móvel de 7 dias.", "การทำงานที่สำเร็จต่อวัน พร้อมค่าเฉลี่ยเคลื่อนที่ 7 วัน"),
        "source": "telemetry_event", "filters": [PROVIDER_FILTER],
        "buckets": [{"field": "started_at", "unit": "day", "name": "day"}],
        "stages": [{"group_by": ["day"], "measures": [
            {"name": "requests", "agg": "count"},
            {"name": "ok", "agg": "count", "where": [{"field": "success", "op": "eq", "value": True}]}],
            "derived": [{"name": "success_rate", "expr": "ok / requests * 100"}],
            "windows": [{"name": "rate_7d", "agg": "avg", "field": "success_rate", "size": 7, "order_by": "day"}]}],
        "sort": [{"field": "day"}],
        "fields": [DAY, out("success_rate", t("Success rate", "Taxa de sucesso", "อัตราความสำเร็จ"), "percent", decimals=1),
                   out("rate_7d", t("7-day mean", "Média de 7 dias", "เฉลี่ย 7 วัน"), "percent", decimals=1)],
    },
    "latency-by-model": {
        "title": t("Latency by Model", "Latência por Modelo", "เวลาแฝงตามโมเดล"),
        "description": t("Mean and highest response time per model.", "Tempo de resposta médio e máximo por modelo.", "เวลาตอบสนองเฉลี่ยและสูงสุดของแต่ละโมเดล"),
        "source": "telemetry_event", "filters": [PROVIDER_FILTER],
        "stages": [{"group_by": ["model"], "measures": [
            {"name": "mean_ms", "agg": "avg", "field": "latency_ms"}, {"name": "max_ms", "agg": "max", "field": "latency_ms"}]}],
        "sort": [{"field": "mean_ms", "desc": True}],
        "fields": [out("model", t("Model", "Modelo", "โมเดล"), "string", role="dimension"),
                   out("mean_ms", t("Mean", "Média", "เฉลี่ย"), "float", unit="ms", decimals=0),
                   out("max_ms", t("Highest", "Máximo", "สูงสุด"), "integer", unit="ms")],
    },
    "errors-by-type": {
        "title": t("Errors by Type", "Erros por Tipo", "ข้อผิดพลาดตามประเภท"),
        "description": t("Failed executions per error type.", "Execuções com falha por tipo de erro.", "การทำงานที่ล้มเหลวตามประเภทข้อผิดพลาด"),
        "source": "telemetry_event",
        "where": [{"field": "success", "op": "eq", "value": False}],
        "stages": [{"group_by": ["error_type"], "measures": [{"name": "errors", "agg": "count"}]}],
        "sort": [{"field": "errors", "desc": True}],
        "fields": [out("error_type", t("Error", "Erro", "ข้อผิดพลาด"), "string", role="dimension"),
                   out("errors", t("Errors", "Erros", "จำนวน"), "integer")],
    },
}

REPORTS = [
    {"slug": "model-usage", "title": t("Model Usage", "Uso de Modelos", "การใช้โมเดล"),
     "description": t("How Cortex spends tokens across providers and tasks.", "Como o Cortex usa tokens entre provedores e tarefas.", "Cortex ใช้โทเค็นอย่างไรในแต่ละผู้ให้บริการและงาน"),
     "tags": ["llm", "tokens"], "period_field": "started_at", "cards": ["tokens-per-day", "tokens-by-provider", "requests-by-task"], "access": {"cards": {"tokens-by-provider": "signed_in", "requests-by-task": "signed_in"}}},
    {"slug": "reliability", "title": t("Reliability", "Confiabilidade", "ความน่าเชื่อถือ"),
     "description": t("Success rate, latency and errors of the orchestration.", "Taxa de sucesso, latência e erros da orquestração.", "อัตราความสำเร็จ เวลาแฝง และข้อผิดพลาดของระบบ"),
     "tags": ["llm", "quality"], "period_field": "started_at", "cards": ["success-rate-per-day", "latency-by-model", "errors-by-type"], "access": {"report": "restricted"}},
]
