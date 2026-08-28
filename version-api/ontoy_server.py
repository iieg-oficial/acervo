import http.client
import http.server
import json
import os
import re
import shutil
import socket
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

VERSION_FILE_PATH = Path(os.environ.get("ONTOY_VERSION_FILE", "/app/VERSION"))
CHANGELOG_FILE_PATH = Path(os.environ.get("ONTOY_CHANGELOG_FILE", "/app/CHANGELOG.md"))
STARTED_AT = datetime.now(timezone.utc)
DOCKER_SOCKET_PATH = Path("/var/run/docker.sock")
PORT = 8088
SERVICE = os.environ.get("ONTOY_SERVICE", "huachicol")
COMPOSE_PROJECT = os.environ.get("ONTOY_COMPOSE_PROJECT", "")
DISK_PATH = os.environ.get("ONTOY_DISK_PATH", "/")
DISK_WARN_PERCENT = float(os.environ.get("ONTOY_DISK_WARN_PERCENT", "85"))
DISK_CRITICAL_PERCENT = float(os.environ.get("ONTOY_DISK_CRITICAL_PERCENT", "95"))
UPSTREAM_URL = os.environ.get("ONTOY_UPSTREAM_URL", "").strip()
NODE = os.environ.get("ONTOY_NODE", "").strip()
NODE_REPORTER = os.environ.get("ONTOY_NODE_REPORTER", "").strip().lower() in ("1", "true", "si")
PROC_PATH = Path(os.environ.get("ONTOY_PROC_PATH", "/proc"))
OS_RELEASE_PATH = Path(os.environ.get("ONTOY_OS_RELEASE_FILE", "/host/etc/os-release"))
NODE_IP = os.environ.get("ONTOY_NODE_IP", "").strip()
LOAD_WARN_PER_CORE = float(os.environ.get("ONTOY_LOAD_WARN_PER_CORE", "0.9"))
LOAD_CRITICAL_PER_CORE = float(os.environ.get("ONTOY_LOAD_CRITICAL_PER_CORE", "1.5"))
MEMORY_WARN_PERCENT = float(os.environ.get("ONTOY_MEMORY_WARN_PERCENT", "80"))
MEMORY_CRITICAL_PERCENT = float(os.environ.get("ONTOY_MEMORY_CRITICAL_PERCENT", "92"))
SWAP_WARN_PERCENT = float(os.environ.get("ONTOY_SWAP_WARN_PERCENT", "10"))
DEPENDENCY_TIMEOUT = 2.0
PEER_TIMEOUT = float(os.environ.get("ONTOY_PEER_TIMEOUT", "0.8"))

STATUS_OK = "ok"
STATUS_DEGRADED = "degraded"
STATUS_DOWN = "down"

_SEVERITY = {STATUS_OK: 0, STATUS_DEGRADED: 1, STATUS_DOWN: 2}

INFORMATIVOS = ("carga", "memoria", "swap")


def _es_informativo(nombre: str) -> bool:
    return nombre in INFORMATIVOS or nombre.startswith("peer_")


def _criticos(checks: dict[str, Any]) -> list[str]:
    return [
        check["status"] for nombre, check in checks.items() if not _es_informativo(nombre)
    ]


def _marcar_informativos(checks: dict[str, Any]) -> None:
    for nombre, check in checks.items():
        if _es_informativo(nombre):
            check["informativo"] = True


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


def _version_de_pyproject(texto: str) -> str | None:
    match = re.search(r'^version\s*=\s*["\']([^"\']+)', texto, re.MULTILINE)
    return match.group(1) if match else None


def _version_de_package_json(texto: str) -> str | None:
    try:
        return json.loads(texto).get("version")
    except (json.JSONDecodeError, AttributeError):
        return None


def _version_del_archivo(ruta: Path) -> str | None:
    try:
        texto = ruta.read_text()
    except OSError:
        return None
    if ruta.name == "pyproject.toml":
        return _version_de_pyproject(texto)
    if ruta.name == "package.json":
        return _version_de_package_json(texto)
    return texto.strip() or None


