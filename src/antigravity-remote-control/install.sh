#!/bin/bash
set -e

echo "======================================================="
echo " Installing Antigravity Remote Control Feature"
echo "  Google Official CLI Installer & Hybrid Daemon"
echo "======================================================="

export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends \
    dbus-x11 gnome-keyring libsecret-1-0 curl ca-certificates jq git
rm -rf /var/lib/apt/lists/*

# Configure system-wide git safe directory to avoid dubious ownership errors on mounted PVCs
git config --system --add safe.directory "*" || true

# 1. Install official Google Antigravity CLI (agy)
echo "Installing official Google Antigravity CLI via https://antigravity.google/cli/install.sh..."
if ! curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- --dir /usr/local/bin; then
    echo "Direct installer script failed, downloading release archive directly from manifest..."
    CLI_MANIFEST=$(curl -sSL "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json")
    CLI_URL=$(echo "$CLI_MANIFEST" | jq -r '.url')
    TMP_CLI=$(mktemp -d)
    curl -sSL -o "${TMP_CLI}/cli.tar.gz" "$CLI_URL"
    tar -xzf "${TMP_CLI}/cli.tar.gz" -C "${TMP_CLI}"
    cp "${TMP_CLI}/antigravity" /usr/local/bin/agy
    chmod 755 /usr/local/bin/agy
    rm -rf "$TMP_CLI"
fi

ln -sf /usr/local/bin/agy /usr/local/bin/antigravity || true

# 2. Install Antigravity language_server daemon
MANIFEST_URL="https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/manifest/latest-x64-linux.yml"
MANIFEST_CONTENT=$(curl -sSL "$MANIFEST_URL")
APPIMAGE_URL=$(echo "$MANIFEST_CONTENT" | grep -o 'https://.*Antigravity\.AppImage' | head -n 1)
STABLE_VERSION=$(echo "$MANIFEST_CONTENT" | grep -i '^version:' | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'")

REQUESTED_VERSION="${VERSION:-${version:-"latest"}}"
if [ "$REQUESTED_VERSION" = "latest" ] || [ -z "$REQUESTED_VERSION" ]; then
    TARGET_VERSION="$STABLE_VERSION"
else
    TARGET_VERSION="$REQUESTED_VERSION"
    if [ "$REQUESTED_VERSION" != "$STABLE_VERSION" ]; then
        echo "Note: Requested version (${REQUESTED_VERSION}) differs from latest stable (${STABLE_VERSION})."
    fi
fi

if [ -z "$TARGET_VERSION" ]; then
    echo "Fatal: Could not determine Antigravity version from manifest." >&2
    exit 1
fi

echo "-------------------------------------------------------"
echo " Requested Version : ${REQUESTED_VERSION}"
echo " Resolved Version  : ${TARGET_VERSION} (Latest Stable: ${STABLE_VERSION})"
echo " Package URL       : ${APPIMAGE_URL}"
echo "-------------------------------------------------------"

mkdir -p /etc/antigravity
echo "$TARGET_VERSION" > /etc/antigravity/version

ENABLE_LOCAL="${ENABLELOCALINTERFACE:-${enablelocalinterface:-"true"}}"
ENABLE_REMOTE="${ENABLEREMOTECONTROL:-${enableremotecontrol:-"true"}}"
CUSTOM_HOSTNAME="${HOSTNAME:-${hostname:-""}}"

cat << EOF > /etc/antigravity/options.env
ENABLE_LOCAL_INTERFACE="${ENABLE_LOCAL}"
ENABLE_REMOTE_CONTROL="${ENABLE_REMOTE}"
CUSTOM_HOSTNAME="${CUSTOM_HOSTNAME}"
TARGET_VERSION="${TARGET_VERSION}"
EOF

echo "Downloading Antigravity language_server (v${TARGET_VERSION}) from: ${APPIMAGE_URL}"

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
curl -sSL -o Antigravity.AppImage "$APPIMAGE_URL"
chmod +x Antigravity.AppImage
./Antigravity.AppImage --appimage-extract >/dev/null 2>&1

cp squashfs-root/resources/bin/language_server /usr/local/bin/language_server
chmod 755 /usr/local/bin/language_server
cd / && rm -rf "$TMP_DIR"

# 3. Create start-antigravity daemon launcher
cat << 'EOF' > /usr/local/bin/start-antigravity
#!/bin/bash
mkdir -p ~/.local/share/keyrings ~/.gemini/antigravity

if [ -f /etc/antigravity/options.env ]; then
    source /etc/antigravity/options.env
fi

ENABLE_LOCAL_INTERFACE="${ENABLE_LOCAL_INTERFACE:-"true"}"
ENABLE_REMOTE_CONTROL="${ENABLE_REMOTE_CONTROL:-"true"}"

if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

pkill -f gnome-keyring-daemon || true
eval $(echo "" | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null || true)
export GNOME_KEYRING_CONTROL

# Handle Remote Control configuration in state file
STATE_FILE="${HOME}/.gemini/antigravity/antigravity_state.pbtxt"
if [ "$ENABLE_REMOTE_CONTROL" = "true" ]; then
    if [ -f "$STATE_FILE" ]; then
        if ! grep -q "remote_control_enabled" "$STATE_FILE"; then
            echo "remote_control_enabled: true" >> "$STATE_FILE"
        else
            sed -i 's/remote_control_enabled: false/remote_control_enabled: true/g' "$STATE_FILE"
        fi
    else
        echo "remote_control_enabled: true" > "$STATE_FILE"
    fi

    if [ -n "$CUSTOM_HOSTNAME" ]; then
        if ! grep -q "remote_control_hostname" "$STATE_FILE"; then
            echo "remote_control_hostname: \"${CUSTOM_HOSTNAME}\"" >> "$STATE_FILE"
        fi
    fi
fi

pkill -9 -f language_server || true
sleep 1

AGY_VERSION=$(cat /etc/antigravity/version 2>/dev/null || true)

EXTRA_ARGS=()
if [ "$ENABLE_LOCAL_INTERFACE" = "true" ]; then
    EXTRA_ARGS+=(
      "--https_server_port" "52425"
      "--http_server_port" "52424"
      "--csrf_token" "devcontainer-secret"
    )
fi

nohup /usr/local/bin/language_server \
  --standalone \
  --override_ide_name antigravity \
  --subclient_type hub \
  --override_ide_version "${AGY_VERSION}" \
  --override_user_agent_name antigravity \
  --app_data_dir antigravity \
  --api_server_url https://generativelanguage.googleapis.com \
  --cloud_code_endpoint https://cloudcode-pa.googleapis.com \
  --persistent_mode \
  --enable_sidecars \
  "${EXTRA_ARGS[@]}" > ~/.gemini/antigravity/language_server.log 2>&1 &

echo "Antigravity daemon v${AGY_VERSION} started (Local: ${ENABLE_LOCAL_INTERFACE}, Remote Control: ${ENABLE_REMOTE_CONTROL})"
EOF
chmod +x /usr/local/bin/start-antigravity
ln -sf /usr/local/bin/start-antigravity /usr/local/bin/start-antigravity-remote

# 4. Create profile autostart hook
cat << 'EOF' > /etc/profile.d/antigravity-autostart.sh
if [ -x /usr/local/bin/start-antigravity ] && ! pgrep -x language_server >/dev/null 2>&1; then
    /usr/local/bin/start-antigravity >/dev/null 2>&1 &
fi
EOF
chmod +x /etc/profile.d/antigravity-autostart.sh

echo "Antigravity Remote Control Feature installed successfully!"
