FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# =========================================================
# BASE + XFCE + VNC + NOVNC
# =========================================================
RUN apt update -y && apt install --no-install-recommends -y \
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
# SAFE EDGE LAUNCHER
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
# CREATE CLEAN EDGE DESKTOP ENTRY
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
# VNC DIRECTORY
# =========================================================
RUN mkdir -p \
    /root/.vnc \
    /root/.config/microsoft-edge \
    /root/.config/xfce4/xfconf/xfce-perchannel-xml

RUN touch /root/.Xauthority

# =========================================================
# XFCE VNC STARTUP
# =========================================================
RUN cat > /root/.vnc/xstartup <<'EOF'
#!/bin/sh

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export XDG_CONFIG_DIRS=/etc/xdg/xdg-xfce:/etc/xdg
export XDG_DATA_DIRS=/usr/share/xfce4:/usr/local/share:/usr/share

# Start XFCE
startxfce4 &

# Wait for X/desktop to initialize
sleep 5

# =========================================================
# SET MICROSOFT EDGE AS DEFAULT BROWSER
# Must be done AFTER X session exists.
# =========================================================
export DISPLAY=:1

xdg-settings set default-web-browser microsoft-edge-safe.desktop 2>/dev/null || true

# Explicit MIME associations
xdg-mime default microsoft-edge-safe.desktop text/html 2>/dev/null || true
xdg-mime default microsoft-edge-safe.desktop application/xhtml+xml 2>/dev/null || true
xdg-mime default microsoft-edge-safe.desktop x-scheme-handler/http 2>/dev/null || true
xdg-mime default microsoft-edge-safe.desktop x-scheme-handler/https 2>/dev/null || true
EOF

RUN chmod +x /root/.vnc/xstartup

# =========================================================
# XFCE DEFAULT APPLICATIONS
# =========================================================
RUN mkdir -p /root/.config/xfce4 && \
    cat > /root/.config/xfce4/helpers.rc <<'EOF'
WebBrowser=microsoft-edge-safe
EOF

# =========================================================
# FORCE XFCE TO USE EDGE
# =========================================================
RUN cat > /usr/share/xfce4/helpers/microsoft-edge-safe.desktop <<'EOF'
[Xfce Helpers]
Name=Microsoft Edge
Icon=microsoft-edge
StartupNotify=true
X-XFCE-Binaries=microsoft-edge-safe
X-XFCE-Category=WebBrowser
X-XFCE-Commands=%B %U
X-XFCE-CommandsWithParameter=%B %U
EOF

# =========================================================
# PORTS
# =========================================================
EXPOSE 5901
EXPOSE 6080

# =========================================================
# START VNC + NOVNC
# =========================================================
CMD bash -c '\
    rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true; \
    vncserver -localhost no \
        -SecurityTypes None \
        -geometry 1920x1080 \
        -depth 24 \
        --I-KNOW-THIS-IS-INSECURE && \
    openssl req -new \
        -subj "/C=JP" \
        -x509 \
        -days 365 \
        -nodes \
        -out /tmp/self.pem \
        -keyout /tmp/self.pem && \
    websockify \
        --web /usr/share/novnc/ \
        6080 \
        localhost:5901 \
        --cert /tmp/self.pem \
'
