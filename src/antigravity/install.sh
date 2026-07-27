#!/bin/bash
set -e

PORT="${PORT:-52425}"
HTTP_PORT="${HTTPPORT:-43635}"
INTERNAL_HTTPS_PORT=$((PORT - 1))
INTERNAL_HTTP_PORT=$((HTTP_PORT - 1))

echo "======================================================="
echo " Installing Antigravity DevContainer Feature v1.0.14"
echo "   HTTPS (HTTP/2 Multiplexed) Port : ${PORT}"
echo "   HTTP (HTTP/1.1) Port            : ${HTTP_PORT}"
echo "======================================================="

# Install Linux D-Bus, secret-service keyring, openssl, and nginx
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends \
    dbus-x11 gnome-keyring libsecret-1-0 curl ca-certificates jq nginx openssl
rm -rf /var/lib/apt/lists/*

# Fetch latest Linux x86_64 AppImage URL from Google updater manifest
MANIFEST_URL="https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/manifest/latest-x64-linux.yml"
APPIMAGE_URL=$(curl -sSL "$MANIFEST_URL" | grep -o 'https://.*Antigravity\.AppImage' | head -n 1)

echo "Downloading Antigravity language_server from: ${APPIMAGE_URL}"

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
curl -sSL -o Antigravity.AppImage "$APPIMAGE_URL"
chmod +x Antigravity.AppImage
./Antigravity.AppImage --appimage-extract >/dev/null 2>&1

cp squashfs-root/resources/bin/language_server /usr/local/bin/language_server
chmod 755 /usr/local/bin/language_server
cd / && rm -rf "$TMP_DIR"

# Generate SSL Certificate for HTTP/2 multiplexing
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/nginx/antigravity.key \
    -out /etc/nginx/antigravity.crt \
    -subj "/CN=devcontainer-antigravity" 2>/dev/null || true

# Create Nginx configuration with HTTP/1.1 and HTTP/2 Multiplexing
cat << EOF > /etc/nginx/antigravity.conf
events {
    worker_connections 4096;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" rt=\$request_time urt=\$upstream_response_time';
    
    access_log /var/log/nginx/antigravity_access.log main;
    error_log  /var/log/nginx/antigravity_error.log info;

    # HTTP/1.1 Port
    server {
        listen ${HTTP_PORT};
        keepalive_timeout 86400s;
        keepalive_requests 10000;
        location / {
            proxy_pass http://127.0.0.1:${INTERNAL_HTTP_PORT};
            proxy_set_header Host localhost:${INTERNAL_HTTP_PORT};
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_buffering off;
            proxy_cache off;
            proxy_read_timeout 86400s;
            proxy_send_timeout 86400s;
        }
    }

    # HTTP/2 SSL Multiplexed Port (Solves Chrome 6-connection HTTP/1.1 pending limit!)
    server {
        listen ${PORT} ssl http2;
        ssl_certificate /etc/nginx/antigravity.crt;
        ssl_certificate_key /etc/nginx/antigravity.key;
        keepalive_timeout 86400s;
        location / {
            proxy_pass http://127.0.0.1:${INTERNAL_HTTP_PORT};
            proxy_set_header Host localhost:${INTERNAL_HTTP_PORT};
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_buffering off;
            proxy_cache off;
            proxy_read_timeout 86400s;
            proxy_send_timeout 86400s;
        }
    }
}
EOF

# Create headless xdg-open OAuth handler
cat << 'EOF' > /usr/local/bin/xdg-open
#!/bin/bash
TARGET_USER="${REMOTE_USER:-vscode}"
USER_HOME=$(eval echo "~${TARGET_USER}")
mkdir -p "${USER_HOME}/.gemini/antigravity"

URL_LINE="$@"
echo "AUTH_URL: ${URL_LINE}" >> "${USER_HOME}/.gemini/antigravity/auth_urls.log"
echo "${URL_LINE}" > /tmp/antigravity-auth.url

echo "" >&2
echo "==========================================================================" >&2
echo "🔑 ANTIGRAVITY OAUTH URL DETECTED:" >&2
echo "${URL_LINE}" >&2
echo "==========================================================================" >&2
echo "" >&2
EOF
chmod +x /usr/local/bin/xdg-open

# Create easy agy-auth helper script
cat << 'EOF' > /usr/local/bin/agy-auth
#!/bin/bash
TARGET_USER="${REMOTE_USER:-vscode}"
USER_HOME=$(eval echo "~${TARGET_USER}")

if [ -f "${USER_HOME}/.gemini/antigravity/auth_urls.log" ]; then
    echo "=========================================================================="
    echo "🔑 Latest Antigravity OAuth URL:"
    echo "=========================================================================="
    tail -n 1 "${USER_HOME}/.gemini/antigravity/auth_urls.log" | sed 's/^AUTH_URL: //'
    echo "=========================================================================="
else
    echo "No OAuth URL logged yet. Open your workspace HTTP URL in browser and click Sign In."
fi
EOF
chmod +x /usr/local/bin/agy-auth
ln -sf /usr/local/bin/agy-auth /usr/local/bin/antigravity-auth

# Create start-antigravity daemon launcher
cat << EOF > /usr/local/bin/start-antigravity
#!/bin/bash
TARGET_USER="\${REMOTE_USER:-vscode}"
USER_HOME=\$(eval echo "~\${TARGET_USER}")
mkdir -p "\${USER_HOME}/.gemini/antigravity"
mkdir -p "\${USER_HOME}/.local/share/keyrings"

if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval \$(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

pkill -f gnome-keyring-daemon || true
eval \$(echo "" | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null || true)
export GNOME_KEYRING_CONTROL

pkill -9 -f language_server || true
pkill -9 -f nginx || true
sleep 1

export PATH="/usr/local/bin:\${USER_HOME}/.gemini/antigravity/bin:\$PATH"

nohup /usr/local/bin/language_server \
  --standalone \
  --override_ide_name antigravity \
  --subclient_type hub \
  --override_ide_version 2.4.2 \
  --override_user_agent_name antigravity \
  --https_server_port "${INTERNAL_HTTPS_PORT}" \
  --http_server_port "${INTERNAL_HTTP_PORT}" \
  --csrf_token devcontainer-secret \
  --app_data_dir antigravity \
  --api_server_url https://generativelanguage.googleapis.com \
  --cloud_code_endpoint https://daily-cloudcode-pa.googleapis.com \
  --enable_sidecars > "\${USER_HOME}/.gemini/antigravity/language_server.log" 2>&1 &

sleep 1
touch /var/log/nginx/antigravity_access.log
chmod 666 /var/log/nginx/antigravity_access.log 2>/dev/null || true
/usr/sbin/nginx -c /etc/nginx/antigravity.conf >/dev/null 2>&1 &

echo "Antigravity daemon & Nginx HTTP/2 proxy started on ports ${HTTP_PORT} and ${PORT}!"
EOF
chmod +x /usr/local/bin/start-antigravity

# Create profile autostart hook
cat << 'EOF' > /etc/profile.d/antigravity-autostart.sh
if [ -x /usr/local/bin/start-antigravity ] && ! pgrep -f language_server >/dev/null 2>&1; then
    /usr/local/bin/start-antigravity >/dev/null 2>&1 &
fi
EOF
chmod +x /etc/profile.d/antigravity-autostart.sh

echo "Antigravity DevContainer Feature installed successfully!"
