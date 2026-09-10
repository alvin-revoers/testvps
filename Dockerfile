# syntax=docker/dockerfile:1.4

FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Jakarta
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

RUN apt-get update && apt-get install -y \
    xfce4 \
    xfce4-goodies \
    tigervnc-standalone-server \
    tigervnc-tools \
    novnc \
    websockify \
    nginx \
    python3 \
    openssl \
    curl \
    wget \
    ca-certificates \
    dbus-x11 \
    x11-xserver-utils \
    xterm \
    fonts-noto \
    fonts-noto-core \
    fonts-noto-mono \
    fonts-noto-color-emoji \
    locales \
    papirus-icon-theme \
    arc-theme \
    plank \
    picom \
    procps \
    net-tools \
    && locale-gen en_US.UTF-8 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p \
    /root/.vnc \
    /root/.config/xfce4/xfconf/xfce-perchannel-xml \
    /opt/novnc-auth \
    /tmp/.X11-unix \
    /run/nginx

RUN chmod 1777 /tmp/.X11-unix

RUN touch /root/.Xauthority

# XFCE settings
RUN cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xsettings" version="1.0">
    <property name="Net" type="empty">
        <property name="ThemeName" type="string" value="Arc-Darker"/>
        <property name="IconThemeName" type="string" value="Papirus-Dark"/>
    </property>

    <property name="Gtk" type="empty">
        <property name="FontName" type="string" value="Noto Sans 10"/>
        <property name="CursorThemeName" type="string" value="Adwaita"/>
        <property name="CursorThemeSize" type="int" value="24"/>
    </property>
</channel>
EOF

# VNC desktop startup
RUN cat > /root/.vnc/xstartup <<'EOF'
#!/bin/sh

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8

xrdb "$HOME/.Xresources" 2>/dev/null || true

xsetroot -solid "#111111"

xfdesktop &
xfce4-panel &
thunar --daemon &
plank &
picom >/tmp/picom.log 2>&1 &

exec startxfce4
EOF

RUN sed -i 's/\r$//' /root/.vnc/xstartup \
    && chmod +x /root/.vnc/xstartup

# XTerm UTF-8 configuration
RUN cat > /root/.Xresources <<'EOF'
XTerm*faceName: Noto Sans Mono
XTerm*faceSize: 11
XTerm*utf8Title: true
XTerm*locale: true
XTerm*metaSendsEscape: true
EOF

# ============================================================
# PIN AUTH SERVER
# ============================================================

RUN cat > /opt/novnc-auth/auth.py <<'PY'
#!/usr/bin/env python3

import os
import time
import hmac
import hashlib
import secrets

from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs


PIN = os.environ.get("NOVNC_PIN", "")

try:
    IDLE_TIMEOUT = int(
        os.environ.get("PIN_IDLE_TIMEOUT", "10")
    ) * 60
except ValueError:
    IDLE_TIMEOUT = 600


SECRET_FILE = "/opt/novnc-auth/secret"


if os.path.exists(SECRET_FILE):
    with open(SECRET_FILE, "rb") as f:
        SECRET = f.read()
else:
    SECRET = secrets.token_bytes(32)

    with open(SECRET_FILE, "wb") as f:
        f.write(SECRET)


def create_token(timestamp):
    message = str(timestamp).encode("utf-8")

    signature = hmac.new(
        SECRET,
        message,
        hashlib.sha256
    ).hexdigest()

    return f"{timestamp}.{signature}"


def verify_token(token):
    if not token:
        return False

    if "." not in token:
        return False

    try:
        timestamp, signature = token.split(".", 1)
        timestamp = int(timestamp)
    except Exception:
        return False

    if time.time() - timestamp > IDLE_TIMEOUT:
        return False

    expected = hmac.new(
        SECRET,
        str(timestamp).encode("utf-8"),
        hashlib.sha256
    ).hexdigest()

    return hmac.compare_digest(
        signature,
        expected
    )


def get_cookie(handler):
    cookie = handler.headers.get("Cookie", "")

    for item in cookie.split(";"):
        item = item.strip()

        if item.startswith("NOVNC_SESSION="):
            return item.split("=", 1)[1]

    return None


