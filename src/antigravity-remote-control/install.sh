#!/bin/bash
set -e

echo "======================================================="
echo " Installing Antigravity Remote Control & Hub"
echo "  (Official Google Native CLI & Headless Daemon)"
echo "======================================================="

export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends \
    dbus-x11 gnome-keyring libsecret-1-0 curl ca-certificates git
rm -rf /var/lib/apt/lists/*

# Configure system-wide git safe directory to avoid dubious ownership errors on mounted PVCs
git config --system --add safe.directory "*" || true

# 1. Install official Google Antigravity CLI (agy)
echo "Running official Google installer: https://antigravity.google/cli/install.sh..."
curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- --dir /usr/local/bin

ln -sf /usr/local/bin/agy /usr/local/bin/antigravity || true

# 2. Save Feature Options
ENABLE_LOCAL="${ENABLELOCALINTERFACE:-${enablelocalinterface:-"true"}}"
ENABLE_REMOTE="${ENABLEREMOTECONTROL:-${enableremotecontrol:-"true"}}"
HUB_PORT="${HUBPORT:-${hubport:-"52425"}}"
CUSTOM_HOSTNAME="${HOSTNAME:-${hostname:-""}}"

mkdir -p /etc/antigravity
cat << EOF > /etc/antigravity/options.env
ENABLE_LOCAL_INTERFACE="${ENABLE_LOCAL}"
ENABLE_REMOTE_CONTROL="${ENABLE_REMOTE}"
HUB_PORT="${HUB_PORT}"
CUSTOM_HOSTNAME="${CUSTOM_HOSTNAME}"
EOF

# 3. Create start-antigravity Launcher
cat << 'EOF' > /usr/local/bin/start-antigravity
#!/bin/bash
mkdir -p ~/.local/share/keyrings ~/.gemini/antigravity ~/.local/bin

if [ -f /etc/antigravity/options.env ]; then
    source /etc/antigravity/options.env
fi

ENABLE_LOCAL_INTERFACE="${ENABLE_LOCAL_INTERFACE:-"true"}"
ENABLE_REMOTE_CONTROL="${ENABLE_REMOTE_CONTROL:-"true"}"
HUB_PORT="${HUB_PORT:-"52425"}"

if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

pkill -f gnome-keyring-daemon || true
eval $(echo "" | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null || true)
export GNOME_KEYRING_CONTROL

pkill -9 -f "agy.*--remote-control" || pkill -9 -f "language_server" || true
sleep 1

FLAGS=()
if [ "$ENABLE_REMOTE_CONTROL" = "true" ]; then
    FLAGS+=("--remote-control")
    if [ -n "$CUSTOM_HOSTNAME" ]; then
        FLAGS+=("--remote-control-name" "$CUSTOM_HOSTNAME")
    fi
else
    FLAGS+=("--remote-control")
fi

if [ "$ENABLE_LOCAL_INTERFACE" = "true" ]; then
    FLAGS+=("--hub-port" "$HUB_PORT")
fi

nohup /usr/local/bin/agy "${FLAGS[@]}" > ~/.gemini/antigravity/agy.log 2>&1 &

echo "Antigravity native daemon started (Flags: ${FLAGS[*]})"
EOF
chmod +x /usr/local/bin/start-antigravity

echo "Antigravity Remote Control & Hub Feature installed successfully!"
