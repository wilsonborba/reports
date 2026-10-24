/// Request and answer examples with the real Reports paths (the values are sample data).
library;

/// A guest reads three rows of a public card through the gateway.
const String datasetRequestShell = '''# Three rows of a public card, English labels
curl -s "https://api.asodya.com/apps/reports/v1/projects/cortex/showcase/model-usage/cards/tokens-per-day?lang=en&limit=3"''';

/// The same request in Python.
const String datasetPythonShell = '''# Read a public Reports card with Python
import requests

URL = "https://api.asodya.com/apps/reports/v1/projects/cortex/showcase/model-usage"
res = requests.get(
    f"{URL}/cards/tokens-per-day",
    params={"lang": "en", "limit": 3, "f.provider": "ollama"},
    timeout=30,
).json()

for row in res.get("rows", []):
    print(f"{row['day']}: {row['input_tokens']} in, {row['output_tokens']} out")''';

/// The answer (sample data).
const String datasetResponseJson = '''{
  "dataset_id": "tokens-per-day",
  "title": "Tokens per Day",
  "data_tier": "sample",
  "visibility": "public",
  "fields": [
    { "name": "day", "label": "Day",
      "type": "date", "role": "dimension" },
    { "name": "input_tokens", "label": "Input",
      "type": "integer", "role": "measure", "unit": "tokens" }
  ],
  "rows": [
    { "day": "2026-10-01", "input_tokens": 48211, "output_tokens": 15902 },
    { "day": "2026-10-02", "input_tokens": 51377, "output_tokens": 17045 },
    { "day": "2026-10-03", "input_tokens": 44890, "output_tokens": 14388 }
  ],
  "total_rows": 30,
  "lineage": { "calculation_id": "tokens-per-day", "calculation_version": 1 }
}''';

/// A producer sends records of a published schema version (on the engine host).
const String ingestRequestShell = '''# One batch of cortex telemetry records (service key on the engine host)
curl -s -X POST "http://localhost:8109/projects/cortex/admin/ingest/telemetry_event" \\
  -H "x-reports-service-key: <service-key>" \\
  -H "Content-Type: application/json" \\
  -d '{"schema_version": 1, "records": [{"idempotency_key": "req-00001",
       "payload": {"request_id": "req-00001", "provider": "ollama", "total_tokens": 1052}}]}\'''';
