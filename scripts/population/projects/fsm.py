"""FSM sample data. Fields of `MediaItem` in fsm/src/domain/models/media_models.py."""

from __future__ import annotations

import hashlib
import random

from .builder import build, chart, dim, measure
from .common import at, days, field, t, weighted

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


SRC = "media_item"
APP_FILTER = {"field": "app", "label": t("App", "App", "แอป"), "type": "category"}
F = [APP_FILTER]


def kind(prefix: str) -> list:
    return [{"field": "content_type", "op": "starts_with", "value": prefix}]


DAY = dim("day", t("Day", "Dia", "วัน"), field="created_at", unit="day", per=t("Day", "Dia", "วัน"))
WEEK = dim("week", t("Week", "Semana", "สัปดาห์"), field="created_at", unit="week", per=t("Week", "Semana", "สัปดาห์"))
APP = dim("app", t("App", "App", "แอป"))
ALBUM = dim("album", t("Album", "Álbum", "อัลบั้ม"))
TYPE = dim("content_type", t("File type", "Tipo de arquivo", "ประเภทไฟล์"))

FILES = measure("files", t("Files", "Arquivos", "ไฟล์"), "count", about=t("Stored files", "Arquivos armazenados", "ไฟล์ที่จัดเก็บ"))
BYTES = measure("bytes", t("Storage", "Armazenamento", "พื้นที่จัดเก็บ"), "sum", "size_bytes", unit="bytes",
                about=t("Bytes of the stored files", "Bytes dos arquivos armazenados", "ขนาดไบต์ของไฟล์ที่จัดเก็บ"))
SHARE = measure("share", t("Share", "Participação", "สัดส่วน"), expr="bytes / sum_bytes * 100", type_="percent", decimals=1)
FILE_SHARE = measure("file_share", t("Share", "Participação", "สัดส่วน"), expr="files / sum_files * 100", type_="percent", decimals=1)
MEAN_SIZE = measure("mean_size", t("Mean file size", "Tamanho médio", "ขนาดไฟล์เฉลี่ย"), "avg", "size_bytes", type_="float", unit="bytes", decimals=0)
LARGEST = measure("largest", t("Largest file", "Maior arquivo", "ไฟล์ใหญ่ที่สุด"), "max", "size_bytes", unit="bytes")
SMALLEST = measure("smallest", t("Smallest file", "Menor arquivo", "ไฟล์เล็กที่สุด"), "min", "size_bytes", unit="bytes")
IMAGES = measure("images", t("Images", "Imagens", "รูปภาพ"), "count", where=kind("image/"), about=t("Stored images", "Imagens armazenadas", "รูปภาพที่จัดเก็บ"))
IMAGE_BYTES = measure("image_bytes", t("Image storage", "Armazenamento de imagens", "พื้นที่ของรูปภาพ"), "sum", "size_bytes", unit="bytes", where=kind("image/"))
PDFS = measure("pdfs", t("PDF documents", "Documentos PDF", "เอกสาร PDF"), "count", where=kind("application/pdf"))
PDF_BYTES = measure("pdf_bytes", t("PDF storage", "Armazenamento de PDF", "พื้นที่ของ PDF"), "sum", "size_bytes", unit="bytes", where=kind("application/pdf"))
VIDEOS = measure("videos", t("Videos", "Vídeos", "วิดีโอ"), "count", where=kind("video/"), about=t("Stored videos", "Vídeos armazenados", "วิดีโอที่จัดเก็บ"))
VIDEO_BYTES = measure("video_bytes", t("Video storage", "Armazenamento de vídeos", "พื้นที่ของวิดีโอ"), "sum", "size_bytes", unit="bytes", where=kind("video/"))
_ALL = measure("all_files", t("Files", "Arquivos", "ไฟล์"), "count")
_IMG = measure("image_files", t("Images", "Imagens", "รูปภาพ"), "count", where=kind("image/"))
_PDF = measure("pdf_files", t("PDF documents", "Documentos PDF", "เอกสาร PDF"), "count", where=kind("application/pdf"))
_VID = measure("video_files", t("Videos", "Vídeos", "วิดีโอ"), "count", where=kind("video/"))
IMAGE_SHARE = measure("image_share", t("Image share", "Parcela de imagens", "สัดส่วนรูปภาพ"), expr="image_files / all_files * 100",
                      type_="percent", decimals=1, needs=(_ALL, _IMG), about=t("Share of files that are images", "Parcela dos arquivos que são imagens", "สัดส่วนไฟล์ที่เป็นรูปภาพ"))
