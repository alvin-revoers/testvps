FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Jakarta

# ============================================================
# VARIABLES
# ============================================================

ENV PIN_IDLE_TIMEOUT=10
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# ============================================================
# INSTALL
# ============================================================

RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-goodies \
    xfce4-whiskermenu-plugin \
    xfce4-pulseaudio-plugin \
    xfce4-terminal \
    xfce4-taskmanager \
    xfce4-notifyd \
    xfce4-screenshooter \
    tigervnc-standalone-server \
    novnc \
    websockify \
    nginx \
    dbus-x11 \
    x11-utils \
    x11-xserver-utils \
    x11-apps \
    xterm \
    sudo \
    vim \
    nano \
    net-tools \
    curl \
    wget \
    git \
    tzdata \
    openssl \
    locales \
    fonts-dejavu \
    fonts-liberation \
    fonts-noto \
    fonts-noto-color-emoji \
    papirus-icon-theme \
    arc-theme \
    numix-gtk-theme \
    plank \
    picom \
    htop \
    unzip \
    ca-certificates \
    firefox \
    python3 \
    python3-minimal \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# LOCALE / TIMEZONE
# ============================================================

RUN locale-gen en_US.UTF-8 \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

# ============================================================
# VNC
# ============================================================

RUN mkdir -p /root/.vnc \
    && touch /root/.Xauthority

RUN printf '%s\n' \
'#!/bin/bash' \
'' \
'export XDG_CURRENT_DESKTOP=XFCE' \
'export XDG_SESSION_DESKTOP=xfce' \
'export DESKTOP_SESSION=xfce' \
'export LANG=en_US.UTF-8' \
'export LC_ALL=en_US.UTF-8' \
'' \
'xset s off' \
'xset -dpms' \
'xset s noblank' \
'' \
'picom --experimental-backends >/tmp/picom.log 2>&1 &' \
'sleep 1' \
'plank >/tmp/plank.log 2>&1 &' \
'' \
'startxfce4 &' \
'wait' \
> /root/.vnc/xstartup

RUN chmod +x /root/.vnc/xstartup

# ============================================================
# MODERN XFCE THEME
# ============================================================

RUN mkdir -p /root/.config/xfce4/xfconf/xfce-perchannel-xml

RUN printf '%s\n' \
'<?xml version="1.0" encoding="UTF-8"?>' \
'<channel name="xsettings" version="1.0">' \
'  <property name="Net" type="empty">' \
'    <property name="ThemeName" type="string" value="Arc-Darker"/>' \
'    <property name="IconThemeName" type="string" value="Papirus-Dark"/>' \
'    <property name="CursorThemeName" type="string" value="Adwaita"/>' \
'    <property name="CursorThemeSize" type="int" value="24"/>' \
'  </property>' \
'  <property name="Gtk" type="empty">' \
'    <property name="FontName" type="string" value="Noto Sans 10"/>' \
'  </property>' \
'</channel>' \
> /root/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml

RUN printf '%s\n' \
'<?xml version="1.0" encoding="UTF-8"?>' \
'<channel name="xfwm4" version="1.0">' \
'  <property name="general" type="empty">' \
'    <property name="theme" type="string" value="Arc-Darker"/>' \
'    <property name="title_font" type="string" value="Noto Sans Bold 10"/>' \
'    <property name="button_layout" type="string" value="CHM|H"/>' \
'    <property name="workspace_count" type="int" value="1"/>' \
'  </property>' \
'</channel>' \
> /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml

# ============================================================
# PLANK
# ============================================================

RUN mkdir -p /root/.config/plank/dock1

RUN printf '%s\n' \
'[Plank]' \
'Theme=Transparent' \
'IconSize=44' \
'HideMode=Intelligent' \
'Position=Bottom' \
'Alignment=Center' \
'ItemsAlignment=Center' \
'ZoomEnabled=true' \
'ZoomPercent=130' \
'TooltipsEnabled=true' \
'ShowDockItem=true' \
> /root/.config/plank/dock1/settings

# ============================================================
# PIN AUTH SERVER
# ============================================================

RUN mkdir -p /opt/novnc-auth

RUN cat > /opt/novnc-auth/auth.py <<'PY'
#!/usr/bin/env python3

import os
import time
import hmac
import hashlib
import base64
import html
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs

PIN = os.environ.get("NOVNC_PIN", "123456")
TIMEOUT = max(1, int(os.environ.get("PIN_IDLE_TIMEOUT", "10"))) * 60

SECRET = os.environ.get("NOVNC_SECRET")

