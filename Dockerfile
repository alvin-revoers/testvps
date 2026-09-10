FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Jakarta

# =========================================================
# BASE SYSTEM + XFCE + VNC + NOVNC
# =========================================================
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        xfce4 \
        xfce4-goodies \
        tigervnc-standalone-server \
        novnc \
        websockify \
        dbus-x11 \
        x11-utils \
        x11-xserver-utils \
        x11-apps \
        xdg-utils \
        xterm \
        sudo \
        curl \
        wget \
        git \
        vim \
        nano \
        net-tools \
        iproute2 \
        ca-certificates \
        openssl \
        tzdata \
        firefox \
        xubuntu-icon-theme \
    && rm -rf /var/lib/apt/lists/*

# =========================================================
# FIREFOX - CONTAINER FRIENDLY LAUNCHER
# =========================================================
RUN cat > /usr/local/bin/firefox-safe <<'EOF'
#!/bin/bash

exec /usr/bin/firefox \
    --no-remote \
    "$@"
EOF

RUN chmod 755 /usr/local/bin/firefox-safe

# =========================================================
# DEFAULT BROWSER DESKTOP ENTRY
# =========================================================
RUN mkdir -p /usr/share/applications

RUN cat > /usr/share/applications/firefox-safe.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Firefox
Comment=Web Browser
Exec=/usr/local/bin/firefox-safe %U
Icon=firefox
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
EOF

# =========================================================
# XFCE CONFIG
# =========================================================
RUN mkdir -p /root/.config/xfce4 \
             /root/.vnc \
             /root/.config \
             /tmp/.X11-unix

# =========================================================
# STARTUP SCRIPT
# =========================================================
RUN cat > /usr/local/bin/start.sh <<'EOF'
#!/bin/bash

set -e

echo "=========================================="
echo " XFCE + TigerVNC + noVNC"
echo "=========================================="

# ---------------------------------------------------------
# CLEAN OLD DISPLAY FILES
# ---------------------------------------------------------
rm -f /tmp/.X1-lock
rm -f /tmp/.X11-unix/X1

mkdir -p /tmp/.X11-unix
mkdir -p /root/.vnc

touch /root/.Xauthority

# ---------------------------------------------------------
# VNC XSTARTUP
# ---------------------------------------------------------
cat > /root/.vnc/xstartup <<'STARTUP'
#!/bin/sh

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export DISPLAY=:1

export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce

export XDG_CONFIG_DIRS=/etc/xdg/xdg-xfce:/etc/xdg
export XDG_DATA_DIRS=/usr/share/xfce4:/usr/local/share:/usr/share

# Start DBus session
if command -v dbus-launch >/dev/null 2>&1; then
    eval "$(dbus-launch --sh-syntax)"
fi

# Start XFCE
exec startxfce4
STARTUP

chmod 755 /root/.vnc/xstartup

echo "Created:"
ls -l /root/.vnc/xstartup

# ---------------------------------------------------------
# START TIGERVNC
# ---------------------------------------------------------
echo "Starting TigerVNC..."

vncserver :1 \
    -localhost no \
    -SecurityTypes None \
    -geometry 1920x1080 \
    -depth 24 \
    -xstartup /root/.vnc/xstartup \
    --I-KNOW-THIS-IS-INSECURE

# ---------------------------------------------------------
# CHECK VNC
# ---------------------------------------------------------
sleep 2

if ! ss -lnt | grep -q ':5901'; then
    echo "ERROR: TigerVNC gagal listen pada port 5901"
    exit 1
fi

echo "TigerVNC OK: port 5901"

# ---------------------------------------------------------
# SSL CERTIFICATE
# ---------------------------------------------------------
echo "Generating SSL certificate..."

openssl req \
    -new \
    -x509 \
    -nodes \
    -days 365 \
    -subj "/C=ID/ST=Jakarta/L=Jakarta/O=RemoteDesktop/CN=localhost" \
    -out /tmp/novnc.pem \
    -keyout /tmp/novnc.pem

# ---------------------------------------------------------
# START NOVNC
# ---------------------------------------------------------
echo "Starting noVNC..."

exec websockify \
    --web=/usr/share/novnc \
    6080 \
    localhost:5901 \
    --cert=/tmp/novnc.pem
EOF

RUN chmod 755 /usr/local/bin/start.sh

# =========================================================
# NOVNC CONFIG
# =========================================================
# noVNC akan tetap menyediakan viewport/drag functionality.
# Resolution desktop dibuat 1920x1080 supaya pada layar HP
# viewport bisa di-clip dan digeser menggunakan Hand/Drag.
# =========================================================

# =========================================================
# PORT
# =========================================================
EXPOSE 6080
EXPOSE 5901

# =========================================================
# START CONTAINER
# =========================================================
CMD ["/usr/local/bin/start.sh"]
