"""Certifications sample data. Fields of `UserCertificationModel` in
certifications_api/src/domain/models/user_certification.py (person fields left out)."""

from __future__ import annotations

import random
import uuid

from .common import at, days, field, out, t, weighted

PROJECT = "certifications"

SCHEMA = {
    "schema_name": "user_certification",
    "description": "certifications_api UserCertificationModel: one finished exam attempt",
    "fields": [
        field("certification_title", "string"), field("uuid_certification", "string"), field("language", "string"),
        field("time_spent", "string", description="HH:MM:SS"), field("created_at", "datetime"), field("is_pdf", "boolean"),
        field("score", "float"), field("total_questions", "integer"), field("correct_questions", "integer"),
        field("wrong_questions", "integer"),
    ],
}

EXAMS = {"AWS Cloud Practitioner": (4, 0.74), "Azure Fundamentals": (3, 0.70), "Google Cloud Digital Leader": (2, 0.68),
         "Kubernetes CKAD": (1, 0.58)}
LANGS = {"en": 5, "pt-BR": 4, "th": 2}
PASS_SCORE = 70


def records(rng: random.Random) -> list[dict]:
    out_ = []
    n = 0
    weights = {k: w for k, (w, _) in EXAMS.items()}
    for day in days():
        for _ in range(rng.randint(3, 12)):
            n += 1
            exam = weighted(rng, weights)
            total = rng.choice([20, 40, 65])
            correct = max(0, min(total, round(rng.gauss(EXAMS[exam][1], 0.12) * total)))
            seconds = rng.randint(total * 25, total * 70)
            created = at(day, rng)
            score = round(correct / total * 100, 1)
            out_.append({
                "idempotency_key": f"certifications-attempt-{n:05d}",
                "event_time": created,
                "payload": {
                    "certification_title": exam, "uuid_certification": str(uuid.UUID(int=rng.getrandbits(128), version=4)),
                    "language": weighted(rng, LANGS),
                    "time_spent": f"{seconds // 3600:02d}:{seconds % 3600 // 60:02d}:{seconds % 60:02d}",
                    "created_at": created, "is_pdf": score >= PASS_SCORE and rng.random() > 0.3,
                    "score": score, "total_questions": total, "correct_questions": correct, "wrong_questions": total - correct,
                },
            })
    return out_


EXAM = out("certification_title", t("Certification", "Certificação", "ใบรับรอง"), "string", role="dimension")
LANG_FILTER = {"field": "language", "label": t("Language", "Idioma", "ภาษา"), "type": "category"}
PASSED = {"name": "passed", "agg": "count", "where": [{"field": "score", "op": "gte", "value": PASS_SCORE}]}

