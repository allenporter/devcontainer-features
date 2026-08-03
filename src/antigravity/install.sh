#!/bin/bash
set -e

PORT="${PORT:-52425}"

echo "======================================================="
echo " Installing Antigravity DevContainer Feature v1.3.0"
echo "   Persistent Keyring & Auth Session Storage Enabled"
echo "======================================================="

# Install Linux D-Bus, secret-service keyring, socat, and openssh-server
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends \
    dbus-x11 gnome-keyring libsecret-1-0 curl ca-certificates jq socat openssh-server
rm -rf /var/lib/apt/lists/*
mkdir -p /var/run/sshd

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

# Create headless xdg-open OAuth handler with auto socat port binding
cat << 'EOF' > /usr/local/bin/xdg-open
#!/bin/bash
if [ -n "${REMOTE_USER}" ]; then
    TARGET_USER="${REMOTE_USER}"
elif [ -d "/home/vscode" ]; then
    TARGET_USER="vscode"
elif [ -d "/home/admin" ]; then
    TARGET_USER="admin"
else
    TARGET_USER="$(whoami)"
fi
USER_HOME=$(eval echo "~${TARGET_USER}")
mkdir -p "${USER_HOME}/.gemini/antigravity"

URL_LINE="$@"
echo "AUTH_URL: ${URL_LINE}" >> "${USER_HOME}/.gemini/antigravity/auth_urls.log"
echo "${URL_LINE}" > /tmp/antigravity-auth.url

# Extract OAuth callback port from redirect_uri
CALLBACK_PORT=$(echo "${URL_LINE}" | grep -oE 'redirect_uri=http(%3A%2F%2F|://)localhost(%3A|:)[0-9]+' | grep -oE '[0-9]+$' || true)

if [ -n "${CALLBACK_PORT}" ]; then
    echo "Auto-binding socat 0.0.0.0:${CALLBACK_PORT} -> 127.0.0.1:${CALLBACK_PORT}" >> "${USER_HOME}/.gemini/antigravity/auth_urls.log"
    pkill -f "socat TCP-LISTEN:${CALLBACK_PORT}" || true
    nohup socat TCP-LISTEN:${CALLBACK_PORT},fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:${CALLBACK_PORT} >/dev/null 2>&1 &
fi

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
if [ -n "${REMOTE_USER}" ]; then
    TARGET_USER="${REMOTE_USER}"
elif [ -d "/home/vscode" ]; then
    TARGET_USER="vscode"
elif [ -d "/home/admin" ]; then
    TARGET_USER="admin"
else
    TARGET_USER="$(whoami)"
fi
USER_HOME=$(eval echo "~${TARGET_USER}")

if [ -f "${USER_HOME}/.gemini/antigravity/auth_urls.log" ]; then
    echo "=========================================================================="
    echo "🔑 Latest Antigravity OAuth URL:"
    echo "=========================================================================="
    tail -n 2 "${USER_HOME}/.gemini/antigravity/auth_urls.log"
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
if [ -n "${REMOTE_USER}" ]; then
    TARGET_USER="${REMOTE_USER}"
elif [ -d "/home/vscode" ]; then
    TARGET_USER="vscode"
elif [ -d "/home/admin" ]; then
    TARGET_USER="admin"
else
    TARGET_USER="$(whoami)"
fi
USER_HOME=$(eval echo "~${TARGET_USER}")

# Symlink keyring & antigravity configs to persistent PVC volume if /workspaces is mounted
if [ -d "/workspaces" ]; then
    PERSISTENT_DIR="/workspaces/.persistent_${TARGET_USER}"
    sudo mkdir -p "${PERSISTENT_DIR}/.local/share/keyrings" "${PERSISTENT_DIR}/.gemini/antigravity"
    sudo chown -R "${TARGET_USER}:${TARGET_USER}" "${PERSISTENT_DIR}"

    sudo mkdir -p "${USER_HOME}/.local/share" "${USER_HOME}/.gemini"

    if [ ! -L "${USER_HOME}/.local/share/keyrings" ]; then
        if [ -d "${USER_HOME}/.local/share/keyrings" ]; then
            sudo cp -rn "${USER_HOME}/.local/share/keyrings/"* "${PERSISTENT_DIR}/.local/share/keyrings/" 2>/dev/null || true
            sudo rm -rf "${USER_HOME}/.local/share/keyrings"
        fi
        sudo ln -sf "${PERSISTENT_DIR}/.local/share/keyrings" "${USER_HOME}/.local/share/keyrings"
        sudo chown -h "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.local/share/keyrings"
    fi

    if [ ! -L "${USER_HOME}/.gemini/antigravity" ]; then
        if [ -d "${USER_HOME}/.gemini/antigravity" ]; then
            sudo cp -rn "${USER_HOME}/.gemini/antigravity/"* "${PERSISTENT_DIR}/.gemini/antigravity/" 2>/dev/null || true
            sudo rm -rf "${USER_HOME}/.gemini/antigravity"
        fi
        sudo ln -sf "${PERSISTENT_DIR}/.gemini/antigravity" "${USER_HOME}/.gemini/antigravity"
        sudo chown -h "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.gemini/antigravity"
    fi
else
    mkdir -p "${USER_HOME}/.gemini/antigravity"
    mkdir -p "${USER_HOME}/.local/share/keyrings"
fi

if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

pkill -f gnome-keyring-daemon || true
eval $(echo "" | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null || true)
export GNOME_KEYRING_CONTROL

pkill -9 -f language_server || true
pkill -9 -f socat || true
sleep 1

export PATH="/usr/local/bin:${USER_HOME}/.gemini/antigravity/bin:$PATH"

nohup /usr/local/bin/language_server \
  --standalone \
  --override_ide_name antigravity \
  --subclient_type hub \
  --override_ide_version 2.4.2 \
  --override_user_agent_name antigravity \
  --https_server_port 52425 \
  --http_server_port 52424 \
  --csrf_token devcontainer-secret \
  --app_data_dir antigravity \
  --api_server_url https://generativelanguage.googleapis.com \
  --cloud_code_endpoint https://daily-cloudcode-pa.googleapis.com \
  --enable_sidecars > "${USER_HOME}/.gemini/antigravity/language_server.log" 2>&1 &

sleep 1
nohup socat TCP-LISTEN:43635,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:52424 >/dev/null 2>&1 &

echo "Antigravity daemon started on port 52425 (HTTP 43635)"
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
