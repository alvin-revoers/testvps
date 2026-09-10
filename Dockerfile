FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# =========================================================
# SYSTEM + DESKTOP + GPG
# =========================================================
RUN apt-get update && apt-get install --no-install-recommends -y \
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
    iproute2 \
    curl \
    wget \
    git \
    tzdata \
    dbus-x11 \
    x11-utils \
    x11-xserver-utils \
    x11-apps \
    xdg-utils \
    openssl \
    ca-certificates \
    software-properties-common \
    gnupg \
    gnupg2 \
    gpg-agent \
    dirmngr \
    && rm -rf /var/lib/apt/lists/*

# =========================================================
# MOZILLA FIREFOX PPA
# =========================================================
RUN mkdir -p /etc/apt/apt.conf.d /etc/apt/preferences.d

RUN add-apt-repository ppa:mozillateam/ppa -y

# Prioritas Firefox dari Mozilla PPA
RUN printf '%s\n' \
    'Package: firefox*' \
    'Pin: release o=LP-PPA-mozillateam' \
    'Pin-Priority: 1001' \
    > /etc/apt/preferences.d/mozilla-firefox

# =========================================================
# FIREFOX
# =========================================================
RUN apt-get update && \
    apt-get install -y \
        firefox \
        xubuntu-icon-theme \
    && rm -rf /var/lib/apt/lists/*

# =========================================================
# XFCE / VNC STARTUP
# Dibuat saat CONTAINER START, bukan hanya saat build
# =========================================================
RUN mkdir -p /usr/local/bin

RUN cat > /usr/local/bin/start.sh <<'EOF'
#!/bin/bash
set -e

echo "======================================"
echo " Starting XFCE + TigerVNC + noVNC"
echo "======================================"

# Bersihkan display lama
rm -f /tmp/.X1-lock
rm -f /tmp/.X11-unix/X1

mkdir -p /tmp/.X11-unix
mkdir -p /root/.vnc

touch /root/.Xauthority

# =========================================================
# CREATE VNC XSTARTUP
# =========================================================
cat > /root/.vnc/xstartup <<'STARTUP'
#!/bin/sh

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export XDG_CONFIG_DIRS=/etc/xdg/xdg-xfce:/etc/xdg
export XDG_DATA_DIRS=/usr/share/xfce4:/usr/local/share:/usr/share

# DBus
if command -v dbus-launch >/dev/null 2>&1; then
    eval "$(dbus-launch --sh-syntax)"
fi

# XFCE
exec startxfce4
STARTUP

chmod 755 /root/.vnc/xstartup

echo "xstartup:"
ls -la /root/.vnc/xstartup

# =========================================================
# START TIGERVNC
# =========================================================
vncserver :1 \
    -localhost no \
    -SecurityTypes None \
    -geometry 1024x768 \
    -depth 24 \
    -xstartup /root/.vnc/xstartup \
    --I-KNOW-THIS-IS-INSECURE

echo "TigerVNC started."

# Pastikan VNC listen
sleep 2

if ! ss -lnt | grep -q ':5901'; then
    echo "ERROR: TigerVNC tidak listen di port 5901"
    exit 1
fi

echo "VNC listening on 5901."

# =========================================================
# SSL CERTIFICATE UNTUK NOVNC
# =========================================================
openssl req \
    -new \
    -subj "/C=JP" \
    -x509 \
    -days 365 \
    -nodes \
    -out /tmp/self.pem \
    -keyout /tmp/self.pem

# =========================================================
# START NOVNC / WEBSOCKIFY
# =========================================================
echo "Starting noVNC on port 6080..."

exec websockify \
    --web /usr/share/novnc/ \
    6080 \
    localhost:5901 \
    --cert /tmp/self.pem
EOF

RUN chmod 755 /usr/local/bin/start.sh

# =========================================================
# PORTS
# =========================================================
EXPOSE 5901
EXPOSE 6080

# =========================================================
# START
# =========================================================
CMD ["/usr/local/bin/start.sh"]