if not SECRET:
    SECRET = hashlib.sha256(
        os.urandom(32)
    ).hexdigest()

SECRET = SECRET.encode()


def make_cookie():
    timestamp = str(int(time.time()))
    signature = hmac.new(
        SECRET,
        timestamp.encode(),
        hashlib.sha256
    ).hexdigest()

    return timestamp + "." + signature


def validate_cookie(cookie):
    if not cookie:
        return False

    try:
        token = cookie.split("=", 1)[1]
        timestamp, signature = token.split(".", 1)

        timestamp = int(timestamp)

        if time.time() - timestamp > TIMEOUT:
            return False

        expected = hmac.new(
            SECRET,
            str(timestamp).encode(),
            hashlib.sha256
        ).hexdigest()

        return hmac.compare_digest(signature, expected)

    except Exception:
        return False


def get_cookie(headers):
    raw = headers.get("Cookie", "")

    for item in raw.split(";"):
        item = item.strip()

        if item.startswith("novnc_session="):
            return item

    return None


def page(message=""):
    msg = ""

    if message:
        msg = f"""
        <div class="error">{html.escape(message)}</div>
        """

    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport"
      content="width=device-width,initial-scale=1">
<title>VNC Access</title>

<style>
* {{
    box-sizing:border-box;
}}

