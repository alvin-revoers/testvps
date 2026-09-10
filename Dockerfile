FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

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
    openssl \
    software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Firefox PPA
RUN add-apt-repository ppa:mozillateam/ppa -y

# Firefox preferences
RUN echo 'Package: *' >> /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Pin: release o=LP-PPA-mozillateam' >> /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Pin-Priority: 1001' >> /etc/apt/preferences.d/mozilla-firefox

# FIX: apt.conf.d, bukan conf.d
RUN echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:jammy";' \
    > /etc/apt/apt.conf.d/51unattended-upgrades-firefox

RUN apt update -y && \
    apt install -y firefox xubuntu-icon-theme && \
    rm -rf /var/lib/apt/lists/*

# =========================================================
# START SCRIPT
# =========================================================
RUN cat > /usr/local/bin/start.sh <<'EOF'
#!/bin/bash

set -e

echo "========================================"
echo "Preparing VNC"
echo "========================================"

# Bersihkan session lama
rm -rf /tmp/.X1-lock
rm -rf /tmp/.X11-unix/X1

mkdir -p /root/.vnc
touch /root/.Xauthority

# =========================================================
# BUAT XSTARTUP SAAT CONTAINER START
# =========================================================
cat > /root/.vnc/xstartup <<'STARTUP'
#!/bin/sh

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export XDG_CONFIG_DIRS=/etc/xdg/xdg-xfce:/etc/xdg
export XDG_DATA_DIRS=/usr/share/xfce4:/usr/local/share:/usr/share

exec startxfce4
STARTUP

chmod 755 /root/.vnc/xstartup

echo "========================================"
echo "Checking xstartup"
echo "========================================"

if [ ! -f /root/.vnc/xstartup ]; then
    echo "ERROR: xstartup was not created!"
    exit 1
fi

if [ ! -x /root/.vnc/xstartup ]; then
    echo "ERROR: xstartup is not executable!"
    exit 1
fi

ls -lah /root/.vnc/xstartup

# =========================================================
# START TIGERVNC
# =========================================================
echo "========================================"
echo "Starting TigerVNC"
echo "========================================"

vncserver \
    :1 \
    -localhost no \
    -SecurityTypes None \
    -geometry 1024x768 \
    -depth 24 \
    -xstartup /root/.vnc/xstartup \
    --I-KNOW-THIS-IS-INSECURE

# Pastikan VNC benar-benar hidup
if ! ss -lnt | grep -q ':5901'; then
    echo "ERROR: TigerVNC is not listening on 5901!"
    exit 1
fi

echo "TigerVNC is running on port 5901"

# =========================================================
# SSL CERTIFICATE
# =========================================================
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

RUN chmod 755 /usr/local/bin/start.sh

EXPOSE 5901
EXPOSE 6080

CMD ["/usr/local/bin/start.sh"]
