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
    gnupg \
    ca-certificates \
    openssl \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# =========================================================
# Microsoft Edge
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
# Edge safe launcher
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

# Replace desktop launcher
RUN if [ -f /usr/share/applications/microsoft-edge.desktop ]; then \
        sed -i 's|^Exec=.*|Exec=/usr/local/bin/edge-safe %U|' \
        /usr/share/applications/microsoft-edge.desktop; \
    fi

# =========================================================
# XFCE settings
# =========================================================
RUN mkdir -p /root/.vnc \
    /root/.config/microsoft-edge \
    /root/.config/xfce4/xfconf/xfce-perchannel-xml

RUN touch /root/.Xauthority

# =========================================================
# VNC xstartup
# =========================================================
RUN cat > /root/.vnc/xstartup <<'EOF'
#!/bin/sh

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export XDG_CONFIG_DIRS=/etc/xdg/xdg-xfce:/etc/xdg
export XDG_DATA_DIRS=/usr/share/xfce4:/usr/local/share:/usr/share

xrdb "$HOME/.Xresources" 2>/dev/null || true

startxfce4 &
EOF

RUN chmod +x /root/.vnc/xstartup

# =========================================================
# noVNC configuration
#
# Force viewport clipping so the Drag/Hand control
# can be used when the remote desktop is larger
# than the mobile browser viewport.
# =========================================================
RUN python3 - <<'PY'
from pathlib import Path

paths = [
    Path("/usr/share/novnc/vnc.html"),
    Path("/usr/share/novnc/app/ui.js"),
]

for p in paths:
    if p.exists():
        print("Found:", p)
PY

# =========================================================
# Custom noVNC startup page
# =========================================================
RUN cp /usr/share/novnc/vnc.html /usr/share/novnc/vnc-original.html

RUN python3 - <<'PY'
from pathlib import Path

p = Path("/usr/share/novnc/vnc.html")

if p.exists():
    text = p.read_text()

    # Add default URL parameters.
    # view_clip=1  -> Clip to Window
    # resize=off   -> Don't resize the remote desktop
    # This keeps the desktop larger than the phone viewport,
    # allowing viewport movement.
    marker = '<body>'

    if marker in text and 'view_clip=1' not in text:
        text = text.replace(
            marker,
            '''<body>
<script>
(function () {
    try {
        const url = new URL(window.location.href);

        if (!url.searchParams.has("view_clip")) {
            url.searchParams.set("view_clip", "1");
        }

        if (!url.searchParams.has("resize")) {
            url.searchParams.set("resize", "off");
        }

        history.replaceState(null, "", url.toString());
    } catch (e) {
        console.log("noVNC viewport configuration:", e);
    }
})();
</script>''',
            1
        )

    p.write_text(text)
PY

# =========================================================
# Custom JavaScript patch
#
# Make sure viewport clipping is enabled after connection.
# =========================================================
RUN if [ -f /usr/share/novnc/app/ui.js ]; then \
    cp /usr/share/novnc/app/ui.js /usr/share/novnc/app/ui-original.js; \
fi

# =========================================================
# Ports
# =========================================================
EXPOSE 5901
EXPOSE 6080

# =========================================================
# Start VNC + noVNC
#
# 1920x1080 intentionally makes the remote desktop larger
# than a typical Android viewport, so viewport dragging
# becomes useful.
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