class Handler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        pass


    def send_text(self, status, text):
        data = text.encode("utf-8")

        self.send_response(status)

        self.send_header(
            "Content-Type",
            "text/plain; charset=utf-8"
        )

        self.send_header(
            "Content-Length",
            str(len(data))
        )

        self.end_headers()

        self.wfile.write(data)


    def do_GET(self):

        if self.path == "/":

            self.send_response(302)

            self.send_header(
                "Location",
                "/login"
            )

            self.end_headers()

            return


        if self.path == "/login":

            html = """<!DOCTYPE html>
<html lang="en">
<head>

<meta charset="UTF-8">

<meta
    name="viewport"
    content="width=device-width, initial-scale=1"
>

<title>VNC Login</title>

<style>

* {
    box-sizing: border-box;
}

html,
body {
    width: 100%;
    height: 100%;
    margin: 0;
}

body {
    background:
        radial-gradient(
            circle at top,
            #202020 0%,
            #090909 45%,
            #030303 100%
        );

    color: #ffffff;

    font-family:
        Arial,
        Helvetica,
        sans-serif;

    display: flex;
    align-items: center;
    justify-content: center;

    padding: 20px;
}

.card {

    width: 100%;
    max-width: 390px;

    padding: 32px;

    border-radius: 22px;

    background:
        rgba(20,20,20,.94);

    border:
        1px solid
        rgba(255,255,255,.10);

    box-shadow:
        0 30px 90px
        rgba(0,0,0,.75);

    backdrop-filter: blur(20px);
}

.logo {

    width: 60px;
    height: 60px;

    margin: 0 auto 20px;

    display: flex;
    align-items: center;
    justify-content: center;

    border-radius: 17px;

    background: #181818;

    font-size: 29px;
}

h1 {

    margin: 0 0 8px;

    text-align: center;

    font-size: 25px;
}

p {

    margin: 0 0 25px;

    text-align: center;

    color: #999999;
}

input {

    width: 100%;

    padding: 15px;

    border-radius: 12px;

    border:
        1px solid
        #333333;

    background: #0b0b0b;

    color: white;

    outline: none;

    text-align: center;

    font-size: 18px;
}

input:focus {

    border-color: #777777;
}

button {

    width: 100%;

    margin-top: 14px;

    padding: 15px;

    border: 0;

    border-radius: 12px;

    background: #ffffff;

    color: #000000;

    font-weight: 700;

    cursor: pointer;

    font-size: 15px;
}

button:hover {

    opacity: .9;
}

</style>

</head>

<body>

<div class="card">

    <div class="logo">🔐</div>

    <h1>VNC Access</h1>

    <p>
        Enter your access PIN to continue
    </p>

    <form method="POST" action="/auth">

        <input
            type="password"
            name="pin"
            placeholder="Enter PIN"
            autocomplete="off"
            autofocus
            required
        >

        <button type="submit">
            Continue
        </button>

    </form>

</div>

</body>
</html>
"""

            data = html.encode("utf-8")

            self.send_response(200)

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

            return


        if self.path == "/status":

            token = get_cookie(self)

            if verify_token(token):
                self.send_text(200, "OK")
            else:
                self.send_text(401, "EXPIRED")

            return


        if self.path == "/heartbeat":

            token = get_cookie(self)

            if not verify_token(token):

                self.send_text(
                    401,
                    "EXPIRED"
                )

                return

            new_token = create_token(
                int(time.time())
            )

            self.send_response(200)

            self.send_header(
                "Content-Type",
                "text/plain"
            )

            self.send_header(
                "Set-Cookie",
                "NOVNC_SESSION="
                + new_token
                + "; Path=/; HttpOnly; SameSite=Lax"
            )

            self.end_headers()

            self.wfile.write(b"OK")

            return


        self.send_text(
            404,
            "Not Found"
        )


    def do_POST(self):

        if self.path != "/auth":

            self.send_text(
                404,
                "Not Found"
            )

            return


        try:

            length = int(
                self.headers.get(
                    "Content-Length",
                    "0"
                )
            )

        except ValueError:

            length = 0


        body = self.rfile.read(
            length
        ).decode(
            "utf-8"
        )


        params = parse_qs(body)

        submitted_pin = params.get(
            "pin",
            [""]
        )[0]


        if PIN and hmac.compare_digest(
            submitted_pin,
            PIN
        ):

            token = create_token(
                int(time.time())
            )

            self.send_response(302)

            self.send_header(
                "Set-Cookie",
                "NOVNC_SESSION="
                + token
                + "; Path=/; HttpOnly; SameSite=Lax"
            )

            self.send_header(
                "Location",
                "/vnc.html?autoconnect=true&resize=scale"
            )

            self.end_headers()

            return


        html = """<!DOCTYPE html>
<html>
<head>

<meta charset="UTF-8">

<meta
    name="viewport"
    content="width=device-width, initial-scale=1"
>

<title>Invalid PIN</title>

<style>

body {

    margin: 0;

    height: 100vh;

    background: #050505;

    color: white;

    font-family: Arial, sans-serif;

    display: flex;

    align-items: center;

    justify-content: center;

    text-align: center;
}

.box {

    padding: 30px;
}

a {

    display: inline-block;

    margin-top: 15px;

    padding: 12px 20px;

    border-radius: 10px;

    background: white;

    color: black;

    text-decoration: none;
}

</style>

</head>

<body>

<div class="box">

<h2>Invalid PIN</h2>

<p>Please try again.</p>

<a href="/login">
    Back
</a>

</div>

</body>
</html>
"""

        data = html.encode("utf-8")

        self.send_response(401)

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


