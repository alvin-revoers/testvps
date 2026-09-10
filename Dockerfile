FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# =========================================================
# XFCE + VNC + noVNC + tools
# =========================================================
RUN apt update -y && apt install --no-install-recommends -y \
    xfce4 \
    xfce4-goodies \
    tigervnc-standalone-server \
    novnc \
    websockify \
    sudo \
    xterm \
    vim \
    net-tools \
    curl \
    wget \
    git \
    tzdata \
    dbus-x11 \
    x11-utils \
    x11-xserver-utils \
    x11-apps \
    xdg-utils \
    exo-utils \
    desktop-file-utils \
    gnupg \
    ca-certificates \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# =========================================================
# MICROSOFT EDGE
# =========================================================
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg && \
    chmod 644 /etc/apt/keyrings/microsoft.gpg && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/edge stable main" \
    > /etc/apt/sources.list.d/microsoft-edge.list

RUN apt update -y && \
    apt install -y microsoft-edge-stable && \
    rm -rf /var/lib/apt/lists/*

# =========================================================
# EDGE SAFE LAUNCHER
# =========================================================
RUN cat > /usr/local/bin/edge-safe <<'EOF'
#!/bin/bash
exec /usr/bin/microsoft-edge-stable \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --disable-software-rasterizer \
    --disable-background-networking \
    --disable-background-timer-throttling \
    --disable-renderer-backgrounding \
    --disable-features=Translate,BackForwardCache \
    "$@"
EOF
RUN chmod +x /usr/local/bin/edge-safe

# =========================================================
# EDGE DESKTOP ENTRY
# =========================================================
RUN cat > /usr/share/applications/microsoft-edge-safe.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Microsoft Edge
GenericName=Web Browser
Comment=Microsoft Edge Web Browser
Exec=/usr/local/bin/edge-safe %U
Icon=microsoft-edge
Terminal=false
StartupNotify=true
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
Keywords=browser;web;internet;
EOF
RUN chmod 644 /usr/share/applications/microsoft-edge-safe.desktop
RUN update-desktop-database /usr/share/applications || true

# =========================================================
# VNC PASSWORD (default: changeme123 — override at build time)
# =========================================================
ARG VNC_PASSWORD=changeme123
RUN mkdir -p /root/.vnc && \
    touch /root/.Xauthority && \
    echo "${VNC_PASSWORD}" | vncpasswd -f > /root/.vnc/passwd && \
    chmod 600 /root/.vnc/passwd

# =========================================================
# VNC START SCRIPT
# =========================================================
RUN cat > /usr/local/bin/start-vnc.sh <<'EOF'
#!/bin/bash
set -e

# Clean old VNC locks
rm -f /tmp/.X1-lock
rm -f /tmp/.X11-unix/X1

mkdir -p /root/.vnc
touch /root/.Xauthority

# ---------------------------------------------------------
# xstartup
# ---------------------------------------------------------
cat > /root/.vnc/xstartup <<'STARTUP'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export XDG_CONFIG_DIRS=/etc/xdg/xdg-xfce:/etc/xdg
export XDG_DATA_DIRS=/usr/share/xfce4:/usr/local/share:/usr/share

startxfce4 &
sleep 5

xdg-settings set default-web-browser microsoft-edge-safe.desktop 2>/dev/null || true
xdg-mime default microsoft-edge-safe.desktop text/html 2>/dev/null || true
xdg-mime default microsoft-edge-safe.desktop application/xhtml+xml 2>/dev/null || true
xdg-mime default microsoft-edge-safe.desktop x-scheme-handler/http 2>/dev/null || true
xdg-mime default microsoft-edge-safe.desktop x-scheme-handler/https 2>/dev/null || true
STARTUP

chmod +x /root/.vnc/xstartup

# ---------------------------------------------------------
# Start TigerVNC (password-protected)
# ---------------------------------------------------------
vncserver \
    -localhost no \
    -SecurityTypes VncAuth \
    -PasswordFile /root/.vnc/passwd \
    -geometry 1920x1080 \
    -depth 24 \
    -xstartup /root/.vnc/xstartup

# ---------------------------------------------------------
# Self-signed cert for noVNC (only if missing)
# ---------------------------------------------------------
if [ ! -f /tmp/self.pem ]; then
    openssl req -new \
        -subj "/C=JP" \
        -x509 \
        -days 365 \
        -nodes \
        -out /tmp/self.pem \
        -keyout /tmp/self.pem
fi

# ---------------------------------------------------------
# Start noVNC (foreground, keeps container alive)
# ---------------------------------------------------------
exec websockify \
    --web /usr/share/novnc/ \
    6080 \
    localhost:5901 \
    --cert /tmp/self.pem
EOF
RUN chmod +x /usr/local/bin/start-vnc.sh

# =========================================================
# PORTS
# =========================================================
EXPOSE 5901
EXPOSE 6080

# =========================================================
# START
# =========================================================
CMD ["/usr/local/bin/start-vnc.sh"]
# =========================================================
# MICROSOFT EDGE
# =========================================================
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg && \
    chmod 644 /etc/apt/keyrings/microsoft.gpg && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/edge stable main" \
    > /etc/apt/sources.list.d/microsoft-edge.list

RUN apt update -y && \
    apt install -y microsoft-edge-stable && \
    rm -rf /var/lib/apt/lists/*

# =========================================================
# EDGE SAFE LAUNCHER
# =========================================================
RUN cat > /usr/local/bin/edge-safe <<'EOF'
#!/bin/bash

exec /usr/bin/microsoft-edge-stable \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --disable-software-rasterizer \
    --disable-background-networking \
    --disable-background-timer-throttling \
    --disable-renderer-backgrounding \
    --disable-features=Translate,BackForwardCache \
    "$@"
EOF

RUN chmod +x /usr/local/bin/edge-safe

# =========================================================
# EDGE DESKTOP ENTRY
# =========================================================
RUN cat > /usr/share/applications/microsoft-edge-safe.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Microsoft Edge
GenericName=Web Browser
Comment=Microsoft Edge Web Browser
Exec=/usr/local/bin/edge-safe %U
Icon=microsoft-edge
Terminal=false
StartupNotify=true
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
Keywords=browser;web;internet;
EOF

RUN chmod 644 /usr/share/applications/microsoft-edge-safe.desktop

RUN update-desktop-database /usr/share/applications || true

# =========================================================
# VNC START SCRIPT
# =========================================================
RUN mkdir -p /root/.vnc && \
    touch /root/.Xauthority

RUN cat > /usr/local/bin/start-vnc.sh <<'EOF'
#!/bin/bash

set -e

# ---------------------------------------------------------
# Clean old VNC locks
# ---------------------------------------------------------
rm -f /tmp/.X1-lock
rm -f /tmp/.X11-unix/X1

mkdir -p /root/.vnc
touch /root/.Xauthority

# ---------------------------------------------------------
# ALWAYS CREATE xstartup BEFORE vncserver
# ---------------------------------------------------------
cat > /root/.vnc/xstartup <<'STARTUP'
#!/bin/sh

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export XDG_CONFIG_DIRS=/etc/xdg/xdg-xfce:/etc/xdg
export XDG_DATA_DIRS=/usr/share/xfce4:/usr/local/share:/usr/share

# Start XFCE
startxfce4 &

# Wait until XFCE is ready
sleep 5

# ---------------------------------------------------------
# Set Microsoft Edge as default browser
# ---------------------------------------------------------
xdg-settings set default-web-browser microsoft-edge-safe.desktop 2>/dev/null || true

xdg-mime default microsoft-edge-safe.desktop text/html 2>/dev/null || true
xdg-mime default microsoft-edge-safe.desktop application/xhtml+xml 2>/dev/null || true
xdg-mime default microsoft-edge-safe.desktop x-scheme-handler/http 2>/dev/null || true
xdg-mime default microsoft-edge-safe.desktop x-scheme-handler/https 2>/dev/null || true
STARTUP

chmod +x /root/.vnc/xstartup

echo "========================================"
echo "xstartup created:"
ls -l /root/.vnc/xstartup
echo "========================================"

# ---------------------------------------------------------
# Start TigerVNC
# ---------------------------------------------------------
vncserver \
    -localhost no \
    -SecurityTypes None \
    -geometry 1920x1080 \
    -depth 24 \
    -xstartup /root/.vnc/xstartup \
    --I-KNOW-THIS-IS-INSECURE

# ---------------------------------------------------------
# Generate SSL certificate
# ---------------------------------------------------------
openssl req -new \
    -subj "/C=JP" \
    -x509 \
    -days 365 \
    -nodes \
    -out /tmp/self.pem \
    -keyout /tmp/self.pem

# ---------------------------------------------------------
# Start noVNC
# ---------------------------------------------------------
exec websockify \
    --web /usr/share/novnc/ \
    6080 \
    localhost:5901 \
    --cert /tmp/self.pem
EOF

RUN chmod +x /usr/local/bin/start-vnc.sh

# =========================================================
# PORTS
# =========================================================
EXPOSE 5901
EXPOSE 6080

# =========================================================
# START
# =========================================================
CMD ["/usr/local/bin/start-vnc.sh"]
