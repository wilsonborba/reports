#!/usr/bin/env python3
"""Guest browser check of the Reports UI (issue #31).

Opens every public report of the catalog in headless Chrome as a guest (an empty
profile, so no session cookie) and records the network traffic through the Chrome
DevTools protocol. It fails when:

1. the page calls a session route (`/me`, `/me/...` or `/projects/{p}/reports/{r}...`),
2. the page asks for the rows of a card that the showcase did not open (any card
   request that does not answer 200),
3. a gated card of the showcase carries rows, a descriptor or a row count,
4. the page throws an exception or sends a client-error report to the telemetry.

Only the Python standard library is used: a small WebSocket client talks to Chrome,
so chromedriver and its version are not needed.

Usage:
  scripts/e2e/browser_check.py [--site https://reports.asodya.com]
                               [--api https://api.asodya.com/apps/reports/v1]
                               [--max-reports 10] [--page cortex/model-usage] [--report out.json]
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

SESSION_ROUTE = re.compile(r"^/me(/|$)|^/projects/[^/]+/reports/[^/]+")
SHOWCASE = re.compile(r"^/projects/(?P<p>[^/]+)/showcase/(?P<r>[^/]+)$")
CARD = re.compile(r"^/projects/(?P<p>[^/]+)/showcase/(?P<r>[^/]+)/cards/(?P<c>[^/]+)$")


class WebSocket:
    """Minimal RFC 6455 client: text frames, masking, fragments, ping and close."""

    def __init__(self, url: str, timeout: float = 30):
        u = urllib.parse.urlsplit(url)
        self.sock = socket.create_connection((u.hostname, u.port or 80), timeout=timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        path = u.path + (f"?{u.query}" if u.query else "")
        self.sock.sendall(
            (f"GET {path} HTTP/1.1\r\nHost: {u.hostname}:{u.port}\r\nUpgrade: websocket\r\n"
             f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode()
        )
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("WebSocket handshake closed")
            head += chunk
        if b" 101 " not in head.split(b"\r\n", 1)[0]:
            raise ConnectionError(head.decode(errors="replace"))
        self.buffer = head.split(b"\r\n\r\n", 1)[1]

    def _read(self, n: int) -> bytes:
        while len(self.buffer) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("WebSocket closed")
            self.buffer += chunk
        out, self.buffer = self.buffer[:n], self.buffer[n:]
        return out

    def _frame(self, opcode: int, payload: bytes) -> None:
        header = bytes([0x80 | opcode])
        n = len(payload)
        if n < 126:
            header += bytes([0x80 | n])
        elif n < 65536:
            header += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            header += bytes([0x80 | 127]) + struct.pack(">Q", n)
        mask = os.urandom(4)
        self.sock.sendall(header + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

    def send(self, text: str) -> None:
        self._frame(0x1, text.encode())

    def recv(self) -> str:
        message = b""
        while True:
            b0, b1 = self._read(2)
            opcode, n = b0 & 0x0F, b1 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._read(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._read(8))[0]
            mask = self._read(4) if b1 & 0x80 else None
            data = self._read(n)
            if mask:
                data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
            if opcode == 0x9:
                self._frame(0xA, data)
                continue
            if opcode == 0x8:
                raise ConnectionError("WebSocket closed by Chrome")
            message += data
            if b0 & 0x80:
                return message.decode()


class Chrome:
    """Headless Chrome with an empty profile and one attached page."""

    def __init__(self, binary: str):
        self.profile = tempfile.mkdtemp(prefix="reports-e2e-")
        self.proc = subprocess.Popen(
            [binary, "--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
             "--disable-extensions", f"--user-data-dir={self.profile}", "--remote-debugging-port=0",
             "--window-size=1440,1000", "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        port_file = os.path.join(self.profile, "DevToolsActivePort")
        for _ in range(100):
            if os.path.exists(port_file) and len(open(port_file).read().split()) >= 2:
                break
            time.sleep(0.1)
        port, path = open(port_file).read().split()[:2]
        self.ws = WebSocket(f"ws://127.0.0.1:{port}{path}")
        self.next_id = 0
        self.events: list[dict] = []
        target = self.call("Target.createTarget", {"url": "about:blank"})["targetId"]
        self.session = self.call("Target.attachToTarget", {"targetId": target, "flatten": True})["sessionId"]
        for domain in ["Network", "Page", "Runtime"]:
            self.call(f"{domain}.enable", session=True)

    def call(self, method: str, params: dict | None = None, session: bool = False) -> dict:
        self.next_id += 1
        msg = {"id": self.next_id, "method": method, "params": params or {}}
        if session:
            msg["sessionId"] = self.session
        self.ws.send(json.dumps(msg))
        while True:
            reply = json.loads(self.ws.recv())
            if reply.get("id") == self.next_id:
                if "error" in reply:
                    raise RuntimeError(f"{method}: {reply['error']}")
                return reply.get("result", {})
            self.events.append(reply)

    def pump(self, seconds: float) -> None:
        """Collects events for up to [seconds]."""
        end = time.time() + seconds
        self.ws.sock.settimeout(0.5)
        try:
            while time.time() < end:
                try:
                    self.events.append(json.loads(self.ws.recv()))
                except socket.timeout:
                    continue
        finally:
            self.ws.sock.settimeout(30)

    def close(self) -> None:
        self.proc.terminate()
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        shutil.rmtree(self.profile, ignore_errors=True)


# Cloudflare refuses the default Python user agent (error 1010).
USER_AGENT = "reports-e2e/1.0 (+https://reports.asodya.com)"


def get_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def public_reports(api: str, limit: int) -> list[tuple[str, str]]:
    out = []
    for project in get_json(f"{api}/catalog?lang=en&page_size=100")["items"]:
        listing = get_json(f"{api}/projects/{project['slug']}/reports?lang=en&page_size=100")
        out += [(project["slug"], r["slug"]) for r in listing["items"] if r.get("can_view", True)]
    return out[:limit]


def check_page(chrome: Chrome, site: str, api: str, project: str, report: str, settle: float) -> dict:
    api_path = urllib.parse.urlsplit(api).path
    chrome.events.clear()
    url = f"{site}/v1/menu/{project}/{report}"
    chrome.call("Page.navigate", {"url": url}, session=True)
    # Wait until the network is quiet for [settle] seconds (at most 60 s).
    start, last_count, quiet_since = time.time(), -1, time.time()
    while time.time() - start < 60:
        chrome.pump(1)
        count = sum(1 for e in chrome.events if e.get("method", "").startswith("Network."))
        if count != last_count:
            last_count, quiet_since = count, time.time()
        elif time.time() - quiet_since >= settle and count > 0:
            break

    requests: dict[str, dict] = {}
    problems: list[str] = []
    for e in chrome.events:
        m, p = e.get("method"), e.get("params", {})
        if m == "Network.requestWillBeSent":
            requests[p["requestId"]] = {"url": p["request"]["url"], "method": p["request"]["method"], "post": p["request"].get("postData")}
        elif m == "Network.responseReceived" and p["requestId"] in requests:
            requests[p["requestId"]]["status"] = p["response"]["status"]
        elif m == "Network.loadingFailed" and p["requestId"] in requests:
            requests[p["requestId"]].setdefault("status", 0)
        elif m == "Runtime.exceptionThrown":
            problems.append(f"exception: {p['exceptionDetails'].get('text')} {p['exceptionDetails'].get('exception', {}).get('description', '')}"[:300])

    api_calls, readable = [], None
    for rid, r in requests.items():
        u = urllib.parse.urlsplit(r["url"])
        if u.path.endswith("/client-error"):
            problems.append(f"telemetry report sent: {(r.get('post') or '')[:200]}")
            continue
        if not r["url"].startswith(api) or r["method"] == "OPTIONS":
            continue
        path = u.path[len(api_path):]
        api_calls.append(f"{r['method']} {path} -> {r.get('status')}")
        if SESSION_ROUTE.search(path):
            problems.append(f"guest called a session route: {path}")
        if SHOWCASE.match(path) and r.get("status") == 200:
            body = chrome.call("Network.getResponseBody", {"requestId": rid}, session=True)
            text = base64.b64decode(body["body"]).decode() if body.get("base64Encoded") else body["body"]
            showcase = json.loads(text)
            readable = set()
            for c in showcase.get("cards", []):
                if c.get("can_view"):
                    readable.add(c["dataset_id"])
                elif any(c.get(k) is not None for k in ("rows", "descriptor", "total_rows")):
                    problems.append(f"gated card {c['dataset_id']} carries data")
    for call in api_calls:
        method, path, _, status = call.split(" ", 3)
        m = CARD.match(path.split("?")[0])
        if m:
            if status != "200":
                problems.append(f"guest asked for protected rows: {call}")
            elif readable is not None and m["c"] not in readable:
                problems.append(f"card outside the readable set: {call}")
    if readable is None:
        problems.append("no showcase answer was seen")
    return {"page": url, "readable_cards": sorted(readable or []), "api_calls": sorted(set(api_calls)), "problems": problems}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", default=os.environ.get("REPORTS_SITE_URL", "https://reports.asodya.com"))
    ap.add_argument("--api", default=os.environ.get("REPORTS_GATEWAY_URL", "https://api.asodya.com/apps/reports/v1"))
    ap.add_argument("--chrome", default=shutil.which("google-chrome") or shutil.which("chromium") or "google-chrome")
    ap.add_argument("--max-reports", type=int, default=10)
    ap.add_argument("--settle", type=float, default=4.0, help="seconds of network quiet before a page counts as loaded")
    ap.add_argument("--page", action="append", default=[], metavar="PROJECT/REPORT", help="check only these reports (repeatable)")
    ap.add_argument("--report", help="write the JSON result to this file")
    args = ap.parse_args()

    pages = [tuple(p.split("/", 1)) for p in args.page] or public_reports(args.api.rstrip("/"), args.max_reports)
    if not pages:
        print("No public report in the catalog.", file=sys.stderr)
        return 1
    chrome = Chrome(args.chrome)
    results = []
    try:
        for project, report in pages:
            r = check_page(chrome, args.site.rstrip("/"), args.api.rstrip("/"), project, report, args.settle)
            results.append(r)
            state = "ok" if not r["problems"] else "FAIL"
            print(f"[{state}] {r['page']} readable={len(r['readable_cards'])} calls={len(r['api_calls'])}")
            for p in r["problems"]:
                print(f"    {p}")
    finally:
        chrome.close()
    if args.report:
        with open(args.report, "w") as f:
            json.dump(results, f, indent=2)
    failed = [r for r in results if r["problems"]]
    print(f"Browser check: {len(results) - len(failed)} of {len(results)} pages clean.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
