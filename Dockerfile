FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install XFCE, VNC, noVNC and required tools
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
    openssl

# Microsoft Edge repository
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg && \
    chmod 644 /etc/apt/keyrings/microsoft.gpg && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/edge stable main" \
    > /etc/apt/sources.list.d/microsoft-edge.list

# Install Microsoft Edge
RUN apt update -y && \
    apt install -y microsoft-edge-stable

# Make Microsoft Edge the default browser
RUN xdg-settings set default-web-browser microsoft-edge.desktop || true

# Edge launcher optimized for VNC/container
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

# Replace Edge desktop launcher with the container-safe launcher
RUN if [ -f /usr/share/applications/microsoft-edge.desktop ]; then \
        sed -i 's|^Exec=.*|Exec=/usr/local/bin/edge-safe %U|' \
        /usr/share/applications/microsoft-edge.desktop; \
    fi

# VNC configuration
RUN mkdir -p /root/.vnc && \
    touch /root/.Xauthority

# Reduce Edge shared-memory related crashes
RUN mkdir -p /root/.config/microsoft-edge

# Ports
EXPOSE 5901
EXPOSE 6080

# Start VNC + noVNC
CMD bash -c "\
    vncserver -localhost no \
    -SecurityTypes None \
    -geometry 1024x768 \
    --I-KNOW-THIS-IS-INSECURE && \
    openssl req -new \
    -subj '/C=JP' \
    -x509 \
    -days 365 \
    -nodes \
    -out self.pem \
    -keyout self.pem && \
    websockify \
    --web /usr/share/novnc/ \
    6080 \
    localhost:5901 \
    --cert self.pem"