if __name__ == "__main__":

    server = HTTPServer(
        ("127.0.0.1", 9000),
        Handler
    )

    server.serve_forever()
PY

RUN sed -i 's/\r$//' /opt/novnc-auth/auth.py \
    && chmod +x /opt/novnc-auth/auth.py

RUN python3 -m py_compile /opt/novnc-auth/auth.py

# ============================================================
# NOVNC SESSION / IDLE TIMEOUT
# ============================================================

RUN cat > /usr/share/novnc/session.js <<'JS'
(function () {

    "use strict";

    let lastHeartbeat = 0;
    let expired = false;


    function expire() {

        if (expired) {
            return;
        }

        expired = true;

        try {

            if (window.rfb) {
                window.rfb.disconnect();
            }

        } catch (e) {}

        window.location.href = "/";
    }


    function activity() {

        const now = Date.now();

        if (
            now - lastHeartbeat <
            15000
        ) {
            return;
        }

        lastHeartbeat = now;


        fetch(
            "/heartbeat",
            {
                method: "GET",
                credentials: "same-origin",
                cache: "no-store"
            }
        )

        .then(function (response) {

            if (response.status === 401) {
                expire();
            }

        })

        .catch(function () {});
    }


    const events = [

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

    ];


    events.forEach(
        function (event) {

            document.addEventListener(
                event,
                activity,
                {
                    passive: true
                }
            );

        }
    );


    setInterval(
        function () {

            fetch(
                "/status",
                {
                    method: "GET",
                    credentials: "same-origin",
                    cache: "no-store"
                }
            )

            .then(
                function (response) {

                    if (response.status === 401) {
                        expire();
                    }

                }
            )

            .catch(function () {});

        },
        5000
    );

})();
JS

RUN sed -i 's/\r$//' /usr/share/novnc/session.js

# ============================================================
# FORCE NOVNC HAND / DRAG BUTTON
# ============================================================

RUN cat >> /usr/share/novnc/vnc.html <<'EOF'

<style>

#noVNC_view_drag_button {
    display: inline-block !important;
    visibility: visible !important;
    opacity: 1 !important;
}

</style>

<script src="session.js"></script>

EOF

# ============================================================
# NGINX
# ============================================================

RUN cat > /etc/nginx/nginx.conf.template <<'EOF'
events {

    worker_connections 1024;

}

