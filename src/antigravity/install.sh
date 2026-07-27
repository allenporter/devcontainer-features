#!/bin/bash
set -e

PORT="${PORT:-52425}"
HTTP_PORT="${HTTPPORT:-43635}"

echo "======================================================="
echo " Installing Antigravity DevContainer Feature"
echo "   HTTPS Port : ${PORT}"
echo "   HTTP Port  : ${HTTP_PORT}"
echo "======================================================="

# Install Linux D-Bus & secret-service keyring dependencies for token persistence
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends \
    dbus-x11 gnome-keyring libsecret-1-0 curl ca-certificates jq
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

# Create headless xdg-open OAuth handler
cat << 'EOF' > /usr/local/bin/xdg-open
#!/bin/bash
TARGET_USER="${REMOTE_USER:-vscode}"
USER_HOME=$(eval echo "~${TARGET_USER}")
mkdir -p "${USER_HOME}/.gemini/antigravity"

URL_LINE="$@"
echo "AUTH_URL: ${URL_LINE}" >> "${USER_HOME}/.gemini/antigravity/auth_urls.log"
echo "${URL_LINE}" > /tmp/antigravity-auth.url

# Print prominently to stderr for container log streaming
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

# Initialize D-Bus session if not present
if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval \$(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

# Kill old gnome-keyring instances to prevent daemon locking
pkill -f gnome-keyring-daemon || true

# Initialize & unlock default gnome-keyring headlessly
eval \$(echo "" | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null || true)
export GNOME_KEYRING_CONTROL

pkill -9 -f language_server 2>/dev/null || true
sleep 1

export PATH="/usr/local/bin:\${USER_HOME}/.gemini/antigravity/bin:\$PATH"

nohup /usr/local/bin/language_server \
  --standalone \
  --override_ide_name antigravity \
  --subclient_type hub \
  --override_ide_version 2.4.2 \
  --override_user_agent_name antigravity \
  --https_server_port "${PORT}" \
  --http_server_port "${HTTP_PORT}" \
  --csrf_token devcontainer-secret \
  --app_data_dir antigravity \
  --api_server_url https://generativelanguage.googleapis.com \
  --cloud_code_endpoint https://daily-cloudcode-pa.googleapis.com \
  --enable_sidecars > "\${USER_HOME}/.gemini/antigravity/language_server.log" 2>&1 &

echo "Antigravity language_server daemon started on HTTPS port ${PORT} and HTTP port ${HTTP_PORT} (PID \$!)"
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
