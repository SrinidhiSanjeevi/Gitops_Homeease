#!/usr/bin/env python3
"""DORA metrics exporter for HomeEase.

Reads real delivery history from Azure DevOps (all pipelines, branch main) and GitHub Actions
(branch main), computes the four DORA metrics over a rolling window and serves them as Prometheus
metrics on :9102/metrics. No third-party dependencies.

Definitions (a "deployment" = a completed pipeline run on main; main only runs the full
Package -> Promote -> Verify flow):
  deployment frequency  successful runs per day
  lead time for changes median(run finish - commit time) of successful runs
  change failure rate   failed / (failed + succeeded) * 100
  time to restore       mean(time from a failed run to the next successful run), resolved incidents only

Env: ADO_ORG, ADO_PROJECT, ADO_PAT (read-only "Build: Read" scope), GH_REPO ("owner/repo"),
     GH_TOKEN (optional; the repo is public), WINDOW_DAYS (default 30), REFRESH_SECONDS (default 300).
"""
import base64
import json
import os
import statistics
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer


def parse_ts(value):
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc).timestamp()


def compute_dora(runs, now, window_days=30):
    """runs: list of {finish, start, commit, ok} for completed, non-cancelled runs (any order)."""
    runs = sorted(runs, key=lambda r: r["finish"])
    window_start = now - window_days * 86400
    win = [r for r in runs if r["finish"] >= window_start]
    ok = [r for r in win if r["ok"]]
    bad = [r for r in win if not r["ok"]]
    out = {"success": len(ok), "failed": len(bad)}

    if win:
        span_days = max(1.0, min(window_days, (now - win[0]["finish"]) / 86400))
        out["frequency_per_day"] = len(ok) / span_days
    lead = [r["finish"] - r["commit"] for r in ok if r.get("commit") and r["finish"] >= r["commit"]]
    if lead:
        out["lead_time_seconds"] = statistics.median(lead)
    if win:
        out["change_failure_rate"] = 100.0 * len(bad) / len(win)
    durations = [r["finish"] - r["start"] for r in win if r.get("start") and r["finish"] >= r["start"]]
    if durations:
        out["duration_seconds"] = statistics.median(durations)

    # Time to restore: each failure streak ends at the next success.
    restores, failing_since = [], None
    for r in runs:
        if not r["ok"] and failing_since is None:
            failing_since = r["finish"]
        elif r["ok"] and failing_since is not None:
            if r["finish"] >= window_start:
                restores.append(r["finish"] - failing_since)
            failing_since = None
    if restores:
        out["mttr_seconds"] = statistics.mean(restores)
    out["open_incident"] = 1 if runs and not runs[-1]["ok"] else 0
    successes = [r for r in runs if r["ok"]]
    if successes:
        out["last_success_ts"] = successes[-1]["finish"]
    return out


def render(results, errors, refreshed):
    lines = []

    def gauge(name, help_text, series):
        lines.append(f"# HELP {name} {help_text}")
        lines.append(f"# TYPE {name} gauge")
        lines.extend(series)

    def per_pipeline(key):
        return [f'{{pipeline="{p}"}} {v[key]}' for p, v in sorted(results.items()) if key in v]

    gauge("dora_deployments_window", "Completed runs on main in the window, by result", [
        f'dora_deployments_window{{pipeline="{p}",result="{res}"}} {v[res]}'
        for p, v in sorted(results.items()) for res in ("success", "failed")])
    for metric, key, text in [
        ("dora_deployment_frequency_per_day", "frequency_per_day", "Successful deployments per day"),
        ("dora_lead_time_seconds", "lead_time_seconds", "Median commit-to-deployed time"),
        ("dora_change_failure_rate_percent", "change_failure_rate", "Percent of runs on main that failed"),
        ("dora_mttr_seconds", "mttr_seconds", "Mean time from a failed run to the next success"),
        ("dora_pipeline_duration_seconds", "duration_seconds", "Median pipeline run duration"),
        ("dora_open_incident", "open_incident", "1 if the latest run on main failed"),
        ("dora_last_success_timestamp_seconds", "last_success_ts", "Unix time of the last successful run"),
    ]:
        gauge(metric, text, [f"{metric}{s}" for s in per_pipeline(key)])
    gauge("dora_exporter_errors", "Fetch errors on the last refresh, by source",
          [f'dora_exporter_errors{{source="{s}"}} {n}' for s, n in sorted(errors.items())])
    gauge("dora_exporter_last_refresh_timestamp_seconds", "Unix time of the last refresh", [
        f"dora_exporter_last_refresh_timestamp_seconds {refreshed}"])
    return "\n".join(lines) + "\n"


def http_json(url, headers):
    req = urllib.request.Request(url, headers={"User-Agent": "homeease-dora-exporter", **headers})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"HTTP {exc.code} from {urllib.parse.urlparse(url).netloc} (check the token and its scope)") from exc
    try:
        return json.loads(raw)
    except ValueError as exc:
        # Azure DevOps answers an invalid/expired PAT with an HTML sign-in page and HTTP 200.
        raise RuntimeError(f"{urllib.parse.urlparse(url).netloc} did not return JSON - the token is probably invalid or expired") from exc