def _read_version() -> dict[str, Any]:
    version = _version_del_archivo(VERSION_FILE_PATH) if VERSION_FILE_PATH.exists() else None
    payload: dict[str, Any] = {"version": version, "service": SERVICE}
    released_at = _released_at()
    if released_at:
        payload["released_at"] = released_at
    return payload


def _released_at() -> str | None:
    if not CHANGELOG_FILE_PATH.exists():
        return None
    try:
        texto = CHANGELOG_FILE_PATH.read_text()
    except OSError:
        return None
    match = re.search(r"^##\s*\[[^\]]+\]\s*-\s*(\d{4}-\d{2}-\d{2})", texto, re.MULTILINE)
    return match.group(1) if match else None


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


def _fetch_upstream(url: str) -> tuple[dict[str, Any], str | None]:
    try:
        request = urllib.request.Request(
            url, method="GET", headers={"Accept": "application/json"}
        )
        with urllib.request.urlopen(request, timeout=DEPENDENCY_TIMEOUT) as response:
            return json.loads(response.read()), None
    except urllib.error.HTTPError as exc:
        try:
            return json.loads(exc.read()), None
        except Exception:
            return {}, f"HTTP {exc.code}"
    except Exception as exc:
        return {}, str(exc)[:120]


def _merge_upstream(payload: dict[str, Any], checks: dict[str, Any]) -> None:
    upstream, error = _fetch_upstream(UPSTREAM_URL)
    if error:
        checks["upstream"] = {"status": STATUS_DOWN, "detail": error}
        return

    for name, check in (upstream.get("checks") or {}).items():
        if isinstance(check, dict) and "status" in check:
            checks.setdefault(name, check)

    for field in ("version", "released_at", "deployed_at"):
        if not payload.get(field) and upstream.get(field):
            payload[field] = upstream[field]

    declared = upstream.get("status")
    merged = _worst(_criticos(checks))
    if declared in _SEVERITY and _SEVERITY[declared] > _SEVERITY[merged]:
        checks["upstream"] = {
            "status": declared,
            "detail": f"el servicio se declara {declared} sin un check que lo explique",
        }


def _leer_proc(nombre: str) -> str | None:
    try:
        return (PROC_PATH / nombre).read_text()
    except OSError:
        return None


def _cpu_cores() -> int:
    return os.cpu_count() or 1


def _check_carga() -> dict[str, Any] | None:
    contenido = _leer_proc("loadavg")
    if not contenido:
        return None
    partes = contenido.split()
    if len(partes) < 3:
        return None
    try:
        uno, cinco, quince = (float(p) for p in partes[:3])
    except ValueError:
        return None

    nucleos = _cpu_cores()
    por_nucleo = uno / nucleos
    if por_nucleo >= LOAD_CRITICAL_PER_CORE:
        estado = STATUS_DOWN
    elif por_nucleo >= LOAD_WARN_PER_CORE:
        estado = STATUS_DEGRADED
    else:
        estado = STATUS_OK
    return {
        "status": estado,
        "load_1m": round(uno, 2),
        "load_5m": round(cinco, 2),
        "load_15m": round(quince, 2),
        "cores": nucleos,
        "load_per_core": round(por_nucleo, 2),
    }


def _meminfo() -> dict[str, int]:
    contenido = _leer_proc("meminfo")
    if not contenido:
        return {}
    valores: dict[str, int] = {}
    for linea in contenido.splitlines():
        clave, _, resto = linea.partition(":")
        numero = resto.strip().split(" ")[0]
        if numero.isdigit():
            valores[clave] = int(numero)
    return valores


def _check_memoria() -> dict[str, Any] | None:
    valores = _meminfo()
    total = valores.get("MemTotal")
    if not total:
        return None
    disponible = valores.get("MemAvailable", valores.get("MemFree", 0))
    usado = total - disponible
    porcentaje = usado / total * 100
    if porcentaje >= MEMORY_CRITICAL_PERCENT:
        estado = STATUS_DOWN
    elif porcentaje >= MEMORY_WARN_PERCENT:
        estado = STATUS_DEGRADED
    else:
        estado = STATUS_OK
    return {
        "status": estado,
        "used_percent": round(porcentaje, 1),
        "used_gb": round(usado / 1024 / 1024, 2),
        "total_gb": round(total / 1024 / 1024, 2),
    }


