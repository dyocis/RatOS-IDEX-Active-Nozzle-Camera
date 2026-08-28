#!/usr/bin/env python3
import base64
import json
import os
import socket
import subprocess
import sys
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

REPO_ROOT = Path(__file__).resolve().parents[1]
SWITCHER = REPO_ROOT / "src" / "active_nozzle_camera.py"

T0_FRAME = b"\xff\xd8T0-FRAME\xff\xd9"
T1_FRAME = b"\xff\xd8T1-FRAME\xff\xd9"


class MockCameraHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        if self.path == "/t0-stream":
            frame = T0_FRAME
        elif self.path == "/t1-stream":
            frame = T1_FRAME
        else:
            self.send_error(404)
            return

        boundary = b"mock-frame"
        body = (
            b"--" + boundary + b"\r\n"
            b"Content-Type: image/jpeg\r\n"
            + f"Content-Length: {len(frame)}\r\n\r\n".encode("ascii")
            + frame
            + b"\r\n--"
            + boundary
            + b"--\r\n"
        )

        self.send_response(200)
        self.send_header(
            "Content-Type",
            "multipart/x-mixed-replace; boundary=" + boundary.decode("ascii"),
        )
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class SwitcherProcess:
    def __init__(self, camera_port, token=None, legacy_token=False):
        self.camera_port = camera_port
        self.token = token
        self.legacy_token = legacy_token
        self.port = None
        self.process = None

    def __enter__(self):
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            self.port = sock.getsockname()[1]

        env = os.environ.copy()
        env.update(
            {
                "ACTIVE_CAMERA_LISTEN_HOST": "127.0.0.1",
                "ACTIVE_CAMERA_LISTEN_PORT": str(self.port),
                "T0_STREAM_URL": f"http://127.0.0.1:{self.camera_port}/t0-stream",
                "T0_SNAPSHOT_URL": "",
                "T1_STREAM_URL": f"http://127.0.0.1:{self.camera_port}/t1-stream",
                "T1_SNAPSHOT_URL": "",
            }
        )
        env.pop("ACTIVE_CAMERA_TOKEN", None)
        env.pop("ACTIVE_CAMERA_TOKEN_B64", None)

        if self.token is not None:
            if self.legacy_token:
                env["ACTIVE_CAMERA_TOKEN"] = self.token
            else:
                env["ACTIVE_CAMERA_TOKEN_B64"] = base64.b64encode(
                    self.token.encode("utf-8")
                ).decode("ascii")

        self.process = subprocess.Popen(
            [sys.executable, str(SWITCHER)],
            cwd=REPO_ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                output = self.process.stdout.read() if self.process.stdout else ""
                raise RuntimeError(f"switcher exited during startup:\n{output}")
            try:
                with urlopen(self.url("/health"), timeout=0.25) as response:
                    if response.status == 200:
                        return self
            except OSError:
                time.sleep(0.05)

        self.stop()
        raise RuntimeError("switcher did not become ready within 5 seconds")

    def __exit__(self, exc_type, exc, tb):
        self.stop()

    def stop(self):
        if self.process is None:
            return ""
        process = self.process
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
        output = process.stdout.read() if process.stdout else ""
        self.process = None
        return output

    def url(self, path, params=None):
        url = f"http://127.0.0.1:{self.port}{path}"
        if params:
            url += "?" + urlencode(params)
        return url

    def request(self, path, params=None, headers=None):
        request = Request(self.url(path, params), headers=headers or {})
        try:
            with urlopen(request, timeout=2) as response:
                return response.status, response.read(), response.headers
        except HTTPError as exc:
            return exc.code, exc.read(), exc.headers

    def request_json(self, path, params=None, headers=None):
        status, body, _ = self.request(path, params, headers)
        return status, json.loads(body.decode("utf-8"))


class ActiveNozzleCameraTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.camera_server = ThreadingHTTPServer(("127.0.0.1", 0), MockCameraHandler)
        cls.camera_port = cls.camera_server.server_address[1]
        cls.camera_thread = threading.Thread(
            target=cls.camera_server.serve_forever,
            daemon=True,
        )
        cls.camera_thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.camera_server.shutdown()
        cls.camera_server.server_close()
        cls.camera_thread.join(timeout=3)

    def test_health_status_and_tool_selection(self):
        with SwitcherProcess(self.camera_port) as switcher:
            status, payload = switcher.request_json("/health")
            self.assertEqual(status, 200)
            self.assertEqual(payload, {"ok": True})

            status, payload = switcher.request_json("/status")
            self.assertEqual(status, 200)
            self.assertEqual(payload["active_tool"], 0)
            self.assertEqual(payload["source"], "T0")
            self.assertEqual(payload["generation"], 0)

            status, payload = switcher.request_json("/select", {"tool": "1"})
            self.assertEqual(status, 200)
            self.assertTrue(payload["ok"])
            self.assertEqual(payload["active_tool"], 1)
            self.assertEqual(payload["generation"], 1)

            status, payload = switcher.request_json("/select", {"tool": "1"})
            self.assertEqual(status, 200)
            self.assertEqual(payload["generation"], 1)

            status, payload = switcher.request_json("/select", {"tool": "2"})
            self.assertEqual(status, 400)
            self.assertIn("error", payload)

    def test_blank_snapshot_urls_extract_frames_from_active_stream(self):
        with SwitcherProcess(self.camera_port) as switcher:
            status, body, headers = switcher.request("/", {"action": "snapshot"})
            self.assertEqual(status, 200)
            self.assertEqual(headers.get_content_type(), "image/jpeg")
            self.assertEqual(body, T0_FRAME)

            status, _ = switcher.request_json("/select", {"tool": "1"})
            self.assertEqual(status, 200)

            status, body, headers = switcher.request("/", {"action": "snapshot"})
            self.assertEqual(status, 200)
            self.assertEqual(headers.get_content_type(), "image/jpeg")
            self.assertEqual(body, T1_FRAME)

    def test_complex_base64_token_header_authentication(self):
        token = "Test token & plus+percent%hash#equals=space ✓"
        with SwitcherProcess(self.camera_port, token=token) as switcher:
            status, payload = switcher.request_json("/select", {"tool": "1"})
            self.assertEqual(status, 403)
            self.assertEqual(payload["error"], "unauthorized")

            status, payload = switcher.request_json(
                "/select",
                {"tool": "1"},
                {"X-Active-Nozzle-Token": "wrong-token"},
            )
            self.assertEqual(status, 403)
            self.assertEqual(payload["error"], "unauthorized")

            status, payload = switcher.request_json(
                "/select",
                {"tool": "1"},
                {"X-Active-Nozzle-Token": token},
            )
            self.assertEqual(status, 200)
            self.assertEqual(payload["active_tool"], 1)

    def test_v011_query_token_remains_compatible_and_is_not_logged(self):
        token = "legacy-query-secret"
        switcher = SwitcherProcess(self.camera_port, token=token)
        switcher.__enter__()
        try:
            status, payload = switcher.request_json(
                "/select", {"tool": "1", "token": token}
            )
            self.assertEqual(status, 200)
            self.assertEqual(payload["active_tool"], 1)
        finally:
            output = switcher.stop()

        self.assertNotIn(token, output)
        self.assertNotIn("?tool=1", output)
        self.assertIn("GET /select HTTP/1.1", output)

    def test_legacy_plain_token_environment_variable_still_works(self):
        token = "legacy-token"
        with SwitcherProcess(
            self.camera_port,
            token=token,
            legacy_token=True,
        ) as switcher:
            status, payload = switcher.request_json(
                "/select",
                {"tool": "1"},
                {"X-Active-Nozzle-Token": token},
            )
            self.assertEqual(status, 200)
            self.assertEqual(payload["active_tool"], 1)


if __name__ == "__main__":
    unittest.main()
