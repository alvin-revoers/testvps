# syntax=docker/dockerfile:1.4
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Jakarta \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    PIN_IDLE_TIMEOUT=10

RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 xfce4-goodies xfce4-terminal xfce4-taskmanager \
    tigervnc-standalone-server novnc websockify nginx \
    dbus-x11 x11-utils x11-xserver-utils \
    locales tzdata openssl ca-certificates curl wget \
    fonts-noto fonts-noto-color-emoji fonts-liberation \
    papirus-icon-theme arc-theme plank picom \
    python3 python3-minimal \
    && locale-gen en_US.UTF-8 \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /root/.vnc /opt/novnc-auth /tmp/.X11-unix \
    && chmod 1777 /tmp/.X11-unix

RUN cat > /root/.vnc/xstartup <<'SH'
#!/bin/sh
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8
export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export DESKTOP_SESSION=xfce
xset s off || true
xset -dpms || true
xset s noblank || true
picom >/tmp/picom.log 2>&1 &
plank >/tmp/plank.log 2>&1 &
exec startxfce4
SH
RUN chmod +x /root/.vnc/xstartup

RUN cat > /opt/novnc-auth/auth.py <<'PY'
#!/usr/bin/env python3
import os,time,hmac,hashlib,html
from http.server import BaseHTTPRequestHandler,HTTPServer
from urllib.parse import parse_qs

PIN=os.environ.get('NOVNC_PIN','').strip()
try: TIMEOUT=max(1,int(os.environ.get('PIN_IDLE_TIMEOUT','10')))*60
except ValueError: TIMEOUT=600
if not PIN: raise SystemExit('ERROR: NOVNC_PIN is not configured')
SECRET=os.environ.get('NOVNC_SECRET') or hashlib.sha256(os.urandom(32)).hexdigest()
SECRET=SECRET.encode()

def token():
    ts=str(int(time.time()))
    sig=hmac.new(SECRET,ts.encode(),hashlib.sha256).hexdigest()
    return ts+'.'+sig

def valid(cookie):
    if not cookie or 'novnc_session=' not in cookie:return False
    try:
        value=cookie.split('novnc_session=',1)[1].split(';',1)[0]
        ts,sig=value.split('.',1); ts=int(ts)
        if time.time()-ts>TIMEOUT or time.time()-ts<0:return False
        exp=hmac.new(SECRET,str(ts).encode(),hashlib.sha256).hexdigest()
        return hmac.compare_digest(sig,exp)
    except Exception:return False

def getcookie(h): return h.get('Cookie','')

def page(error=''):
    e=f'<div class="err">{html.escape(error)}</div>' if error else ''
    return f'''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>VNC Access</title><style>*{{box-sizing:border-box}}body{{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:radial-gradient(circle at top,#172554,#020617 55%,#000);font-family:Arial,sans-serif;color:#fff;padding:20px}}.card{{width:min(390px,100%);padding:32px;border-radius:24px;background:rgba(15,23,42,.88);border:1px solid #334155;box-shadow:0 25px 80px #0008;text-align:center}}.logo{{font-size:42px}}h1{{margin:14px 0 8px}}p{{color:#94a3b8}}input{{width:100%;padding:15px;margin-top:15px;border-radius:12px;border:1px solid #334155;background:#020617;color:#fff;text-align:center;font-size:22px;letter-spacing:6px;outline:0}}button{{width:100%;padding:14px;margin-top:12px;border:0;border-radius:12px;background:linear-gradient(135deg,#38bdf8,#6366f1);color:white;font-weight:bold;font-size:16px}}.err{{margin-top:14px;padding:10px;border-radius:10px;background:#7f1d1dcc;color:#fecaca}}</style></head><body><div class="card"><div class="logo">🖥️</div><h1>VNC Access</h1><p>Masukkan PIN untuk membuka desktop</p>{e}<form method="POST" action="/login"><input name="pin" type="password" inputmode="numeric" autocomplete="one-time-code" maxlength="32" placeholder="••••••" autofocus><button>Masuk ke VNC</button></form></div></body></html>'''

class H(BaseHTTPRequestHandler):
    def log_message(self,*a):pass
    def html(self,status,body):
        b=body.encode();self.send_response(status);self.send_header('Content-Type','text/html; charset=utf-8');self.send_header('Content-Length',str(len(b)));self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(b)
    def do_GET(self):
        if self.path=='/auth':
            self.send_response(204 if valid(getcookie(self.headers)) else 401);self.end_headers();return
        if self.path=='/status':
            ok=valid(getcookie(self.headers));self.send_response(200 if ok else 401);self.send_header('Content-Type','application/json');self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(b'{"ok":true}' if ok else b'{"ok":false}');return
        if self.path=='/heartbeat':
            if valid(getcookie(self.headers)):
                self.send_response(204);self.send_header('Set-Cookie','novnc_session='+token()+'; Path=/; HttpOnly; SameSite=Lax');self.end_headers()
            else:self.send_response(401);self.end_headers()
            return
        self.html(200,page())
    def do_POST(self):
        if self.path!='/login':self.send_response(404);self.end_headers();return
        try:n=int(self.headers.get('Content-Length','0'))
        except:n=0
        pin=parse_qs(self.rfile.read(n).decode(errors='ignore')).get('pin',[''])[0].strip()
        if hmac.compare_digest(pin,PIN):
            self.send_response(303);self.send_header('Location','/vnc.html?autoconnect=true');self.send_header('Set-Cookie','novnc_session='+token()+'; Path=/; HttpOnly; SameSite=Lax');self.end_headers()
        else:self.html(403,page('PIN salah.'))