PDF_SHARE = measure("pdf_share", t("PDF share", "Parcela de PDF", "สัดส่วน PDF"), expr="pdf_files / all_files * 100",
                    type_="percent", decimals=1, needs=(_ALL, _PDF), about=t("Share of files that are PDF", "Parcela dos arquivos em PDF", "สัดส่วนไฟล์ที่เป็น PDF"))
VIDEO_SHARE = measure("video_share", t("Video share", "Parcela de vídeos", "สัดส่วนวิดีโอ"), expr="video_files / all_files * 100",
                      type_="percent", decimals=1, needs=(_ALL, _VID), about=t("Share of files that are videos", "Parcela dos arquivos que são vídeos", "สัดส่วนไฟล์ที่เป็นวิดีโอ"))
APPS_ = measure("apps", t("Apps in use", "Apps em uso", "แอปที่ใช้"), "count_distinct", "app", about=t("Distinct apps", "Apps distintos", "แอปที่ไม่ซ้ำ"))
ALBUMS = measure("albums", t("Albums in use", "Álbuns em uso", "อัลบั้มที่ใช้"), "count_distinct", "album", about=t("Distinct albums", "Álbuns distintos", "อัลบั้มที่ไม่ซ้ำ"))
TYPES_IN_USE = measure("types", t("File types in use", "Tipos de arquivo em uso", "ประเภทไฟล์ที่ใช้"), "count_distinct", "content_type",
                about=t("Distinct file types", "Tipos de arquivo distintos", "ประเภทไฟล์ที่ไม่ซ้ำ"))


def c(measures, dims=(), **kw):
    return chart(SRC, measures, dims, filters=kw.pop("filters", F), **kw)


