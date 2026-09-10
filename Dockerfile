FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# =========================================================
# INSTALL XFCE + VNC + NOVNC + TOOLS
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
    openssl \
    && rm -rf /var/lib/apt/lists/*

# =========================================================
# FIREFOX PPA
# =========================================================
RUN apt update -y && \
    apt install -y software-properties-common

RUN add-apt-repository ppa:mozillateam/ppa -y

# =========================================================
# FIREFOX APT PREFERENCES
# =========================================================
RUN echo 'Package: *' \
    >> /etc/apt/preferences.d/mozilla-firefox

RUN echo 'Pin: release o=LP-PPA-mozillateam' \
    >> /etc/apt/preferences.d/mozilla-firefox

RUN echo 'Pin-Priority: 1001' \
    >> /etc/apt/preferences.d/mozilla-firefox

# =========================================================
# FIXED PATH
# /etc/apt/conf.d/     ❌
# /etc/apt/apt.conf.d/ ✅
# =========================================================
RUN echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:jammy";' \
    | tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox

# =========================================================
# INSTALL FIREFOX
# =========================================================
RUN apt update -y && \
    apt install -y firefox

# =========================================================
# XUBUNTU ICON THEME
# =========================================================
RUN apt update -y && \
    apt install -y xubuntu-icon-theme

# =========================================================
# VNC
# =========================================================
RUN mkdir -p /root/.vnc && \
    touch /root/.Xauthority

# =========================================================
# VNC STARTUP
# =========================================================
RUN cat > /root/.vnc/xstartup <<'EOF'
#!/bin/sh

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce

startxfce4 &
EOF

RUN chmod +x /root/.vnc/xstartup

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
    vncserver \
        -localhost no \
        -SecurityTypes None \
        -geometry 1024x768 \
        -depth 24 \
        -xstartup /root/.vnc/xstartup \
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
