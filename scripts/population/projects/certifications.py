"""Certifications sample data. Fields of `UserCertificationModel` in
certifications_api/src/domain/models/user_certification.py (person fields left out)."""

from __future__ import annotations

import random
import uuid

from .builder import build, chart, dim, measure
from .common import at, days, field, t, weighted

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


SRC = "user_certification"
LANG_FILTER = {"field": "language", "label": t("Language", "Idioma", "ภาษา"), "type": "category"}
F = [LANG_FILTER]
PASS = [{"field": "score", "op": "gte", "value": PASS_SCORE}]
FAIL = [{"field": "score", "op": "lt", "value": PASS_SCORE}]
PDF = [{"field": "is_pdf", "op": "eq", "value": True}]

DAY = dim("day", t("Day", "Dia", "วัน"), field="created_at", unit="day", per=t("Day", "Dia", "วัน"))
WEEK = dim("week", t("Week", "Semana", "สัปดาห์"), field="created_at", unit="week", per=t("Week", "Semana", "สัปดาห์"))
EXAM = dim("certification_title", t("Certification", "Certificação", "ใบรับรอง"))
LANG = dim("language", t("Language", "Idioma", "ภาษา"))

ATTEMPTS = measure("attempts", t("Attempts", "Tentativas", "การสอบ"), "count", about=t("Finished exam attempts", "Tentativas de prova concluídas", "การสอบที่ทำเสร็จ"))
_ALL = measure("all_attempts", t("Attempts", "Tentativas", "การสอบ"), "count")
_PASSED = measure("passed_attempts", t("Passed", "Aprovadas", "ผ่าน"), "count", where=PASS)
PASSED = measure("passed", t("Passed attempts", "Tentativas aprovadas", "การสอบที่ผ่าน"), "count", where=PASS,
                 about=t(f"Attempts with a score of {PASS_SCORE} or more", f"Tentativas com nota {PASS_SCORE} ou mais", f"การสอบที่ได้คะแนน {PASS_SCORE} ขึ้นไป"))
FAILED = measure("failed", t("Failed attempts", "Tentativas reprovadas", "การสอบที่ไม่ผ่าน"), "count", where=FAIL,
                 about=t(f"Attempts with a score under {PASS_SCORE}", f"Tentativas com nota abaixo de {PASS_SCORE}", f"การสอบที่ได้คะแนนต่ำกว่า {PASS_SCORE}"))
PASS_RATE = measure("pass_rate", t("Pass rate", "Taxa de aprovação", "อัตราการผ่าน"), expr="passed_attempts / all_attempts * 100",
                    type_="percent", decimals=1, needs=(_ALL, _PASSED),
                    about=t("Share of attempts that passed", "Parcela de tentativas aprovadas", "สัดส่วนการสอบที่ผ่าน"))
RATE_7D = measure("rate_7d", t("7-day mean", "Média de 7 dias", "เฉลี่ย 7 วัน"), type_="percent", decimals=1,
                  window={"agg": "avg", "field": "pass_rate", "size": 7})
MEAN_SCORE = measure("mean_score", t("Mean score", "Nota média", "คะแนนเฉลี่ย"), "avg", "score", type_="float", decimals=1)
MAX_SCORE = measure("max_score", t("Highest score", "Nota máxima", "คะแนนสูงสุด"), "max", "score", type_="float", decimals=1)
MIN_SCORE = measure("min_score", t("Lowest score", "Nota mínima", "คะแนนต่ำสุด"), "min", "score", type_="float", decimals=1)
_CORRECT = measure("correct_sum", t("Correct answers", "Respostas certas", "คำตอบที่ถูก"), "sum", "correct_questions")
_TOTAL = measure("total_sum", t("Questions", "Questões", "คำถาม"), "sum", "total_questions")
ACCURACY = measure("accuracy", t("Accuracy", "Acurácia", "ความแม่นยำ"), expr="correct_sum / total_sum * 100", type_="percent", decimals=1,
                   needs=(_CORRECT, _TOTAL), about=t("Correct answers over all questions", "Respostas certas sobre todas as questões", "คำตอบที่ถูกเทียบกับคำถามทั้งหมด"))
