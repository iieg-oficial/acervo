import http.client
import http.server
import json
import os
import shutil
import socket
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

VERSION_FILE_PATH = Path("/app/VERSION")
STARTED_AT = datetime.now(timezone.utc)
DOCKER_SOCKET_PATH = Path("/var/run/docker.sock")
PORT = 8088
SERVICE = os.environ.get("ONTOY_SERVICE", "huachicol")
COMPOSE_PROJECT = os.environ.get("ONTOY_COMPOSE_PROJECT", "")
DISK_PATH = os.environ.get("ONTOY_DISK_PATH", "/")
DISK_WARN_PERCENT = float(os.environ.get("ONTOY_DISK_WARN_PERCENT", "85"))
DISK_CRITICAL_PERCENT = float(os.environ.get("ONTOY_DISK_CRITICAL_PERCENT", "95"))
DEPENDENCY_TIMEOUT = 2.0

STATUS_OK = "ok"
STATUS_DEGRADED = "degraded"
STATUS_DOWN = "down"

_SEVERITY = {STATUS_OK: 0, STATUS_DEGRADED: 1, STATUS_DOWN: 2}


class _UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, socket_path: str, timeout: float = 2.0) -> None:
        super().__init__("localhost", timeout=timeout)
        self.socket_path = socket_path

    def connect(self) -> None:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        sock.connect(self.socket_path)
        self.sock = sock


def _worst(statuses: list[str]) -> str:
    if not statuses:
        return STATUS_OK
    return max(statuses, key=lambda s: _SEVERITY.get(s, 0))


def _read_version() -> dict[str, Any]:
    if VERSION_FILE_PATH.exists():
        return {
            "version": VERSION_FILE_PATH.read_text().strip(),
            "service": SERVICE,
        }
    return {"version": None, "service": SERVICE}


def _deployed_at() -> str:
    return STARTED_AT.isoformat(timespec="seconds").replace("+00:00", "Z")


def _check_disk() -> dict[str, Any]:
    try:
        usage = shutil.disk_usage(DISK_PATH)
    except OSError as exc:
        return {"status": STATUS_DEGRADED, "detail": f"no se pudo leer {DISK_PATH}: {exc}"}

    used_percent = round(usage.used / usage.total * 100, 1)
    if used_percent >= DISK_CRITICAL_PERCENT:
        status = STATUS_DOWN
    elif used_percent >= DISK_WARN_PERCENT:
        status = STATUS_DEGRADED
    else:
        status = STATUS_OK
    return {
        "status": status,
        "used_percent": used_percent,
        "free_gb": round(usage.free / 1024**3, 1),
    }


def _parse_dependencies() -> list[tuple[str, str]]:
    raw = os.environ.get("ONTOY_DEPENDENCIES", "").strip()
    if not raw:
        return []
    dependencies = []
    for item in raw.split(","):
        item = item.strip()
        if not item or "=" not in item:
            continue
        name, url = item.split("=", 1)
        dependencies.append((name.strip(), url.strip()))
    return dependencies


def _check_dependency(url: str) -> dict[str, Any]:
    try:
        request = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(request, timeout=DEPENDENCY_TIMEOUT) as response:
            if 200 <= response.status < 400:
                return {"status": STATUS_OK}
            return {"status": STATUS_DOWN, "detail": f"HTTP {response.status}"}
    except urllib.error.HTTPError as exc:
        return {"status": STATUS_DOWN, "detail": f"HTTP {exc.code}"}
    except Exception as exc:
        return {"status": STATUS_DOWN, "detail": str(exc)[:120]}


def _parse_port_checks() -> list[tuple[str, str, int]]:
    raw = os.environ.get("ONTOY_PORT_CHECKS", "").strip()
    if not raw:
        return []
    checks = []
    for item in raw.split(","):
        item = item.strip()
        if not item or "=" not in item:
            continue
        name, target = item.split("=", 1)
        host, _, port = target.strip().rpartition(":")
        if not host or not port.isdigit():
            continue
        checks.append((name.strip(), host, int(port)))
    return checks


def _check_port(host: str, port: int) -> dict[str, Any]:
    try:
        with socket.create_connection((host, port), timeout=DEPENDENCY_TIMEOUT):
            return {"status": STATUS_OK, "port": port}
    except Exception as exc:
        return {"status": STATUS_DOWN, "port": port, "detail": str(exc)[:120]}


def _docker_get(path: str) -> Any:
    connection = _UnixHTTPConnection(str(DOCKER_SOCKET_PATH), timeout=DEPENDENCY_TIMEOUT)
    try:
        connection.request("GET", path, headers={"Host": "localhost"})
        response = connection.getresponse()
        payload = response.read()
        if response.status != 200:
            raise RuntimeError(f"docker API HTTP {response.status}")
        return json.loads(payload)
    finally:
        connection.close()


def _list_containers() -> tuple[list[dict[str, Any]], str | None]:
    if not DOCKER_SOCKET_PATH.exists():
        return [], None

    try:
        raw = _docker_get("/v1.43/containers/json?all=1")
    except Exception as exc:
        return [], str(exc)[:120]

    containers = []
    for item in raw:
        labels = item.get("Labels") or {}
        project = labels.get("com.docker.compose.project", "")
        if COMPOSE_PROJECT and project != COMPOSE_PROJECT:
            continue
        name = (item.get("Names") or ["/desconocido"])[0].lstrip("/")
        state = item.get("State", "unknown")
        containers.append({
            "name": name,
            "state": state,
            "health": _container_health(item.get("Status", "")),
            "image": item.get("Image", ""),
            "project": project or None,
        })
    containers.sort(key=lambda c: c["name"])
    return containers, None


def _container_health(status_text: str) -> str | None:
    lowered = status_text.lower()
    if "(healthy)" in lowered:
        return "healthy"
    if "(unhealthy)" in lowered:
        return "unhealthy"
    if "(health: starting)" in lowered:
        return "starting"
    return None


def _containers_status(containers: list[dict[str, Any]], error: str | None) -> str:
    if error or not containers:
        return STATUS_OK
    if any(c["health"] == "unhealthy" for c in containers):
        return STATUS_DOWN
    if any(c["state"] not in ("running", "created") for c in containers):
        return STATUS_DEGRADED
    return STATUS_OK


def build_payload() -> dict[str, Any]:
    payload = _read_version()
    payload.setdefault("service", SERVICE)
    payload["deployed_at"] = _deployed_at()

    checks: dict[str, Any] = {"disk": _check_disk()}
    for name, url in _parse_dependencies():
        checks[name] = _check_dependency(url)
    for name, host, port in _parse_port_checks():
        checks[name] = _check_port(host, port)

    containers, containers_error = _list_containers()
    if containers or containers_error:
        payload["containers"] = containers
        checks["containers"] = {
            "status": _containers_status(containers, containers_error),
            "total": len(containers),
            "running": sum(1 for c in containers if c["state"] == "running"),
        }
        if containers_error:
            checks["containers"]["detail"] = containers_error

    payload["checks"] = checks
    payload["status"] = _worst([c["status"] for c in checks.values()])
    return payload


class OntoyHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path.split("?")[0] != "/ontoy":
            self.send_error(404)
            return

        try:
            payload = build_payload()
        except Exception as exc:
            self.send_error(500, f"error building payload: {exc}")
            return

        body = json.dumps(payload).encode()
        self.send_response(200 if payload["status"] != STATUS_DOWN else 503)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args) -> None:
        return


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), OntoyHandler)
    print(f"ontoy server listening on :{PORT}", flush=True)
    server.serve_forever()