def _check_swap() -> dict[str, Any] | None:
    valores = _meminfo()
    total = valores.get("SwapTotal")
    if not total:
        return None
    libre = valores.get("SwapFree", 0)
    usado = total - libre
    porcentaje = usado / total * 100
    estado = STATUS_DEGRADED if porcentaje >= SWAP_WARN_PERCENT else STATUS_OK
    return {
        "status": estado,
        "used_percent": round(porcentaje, 1),
        "used_gb": round(usado / 1024 / 1024, 2),
        "total_gb": round(total / 1024 / 1024, 2),
    }


def _uptime_segundos() -> int | None:
    contenido = _leer_proc("uptime")
    if not contenido:
        return None
    try:
        return int(float(contenido.split()[0]))
    except (ValueError, IndexError):
        return None


def _parse_peer_checks() -> list[tuple[str, str, int]]:
    raw = os.environ.get("ONTOY_PEER_CHECKS", "").strip()
    if not raw:
        return []
    aristas = []
    for item in raw.split(","):
        item = item.strip()
        if not item or "=" not in item:
            continue
        nodo, destino = item.split("=", 1)
        host, _, puerto = destino.strip().rpartition(":")
        if not host or not puerto.isdigit():
            continue
        aristas.append((nodo.strip(), host, int(puerto)))
    return aristas


def _check_peer(host: str, puerto: int) -> dict[str, Any]:
    inicio = time.monotonic()
    try:
        with socket.create_connection((host, puerto), timeout=PEER_TIMEOUT):
            latencia = int((time.monotonic() - inicio) * 1000)
            return {"status": STATUS_OK, "port": puerto, "latency_ms": latencia}
    except Exception as exc:
        return {"status": STATUS_DOWN, "port": puerto, "detail": str(exc)[:120]}


def _kernel() -> str | None:
    contenido = _leer_proc("version")
    if not contenido:
        return None
    partes = contenido.split()
    return partes[2] if len(partes) > 2 else None


def _sistema_operativo() -> str | None:
    try:
        contenido = OS_RELEASE_PATH.read_text()
    except OSError:
        return None
    for linea in contenido.splitlines():
        if linea.startswith("PRETTY_NAME="):
            return linea.split("=", 1)[1].strip().strip('"') or None
    return None


def _host_metrics(checks: dict[str, Any]) -> dict[str, Any]:
    metricas: dict[str, Any] = {"cores": _cpu_cores()}

    if NODE_IP:
        metricas["ip"] = NODE_IP

    kernel = _kernel()
    if kernel:
        metricas["kernel"] = kernel

    sistema = _sistema_operativo()
    if sistema:
        metricas["os"] = sistema

    carga = _check_carga()
    if carga:
        checks["carga"] = carga
        metricas["load_1m"] = carga["load_1m"]
        metricas["load_5m"] = carga["load_5m"]
        metricas["load_15m"] = carga["load_15m"]

    memoria = _check_memoria()
    if memoria:
        checks["memoria"] = memoria
        metricas["memory_used_gb"] = memoria["used_gb"]
        metricas["memory_total_gb"] = memoria["total_gb"]
        metricas["memory_used_percent"] = memoria["used_percent"]

    swap = _check_swap()
    if swap:
        checks["swap"] = swap
        metricas["swap_used_gb"] = swap["used_gb"]
        metricas["swap_used_percent"] = swap["used_percent"]

    segundos = _uptime_segundos()
    if segundos is not None:
        metricas["uptime_seconds"] = segundos

    return metricas


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

    peers = {}
    for nodo, host, puerto in _parse_peer_checks():
        resultado = _check_peer(host, puerto)
        peers[nodo] = resultado
        checks[f"peer_{nodo}"] = resultado
    if peers:
        payload["peers"] = peers

    if NODE:
        payload["node"] = NODE
        payload["node_reporter"] = NODE_REPORTER
        if NODE_REPORTER:
            payload["host"] = _host_metrics(checks)

    if UPSTREAM_URL:
        _merge_upstream(payload, checks)

    _marcar_informativos(checks)
    payload["checks"] = checks
    payload["status"] = _worst(_criticos(checks))
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
