#!/usr/bin/env bash
set -euo pipefail

HARBOR_URL="${HARBOR_URL:-https://127.0.0.1}"
HARBOR_INSECURE="${HARBOR_INSECURE:-true}"
PROJECT_NAME="${PROJECT_NAME:-erp007}"
ROBOT_NAME="${ROBOT_NAME:-harbor-robot-erp007}"
QUOTA_BYTES="${QUOTA_BYTES:-128849018880}"
RETENTION_COUNT="${RETENTION_COUNT:-10}"
RETENTION_CRON="${RETENTION_CRON:-0 0 3 * * *}"
GC_CRON="${GC_CRON:-0 0 4 * * 0}"
ADMIN_PASSWORD_FILE="${ADMIN_PASSWORD_FILE:-/home/taehyung/apps/msa-server/infra/server-secrets/harbor/admin-password}"
ROBOT_SECRET_FILE="${ROBOT_SECRET_FILE:-/home/taehyung/apps/msa-server/infra/server-secrets/harbor/jenkins-robot.json}"

if [ ! -f "$ADMIN_PASSWORD_FILE" ]; then
  echo "missing Harbor admin password file: $ADMIN_PASSWORD_FILE" >&2
  exit 1
fi

export HARBOR_URL HARBOR_INSECURE PROJECT_NAME ROBOT_NAME QUOTA_BYTES
export RETENTION_COUNT RETENTION_CRON GC_CRON ADMIN_PASSWORD_FILE ROBOT_SECRET_FILE

python3 - <<'PY'
import base64
import json
import os
import ssl
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

harbor_url = os.environ["HARBOR_URL"].rstrip("/")
project_name = os.environ["PROJECT_NAME"]
robot_name = os.environ["ROBOT_NAME"]
quota_bytes = int(os.environ["QUOTA_BYTES"])
retention_count = int(os.environ["RETENTION_COUNT"])
retention_cron = os.environ["RETENTION_CRON"]
gc_cron = os.environ["GC_CRON"]
robot_secret_file = Path(os.environ["ROBOT_SECRET_FILE"])
admin_password = Path(os.environ["ADMIN_PASSWORD_FILE"]).read_text().strip()
ssl_context = ssl._create_unverified_context() if os.environ["HARBOR_INSECURE"] == "true" else None


class HarborError(RuntimeError):
    pass


def request(method, path, body=None, expected=(200,)):
    data = None
    headers = {
        "Authorization": "Basic " + base64.b64encode(f"admin:{admin_password}".encode()).decode(),
        "Accept": "application/json",
    }
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(harbor_url + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, context=ssl_context, timeout=30) as resp:
            raw = resp.read()
            if resp.status not in expected:
                raise HarborError(f"{method} {path} returned {resp.status}: {raw[:500]!r}")
            if not raw:
                return None, resp
            return json.loads(raw), resp
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        if exc.code in expected:
            return None, exc
        raise HarborError(f"{method} {path} returned {exc.code}: {raw[:500].decode(errors='replace')}") from exc


def get_project():
    encoded = urllib.parse.quote(project_name, safe="")
    try:
        data, _ = request("GET", f"/api/v2.0/projects/{encoded}", expected=(200,))
        return data
    except HarborError as exc:
        if "returned 404" not in str(exc):
            raise
    request("POST", "/api/v2.0/projects", {"project_name": project_name, "public": False}, expected=(201,))
    data, _ = request("GET", f"/api/v2.0/projects/{encoded}", expected=(200,))
    return data


project = get_project()
project_id = int(project["project_id"])
print(f"project={project_name} id={project_id}")

quotas, _ = request(
    "GET",
    f"/api/v2.0/quotas?reference=project&reference_id={project_id}",
    expected=(200,),
)
if quotas:
    quota_id = int(quotas[0]["id"])
    request("PUT", f"/api/v2.0/quotas/{quota_id}", {"hard": {"storage": quota_bytes}}, expected=(200,))
    print(f"quota={quota_bytes}")
else:
    print("quota=skipped (quota record not found)")

retention_body = {
    "algorithm": "or",
    "rules": [
        {
            "disabled": False,
            "action": "retain",
            "template": "latestPushedK",
            "params": {"latestPushedK": retention_count},
            "tag_selectors": [{"kind": "doublestar", "decoration": "matches", "pattern": "**"}],
            "scope_selectors": {
                "repository": [{"kind": "doublestar", "decoration": "repoMatches", "pattern": "**"}]
            },
        }
    ],
    "trigger": {"kind": "Schedule", "settings": {"cron": retention_cron}},
    "scope": {"level": "project", "ref": project_id},
}
metadata = project.get("metadata") or {}
retention_id = metadata.get("retention_id") or metadata.get("retention")
if retention_id:
    request("PUT", f"/api/v2.0/retentions/{retention_id}", retention_body, expected=(200,))
else:
    request("POST", "/api/v2.0/retentions", retention_body, expected=(201,))
print(f"retention=latest-{retention_count}")

gc_body = {"schedule": {"type": "Custom", "cron": gc_cron}, "parameters": {"delete_untagged": False, "dry_run": False}}
try:
    request("PUT", "/api/v2.0/system/gc/schedule", gc_body, expected=(200,))
except HarborError as exc:
    if "returned 404" in str(exc) or "returned 409" in str(exc):
        request("POST", "/api/v2.0/system/gc/schedule", gc_body, expected=(201,))
    else:
        raise
print("gc=scheduled")

robots, _ = request(
    "GET",
    "/api/v2.0/robots?page_size=100",
    expected=(200,),
)
existing = [r for r in robots or [] if r.get("name") == robot_name or r.get("name") == f"robot${robot_name}"]
if existing and robot_secret_file.exists():
    print("robot=exists")
else:
    robot_body = {
        "name": robot_name,
        "description": "Jenkins push/pull robot for ERP007 backend images",
        "level": "project",
        "disable": False,
        "duration": -1,
        "permissions": [
            {
                "kind": "project",
                "namespace": project_name,
                "access": [
                    {"resource": "repository", "action": "pull", "effect": "allow"},
                    {"resource": "repository", "action": "push", "effect": "allow"},
                    {"resource": "repository", "action": "read", "effect": "allow"},
                    {"resource": "artifact", "action": "read", "effect": "allow"},
                    {"resource": "artifact", "action": "create", "effect": "allow"},
                    {"resource": "tag", "action": "create", "effect": "allow"},
                    {"resource": "tag", "action": "delete", "effect": "allow"},
                ],
            }
        ],
    }
    created, _ = request("POST", "/api/v2.0/robots", robot_body, expected=(201,))
    robot_secret_file.parent.mkdir(parents=True, exist_ok=True)
    robot_secret_file.write_text(json.dumps(created, indent=2) + "\n")
    robot_secret_file.chmod(0o600)
    print(f"robot={created.get('name', robot_name)} secret_file={robot_secret_file}")
PY
