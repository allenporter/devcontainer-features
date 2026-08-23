#!/bin/bash
set -e

echo "======================================================="
echo " Installing Antigravity Remote Control & Hub (v1.6.0)"
echo "  (Language Server v2.9.1 + Native agy CLI Bundle)"
echo "======================================================="

export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends \
    dbus-x11 gnome-keyring libsecret-1-0 curl ca-certificates jq git
rm -rf /var/lib/apt/lists/*

git config --system --add safe.directory "*" || true

# 1. Fetch latest Linux x86_64 AppImage URL and extract language_server (v2.9.1)
MANIFEST_URL="https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/manifest/latest-x64-linux.yml"
MANIFEST_CONTENT=$(curl -sSL "$MANIFEST_URL")
APPIMAGE_URL=$(echo "$MANIFEST_CONTENT" | grep -o 'https://.*Antigravity\.AppImage' | head -n 1)
STABLE_VERSION=$(echo "$MANIFEST_CONTENT" | grep -i '^version:' | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'")

REQUESTED_VERSION="${VERSION:-${version:-"latest"}}"
if [ "$REQUESTED_VERSION" = "latest" ] || [ -z "$REQUESTED_VERSION" ]; then
    TARGET_VERSION="$STABLE_VERSION"
else
    TARGET_VERSION="$REQUESTED_VERSION"
fi

if [ -z "$TARGET_VERSION" ]; then
    TARGET_VERSION="2.9.1"
fi

mkdir -p /etc/antigravity
echo "$TARGET_VERSION" > /etc/antigravity/version

echo "Downloading Antigravity language_server (v${TARGET_VERSION}) from: ${APPIMAGE_URL}"
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
curl -sSL -o Antigravity.AppImage "$APPIMAGE_URL"
chmod +x Antigravity.AppImage
./Antigravity.AppImage --appimage-extract >/dev/null 2>&1
cp squashfs-root/resources/bin/language_server /usr/local/bin/language_server
chmod 755 /usr/local/bin/language_server
cd / && rm -rf "$TMP_DIR"

# 2. Install official Google Antigravity CLI (agy)
echo "Installing official Google Antigravity CLI (agy)..."
curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- --dir /usr/local/bin
ln -sf /usr/local/bin/agy /usr/local/bin/antigravity || true
chmod 777 /usr/local/bin/agy || true

# 3. Create start-antigravity Launcher
cat << 'EOF' > /usr/local/bin/start-antigravity
#!/bin/bash
mkdir -p ~/.local/share/keyrings ~/.gemini/antigravity ~/.gemini/antigravity-cli ~/.local/bin

# Sync tokens across components so CLI and Language Server share authentication
if [ -f ~/.gemini/antigravity-cli/antigravity-oauth-token ]; then
    ln -sf ~/.gemini/antigravity-cli/antigravity-oauth-token ~/.gemini/jetski-standalone-oauth-token
    ln -sf ~/.gemini/antigravity-cli/antigravity-oauth-token ~/.gemini/antigravity/antigravity-oauth-token
    ln -sf ~/.gemini/antigravity-cli/antigravity-oauth-token ~/.gemini/antigravity/jetski-standalone-oauth-token
elif [ -f ~/.gemini/jetski-standalone-oauth-token ]; then
    ln -sf ~/.gemini/jetski-standalone-oauth-token ~/.gemini/antigravity-cli/antigravity-oauth-token
    ln -sf ~/.gemini/jetski-standalone-oauth-token ~/.gemini/antigravity/antigravity-oauth-token
fi

if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

pkill -f gnome-keyring-daemon || true
eval $(echo "" | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null || true)
export GNOME_KEYRING_CONTROL

pkill -9 -f "language_server" || pkill -9 -f "agy.*--remote-control" || true
sleep 1

AGY_VERSION=$(cat /etc/antigravity/version 2>/dev/null || echo "2.9.1")

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

echo "Antigravity Hub daemon v${AGY_VERSION} started on port 52424 (HTTPS 52425)"
EOF
chmod +x /usr/local/bin/start-antigravity

echo "Antigravity Remote Control & Hub Feature v1.6.0 installed successfully!"