html,body {{
    margin:0;
    width:100%;
    height:100%;
    background:
        radial-gradient(circle at top,#172554,#020617 55%);
    font-family:Arial,sans-serif;
    color:white;
}}

body {{
    display:flex;
    align-items:center;
    justify-content:center;
}}

.card {{
    width:min(380px,90%);
    padding:32px;
    border-radius:24px;
    background:rgba(15,23,42,.82);
    border:1px solid rgba(255,255,255,.10);
    box-shadow:0 25px 80px rgba(0,0,0,.55);
    backdrop-filter:blur(20px);
}}

.logo {{
    width:64px;
    height:64px;
    margin:auto;
    border-radius:18px;
    display:flex;
    align-items:center;
    justify-content:center;
    background:linear-gradient(135deg,#38bdf8,#6366f1);
    font-size:30px;
}}

h1 {{
    text-align:center;
    margin:20px 0 8px;
}}

p {{
    text-align:center;
    color:#94a3b8;
}}

input {{
    width:100%;
    padding:15px;
    margin-top:18px;
    border-radius:12px;
    border:1px solid #334155;
    background:#020617;
    color:white;
    text-align:center;
    font-size:22px;
    letter-spacing:6px;
    outline:none;
}}

button {{
    width:100%;
    padding:14px;
    margin-top:14px;
    border:0;
    border-radius:12px;
    background:linear-gradient(135deg,#38bdf8,#6366f1);
    color:white;
    font-size:16px;
    font-weight:bold;
    cursor:pointer;
}}

.error {{
    margin-top:15px;
    padding:10px;
    border-radius:10px;
    background:#7f1d1d;
    color:#fecaca;
    text-align:center;
}}
</style>
</head>

<body>

<div class="card">

<div class="logo">🖥️</div>

<h1>VNC Access</h1>

<p>Masukkan PIN untuk membuka desktop</p>

{msg}

<form method="POST" action="/login">

<input
    name="pin"
    type="password"
    inputmode="numeric"
    autocomplete="one-time-code"
    maxlength="32"
    placeholder="••••••"
    autofocus
>

<button type="submit">
    Masuk ke VNC
</button>

</form>

</div>

</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        return

    def send_html(self, code, content):
        data = content.encode()

        self.send_response(code)
        self.send_header(
            "Content-Type",
            "text/html; charset=utf-8"
        )
        self.send_header(
            "Content-Length",
            str(len(data))
        )
        self.end_headers()
        self.wfile.write(data)

    def send_json_status(self, code):
        self.send_response(code)
        self.send_header(
            "Content-Type",
            "application/json"
        )
        self.send_header(
            "Cache-Control",
            "no-store"
        )
        self.end_headers()

        self.wfile.write(
            b'{"ok":true}'
            if code == 200
            else b'{"ok":false}'
        )

    def do_GET(self):

        if self.path == "/auth":
            cookie = get_cookie(self.headers)

            if validate_cookie(cookie):
                self.send_response(204)
                self.end_headers()
            else:
                self.send_response(401)
                self.end_headers()

            return

        if self.path == "/status":
            cookie = get_cookie(self.headers)

            if validate_cookie(cookie):
                self.send_json_status(200)
            else:
                self.send_json_status(401)

            return

        if self.path == "/heartbeat":
            cookie = get_cookie(self.headers)

            if validate_cookie(cookie):
                self.send_response(204)
                self.send_header(
                    "Set-Cookie",
                    "novnc_session="
                    + make_cookie()
                    + "; Path=/; HttpOnly; SameSite=Lax"
                )
                self.end_headers()
            else:
                self.send_response(401)
                self.end_headers()

            return

        self.send_html(200, page())

    def do_POST(self):

        if self.path != "/login":
            self.send_response(404)
            self.end_headers()
            return

        length = int(
            self.headers.get("Content-Length", "0")
        )

        body = self.rfile.read(length).decode(
            "utf-8",
            errors="ignore"
        )

        params = parse_qs(body)

        submitted = params.get("pin", [""])[0]

        if hmac.compare_digest(submitted, PIN):

            self.send_response(303)

            self.send_header(
                "Location",
                "/vnc.html?autoconnect=true"
            )

            self.send_header(
                "Set-Cookie",
                "novnc_session="
                + make_cookie()
                + "; Path=/; HttpOnly; SameSite=Lax"
            )

            self.end_headers()

        else:
            self.send_html(
                403,
                page("PIN salah.")
            )


if __name__ == "__main__":
    HTTPServer(
        ("127.0.0.1", 9000),
        Handler
    ).serve_forever()
PY

RUN chmod +x /opt/novnc-auth/auth.py

# ============================================================
# NoVNC SETTINGS
# ============================================================

RUN cat > /usr/share/novnc/defaults.json <<'EOF'
{
    "autoconnect": true,
    "reconnect": true,
    "reconnect_delay": 1000,
    "view_clip": true,
    "scale": true
}
EOF

RUN cat > /usr/share/novnc/mandatory.json <<'EOF'
{}
EOF

# ============================================================
# SESSION / IDLE SCRIPT
# ============================================================

RUN cat > /usr/share/novnc/session.js <<'JS'
(() => {

    let lastSent = 0;
    let expired = false;

    const HEARTBEAT_GAP = 15000;

    async function heartbeat() {

        if (expired) return;

        const now = Date.now();

        if (now - lastSent < HEARTBEAT_GAP) {
            return;
        }

        lastSent = now;

        try {

            const r = await fetch(
                "/heartbeat",
                {
                    method: "GET",
                    credentials: "same-origin",
                    cache: "no-store"
                }
            );

            if (!r.ok) {
                expire();
            }

        } catch (_) {
            // temporary network error
        }
    }

    async function checkSession() {

        if (expired) return;

        try {

            const r = await fetch(
                "/status",
                {
                    credentials: "same-origin",
                    cache: "no-store"
                }
            );

            if (!r.ok) {
                expire();
            }

        } catch (_) {
            // temporary network error
        }
    }

    function activity() {
        heartbeat();
    }

    function expire() {

        if (expired) return;

        expired = true;

        window.location.replace("/");
    }

    [
        "mousemove",
        "mousedown",
        "mouseup",
        "wheel",
        "keydown",
        "keyup",
        "touchstart",
        "touchmove",
        "pointerdown",
        "pointermove"
    ].forEach(event => {

        document.addEventListener(
            event,
            activity,
            {
                passive: true
            }
        );

    });

    /*
     * Check expiration without refreshing
     * the idle timer.
     */
    setInterval(
        checkSession,
        5000
    );

})();
JS

# ============================================================
# PATCH NoVNC vnc.html
# ============================================================

RUN python3 - <<'PY'
from pathlib import Path

p = Path("/usr/share/novnc/vnc.html")

text = p.read_text(
    encoding="utf-8",
    errors="ignore"
)

inject = r'''
<script src="/session.js"></script>

<style>
/* Keep the Hand / Drag Viewport button visible */
#noVNC_view_drag_button {
    display: inline-block !important;
}
</style>

<script type="module">
import UI from "./app/ui.js";

function enableViewportDragButton() {

    const button =
        document.getElementById(
            "noVNC_view_drag_button"
        );

    if (button) {
        button.classList.remove(
            "noVNC_hidden"
        );
    }

    if (UI.rfb) {

        try {
            UI.rfb.clipViewport = true;
        } catch (_) {}

        if (typeof UI.updateViewDrag === "function") {
            try {
                UI.updateViewDrag();
            } catch (_) {}
        }
    }
}

setInterval(
    enableViewportDragButton,
    500
);

</script>
'''

if "</body>" in text:
    text = text.replace(
        "</body>",
        inject + "\n</body>",
        1
    )
else:
    text += inject

p.write_text(
    text,
    encoding="utf-8"
)
PY

# ============================================================
# NGINX CONFIG
# ============================================================

RUN rm -f /etc/nginx/sites-enabled/default

RUN cat > /etc/nginx/nginx.conf <<'NGINX'
worker_processes auto;

events {
    worker_connections 1024;
}

http {

    include /etc/nginx/mime.types;

    default_type application/octet-stream;

    sendfile on;

    keepalive_timeout 65;

    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }

    server {

        listen 6080 ssl;

        server_name _;

        ssl_certificate     /root/novnc.crt;
        ssl_certificate_key /root/novnc.key;

        ssl_protocols TLSv1.2 TLSv1.3;

        # ----------------------------------------------------
        # PIN LOGIN
        # ----------------------------------------------------

        location = / {
            proxy_pass http://127.0.0.1:9000;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        location = /login {

            proxy_pass http://127.0.0.1:9000;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        # ----------------------------------------------------
        # SESSION STATUS
        # ----------------------------------------------------

        location = /status {

            proxy_pass http://127.0.0.1:9000;

            proxy_set_header Host $host;
            proxy_set_header Cookie $http_cookie;
        }

        location = /heartbeat {

            proxy_pass http://127.0.0.1:9000;

            proxy_set_header Host $host;
            proxy_set_header Cookie $http_cookie;
        }

        # ----------------------------------------------------
        # INTERNAL AUTH
        # ----------------------------------------------------

        location = /_auth {

            internal;

            proxy_pass http://127.0.0.1:9000/auth;

            proxy_pass_request_body off;

            proxy_set_header Content-Length "";

            proxy_set_header Cookie $http_cookie;
        }

        # ----------------------------------------------------
        # NoVNC PAGE
        # ----------------------------------------------------

        location = /vnc.html {

            auth_request /_auth;

            root /usr/share/novnc;

            try_files /vnc.html =404;

            add_header Cache-Control "no-store";
        }

        # ----------------------------------------------------
        # WEBSOCKET
        # ----------------------------------------------------

        location /websockify {

            auth_request /_auth;

            proxy_pass http://127.0.0.1:6081;

            proxy_http_version 1.1;

            proxy_set_header Upgrade $http_upgrade;

            proxy_set_header Connection $connection_upgrade;

            proxy_set_header Host $host;

            proxy_read_timeout 86400;

            proxy_send_timeout 86400;
        }

        # ----------------------------------------------------
        # NoVNC STATIC FILES
        # ----------------------------------------------------

        location / {

            root /usr/share/novnc;

            try_files $uri $uri/ =404;

            add_header Cache-Control "no-cache";
        }
    }
}
NGINX

# ============================================================
# START SCRIPT
# ============================================================

RUN cat > /usr/local/bin/start-vnc.sh <<'SH'
#!/bin/bash

set -e

echo "========================================"
echo " Ubuntu 24.04 + XFCE + NoVNC"
echo "========================================"

echo "PIN idle timeout: ${PIN_IDLE_TIMEOUT} minutes"

# ------------------------------------------------------------
# Clean old VNC state
# ------------------------------------------------------------

rm -f \
    /tmp/.X1-lock \
    /tmp/.X11-unix/X1 \
    /root/.vnc/*.pid \
    /root/.vnc/*.log \
    2>/dev/null || true

# ------------------------------------------------------------
# Certificate
# ------------------------------------------------------------

if [ ! -f /root/novnc.crt ] || [ ! -f /root/novnc.key ]; then

    openssl req \
        -x509 \
        -nodes \
        -newkey rsa:2048 \
        -days 3650 \
        -subj "/C=ID/O=NoVNC/CN=localhost" \
        -keyout /root/novnc.key \
        -out /root/novnc.crt

fi

# ------------------------------------------------------------
# Start VNC
# ------------------------------------------------------------

vncserver :1 \
    -localhost no \
    -SecurityTypes None \
    -geometry 1024x768 \
    -depth 24

# ------------------------------------------------------------
# Start PIN server
# ------------------------------------------------------------

python3 \
    /opt/novnc-auth/auth.py \
    >/tmp/novnc-auth.log 2>&1 &

# ------------------------------------------------------------
# Start Websockify
# ------------------------------------------------------------

websockify \
    6081 \
    127.0.0.1:5901 \
    --heartbeat 30 \
    >/tmp/websockify.log 2>&1 &

# ------------------------------------------------------------
# Start Ngi
