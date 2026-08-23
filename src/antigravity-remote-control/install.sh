#!/bin/bash
set -e

echo "======================================================="
echo " Installing Antigravity Remote Control Feature v1.3.0"
echo "  Pure Native Google CLI Daemon (antigravity.google)"
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

# Save feature options
ENABLE_LOCAL="${ENABLELOCALINTERFACE:-${enablelocalinterface:-"true"}}"
ENABLE_REMOTE="${ENABLEREMOTECONTROL:-${enableremotecontrol:-"true"}}"
CUSTOM_HOSTNAME="${HOSTNAME:-${hostname:-""}}"

mkdir -p /etc/antigravity
cat << EOF > /etc/antigravity/options.env
ENABLE_LOCAL_INTERFACE="${ENABLE_LOCAL}"
ENABLE_REMOTE_CONTROL="${ENABLE_REMOTE}"
CUSTOM_HOSTNAME="${CUSTOM_HOSTNAME}"
EOF

# 2. Create start-antigravity launcher using native agy binary
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

pkill -9 -f "agy" || true
sleep 1

DAEMON_ARGS=()

if [ "$ENABLE_REMOTE_CONTROL" = "true" ]; then
    DAEMON_ARGS+=("--remote-control")
    if [ -n "$CUSTOM_HOSTNAME" ]; then
        DAEMON_ARGS+=("--remote-control-name" "${CUSTOM_HOSTNAME}")
    fi
fi

if [ "$ENABLE_LOCAL_INTERFACE" = "true" ]; then
    DAEMON_ARGS+=("--hub" "--hub-port" "52425")
fi

nohup /usr/local/bin/agy "${DAEMON_ARGS[@]}" > ~/.gemini/antigravity/agy.log 2>&1 &

echo "Antigravity native daemon started (Local: ${ENABLE_LOCAL_INTERFACE}, Remote Control: ${ENABLE_REMOTE_CONTROL})"
EOF
chmod +x /usr/local/bin/start-antigravity
ln -sf /usr/local/bin/start-antigravity /usr/local/bin/start-antigravity-remote

# 3. Create profile autostart hook
cat << 'EOF' > /etc/profile.d/antigravity-autostart.sh
if [ -x /usr/local/bin/start-antigravity ] && ! pgrep -x agy >/dev/null 2>&1; then
    /usr/local/bin/start-antigravity >/dev/null 2>&1 &
fi
EOF
chmod +x /etc/profile.d/antigravity-autostart.sh

echo "Antigravity Remote Control Feature installed successfully!"
