#!/bin/bash
set -e

echo "======================================================="
echo " Installing Antigravity DevContainer Feature v1.5.0"
echo "   Native Kubernetes SubPath Persistence (Zero Hacks)"
echo "======================================================="

# Install Linux D-Bus, secret-service keyring, and libsecret
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends \
    dbus-x11 gnome-keyring libsecret-1-0 curl ca-certificates jq
rm -rf /var/lib/apt/lists/*

# Fetch latest Linux x86_64 AppImage URL and version from Google updater manifest
MANIFEST_URL="https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/manifest/latest-x64-linux.yml"
MANIFEST_CONTENT=$(curl -sSL "$MANIFEST_URL")
APPIMAGE_URL=$(echo "$MANIFEST_CONTENT" | grep -o 'https://.*Antigravity\.AppImage' | head -n 1)
VERSION=$(echo "$MANIFEST_CONTENT" | grep -i '^version:' | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'")

if [ -z "$VERSION" ]; then
    VERSION="2.6.0"
fi

mkdir -p /etc/antigravity
echo "$VERSION" > /etc/antigravity/version

echo "Downloading Antigravity language_server (v${VERSION}) from: ${APPIMAGE_URL}"

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
mkdir -p ~/.gemini/antigravity

URL_LINE="$@"
echo "AUTH_URL: ${URL_LINE}" >> ~/.gemini/antigravity/auth_urls.log
echo "${URL_LINE}" > /tmp/antigravity-auth.url

CALLBACK_PORT=$(echo "${URL_LINE}" | grep -oE 'redirect_uri=http(%3A%2F%2F|://)localhost(%3A|:)[0-9]+' | grep -oE '[0-9]+$' || true)

echo "" >&2
echo "==========================================================================" >&2
echo "🔑 ANTIGRAVITY OAUTH URL DETECTED (Callback Port: ${CALLBACK_PORT}):" >&2
echo "${URL_LINE}" >&2
echo "==========================================================================" >&2
echo "" >&2
EOF
chmod +x /usr/local/bin/xdg-open

# Create easy agy-auth helper script
cat << 'EOF' > /usr/local/bin/agy-auth
#!/bin/bash
if [ -f ~/.gemini/antigravity/auth_urls.log ]; then
    echo "=========================================================================="
    echo "🔑 Latest Antigravity OAuth URL:"
    echo "=========================================================================="
    tail -n 2 ~/.gemini/antigravity/auth_urls.log
    echo "=========================================================================="
else
    echo "No OAuth URL logged yet. Open your workspace HTTP URL in browser and click Sign In."
fi
EOF
chmod +x /usr/local/bin/agy-auth
ln -sf /usr/local/bin/agy-auth /usr/local/bin/antigravity-auth

# Create start-antigravity daemon launcher
cat << 'EOF' > /usr/local/bin/start-antigravity
#!/bin/bash
mkdir -p ~/.local/share/keyrings ~/.gemini/antigravity

if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

pkill -f gnome-keyring-daemon || true
eval $(echo "" | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null || true)
export GNOME_KEYRING_CONTROL

pkill -9 -f language_server || true
sleep 1

AGY_VERSION=$(cat /etc/antigravity/version 2>/dev/null || echo "2.6.0")

nohup /usr/local/bin/language_server \
  --standalone \
  --override_ide_name antigravity \
  --subclient_type hub \
  --override_ide_version "${AGY_VERSION}" \
  --override_user_agent_name antigravity \
  --https_server_port 52425 \
  --http_server_port 52424 \
  --csrf_token devcontainer-secret \
  --app_data_dir antigravity \
  --api_server_url https://generativelanguage.googleapis.com \
  --cloud_code_endpoint https://daily-cloudcode-pa.googleapis.com \
  --enable_sidecars > ~/.gemini/antigravity/language_server.log 2>&1 &

echo "Antigravity daemon v${AGY_VERSION} started on port 52425 (HTTP 52424)"
EOF
chmod +x /usr/local/bin/start-antigravity

# Create profile autostart hook
cat << 'EOF' > /etc/profile.d/antigravity-autostart.sh
if [ -x /usr/local/bin/start-antigravity ] && ! pgrep -x language_server >/dev/null 2>&1; then
    /usr/local/bin/start-antigravity >/dev/null 2>&1 &
fi
EOF
chmod +x /etc/profile.d/antigravity-autostart.sh

echo "Antigravity DevContainer Feature installed successfully!"
