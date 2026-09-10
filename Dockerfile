FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Jakarta
ENV NOVNC_PIN=123456
ENV PIN_IDLE_TIMEOUT=10

RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-goodies \
    tigervnc-standalone-server \
    novnc \
    websockify \
    nginx \
    python3 \
    dbus-x11 \
    x11-utils \
    x11-xserver-utils \
    x11-apps \
    xterm \
    sudo \
    vim \
    net-tools \
    curl \
    wget \
    git \
    tzdata \
    firefox \
    openssl \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /root/.vnc /opt/novnc-auth /var/log/nginx

RUN printf '#!/bin/bash\n\nxrdb $HOME/.Xresources 2>/dev/null || true\nstartxfce4 &\n' > /root/.vnc/xstartup \
    && chmod +x /root/.vnc/xstartup \
    && touch /root/.Xauthority

# Replace noVNC landing page with PIN page, while keeping the original UI as vnc-real.html.
RUN mv /usr/share/novnc/vnc.html /usr/share/novnc/vnc-real.html

COPY auth_server.py /opt/novnc-auth/auth_server.py
COPY index.html /usr/share/novnc/index.html
COPY vnc.html /usr/share/novnc/vnc.html
COPY nginx.conf /etc/nginx/nginx.conf
COPY start.sh /start.sh

RUN chmod +x /start.sh /opt/novnc-auth/auth_server.py

EXPOSE 6080
EXPOSE 5901

CMD ["/start.sh"]
