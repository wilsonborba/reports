"""FSM sample data. Fields of `MediaItem` in fsm/src/domain/models/media_models.py."""

from __future__ import annotations

import hashlib
import random

from .common import at, days, field, out, t, weighted

PROJECT = "fsm"

SCHEMA = {
    "schema_name": "media_item",
    "description": "fsm MediaItem: one stored media file",
    "fields": [
        field("key", "string"), field("app", "string"), field("album", "string"), field("filename", "string"),
        field("content_type", "string"), field("size_bytes", "integer"), field("relative_path", "string"),
        field("checksum_sha256", "string"), field("created_at", "datetime"),
    ],
}

APPS = {"domain_api": ("covers", 5), "certifications_api": ("study-sources", 3), "plane": ("uploads", 3),
        "api_for_apps": ("support", 1), "wilson_borba_api": ("documents", 2)}
TYPES = {("image/png", "png"): 5, ("image/webp", "webp"): 3, ("application/pdf", "pdf"): 2, ("video/mp4", "mp4"): 1}


def records(rng: random.Random) -> list[dict]:
    out_ = []
    n = 0
    weights = {app: w for app, (_, w) in APPS.items()}
    for day in days():
        for _ in range(rng.randint(4, 14)):
            n += 1
            app = weighted(rng, weights)
            album = APPS[app][0]
            content_type, ext = weighted(rng, TYPES)
            size = {"pdf": rng.randint(80_000, 4_000_000), "mp4": rng.randint(5_000_000, 90_000_000)}.get(ext, rng.randint(20_000, 900_000))
            key = f"{n:032x}"
            out_.append({
                "idempotency_key": f"fsm-media-{n:05d}",
                "event_time": at(day, rng),
                "payload": {
                    "key": key, "app": app, "album": album, "filename": f"file-{n:05d}.{ext}",
                    "content_type": content_type, "size_bytes": size,
                    "relative_path": f"{app}/{album}/{key}.{ext}",
                    "checksum_sha256": hashlib.sha256(key.encode()).hexdigest(), "created_at": at(day, rng),
                },
            })
    return out_


APP = out("app", t("Application", "Aplicação", "แอปพลิเคชัน"), "string", role="dimension")
APP_FILTER = {"field": "app", "label": t("Application", "Aplicação", "แอปพลิเคชัน"), "type": "category"}