CALCULATIONS, REPORTS = build([
    {"slug": "storage-usage", "title": t("Storage Usage", "Uso de Armazenamento", "การใช้พื้นที่จัดเก็บ"),
     "description": t("Bytes and files that each app keeps in FSM.", "Bytes e arquivos que cada app guarda no FSM.", "ขนาดและจำนวนไฟล์ที่แต่ละแอปเก็บใน FSM"),
     "tags": ["storage"], "period_field": "created_at",
     "sections": [
         [("total-storage", c([BYTES], warm=True)), ("storage-per-day", c([BYTES], [DAY], warm=True)),
          ("storage-by-app", c([BYTES, SHARE], [APP])), ("storage-by-type", c([BYTES], [TYPE]))],
         [("total-files", c([FILES])), ("files-per-day", c([FILES], [DAY])),
          ("files-by-app", c([FILES], [APP])), ("files-by-type", c([FILES], [TYPE]))],
         [("mean-file-size", c([MEAN_SIZE])), ("mean-size-by-app", c([MEAN_SIZE], [APP])),
          ("mean-size-by-type", c([MEAN_SIZE], [TYPE])), ("mean-size-per-day", c([MEAN_SIZE], [DAY]))],
         [("storage-per-week", c([BYTES], [WEEK])), ("files-per-week", c([FILES], [WEEK])),
          ("storage-per-week-by-app", c([BYTES], [WEEK, APP])), ("storage-summary-by-app", c([FILES, BYTES, MEAN_SIZE, LARGEST], [APP]))],
     ]},
    {"slug": "media-activity", "title": t("Media Activity", "Atividade de Mídia", "กิจกรรมสื่อ"),
     "description": t("Albums, images, documents and videos that the apps store.", "Álbuns, imagens, documentos e vídeos que os apps guardam.", "อัลบั้ม รูปภาพ เอกสาร และวิดีโอที่แอปจัดเก็บ"),
     "tags": ["storage", "media"], "period_field": "created_at",
     "access": {"cards": {"images-per-day": "signed_in", "pdf-per-day": "signed_in", "largest-by-app": "restricted"}, "hidden": ["largest-by-app"]},
     "sections": [
         [("albums-in-use", c([ALBUMS])), ("files-by-album", c([FILES], [ALBUM])),
          ("storage-by-album", c([BYTES], [ALBUM])), ("files-per-day-by-album", c([FILES], [DAY, ALBUM]))],
         [("images", c([IMAGES])), ("images-per-day", c([IMAGES], [DAY])),
          ("images-by-app", c([IMAGES], [APP])), ("image-storage-by-app", c([IMAGE_BYTES], [APP]))],
         [("pdf-documents", c([PDFS])), ("pdf-per-day", c([PDFS], [DAY])),
          ("pdf-by-app", c([PDFS], [APP])), ("pdf-storage-by-app", c([PDF_BYTES], [APP]))],
         [("videos", c([VIDEOS])), ("videos-per-week", c([VIDEOS], [WEEK])),
          ("video-storage-by-app", c([VIDEO_BYTES], [APP])), ("largest-by-app", c([LARGEST], [APP]))],
     ]},
    {"slug": "file-types", "title": t("File Types", "Tipos de Arquivo", "ประเภทไฟล์"),
     "description": t("Sizes and volume of each stored file type.", "Tamanhos e volume de cada tipo de arquivo armazenado.", "ขนาดและปริมาณของไฟล์แต่ละประเภทที่จัดเก็บ"),
     "tags": ["storage", "types"], "period_field": "created_at", "access": {"report": "signed_in"},
     "sections": [
         [("file-types-in-use", c([TYPES_IN_USE])), ("files-per-day-by-type", c([FILES], [DAY, TYPE])),
          ("storage-per-day-by-type", c([BYTES], [DAY, TYPE])), ("type-summary", c([FILES, BYTES, MEAN_SIZE, LARGEST], [TYPE]))],
         [("largest-file", c([LARGEST])), ("largest-by-type", c([LARGEST], [TYPE])),
          ("largest-per-day", c([LARGEST], [DAY])), ("largest-by-album", c([LARGEST], [ALBUM]))],
         [("smallest-file", c([SMALLEST])), ("smallest-by-type", c([SMALLEST], [TYPE])),
          ("smallest-by-app", c([SMALLEST], [APP])), ("smallest-per-week", c([SMALLEST], [WEEK]))],
         [("type-share-of-storage", c([BYTES, SHARE], [TYPE])), ("files-by-app-and-type", c([FILES, BYTES], [APP, TYPE])),
          ("storage-per-week-by-type", c([BYTES], [WEEK, TYPE])), ("files-per-week-by-type", c([FILES], [WEEK, TYPE]))],
     ]},
    {"slug": "apps", "title": t("Apps", "Apps", "แอป"),
     "description": t("How each Asodya app uses FSM: albums, file mix and growth.", "Como cada app Asodya usa o FSM: álbuns, tipos de arquivo e crescimento.", "แต่ละแอป Asodya ใช้ FSM อย่างไร: อัลบั้ม ประเภทไฟล์ และการเติบโต"),
     "tags": ["storage", "apps"], "period_field": "created_at",
     "access": {"cards": {"apps-summary": "restricted"}},
     "sections": [
         [("apps-in-use", c([APPS_])), ("files-per-week-by-app", c([FILES], [WEEK, APP])),
          ("file-share-by-app", c([FILES, FILE_SHARE], [APP])), ("mean-size-per-week", c([MEAN_SIZE], [WEEK]))],
         [("files-by-app-and-album", c([FILES, BYTES], [APP, ALBUM])), ("files-per-day-by-app", c([FILES], [DAY, APP])),
          ("storage-per-day-by-app", c([BYTES], [DAY, APP])), ("storage-by-app-and-type", c([BYTES], [APP, TYPE]))],
         [("image-share", c([IMAGE_SHARE])), ("image-share-by-app", c([IMAGE_SHARE], [APP])),
          ("pdf-share-by-app", c([PDF_SHARE], [APP])), ("video-share-by-app", c([VIDEO_SHARE], [APP]))],
         [("largest-per-week", c([LARGEST], [WEEK])), ("files-per-week-by-album", c([FILES], [WEEK, ALBUM])),
          ("albums-by-app", c([ALBUMS], [APP])), ("apps-summary", c([FILES, BYTES, IMAGES, PDFS], [APP]))],
     ]},
])
