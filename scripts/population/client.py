"""Small HTTP client for the Reports engine admin API (standard library only).

The scripts call the engine directly on this host with the service key, like every
local operator tool: http://127.0.0.1:8109 and the header x-reports-service-key.
"""

from __future__ import annotations

import json
import os
import pathlib
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]


def load_env() -> dict[str, str]:
    """Values of the repository .env (the process environment wins)."""
    values: dict[str, str] = {}
    env_file = ROOT / ".env"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                values[key.strip()] = value.strip().strip('"').strip("'")
    values.update({k: v for k, v in os.environ.items() if k.startswith(("REPORTS_", "SERVER_"))})
    return values


class EngineError(RuntimeError):
    def __init__(self, status: int, method: str, path: str, body: str):
        super().__init__(f"{method} {path} returned {status}: {body[:600]}")
        self.status = status


class Engine:
    #: When set (by --dump), requests are appended here instead of being sent.
    recorder: list | None = None

    def __init__(self, fixture: str | None = None, dry_run: bool = False):
        env = load_env()
        if Engine.recorder is not None:
            env.setdefault("REPORTS_SERVICE_API_KEY", "dump")
        self.base = env.get("REPORTS_ENGINE_URL") or f"http://127.0.0.1:{env.get('SERVER_PORT', '8109')}"
        self.key = env.get("REPORTS_SERVICE_API_KEY", "")
        if not self.key:
            raise SystemExit("REPORTS_SERVICE_API_KEY is missing in .env")
        self.fixture = fixture
        self.dry_run = dry_run
        self.writes = 0

    def request(self, method: str, path: str, body=None, fixture: bool = True):
        if Engine.recorder is not None:
            Engine.recorder.append({"method": method, "path": path, "body": body,
                                    "fixture": self.fixture if fixture and method != "GET" else None})
            if method == "GET":
                return [] if path.startswith("/admin/") else {}
            return {"version": 1}
        if self.dry_run and method != "GET":
            self.writes += 1
            print(f"  [dry run] {method} {path}")
            return {}
        headers = {"x-reports-service-key": self.key, "Accept": "application/json"}
        if fixture and self.fixture and method != "GET":
            headers["x-reports-fixture"] = self.fixture
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(self.base + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                raw = response.read()
                self.writes += method != "GET"
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            raise EngineError(error.code, method, path, error.read().decode(errors="replace")) from None
        except urllib.error.URLError as error:
            raise SystemExit(f"The engine does not answer at {self.base}: {error.reason}") from None

    def get(self, path: str):
        return self.request("GET", path)

    def health(self) -> dict:
        return self.get("/health")