CALCULATIONS = {
    "pass-rate-by-exam": {
        "title": t("Pass Rate", "Taxa de Aprovação", "อัตราการสอบผ่าน"),
        "description": t("Attempts with a score of 70 or more, per certification.", "Tentativas com nota 70 ou mais, por certificação.", "การสอบที่ได้คะแนน 70 ขึ้นไป ตามใบรับรอง"),
        "source": "user_certification", "filters": [LANG_FILTER], "warm": True,
        "stages": [{"group_by": ["certification_title"], "measures": [{"name": "attempts", "agg": "count"}, PASSED],
                    "derived": [{"name": "pass_rate", "expr": "passed / attempts * 100"}]}],
        "sort": [{"field": "pass_rate", "desc": True}],
        "fields": [EXAM, out("attempts", t("Attempts", "Tentativas", "จำนวนครั้ง"), "integer"),
                   out("pass_rate", t("Pass rate", "Taxa de aprovação", "อัตราการสอบผ่าน"), "percent", decimals=1)],
    },
    "score-by-language": {
        "title": t("Score by Language", "Nota por Idioma", "คะแนนตามภาษา"),
        "description": t("Mean score of the attempts in each language.", "Nota média das tentativas em cada idioma.", "คะแนนเฉลี่ยของการสอบในแต่ละภาษา"),
        "source": "user_certification",
        "stages": [{"group_by": ["language"], "measures": [{"name": "score", "agg": "avg", "field": "score"}]}],
        "sort": [{"field": "language"}],
        "fields": [out("language", t("Language", "Idioma", "ภาษา"), "string", role="dimension"),
                   out("score", t("Mean score", "Nota média", "คะแนนเฉลี่ย"), "float", decimals=1)],
    },
    "attempts-per-day": {
        "title": t("Attempts per Day", "Tentativas por Dia", "การสอบต่อวัน"),
        "description": t("Finished attempts per day, with a 7-day moving mean.", "Tentativas concluídas por dia, com média móvel de 7 dias.", "การสอบที่เสร็จต่อวัน พร้อมค่าเฉลี่ยเคลื่อนที่ 7 วัน"),
        "source": "user_certification", "filters": [LANG_FILTER],
        "buckets": [{"field": "created_at", "unit": "day", "name": "day"}],
        "stages": [{"group_by": ["day"], "measures": [{"name": "attempts", "agg": "count"}],
                    "windows": [{"name": "attempts_7d", "agg": "avg", "field": "attempts", "size": 7, "order_by": "day"}]}],
        "sort": [{"field": "day"}],
        "fields": [out("day", t("Day", "Dia", "วัน"), "date", role="dimension"), out("attempts", t("Attempts", "Tentativas", "จำนวนครั้ง"), "integer"),
                   out("attempts_7d", t("7-day mean", "Média de 7 dias", "เฉลี่ย 7 วัน"), "float", decimals=1)],
    },
    "accuracy-by-exam": {
        "title": t("Accuracy", "Acurácia", "ความแม่นยำ"),
        "description": t("Correct answers over all answered questions, per certification.", "Respostas corretas sobre todas as questões, por certificação.", "คำตอบที่ถูกจากคำถามทั้งหมด ตามใบรับรอง"),
        "source": "user_certification", "filters": [LANG_FILTER],
        "stages": [{"group_by": ["certification_title"], "measures": [
            {"name": "correct", "agg": "sum", "field": "correct_questions"}, {"name": "questions", "agg": "sum", "field": "total_questions"}],
            "derived": [{"name": "accuracy", "expr": "correct / questions * 100"}]}],
        "sort": [{"field": "certification_title"}],
        "fields": [EXAM, out("accuracy", t("Accuracy", "Acurácia", "ความแม่นยำ"), "percent", decimals=1)],
    },
    "certificates-issued": {
        "title": t("Certificates Issued", "Certificados Emitidos", "ใบรับรองที่ออกแล้ว"),
        "description": t("PDF certificates per certification.", "Certificados em PDF por certificação.", "ใบรับรอง PDF ตามใบรับรอง"),
        "source": "user_certification",
        "where": [{"field": "is_pdf", "op": "eq", "value": True}],
        "stages": [{"group_by": ["certification_title"], "measures": [{"name": "certificates", "agg": "count"}]}],
        "sort": [{"field": "certificates", "desc": True}],
        "fields": [EXAM, out("certificates", t("Certificates", "Certificados", "ใบรับรอง"), "integer")],
    },
    "score-per-week": {
        "title": t("Score per Week", "Nota por Semana", "คะแนนต่อสัปดาห์"),
        "description": t("Mean score per ISO week.", "Nota média por semana ISO.", "คะแนนเฉลี่ยต่อสัปดาห์"),
        "source": "user_certification", "filters": [LANG_FILTER],
        "buckets": [{"field": "created_at", "unit": "week", "name": "week"}],
        "stages": [{"group_by": ["week"], "measures": [{"name": "score", "agg": "avg", "field": "score"}]}],
        "sort": [{"field": "week"}],
        "fields": [out("week", t("Week", "Semana", "สัปดาห์"), "date", role="dimension"),
                   out("score", t("Mean score", "Nota média", "คะแนนเฉลี่ย"), "float", decimals=1)],
    },
}

REPORTS = [
    {"slug": "exam-results", "title": t("Exam Results", "Resultados das Provas", "ผลการสอบ"),
     "description": t("Pass rates and scores of the exam simulations.", "Taxas de aprovação e notas dos simulados.", "อัตราการสอบผ่านและคะแนนของข้อสอบจำลอง"),
     "tags": ["learning"], "period_field": "created_at", "cards": ["pass-rate-by-exam", "score-by-language", "attempts-per-day"], "access": {"cards": {"score-by-language": "signed_in", "attempts-per-day": "restricted"}}},
    {"slug": "study-progress", "title": t("Study Progress", "Progresso dos Estudos", "ความก้าวหน้าในการเรียน"),
     "description": t("Accuracy, certificates and weekly scores.", "Acurácia, certificados e notas semanais.", "ความแม่นยำ ใบรับรอง และคะแนนรายสัปดาห์"),
     "tags": ["learning"], "period_field": "created_at", "cards": ["accuracy-by-exam", "certificates-issued", "score-per-week"], "access": {"report": "signed_in"}},
]
