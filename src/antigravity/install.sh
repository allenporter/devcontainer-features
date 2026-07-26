#!/bin/bash
set -e

PORT="${PORT:-52425}"

echo "======================================================="
echo " Installing Antigravity DevContainer Feature"
echo "======================================================="

# Install Linux D-Bus & secret-service keyring dependencies for token persistence
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends \
    dbus-x11 gnome-keyring libsecret-1-0 curl ca-certificates jq
rm -rf /var/lib/apt/lists/*

# Run official Google Antigravity installer
echo "Running official Antigravity installer..."
curl -fsSL https://antigravity.google/install.sh | bash

# Create headless xdg-open OAuth handler
cat << 'EOF' > /usr/local/bin/xdg-open
#!/bin/bash
TARGET_USER="${REMOTE_USER:-vscode}"
USER_HOME=$(eval echo "~${TARGET_USER}")
mkdir -p "${USER_HOME}/.gemini/antigravity"
echo "AUTH_URL: $@" >> "${USER_HOME}/.gemini/antigravity/auth_urls.log"
EOF
chmod +x /usr/local/bin/xdg-open

# Create start-antigravity daemon launcher
cat << EOF > /usr/local/bin/start-antigravity
#!/bin/bash
TARGET_USER="\${REMOTE_USER:-vscode}"
USER_HOME=\$(eval echo "~\${TARGET_USER}")
mkdir -p "\${USER_HOME}/.gemini/antigravity"

if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval \$(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

pkill -9 -f language_server 2>/dev/null || true
sleep 1

export PATH="/usr/local/bin:\${USER_HOME}/.gemini/antigravity/bin:\$PATH"

nohup language_server \
  --standalone \
  --override_ide_name antigravity \
  --subclient_type hub \
  --override_ide_version 2.4.2 \
  --override_user_agent_name antigravity \
  --https_server_port "${PORT}" \
  --csrf_token devcontainer-secret \
  --app_data_dir antigravity \
  --api_server_url https://generativelanguage.googleapis.com \
  --cloud_code_endpoint https://daily-cloudcode-pa.googleapis.com \
  --enable_sidecars > "\${USER_HOME}/.gemini/antigravity/language_server.log" 2>&1 &

echo "Antigravity language_server daemon started on port ${PORT} (PID \$!)"
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
