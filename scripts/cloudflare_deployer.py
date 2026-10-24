"""Reuse the workspace's established Cloudflare Pages API deployer.

The other Asodya web projects keep one implementation of the Pages upload
protocol. This adapter lets reports use the same implementation without
requiring Wrangler or Node.js on the deployment machine.
"""
from __future__ import annotations

import importlib.util
import json
import os
import time
from pathlib import Path
from urllib.request import Request, urlopen


def _load_deployer():
    candidates = (
        Path(__file__).resolve().parents[2] / "domain" / "scripts" / "cloudflare_deployer.py",
        Path(__file__).resolve().parents[2] / "certifications" / "scripts" / "cloudflare_deployer.py",
    )
    for path in candidates:
        if path.is_file() and path.resolve() != Path(__file__).resolve():
            spec = importlib.util.spec_from_file_location("asodya_shared_cloudflare_deployer", path)
            if spec is None or spec.loader is None:
                continue
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module
    raise RuntimeError("Could not find the shared Asodya Cloudflare Pages deployer.")


_shared = _load_deployer()


def _cloudflare_request(method: str, path: str, payload: dict | None = None) -> dict:
    account_email = os.environ["CLOUDFLARE_EMAIL"]
    api_key = os.environ["CLOUDFLARE_API_KEY"]
    body = json.dumps(payload).encode() if payload is not None else None
    headers = {
        "X-Auth-Email": account_email,
        "X-Auth-Key": api_key,
        "Content-Type": "application/json",
    }
    request = Request(
        f"https://api.cloudflare.com/client/v4{path}",
        data=body,
        headers=headers,
        method=method,
    )
    with urlopen(request, timeout=30) as response:
        result = json.loads(response.read().decode("utf-8"))
    if not result.get("success"):
        raise RuntimeError(f"Cloudflare API request failed: {method} {path}")
    return result


def _ensure_pages_dns(project_name: str, custom_domain: str, *, proxied: bool) -> None:
    if "." not in custom_domain:
        raise RuntimeError(f"Custom domain is not a DNS name: {custom_domain}")

    zone_name = custom_domain.split(".", 1)[1]
    zones = _cloudflare_request("GET", f"/zones?name={zone_name}&status=active")["result"]
    if not zones:
        raise RuntimeError(f"Cloudflare zone not found for {custom_domain}")
    zone_id = zones[0]["id"]
    target = f"{project_name}.pages.dev"
    records = _cloudflare_request(
        "GET", f"/zones/{zone_id}/dns_records?name={custom_domain}"
    )["result"]
    payload = {
        "type": "CNAME",
        "name": custom_domain,
        "content": target,
        "ttl": 1,
        "proxied": proxied,
    }
    if records:
        record = records[0]
        if record["type"] != "CNAME" or record["content"] != target or not record.get("proxied"):
            _cloudflare_request("PUT", f"/zones/{zone_id}/dns_records/{record['id']}", payload)
    else:
        _cloudflare_request("POST", f"/zones/{zone_id}/dns_records", payload)
    print(f"DNS ensured: {custom_domain} -> {target} (proxied={proxied})")


def _wait_for_pages_domain(project_name: str, custom_domain: str, timeout: int = 90) -> bool:
    endpoint = f"/accounts/{os.environ['CLOUDFLARE_ACCOUNT_ID']}/pages/projects/{project_name}/domains"
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        domains = _cloudflare_request("GET", endpoint)["result"]
        match = next((d for d in domains if d.get("name") == custom_domain), None)
        if match and match.get("status") == "active":
            return True
        time.sleep(5)
    return False


def deploy_pages_project(project_name, build_dir, custom_domain=None, branch="main", timestamp_str=None):
    if custom_domain:
        # Pages must see an unproxied CNAME while it provisions/verifies its
        # certificate. Proxy it only after the custom domain becomes active.
        _ensure_pages_dns(project_name, custom_domain, proxied=False)
    _shared.deploy_pages_project(
        project_name,
        build_dir,
        custom_domain=custom_domain,
        branch=branch,
        timestamp_str=timestamp_str,
    )
    if custom_domain:
        if _wait_for_pages_domain(project_name, custom_domain):
            _ensure_pages_dns(project_name, custom_domain, proxied=True)
        else:
            raise RuntimeError(f"Cloudflare Pages custom domain did not become active: {custom_domain}")
