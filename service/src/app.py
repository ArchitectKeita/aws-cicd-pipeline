"""cicd-demo: the service the pipeline ships.

It's deliberately small. The point of Project 10 is HOW it gets to production, so the service's main
job is to report exactly which commit is live:

  GET /         a status page: version, commit, region and how it got there
  GET /health   JSON the pipeline's smoke test checks after every deploy
"""

from __future__ import annotations

import html
import json
import os

SERVICE = os.environ.get("SERVICE_NAME", "cicd-demo")


def info() -> dict:
    return {
        "service": SERVICE,
        "version": os.environ.get("APP_VERSION", "dev"),
        "commit": os.environ.get("COMMIT_SHA", "local"),
        "region": os.environ.get("AWS_REGION", "local"),
        "lambda_version": os.environ.get("AWS_LAMBDA_FUNCTION_VERSION", "$LATEST"),
    }


def healthy() -> bool:
    """False only when a deploy was built broken on purpose (the auto-rollback demo)."""
    return os.environ.get("SIMULATE_BAD_DEPLOY", "false").lower() != "true"


def _response(status: int, body: str, content_type: str) -> dict:
    return {
        "statusCode": status,
        "headers": {
            "content-type": content_type,
            "cache-control": "no-store",
            "x-content-type-options": "nosniff",
            "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'",
            "referrer-policy": "no-referrer",
        },
        "body": body,
    }


def health() -> dict:
    ok = healthy()
    return _response(200 if ok else 503, json.dumps({"ok": ok, **info()}), "application/json")


def page() -> dict:
    i = {k: html.escape(str(v)) for k, v in info().items()}
    short = i["commit"][:7]
    ok = healthy()
    status, color = ("OPERATIONAL", "#3fb950") if ok else ("DEGRADED", "#f85149")
    body = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>{i['service']} · {short}</title>
<style>
:root{{--bg:#0d1117;--card:#161b22;--line:#30363d;--fg:#e6edf3;--dim:#8b949e;--ok:{color}}}
*{{box-sizing:border-box}}body{{margin:0;min-height:100vh;display:grid;place-items:center;background:var(--bg);
color:var(--fg);font:15px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;padding:24px 16px}}
.card{{width:100%;max-width:560px;background:var(--card);border:1px solid var(--line);border-radius:12px;overflow:hidden}}
.top{{padding:20px 24px;border-bottom:1px solid var(--line);display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap}}
.dot{{display:inline-block;width:10px;height:10px;border-radius:50%;background:var(--ok);margin-right:8px;
box-shadow:0 0 12px var(--ok)}}dl{{margin:0;padding:12px 24px;display:grid;grid-template-columns:auto 1fr;gap:6px 20px}}
dt{{color:var(--dim)}}dd{{margin:0;word-break:break-all}}
.flow{{padding:16px 24px;border-top:1px solid var(--line);color:var(--dim);font-size:13px}}
</style></head><body><main class="card">
<div class="top"><strong>{i['service']}</strong><span><span class="dot"></span>{status}</span></div>
<dl><dt>commit</dt><dd>{i['commit']}</dd><dt>version</dt><dd>{i['version']}</dd>
<dt>lambda</dt><dd>v{i['lambda_version']} (alias: live)</dd><dt>region</dt><dd>{i['region']}</dd></dl>
<div class="flow">pull request &rarr; tests + security scan &rarr; plan &rarr; human approval &rarr; apply &rarr; smoke test &rarr; live
<br>No AWS keys exist anywhere: GitHub signs in with a 1-hour OIDC token.</div>
</main></body></html>"""
    return _response(200, body, "text/html; charset=utf-8")


def handler(event, context=None):
    path = (event or {}).get("rawPath") or "/"
    if path == "/health":
        return health()
    if path == "/":
        return page()
    return _response(404, json.dumps({"error": "not found"}), "application/json")
