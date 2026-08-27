#!/usr/bin/env python3
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
from urllib.request import urlopen

LISTEN_HOST = os.environ.get("ACTIVE_CAMERA_LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("ACTIVE_CAMERA_LISTEN_PORT", "8084"))
TOKEN = os.environ.get("ACTIVE_CAMERA_TOKEN", "")

SOURCES = {
    0: {
        "name": "T0",
        "stream": os.environ["T0_STREAM_URL"],
        "snapshot": os.environ.get("T0_SNAPSHOT_URL", ""),
    },
    1: {
        "name": "T1",
        "stream": os.environ["T1_STREAM_URL"],
        "snapshot": os.environ.get("T1_SNAPSHOT_URL", ""),
    },
}

STATE_LOCK = threading.Lock()
ACTIVE_TOOL = 0
GENERATION = 0

BOUNDARY = b"active-nozzle-boundary"
SOI = b"\xff\xd8"
EOI = b"\xff\xd9"


def get_state():
    with STATE_LOCK:
        return ACTIVE_TOOL, GENERATION


def set_tool(tool):
    global ACTIVE_TOOL, GENERATION
    with STATE_LOCK:
        if tool != ACTIVE_TOOL:
            ACTIVE_TOOL = tool
            GENERATION += 1
        return ACTIVE_TOOL, GENERATION


def iter_jpegs(url, timeout=10):
    """Extract JPEG frames from an MJPEG HTTP response."""
    with urlopen(url, timeout=timeout) as response:
        buf = bytearray()
        while True:
            chunk = response.read(16384)
            if not chunk:
                return
            buf.extend(chunk)

            while True:
                start = buf.find(SOI)
                if start < 0:
                    if len(buf) > 2_000_000:
                        del buf[:-2]
                    break

                end = buf.find(EOI, start + 2)
                if end < 0:
                    if start > 0:
                        del buf[:start]
                    break

                end += 2
                frame = bytes(buf[start:end])
                del buf[:end]
                yield frame


def first_frame(url, timeout=5):
    for frame in iter_jpegs(url, timeout=timeout):
        return frame
    raise RuntimeError("No JPEG frame received from upstream stream")


class Handler(BaseHTTPRequestHandler):
    server_version = "ActiveNozzleCamera/1.0"

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}", flush=True)

    def send_json(self, payload, status=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def authorized(self, query):
        if not TOKEN:
            return True
        return query.get("token", [""])[0] == TOKEN

    def do_GET(self):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)

        if parsed.path == "/health":
            self.send_json({"ok": True})
            return

        if parsed.path == "/status":
            tool, generation = get_state()
            self.send_json({
                "active_tool": tool,
                "source": SOURCES[tool]["name"],
                "generation": generation,
            })
            return

        if parsed.path == "/select":
            if not self.authorized(query):
                self.send_json({"error": "unauthorized"}, 403)
                return

            try:
                tool = int(query.get("tool", [""])[0])
            except (TypeError, ValueError):
                tool = -1

            if tool not in SOURCES:
                self.send_json({"error": "tool must be 0 or 1"}, 400)
                return

            tool, generation = set_tool(tool)
            self.send_json({
                "ok": True,
                "active_tool": tool,
                "source": SOURCES[tool]["name"],
                "generation": generation,
            })
            return

        action = query.get("action", ["stream"])[0]
        if action == "snapshot":
            self.serve_snapshot()
        elif action == "stream":
            self.serve_stream()
        else:
            self.send_json({"error": "supported actions are stream and snapshot"}, 400)

    def serve_snapshot(self):
        tool, _ = get_state()
        source = SOURCES[tool]

        try:
            if source["snapshot"]:
                with urlopen(source["snapshot"], timeout=5) as upstream:
                    frame = upstream.read()
            else:
                frame = first_frame(source["stream"], timeout=5)
        except Exception as exc:
            self.send_json({"error": f"snapshot upstream failed: {exc}"}, 502)
            return

        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Content-Length", str(len(frame)))
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self.end_headers()
        self.wfile.write(frame)

    def write_frame(self, frame):
        self.wfile.write(b"--" + BOUNDARY + b"\r\n")
        self.wfile.write(b"Content-Type: image/jpeg\r\n")
        self.wfile.write(f"Content-Length: {len(frame)}\r\n\r\n".encode("ascii"))
        self.wfile.write(frame)
        self.wfile.write(b"\r\n")
        self.wfile.flush()

    def serve_stream(self):
        self.send_response(200)
        self.send_header(
            "Content-Type",
            "multipart/x-mixed-replace; boundary=" + BOUNDARY.decode("ascii"),
        )
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.end_headers()

        try:
            while True:
                tool, my_generation = get_state()
                source_url = SOURCES[tool]["stream"]

                try:
                    for frame in iter_jpegs(source_url, timeout=10):
                        _, current_generation = get_state()
                        if current_generation != my_generation:
                            break
                        self.write_frame(frame)
                    else:
                        time.sleep(0.25)
                except (BrokenPipeError, ConnectionResetError):
                    return
                except Exception as exc:
                    print(
                        f"Upstream {SOURCES[tool]['name']} stream error: {exc}",
                        flush=True,
                    )
                    time.sleep(1)
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    print(
        f"Active nozzle camera listening on {LISTEN_HOST}:{LISTEN_PORT}; default=T0",
        flush=True,
    )
    ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler).serve_forever()