HTTPServer(('127.0.0.1',9000),H).serve_forever()
PY
RUN chmod +x /opt/novnc-auth/auth.py

RUN cat > /usr/share/novnc/session.js <<'JS'
(()=>{let last=0,dead=false;const gap=15000;async function hb(){if(dead)return;let n=Date.now();if(n-last<gap)return;last=n;try{let r=await fetch('/heartbeat',{credentials:'same-origin',cache:'no-store'});if(!r.ok)die()}catch(e){}}async function check(){if(dead)return;try{let r=await fetch('/status',{credentials:'same-origin',cache:'no-store'});if(!r.ok)die()}catch(e){}}function die(){if(dead)return;dead=true;location.replace('/')}['mousemove','mousedown','mouseup','wheel','keydown','keyup','touchstart','touchmove','pointerdown','pointermove'].forEach(e=>document.addEventListener(e,hb,{passive:true}));setInterval(check,5000)})();
JS

RUN python3 - <<'PY'
from pathlib import Path
p=Path('/usr/share/novnc/vnc.html')
s=p.read_text(errors='ignore')
extra='''\n<script src="/session.js"></script>\n<style>#noVNC_view_drag_button{display:inline-block!important}</style>\n<script>setInterval(()=>{const b=document.getElementById("noVNC_view_drag_button");if(b){b.classList.remove("noVNC_hidden");b.style.display="inline-block"}},500);</script>\n'''
p.write_text(s.replace('</body>',extra+'</body>',1) if '</body>' in s else s+extra)
PY

RUN rm -f /etc/nginx/sites-enabled/default && cat > /etc/nginx/nginx.conf <<'NGINX'
worker_processes auto;
events { worker_connections 1024; }
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    map $http_upgrade $connection_upgrade { default upgrade; '' close; }
    server {
        listen 6080 ssl;
        server_name _;
        ssl_certificate /root/novnc.crt;
        ssl_certificate_key /root/novnc.key;
        ssl_protocols TLSv1.2 TLSv1.3;

        location = / { proxy_pass http://127.0.0.1:9000; proxy_set_header Host $host; }
        location = /login { proxy_pass http://127.0.0.1:9000; proxy_set_header Host $host; }
        location = /status { proxy_pass http://127.0.0.1:9000; proxy_set_header Cookie $http_cookie; }
        location = /heartbeat { proxy_pass http://127.0.0.1:9000; proxy_set_header Cookie $http_cookie; }
        location = /_auth { internal; proxy_pass http://127.0.0.1:9000/auth; proxy_pass_request_body off; proxy_set_header Content-Length ""; proxy_set_header Cookie $http_cookie; }

        location = /vnc.html { auth_request /_auth; root /usr/share/novnc; try_files /vnc.html =404; add_header Cache-Control "no-store"; }
        location /websockify { auth_request /_auth; proxy_pass http://127.0.0.1:6081; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection $connection_upgrade; proxy_read_timeout 86400; proxy_send_timeout 86400; }
        location / { root /usr/share/novnc; try_files $uri $uri/ =404; }
    }
}
NGINX

RUN cat > /usr/local/bin/start-vnc.sh <<'SH'
#!/bin/bash
set -e
if [ -z "${NOVNC_PIN:-}" ]; then echo 'ERROR: Set NOVNC_PIN in Railway Variables.'; exit 1; fi
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 /root/.vnc/*.pid /root/.vnc/*.log 2>/dev/null || true
mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix
openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj '/C=ID/O=NoVNC/CN=localhost' -keyout /root/novnc.key -out /root/novnc.crt >/tmp/openssl.log 2>&1
chmod 600 /root/novnc.key
vncserver :1 -localhost yes -SecurityTypes None -geometry 1280x800 -depth 24
python3 /opt/novnc-auth/auth.py >/tmp/novnc-auth.log 2>&1 &
websockify 127.0.0.1:6081 127.0.0.1:5901 --heartbeat 30 >/tmp/websockify.log 2>&1 &
nginx -t
exec nginx -g 'daemon off;'
SH
RUN chmod +x /usr/local/bin/start-vnc.sh

EXPOSE 6080
CMD ["/usr/local/bin/start-vnc.sh"]
"/login":
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
