FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# =========================================================
# BASE PACKAGES
# =========================================================
RUN apt update -y && \
    apt install --no-install-recommends -y \
    xfce4 \
    xfce4-goodies \
    tigervnc-standalone-server \
    novnc \
    websockify \
    sudo \
    xterm \
    init \
    systemd \
    snapd \
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
    software-properties-common \
    gnupg \
    ca-certificates \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# =========================================================
# MICROSOFT EDGE REPOSITORY
# =========================================================
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg && \
    chmod 644 /etc/apt/keyrings/microsoft.gpg && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/edge stable main" \
    > /etc/apt/sources.list.d/microsoft-edge.list

# =========================================================
# INSTALL MICROSOFT EDGE
# =========================================================
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

RUN chmod 644 /usr/share/applications/microsoft-edge-safe.desktop && \
    update-desktop-database /usr/share/applications || true

# =========================================================
# VNC DIRECTORIES
# =========================================================
RUN mkdir -p /root/.vnc && \
    mkdir -p /root/.config/microsoft-edge && \
    mkdir -p /root/.config/xfce4 && \
    touch /root/.Xauthority

# =========================================================
# VNC STARTUP SCRIPT
# =========================================================
RUN cat > /usr/local/bin/start-vnc.sh <<'EOF'
#!/bin/bash

set -e

echo "========================================"
echo "Starting VNC environment"
echo "========================================"

# Clean old locks
rm -f /tmp/.X1-lock 2>/dev/null || true
rm -f /tmp/.X11-unix/X1 2>/dev/null || true

mkdir -p /root/.vnc
touch /root/.Xauthority

# =========================================================
# CREATE XSTARTUP
# =========================================================
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

# Wait for desktop
sleep 5

# =========================================================
# MICROSOFT EDGE AS DEFAULT BROWSER
# =========================================================
xdg-settings set default-web-browser \
    microsoft-edge-safe.desktop 2>/dev/null || true

xdg-mime default \
    microsoft-edge-safe.desktop \
    text/html 2>/dev/null || true

xdg-mime default \
    microsoft-edge-safe.desktop \
    application/xhtml+xml 2>/dev/null || true

xdg-mime default \
    microsoft-edge-safe.desktop \
    x-scheme-handler/http 2>/dev/null || true

xdg-mime default \
    microsoft-edge-safe.desktop \
    x-scheme-handler/https 2>/dev/null || true
STARTUP

chmod +x /root/.vnc/xstartup

echo "========================================"
echo "Checking xstartup"
echo "========================================"

ls -lah /root/.vnc/
ls -lah /root/.vnc/xstartup

# =========================================================
# START TIGERVNC
# =========================================================
echo "========================================"
echo "Starting TigerVNC"
echo "========================================"

vncserver \
    -localhost no \
    -SecurityTypes None \
    -geometry 1920x1080 \
    -depth 24 \
    -xstartup /root/.vnc/xstartup \
    --I-KNOW-THIS-IS-INSECURE

# =========================================================
# SSL CERTIFICATE
# =========================================================
echo "========================================"
echo "Creating SSL certificate"
echo "========================================"

openssl req -new \
    -subj "/C=JP" \
    -x509 \
    -days 365 \
    -nodes \
    -out /tmp/self.pem \
    -keyout /tmp/self.pem

# =========================================================
# START NOVNC
# =========================================================
echo "========================================"
echo "Starting noVNC on port 6080"
echo "========================================"

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
# START CONTAINER
# =========================================================
CMD ["/usr/local/bin/start-vnc.sh"]
