import json

import pytest

import app


@pytest.fixture(autouse=True)
def env(monkeypatch):
    monkeypatch.setenv("COMMIT_SHA", "abc1234def5678")
    monkeypatch.setenv("APP_VERSION", "1.0.0")
    monkeypatch.setenv("AWS_REGION", "us-east-2")
    monkeypatch.delenv("SIMULATE_BAD_DEPLOY", raising=False)


def get(path):
    return app.handler({"rawPath": path})


def test_health_reports_the_live_commit():
    r = get("/health")
    body = json.loads(r["body"])
    assert r["statusCode"] == 200
    assert body["ok"] is True and body["commit"] == "abc1234def5678" and body["version"] == "1.0.0"


def test_status_page_shows_commit_and_is_locked_down():
    r = get("/")
    assert r["statusCode"] == 200 and "abc1234def5678" in r["body"] and "OPERATIONAL" in r["body"]
    h = r["headers"]
    assert "frame-ancestors 'none'" in h["content-security-policy"]
    assert h["x-content-type-options"] == "nosniff" and h["cache-control"] == "no-store"


def test_a_bad_build_fails_its_health_check(monkeypatch):
    monkeypatch.setenv("SIMULATE_BAD_DEPLOY", "true")
    assert get("/health")["statusCode"] == 503
    assert "DEGRADED" in get("/")["body"]


def test_unknown_paths_are_404():
    assert get("/admin")["statusCode"] == 404


def test_values_are_html_escaped(monkeypatch):
    monkeypatch.setenv("COMMIT_SHA", "<script>alert(1)</script>")
    body = get("/")["body"]
    assert "<script>alert" not in body and "&lt;script&gt;" in body


def test_missing_event_falls_back_to_status_page():
    assert app.handler(None)["statusCode"] == 200
