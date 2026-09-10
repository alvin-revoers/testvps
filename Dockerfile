FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Jakarta

# ============================================================
# SYSTEM + MODERN XFCE DESKTOP
# ============================================================

RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-goodies \
    xfce4-whiskermenu-plugin \
    xfce4-pulseaudio-plugin \
    xfce4-terminal \
    xfce4-taskmanager \
    xfce4-notifyd \
    xfce4-screenshooter \
    tigervnc-standalone-server \
    novnc \
    websockify \
    dbus-x11 \
    x11-utils \
    x11-xserver-utils \
    x11-apps \
    xterm \
    sudo \
    vim \
    nano \
    net-tools \
    curl \
    wget \
    git \
    tzdata \
    openssl \
    fonts-dejavu \
    fonts-liberation \
    fonts-noto \
    papirus-icon-theme \
    arc-theme \
    numix-gtk-theme \
    plank \
    picom \
    htop \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# TIMEZONE
# ============================================================

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

# ============================================================
# ROOT VNC DIRECTORY
# ============================================================

RUN mkdir -p /root/.vnc \
    && touch /root/.Xauthority

# ============================================================
# XFCE STARTUP
# ============================================================

RUN printf '%s\n' \
'#!/bin/bash' \
'' \
'export XDG_CURRENT_DESKTOP=XFCE' \
'export XDG_SESSION_DESKTOP=xfce' \
'export DESKTOP_SESSION=xfce' \
'' \
'# Disable screen blanking' \
'xset s off' \
'xset -dpms' \
'xset s noblank' \
'' \
'# Start compositor' \
'picom --experimental-backends &' \
'' \
'# Start modern dock' \
'plank &' \
'' \
'# Start XFCE' \
'startxfce4 &' \
'' \
'wait' \
> /root/.vnc/xstartup

RUN chmod +x /root/.vnc/xstartup

# ============================================================
# MODERN XFCE CONFIG
# ============================================================

RUN mkdir -p /root/.config/xfce4/xfconf/xfce-perchannel-xml

# GTK theme
RUN printf '%s\n' \
'<?xml version="1.0" encoding="UTF-8"?>' \
'<channel name="xsettings" version="1.0">' \
'  <property name="Net" type="empty">' \
'    <property name="ThemeName" type="string" value="Arc-Darker"/>' \
'    <property name="IconThemeName" type="string" value="Papirus-Dark"/>' \
'    <property name="CursorThemeName" type="string" value="Adwaita"/>' \
'    <property name="CursorThemeSize" type="int" value="24"/>' \
'    <property name="DoubleClickDistance" type="int" value="5"/>' \
'    <property name="DoubleClickTime" type="int" value="400"/>' \
'  </property>' \
'  <property name="Gtk" type="empty">' \
'    <property name="FontName" type="string" value="Noto Sans 10"/>' \
'  </property>' \
'</channel>' \
> /root/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml

# Window manager
RUN printf '%s\n' \
'<?xml version="1.0" encoding="UTF-8"?>' \
'<channel name="xfwm4" version="1.0">' \
'  <property name="general" type="empty">' \
'    <property name="theme" type="string" value="Arc-Darker"/>' \
'    <property name="title_font" type="string" value="Noto Sans Bold 10"/>' \
'    <property name="button_layout" type="string" value="CHM|H"/>' \
'    <property name="placement_ratio" type="int" value="20"/>' \
'    <property name="workspace_count" type="int" value="1"/>' \
'  </property>' \
'</channel>' \
> /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml

# ============================================================
# PANEL CONFIG
# ============================================================

RUN printf '%s\n' \
'<?xml version="1.0" encoding="UTF-8"?>' \
'<channel name="xfce4-panel" version="1.0">' \
'  <property name="configver" type="int" value="2"/>' \
'  <property name="panels" type="array">' \
'    <value type="int" value="1"/>' \
'  </property>' \
'  <property name="panels" type="empty">' \
'    <property name="panel-1" type="empty">' \
'      <property name="position" type="string" value="p=6;x=0;y=0"/>' \
'      <property name="length" type="uint" value="100"/>' \
'      <property name="size" type="uint" value="38"/>' \
'      <property name="autohide-behavior" type="uint" value="0"/>' \
'      <property name="plugin-ids" type="array">' \
'        <value type="int" value="1"/>' \
'        <value type="int" value="2"/>' \
'        <value type="int" value="3"/>' \
'        <value type="int" value="4"/>' \
'      </property>' \
'    </property>' \
'  </property>' \
'</channel>' \
> /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml

# ============================================================
# PLANK CONFIG
# ============================================================

RUN mkdir -p /root/.config/plank/dock1

RUN printf '%s\n' \
'[Plank]' \
'Theme=Transparent' \
'IconSize=44' \
'HideMode=Intelligent' \
'Position=Bottom' \
'Alignment=Center' \
'ItemsAlignment=Center' \
'ZoomEnabled=true' \
'ZoomPercent=130' \
'TooltipsEnabled=true' \
'ShowDockItem=true' \
> /root/.config/plank/dock1/settings

# ============================================================
# VNC
# ============================================================

EXPOSE 5901
EXPOSE 6080

# ============================================================
# START
# ============================================================

CMD bash -c '\
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true; \
vncserver :1 \
    -localhost no \
    -SecurityTypes None \
    -geometry 1024x768 \
    -depth 24 \
    && \
openssl req \
    -new \
    -subj "/C=ID" \
    -x509 \
    -days 365 \
    -nodes \
    -out /root/self.pem \
    -keyout /root/self.pem \
    && \
websockify \
    --web /usr/share/novnc/ \
    6080 \
    localhost:5901 \
    --cert /root/self.pem \
'
