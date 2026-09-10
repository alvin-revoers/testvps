#!/bin/bash
set -e

# Generate a fresh certificate for nginx TLS.
openssl req -new -subj "/C=ID/CN=novnc" -x509 -days 365 -nodes \
  -out /root/self.pem -keyout /root/self.pem >/dev/null 2>&1

# Keep the idle timeout in the browser aligned with the deployment variable.
IDLE_MINUTES="${PIN_IDLE_TIMEOUT:-10}"
IDLE_MS=$(( ${IDLE_MINUTES%.*} * 60 * 1000 ))
# Replace the placeholder with the configured value.
sed -i "s/const IDLE=10\*60\*1000;/const IDLE=${IDLE_MS};/" /usr/share/novnc/vnc.html

# Start PIN session service.
python3 /opt/novnc-auth/auth_server.py &

# Start VNC. No VNC password: PIN is enforced at the Web UI layer.
vncserver :1 \
  -localhost no \
  -SecurityTypes None \
  -geometry 1024x768 \
  -depth 24

# Websockify listens internally; nginx performs the Web UI authentication.
websockify 6081 localhost:5901 >/var/log/websockify.log 2>&1 &

nginx -g 'daemon off;'