CALCULATIONS = {
    "bytes-by-app": {
        "title": t("Storage by Application", "Armazenamento por Aplicação", "พื้นที่จัดเก็บตามแอปพลิเคชัน"),
        "description": t("Stored bytes per application.", "Bytes armazenados por aplicação.", "จำนวนไบต์ที่จัดเก็บของแต่ละแอปพลิเคชัน"),
        "source": "media_item", "warm": True,
        "stages": [{"group_by": ["app"], "measures": [{"name": "bytes", "agg": "sum", "field": "size_bytes"}, {"name": "files", "agg": "count"}],
                    "derived": [{"name": "megabytes", "expr": "bytes / 1048576"}]}],
        "sort": [{"field": "bytes", "desc": True}],
        "fields": [APP, out("megabytes", t("Size", "Tamanho", "ขนาด"), "float", unit="MB", decimals=1), out("files", t("Files", "Arquivos", "ไฟล์"), "integer")],
    },
    "files-by-type": {
        "title": t("Files by Type", "Arquivos por Tipo", "ไฟล์ตามประเภท"),
        "description": t("Stored files per content type.", "Arquivos armazenados por tipo de conteúdo.", "ไฟล์ที่จัดเก็บตามประเภทเนื้อหา"),
        "source": "media_item", "filters": [APP_FILTER],
        "stages": [{"group_by": ["content_type"], "measures": [{"name": "files", "agg": "count"}]}],
        "sort": [{"field": "files", "desc": True}],
        "fields": [out("content_type", t("Content type", "Tipo de conteúdo", "ประเภทเนื้อหา"), "string", role="dimension"),
                   out("files", t("Files", "Arquivos", "ไฟล์"), "integer")],
    },
    "uploads-per-day": {
        "title": t("Uploads per Day", "Envios por Dia", "การอัปโหลดต่อวัน"),
        "description": t("New files and their size per day.", "Novos arquivos e seu tamanho por dia.", "ไฟล์ใหม่และขนาดต่อวัน"),
        "source": "media_item", "filters": [APP_FILTER],
        "buckets": [{"field": "created_at", "unit": "day", "name": "day"}],
        "stages": [{"group_by": ["day"], "measures": [{"name": "files", "agg": "count"}, {"name": "bytes", "agg": "sum", "field": "size_bytes"}],
                    "derived": [{"name": "megabytes", "expr": "bytes / 1048576"}]}],
        "sort": [{"field": "day"}],
        "fields": [out("day", t("Day", "Dia", "วัน"), "date", role="dimension"), out("files", t("Files", "Arquivos", "ไฟล์"), "integer"),
                   out("megabytes", t("Size", "Tamanho", "ขนาด"), "float", unit="MB", decimals=1)],
    },
    "uploads-per-week": {
        "title": t("Uploads per Week", "Envios por Semana", "การอัปโหลดต่อสัปดาห์"),
        "description": t("New files per ISO week.", "Novos arquivos por semana ISO.", "ไฟล์ใหม่ต่อสัปดาห์"),
        "source": "media_item", "filters": [APP_FILTER],
        "buckets": [{"field": "created_at", "unit": "week", "name": "week"}],
        "stages": [{"group_by": ["week"], "measures": [{"name": "files", "agg": "count"}]}],
        "sort": [{"field": "week"}],
        "fields": [out("week", t("Week", "Semana", "สัปดาห์"), "date", role="dimension"), out("files", t("Files", "Arquivos", "ไฟล์"), "integer")],
    },
    "albums-by-app": {
        "title": t("Albums by Application", "Álbuns por Aplicação", "อัลบั้มตามแอปพลิเคชัน"),
        "description": t("Distinct albums per application.", "Álbuns distintos por aplicação.", "จำนวนอัลบั้มที่ไม่ซ้ำของแต่ละแอปพลิเคชัน"),
        "source": "media_item",
        "stages": [{"group_by": ["app"], "measures": [{"name": "albums", "agg": "count_distinct", "field": "album"}]}],
        "sort": [{"field": "app"}],
        "fields": [APP, out("albums", t("Albums", "Álbuns", "อัลบั้ม"), "integer")],
    },
    "largest-by-app": {
        "title": t("Largest File", "Maior Arquivo", "ไฟล์ที่ใหญ่ที่สุด"),
        "description": t("Largest stored file per application.", "Maior arquivo armazenado por aplicação.", "ไฟล์ที่ใหญ่ที่สุดของแต่ละแอปพลิเคชัน"),
        "source": "media_item",
        "stages": [{"group_by": ["app"], "measures": [{"name": "largest", "agg": "max", "field": "size_bytes"}],
                    "derived": [{"name": "megabytes", "expr": "largest / 1048576"}]}],
        "sort": [{"field": "largest", "desc": True}],
        "fields": [APP, out("megabytes", t("Size", "Tamanho", "ขนาด"), "float", unit="MB", decimals=1)],
    },
}

REPORTS = [
    {"slug": "storage-usage", "title": t("Storage Usage", "Uso de Armazenamento", "การใช้พื้นที่จัดเก็บ"),
     "description": t("How much each application stores in FSM.", "Quanto cada aplicação armazena no FSM.", "แต่ละแอปพลิเคชันจัดเก็บข้อมูลใน FSM เท่าใด"),
     "tags": ["storage"], "period_field": "created_at", "cards": ["bytes-by-app", "files-by-type", "uploads-per-day"]},
    {"slug": "media-activity", "title": t("Media Activity", "Atividade de Mídia", "กิจกรรมสื่อ"),
     "description": t("New media files over time.", "Novos arquivos de mídia ao longo do tempo.", "ไฟล์สื่อใหม่ตามช่วงเวลา"),
     "tags": ["storage"], "period_field": "created_at", "cards": ["uploads-per-week", "albums-by-app", "largest-by-app"]},
]