http {

    include /etc/nginx/mime.types;

    default_type application/octet-stream;

    sendfile on;


    map $http_upgrade $connection_upgrade {

        default upgrade;

        '' close;

    }


    upstream auth_backend {

        server 127.0.0.1:9000;

    }


    upstream websocket_backend {

        server 127.0.0.1:6081;

    }


    server {

        listen __PORT__;

        server_name _;


        client_max_body_size 10m;


        location = /_auth {

            internal;

            proxy_pass
                http://auth_backend/status;

            proxy_pass_request_body off;

            proxy_set_header
                Content-Length "";

            proxy_set_header
                X-Original-URI
                $request_uri;

            proxy_set_header
                Cookie
                $http_cookie;

        }


        location = /login {

            proxy_pass
                http://auth_backend/login;

            proxy_set_header
                Host
                $host;

            proxy_set_header
                X-Real-IP
                $remote_addr;

        }


        location = /auth {

            proxy_pass
                http://auth_backend/auth;

            proxy_set_header
                Host
                $host;

            proxy_set_header
                X-Real-IP
                $remote_addr;

        }


        location = /heartbeat {

            proxy_pass
                http://auth_backend/heartbeat;

            proxy_set_header
                Host
                $host;

            proxy_set_header
                Cookie
                $http_cookie;

        }


        location = /status {

            proxy_pass
                http://auth_backend/status;

            proxy_set_header
                Host
                $host;

            proxy_set_header
                Cookie
                $http_cookie;

        }


        location = / {

            proxy_pass
                http://auth_backend/;

            proxy_set_header
                Host
                $host;

        }


        location = /vnc.html {

            auth_request /_auth;

            root /usr/share/novnc;

            try_files
                $uri
                =404;

        }


        location /websockify {

            auth_request /_auth;


            proxy_http_version 1.1;


            proxy_set_header
                Upgrade
                $http_upgrade;

            proxy_set_header
                Connection
                $connection_upgrade;

            proxy_set_header
                Host
                $host;

            proxy_set_header
                X-Real-IP
                $remote_addr;


            proxy_read_timeout 3600s;

            proxy_send_timeout 3600s;


            proxy_pass
                http://websocket_backend;

        }


        location / {

            root /usr/share/novnc;

            try_files
                $uri
                $uri/
                =404;

        }

    }

}
EOF

# ============================================================
# STARTUP SCRIPT
# ============================================================

RUN cat > /usr/local/bin/start-vnc.sh <<'SH'
#!/bin/bash

set -e


export LANG="${LANG:-en_US.UTF-8}"
export LANGUAGE="${LANGUAGE:-en_US:en}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"


PORT="${PORT:-6080}"


mkdir -p \
    /root/.vnc \
    /tmp/.X11-unix \
    /run/nginx


chmod 1777 /tmp/.X11-unix


# Convert configuration files to Unix LF
sed -i 's/\r$//' \
    /root/.vnc/xstartup \
    /opt/novnc-auth/auth.py \
    /usr/share/novnc/session.js


# Generate nginx configuration
sed \
    "s/__PORT__/${PORT}/g" \
    /etc/nginx/nginx.conf.template \
    > /etc/nginx/nginx.conf


# Start PIN authentication server
python3 \
    /opt/novnc-auth/auth.py \
    >/tmp/auth.log 2>&1 &