QUESTIONS = measure("questions", t("Questions answered", "Questões respondidas", "คำถามที่ตอบ"), "sum", "total_questions")
MEAN_QUESTIONS = measure("mean_questions", t("Questions per exam", "Questões por prova", "คำถามต่อการสอบ"), "avg", "total_questions", type_="float", decimals=0,
                         about=t("Mean questions per attempt", "Média de questões por tentativa", "จำนวนคำถามเฉลี่ยต่อการสอบ"))
CORRECT = measure("correct", t("Correct answers", "Respostas certas", "คำตอบที่ถูก"), "sum", "correct_questions")
WRONG = measure("wrong", t("Wrong answers", "Respostas erradas", "คำตอบที่ผิด"), "sum", "wrong_questions")
CERTIFICATES = measure("certificates", t("Certificates issued", "Certificados emitidos", "ใบรับรองที่ออก"), "count", where=PDF,
                       about=t("Passed attempts with a PDF certificate", "Tentativas aprovadas com certificado em PDF", "การสอบที่ผ่านและได้ใบรับรอง PDF"))
EXAMS_IN_USE = measure("exams", t("Certifications in use", "Certificações em uso", "ใบรับรองที่ใช้"), "count_distinct", "certification_title",
                about=t("Distinct certifications", "Certificações distintas", "ใบรับรองที่ไม่ซ้ำ"))
LANGS_IN_USE = measure("languages", t("Languages in use", "Idiomas em uso", "ภาษาที่ใช้"), "count_distinct", "language",
                       about=t("Distinct exam languages", "Idiomas de prova distintos", "ภาษาการสอบที่ไม่ซ้ำ"))


def c(measures, dims=(), **kw):
    return chart(SRC, measures, dims, filters=kw.pop("filters", F), **kw)


