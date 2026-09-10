#!/usr/bin/env python3
import http.server
import json
import os
import secrets
import time
from urllib.parse import urlparse

PIN = os.environ.get("NOVNC_PIN", "123456")
try:
    IDLE_SECONDS = max(30, int(float(os.environ.get("PIN_IDLE_TIMEOUT", "10")) * 60))
except ValueError:
    IDLE_SECONDS = 600

sessions = {}
COOKIE = "novnc_session"


def cleanup():
    now = time.time()
    for token, last in list(sessions.items()):
        if now - last > IDLE_SECONDS:
            sessions.pop(token, None)


def get_token(handler):
    raw = handler.headers.get("Cookie", "")
    for item in raw.split(";"):
        item = item.strip()
        if item.startswith(COOKIE + "="):
            return item.split("=", 1)[1]
    return None


def valid(handler, touch=False):
    cleanup()
    token = get_token(handler)
    if not token or token not in sessions:
        return False
    if touch:
        sessions[token] = time.time()
    return True


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def send_json(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/auth/check":
            if valid(self, touch=False):
                self.send_response(200)
                self.end_headers()
            else:
                self.send_response(401)
                self.end_headers()
            return
        if path == "/api/status":
            self.send_json(200, {
                "authenticated": valid(self),
                "idle_timeout_minutes": IDLE_SECONDS // 60
            })
            return
        if path == "/api/activity":
            if valid(self, touch=True):
                self.send_json(200, {"ok": True})
            else:
                self.send_json(401, {"ok": False})
            return
        self.send_json(404, {"error": "not found"})

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", "0"))
        try:
            data = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            data = {}

        if path == "/api/login":
            cleanup()
            supplied = str(data.get("pin", ""))
            if secrets.compare_digest(supplied, PIN):
                token = secrets.token_urlsafe(32)
                sessions[token] = time.time()
                self.send_response(200)
                self.send_header(
                    "Set-Cookie",
                    f"{COOKIE}={token}; Path=/; HttpOnly; SameSite=Lax"
                )
                self.send_header("Content-Type", "application/json")
                body = b'{"ok":true}'
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_json(401, {"ok": False, "error": "PIN salah"})
            return

        if path == "/api/activity":
            if valid(self, touch=True):
                self.send_json(200, {"ok": True})
            else:
                self.send_json(401, {"ok": False})
            return

        if path == "/api/logout":
            token = get_token(self)
            if token:
                sessions.pop(token, None)
            self.send_response(200)
            self.send_header("Set-Cookie", f"{COOKIE}=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax")
            self.end_headers()
            return

        self.send_json(404, {"error": "not found"})


http.server.ThreadingHTTPServer(("127.0.0.1", 9000), Handler).serve_forever()
