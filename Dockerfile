FROM --platform=linux/amd64 ubuntu:24.04

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
    gnupg \
    ca-certificates \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# =========================================================
# MICROSOFT EDGE (browser utama, ringan & stabil di container)
# =========================================================
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg && \
    chmod 644 /etc/apt/keyrings/microsoft.gpg && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/edge stable main" \
    > /etc/apt/sources.list.d/microsoft-edge.list && \
    apt update -y && \
    apt install -y microsoft-edge-stable && \
    rm -rf /var/lib/apt/lists/*

# Launcher dengan flag aman untuk jalan di dalam container (root, no-sandbox, no-gpu)
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

RUN touch /root/.Xauthority

# =========================================================
# NOVNC — aktifkan tombol hand/drag (pan/scroll) secara default
# Script kecil ini otomatis "klik" tombol drag begitu halaman
# noVNC selesai dimuat, jadi user tidak perlu klik manual.
# =========================================================
RUN sed -i 's#</body>#<script>\
document.addEventListener("DOMContentLoaded", function () {\
  var tryEnableDrag = setInterval(function () {\
    var btn = document.getElementById("noVNC_view_drag_button");\
    if (btn) {\
      btn.click();\
      clearInterval(tryEnableDrag);\
    }\
  }, 300);\
});\
</script>\
</body>#' /usr/share/novnc/vnc.html

# =========================================================
# XSTARTUP — set Edge sebagai browser default
# =========================================================
RUN mkdir -p /root/.vnc && cat > /root/.vnc/xstartup <<'EOF'
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
EOF
RUN chmod +x /root/.vnc/xstartup

EXPOSE 5901
EXPOSE 6080

CMD bash -c "vncserver -localhost no -SecurityTypes None -geometry 1280x800 -depth 24 -xstartup /root/.vnc/xstartup --I-KNOW-THIS-IS-INSECURE && openssl req -new -subj '/C=JP' -x509 -days 365 -nodes -out /tmp/self.pem -keyout /tmp/self.pem && websockify --web /usr/share/novnc/ 6080 localhost:5901 --cert /tmp/self.pem"
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