CALCULATIONS, REPORTS = build([
    {"slug": "exam-results", "title": t("Exam Results", "Resultados das Provas", "ผลการสอบ"),
     "description": t("Attempts, pass rate and scores per certification and language.", "Tentativas, taxa de aprovação e notas por certificação e idioma.", "การสอบ อัตราการผ่าน และคะแนนตามใบรับรองและภาษา"),
     "tags": ["learning"], "period_field": "created_at",
     "access": {"cards": {"pass-rate-by-language": "signed_in", "score-by-language": "signed_in", "results-by-exam-and-language": "restricted"}},
     "sections": [
         [("total-attempts", c([ATTEMPTS], warm=True)), ("attempts-per-day", c([ATTEMPTS], [DAY], warm=True)),
          ("attempts-by-exam", c([ATTEMPTS], [EXAM])), ("attempts-by-language", c([ATTEMPTS], [LANG]))],
         [("pass-rate", c([PASS_RATE])), ("pass-rate-per-day", c([PASS_RATE, RATE_7D], [DAY])),
          ("pass-rate-by-exam", c([PASS_RATE], [EXAM])), ("pass-rate-by-language", c([PASS_RATE], [LANG]))],
         [("mean-score", c([MEAN_SCORE])), ("score-per-day", c([MEAN_SCORE, MAX_SCORE], [DAY])),
          ("score-by-exam", c([MEAN_SCORE, MIN_SCORE, MAX_SCORE], [EXAM])), ("score-by-language", c([MEAN_SCORE], [LANG]))],
         [("passed-attempts", c([PASSED])), ("passed-per-day", c([PASSED], [DAY])),
          ("passed-per-day-by-exam", c([PASSED], [DAY, EXAM])), ("results-by-exam-and-language", c([ATTEMPTS, PASSED], [EXAM, LANG]))],
     ]},
    {"slug": "study-progress", "title": t("Study Progress", "Progresso dos Estudos", "ความก้าวหน้าในการเรียน"),
     "description": t("Accuracy, answered questions and issued certificates over time.", "Acurácia, questões respondidas e certificados emitidos ao longo do tempo.", "ความแม่นยำ คำถามที่ตอบ และใบรับรองที่ออกตามช่วงเวลา"),
     "tags": ["learning"], "period_field": "created_at", "access": {"report": "signed_in"},
     "sections": [
         [("accuracy", c([ACCURACY])), ("accuracy-per-day", c([ACCURACY], [DAY])),
          ("accuracy-by-exam", c([ACCURACY], [EXAM])), ("accuracy-by-language", c([ACCURACY], [LANG]))],
         [("questions-answered", c([QUESTIONS])), ("questions-per-day", c([QUESTIONS], [DAY])),
          ("answers-by-exam", c([CORRECT, WRONG], [EXAM])), ("answers-per-day", c([CORRECT, WRONG], [DAY]))],
         [("certificates-issued", c([CERTIFICATES])), ("certificates-per-day", c([CERTIFICATES], [DAY])),
          ("certificates-by-exam", c([CERTIFICATES], [EXAM])), ("certificates-by-language", c([CERTIFICATES], [LANG]))],
         [("attempts-per-week", c([ATTEMPTS], [WEEK])), ("pass-rate-per-week", c([PASS_RATE], [WEEK])),
          ("accuracy-per-week", c([ACCURACY], [WEEK])), ("weekly-summary", c([ATTEMPTS, PASSED, CERTIFICATES, MEAN_SCORE], [WEEK]))],
     ]},
    {"slug": "exam-catalog", "title": t("Exam Catalog", "Catálogo de Provas", "แคตตาล็อกการสอบ"),
     "description": t("How each certification and language performs, and where attempts fail.", "Como cada certificação e idioma se saem, e onde as tentativas falham.", "ผลของแต่ละใบรับรองและภาษา และจุดที่การสอบไม่ผ่าน"),
     "tags": ["learning", "catalog"], "period_field": "created_at",
     "sections": [
         [("certifications-in-use", c([EXAMS_IN_USE])), ("attempts-per-week-by-exam", c([ATTEMPTS], [WEEK, EXAM])),
          ("wrong-answers-by-exam", c([WRONG], [EXAM])), ("highest-score-by-exam", c([MAX_SCORE], [EXAM]))],
         [("languages-in-use", c([LANGS_IN_USE])), ("attempts-per-week-by-language", c([ATTEMPTS], [WEEK, LANG])),
          ("wrong-answers-by-language", c([WRONG], [LANG])), ("accuracy-by-exam-and-language", c([ACCURACY, ATTEMPTS], [EXAM, LANG]))],
         [("lowest-score", c([MIN_SCORE])), ("lowest-score-by-exam", c([MIN_SCORE], [EXAM])),
          ("lowest-score-per-day", c([MIN_SCORE], [DAY])), ("failed-by-exam", c([FAILED], [EXAM]))],
         [("failed-attempts", c([FAILED])), ("failed-per-day", c([FAILED], [DAY])),
          ("failed-by-language", c([FAILED], [LANG])), ("failed-per-day-by-exam", c([FAILED], [DAY, EXAM]))],
     ]},
    {"slug": "question-volume", "title": t("Question Volume", "Volume de Questões", "ปริมาณคำถาม"),
     "description": t("Questions, correct and wrong answers per certification, language and week.", "Questões, respostas certas e erradas por certificação, idioma e semana.", "คำถาม คำตอบที่ถูกและผิด ตามใบรับรอง ภาษา และสัปดาห์"),
     "tags": ["learning", "questions"], "period_field": "created_at", "access": {"report": "restricted"},
     "sections": [
         [("questions-per-exam", c([MEAN_QUESTIONS])), ("questions-by-exam", c([QUESTIONS], [EXAM])),
          ("mean-questions-by-exam", c([MEAN_QUESTIONS], [EXAM])), ("questions-by-language", c([QUESTIONS], [LANG]))],
         [("correct-answers", c([CORRECT])), ("correct-per-day", c([CORRECT], [DAY])),
          ("correct-by-exam", c([CORRECT], [EXAM])), ("correct-by-language", c([CORRECT], [LANG]))],
         [("wrong-answers", c([WRONG])), ("wrong-per-day", c([WRONG], [DAY])),
          ("wrong-per-week", c([WRONG], [WEEK])), ("wrong-per-day-by-exam", c([WRONG], [DAY, EXAM]))],
         [("questions-per-week", c([QUESTIONS], [WEEK])), ("correct-per-week", c([CORRECT], [WEEK])),
          ("questions-per-week-by-language", c([QUESTIONS], [WEEK, LANG])), ("answers-by-exam-and-language", c([QUESTIONS, CORRECT, WRONG], [EXAM, LANG]))],
     ]},
])