def fetch_ado(org, project, pat, window_days, now):
    token = base64.b64encode(f":{pat}".encode()).decode()
    since = datetime.fromtimestamp(now - window_days * 86400 - 7 * 86400, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    query = urllib.parse.urlencode({
        "branchName": "refs/heads/main", "statusFilter": "completed", "minTime": since,
        "queryOrder": "finishTimeAscending", "$top": "500", "api-version": "7.1"})
    url = f"https://dev.azure.com/{org}/{project}/_apis/build/builds?{query}"
    builds = http_json(url, {"Authorization": f"Basic {token}"}).get("value", [])
    return builds


def commit_time(repo, sha, gh_token, cache):
    if sha in cache:
        return cache[sha]
    headers = {"Authorization": f"Bearer {gh_token}"} if gh_token else {}
    try:
        data = http_json(f"https://api.github.com/repos/{repo}/commits/{sha}", headers)
        cache[sha] = parse_ts(data["commit"]["committer"]["date"])
    except (urllib.error.URLError, RuntimeError, KeyError, ValueError):
        cache[sha] = None
    return cache[sha]


def ado_runs(builds, repo, gh_token, cache):
    by_pipeline = {}
    for b in builds:
        if b.get("result") not in ("succeeded", "failed", "partiallySucceeded"):
            continue  # skip cancelled
        finish = parse_ts(b.get("finishTime"))
        if finish is None:
            continue
        queued = parse_ts(b.get("queueTime"))
        commit = commit_time(repo, b.get("sourceVersion", ""), gh_token, cache) if repo else None
        by_pipeline.setdefault(f"azure-devops/{b['definition']['name']}", []).append({
            "finish": finish, "start": parse_ts(b.get("startTime")) or queued,
            "commit": commit or queued, "ok": b["result"] == "succeeded"})
    return by_pipeline


def fetch_github(repo, gh_token, window_days, now):
    headers = {"Authorization": f"Bearer {gh_token}"} if gh_token else {}
    since = datetime.fromtimestamp(now - window_days * 86400 - 7 * 86400, timezone.utc).strftime("%Y-%m-%d")
    runs = http_json(f"https://api.github.com/repos/{repo}/actions/runs?branch=main&event=push"
                     f"&status=completed&per_page=100&created=%3E{since}", headers).get("workflow_runs", [])
    by_pipeline = {}
    for r in runs:
        if r.get("conclusion") not in ("success", "failure"):
            continue
        finish = parse_ts(r["updated_at"])
        by_pipeline.setdefault(f"github-actions/{r['name']}", []).append({
            "finish": finish, "start": parse_ts(r.get("run_started_at")),
            "commit": parse_ts(r["head_commit"]["timestamp"]) if r.get("head_commit") else parse_ts(r["created_at"]),
            "ok": r["conclusion"] == "success"})
    return by_pipeline


class State:
    def __init__(self):
        self.body = "# not ready\n"
        self.lock = threading.Lock()


def refresh(state, cfg, cache):
    now = time.time()
    runs, errors = {}, {"azure-devops": 0, "github-actions": 0}
    if cfg["ado_pat"]:
        try:
            runs.update(ado_runs(fetch_ado(cfg["ado_org"], cfg["ado_project"], cfg["ado_pat"], cfg["window"], now),
                                 cfg["gh_repo"], cfg["gh_token"], cache))
        except Exception as exc:  # noqa: BLE001 - keep serving the other source
            errors["azure-devops"] = 1
            print(f"azure-devops fetch failed: {exc}", flush=True)
    if cfg["gh_repo"]:
        try:
            runs.update(fetch_github(cfg["gh_repo"], cfg["gh_token"], cfg["window"], now))
        except Exception as exc:  # noqa: BLE001
            errors["github-actions"] = 1
            print(f"github-actions fetch failed: {exc}", flush=True)
    results = {p: compute_dora(r, now, cfg["window"]) for p, r in runs.items()}
    with state.lock:
        state.body = render(results, errors, int(now))
    print(f"refreshed: {sorted(results)} errors={errors}", flush=True)


def main():
    cfg = {
        "ado_org": os.environ.get("ADO_ORG", ""), "ado_project": os.environ.get("ADO_PROJECT", ""),
        "ado_pat": os.environ.get("ADO_PAT", ""), "gh_repo": os.environ.get("GH_REPO", ""),
        "gh_token": os.environ.get("GH_TOKEN", ""), "window": int(os.environ.get("WINDOW_DAYS", "30")),
    }
    interval = int(os.environ.get("REFRESH_SECONDS", "300"))
    state, cache = State(), {}

    def loop():
        while True:
            try:
                refresh(state, cfg, cache)
            except Exception as exc:  # noqa: BLE001
                print(f"refresh crashed: {exc}", flush=True)
            time.sleep(interval)

    threading.Thread(target=loop, daemon=True).start()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            if self.path == "/healthz":
                self.send_response(200); self.end_headers(); self.wfile.write(b"ok"); return
            with state.lock:
                body = state.body.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    HTTPServer(("0.0.0.0", 9102), Handler).serve_forever()


if __name__ == "__main__":
    main()