# Remove stale VNC locks
rm -f \
    /tmp/.X1-lock \
    /tmp/.X11-unix/X1 \
    /root/.vnc/*.pid


# Start TigerVNC
vncserver :1 \
    -geometry 1920x1080 \
    -depth 24 \
    -localhost yes \
    -SecurityTypes None \
    -AlwaysShared \
    -AcceptSetDesktopSize=1


# Start WebSocket proxy
websockify \
    127.0.0.1:6081 \
    localhost:5901 \
    >/tmp/websockify.log 2>&1 &


# Validate nginx configuration
nginx -t


# Run nginx foreground
exec nginx -g "daemon off;"
SH

# IMPORTANT:
# Normalize CRLF so the script can never have a broken shebang.
RUN sed -i 's/\r$//' /usr/local/bin/start-vnc.sh \
    && chmod +x /usr/local/bin/start-vnc.sh


# Verify that the startup script exists
RUN test -f /usr/local/bin/start-vnc.sh \
    && test -x /usr/local/bin/start-vnc.sh


EXPOSE 6080

# Run explicitly through bash.
# This avoids the previous "No such file or directory"
# caused by a broken/CRLF shebang.
CMD ["bash", "/usr/local/bin/start-vnc.sh"]
RUN cat > /usr/share/novnc/session.js <<'JS'
(function () {
    "use strict";

    let lastHeartbeat = 0;
    let expired = false;

    function activity() {
        const now = Date.now();

        if (now - lastHeartbeat < 15000) {
            return;
        }

        lastHeartbeat = now;

        fetch("/heartbeat", {
            method: "GET",
            credentials: "same-origin",
            cache: "no-store"
        }).then(function (response) {
            if (response.status === 401) {
                expire();
            }
        }).catch(function () {});
    }

    function expire() {
        if (expired) return;

        expired = true;

        try {
            if (window.rfb) {
                window.rfb.disconnect();
            }
        } catch (e) {}

        window.location.href = "/";
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
    ].forEach(function (event) {
        document.addEventListener(event, activity, {
            passive: true
        });
    });

    setInterval(function () {
        fetch("/status", {
            method: "GET",
            credentials: "same-origin",
            cache: "no-store"
        }).then(function (response) {
            if (response.status === 401) {
                expire();
            }
        }).catch(function () {});
    }, 5000);
})();
JS

# Force NoVNC Hand / Drag button visible
RUN cat >> /usr/share/novnc/vnc.html <<'EOF'

<style>
#noVNC_view_drag_button {
    display: inline-block !important;
    visibility: visible !important;
    opacity: 1 !important;
}
</style>

<script src="session.js"></script>
EOF

# Nginx template
RUN cat > /etc/nginx/nginx.conf.template <<'EOF'
events {
    worker_connections 1024;
}

http {

    include /etc/nginx/mime.types;

    default_type application/octet-stream;

    sendfile on;

    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }

    upstream auth_backend {
        server 127.0.0.1:9000;
    }

    upstream websocket_backend {
        server 127.0.0.1:6081;
    }

    server {
        listen __PORT__ ssl;
        server_name _;

        ssl_certificate     /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;

        ssl_protocols TLSv1.2 TLSv1.3;

        client_max_body_size 10m;

        location = /_auth {
            internal;

            proxy_pass http://auth_backend/status;
            proxy_pass_request_body off;

            proxy_set_header Content-Length "";
            proxy_set_header X-Original-URI $request_uri;
            proxy_set_header Cookie $http_cookie;
        }

        location = /login {
            proxy_pass http://auth_backend/login;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        location = /auth {
            proxy_pass http://auth_backend/auth;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        location = /heartbeat {
            proxy_pass http://auth_backend/heartbeat;
            proxy_set_header Host $host;
            proxy_set_header Cookie $http_cookie;
        }

        location = /status {
            proxy_pass http://auth_backend/status;
            proxy_set_header Host $host;
            proxy_set_header Cookie $http_cookie;
        }

        location = / {
            proxy_pass http://auth_backend/;
            proxy_set_header Host $host;
        }

        location = /vnc.html {
            auth_request /_auth;

            root /usr/share/novnc;

            try_files $uri =404;
        }

        location /websockify {
            auth_request /_auth;

            proxy_http_version 1.1;

            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;

            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;

            proxy_pass http://websocket_backend;
        }

        location / {
            root /usr/share/novnc;
            try_files $uri $uri/ =404;
        }
    }
}
EOF

# Startup script
RUN cat > /usr/local/bin/start-vnc.sh <<'SH'
#!/bin/bash

set -e

export LANG="${LANG:-en_US.UTF-8}"
export LANGUAGE="${LANGUAGE:-en_US:en}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

PORT="${PORT:-6080}"

mkdir -p \
    /root/.vnc \
    /tmp/.X11-unix \
    /run/nginx \
    /etc/nginx/ssl

chmod 1777 /tmp/.X11-unix

# Generate internal TLS certificate
if [ ! -f /etc/nginx/ssl/cert.pem ] || [ ! -f /etc/nginx/ssl/key.pem ]; then

    openssl req \
        -x509 \
        -nodes \
        -newkey rsa:2048 \
        -days 3650 \
        -keyout /etc/nginx/ssl/key.pem \
        -out /etc/nginx/ssl/cert.pem \
        -subj "/CN=localhost" \
        >/dev/null 2>&1

fi

# Make sure old VNC locks do not block startup
rm -f \
    /tmp/.X1-lock \
    /tmp/.X11-unix/X1 \
    /root/.vnc/*.pid \
    /root/.vnc/*.log

# Generate nginx config using Railway PORT
sed "s/__PORT__/${PORT}/g" \
    /etc/nginx/nginx.conf.template \
    > /etc/nginx/nginx.conf

# Start PIN authentication
python3 /opt/novnc-auth/auth.py &

# Start VNC
vncserver :1 \
    -geometry 1920x1080 \
    -depth 24 \
    -localhost yes \
    -SecurityTypes None \
    -AlwaysShared \
    -AcceptSetDesktopSize=1

# Start WebSocket proxy
websockify \
    --web=/usr/share/novnc \
    127.0.0.1:6081 \
    localhost:5901 \
    >/tmp/websockify.log 2>&1 &

# Validate nginx
nginx -t

# Start nginx in foreground
exec nginx -g "daemon off;"
SH

RUN chmod +x /usr/local/bin/start-vnc.sh

EXPOSE 6080

CMD ["/usr/local/bin/start-vnc.sh"]
