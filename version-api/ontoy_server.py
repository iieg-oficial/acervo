import http.server
import json
from pathlib import Path

VERSION_JSON_PATH = Path("/app/version.json")
VERSION_FILE_PATH = Path("/app/VERSION")
PORT = 8088
SERVICE = "acervo"


class OntoyHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/ontoy":
            self.send_error(404)
            return

        try:
            if VERSION_JSON_PATH.exists():
                data = json.loads(VERSION_JSON_PATH.read_text())
            elif VERSION_FILE_PATH.exists():
                data = {
                    "version": VERSION_FILE_PATH.read_text().strip(),
                    "service": SERVICE,
                }
            else:
                self.send_error(503, "version not available")
                return
        except Exception as exc:
            self.send_error(500, f"error reading version: {exc}")
            return

        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        return


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), OntoyHandler)
    print(f"ontoy server listening on :{PORT}", flush=True)
    server.serve_forever()
