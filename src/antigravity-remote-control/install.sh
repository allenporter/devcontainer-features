#!/bin/bash
set -e

echo "======================================================="
echo " Installing Antigravity Remote Control & Hub (v1.7.0)"
echo "  (Language Server + Native agy CLI + Self-Updater)"
echo "======================================================="

export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends \
    dbus-x11 gnome-keyring libsecret-1-0 curl ca-certificates jq git psmisc python3
rm -rf /var/lib/apt/lists/*

git config --system --add safe.directory "*" || true

# Disable Microsoft's dummy systemctl shim if present so agy remote-control uses its native container fallback
if [ -f /usr/local/bin/systemctl ] && grep -q "is not running in this container" /usr/local/bin/systemctl 2>/dev/null; then
    mv /usr/local/bin/systemctl /usr/local/bin/systemctl.devcontainer-shim.bak || true
fi

# 1. Fetch latest Linux x86_64 package URL and extract language_server
MANIFEST_URL="https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/manifest/latest-x64-linux.yml"
MANIFEST_CONTENT=$(curl -sSL "$MANIFEST_URL")
DEB_URL=$(echo "$MANIFEST_CONTENT" | grep -oE 'https://[^[:space:]]+Antigravity\.deb' | head -n 1 || true)
APPIMAGE_URL=$(echo "$MANIFEST_CONTENT" | grep -oE 'https://[^[:space:]]+Antigravity\.AppImage' | head -n 1 || true)
STABLE_VERSION=$(echo "$MANIFEST_CONTENT" | grep -i '^version:' | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'")

REQUESTED_VERSION="${VERSION:-${version:-"latest"}}"
if [ "$REQUESTED_VERSION" = "latest" ] || [ -z "$REQUESTED_VERSION" ]; then
    TARGET_VERSION="$STABLE_VERSION"
else
    TARGET_VERSION="$REQUESTED_VERSION"
fi

if [ -z "$TARGET_VERSION" ]; then
    TARGET_VERSION="2.24.0"
fi

mkdir -p /etc/antigravity
echo "$TARGET_VERSION" > /etc/antigravity/version

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
if [ -n "$DEB_URL" ]; then
    echo "Downloading Antigravity language_server (v${TARGET_VERSION}) from: ${DEB_URL}"
    curl -sSL -o antigravity.deb "$DEB_URL"
    dpkg-deb -x antigravity.deb extract
    cp extract/opt/Antigravity/resources/bin/language_server /usr/local/bin/language_server
else
    echo "Downloading Antigravity language_server (v${TARGET_VERSION}) from: ${APPIMAGE_URL}"
    curl -sSL -o Antigravity.AppImage "$APPIMAGE_URL"
    chmod +x Antigravity.AppImage
    ./Antigravity.AppImage --appimage-extract >/dev/null 2>&1
    cp squashfs-root/resources/bin/language_server /usr/local/bin/language_server
fi
chmod 755 /usr/local/bin/language_server
cd / && rm -rf "$TMP_DIR"

# 2. Install official Google Antigravity CLI (agy)
echo "Installing official Google Antigravity CLI (agy)..."
curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- --dir /usr/local/bin
ln -sf /usr/local/bin/agy /usr/local/bin/antigravity || true
chmod 775 /usr/local/bin/agy || true
chgrp vscode /usr/local/bin 2>/dev/null || true
chmod 775 /usr/local/bin 2>/dev/null || true

# 3. Install agy-upgrade CLI tool for on-demand staging & persistent upgrades
cat << 'EOF' > /usr/local/bin/agy-upgrade
#!/bin/bash
set -euo pipefail

PERSISTENT_BIN="/workspaces/.persistent/bin"
VERSION_FILE="${PERSISTENT_BIN}/version"
ETC_VERSION_FILE="/etc/antigravity/version"
MANIFEST_URL="https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/manifest/latest-x64-linux.yml"

MODE="restart"
FORCE=0
TARGET_VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check|-c)
            MODE="check"
            shift
            ;;
        --stage|-s)
            MODE="stage"
            shift
            ;;
        --restart|-r)
            MODE="restart"
            shift
            ;;
        --force|-f)
            FORCE=1
            shift
            ;;
        --version|-v)
            TARGET_VERSION="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: agy-upgrade [--check | --stage | --restart] [--force]"
            echo "  --check    Check current vs upstream versions without modifying anything"
            echo "  --stage    Download and stage latest binaries in ${PERSISTENT_BIN} without restarting"
            echo "  --restart  Stage latest binaries and gracefully restart language_server (default)"
            echo "  --force    Re-download even if version matches"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

mkdir -p "${PERSISTENT_BIN}"

CURRENT_VERSION="unknown"
if [[ -f "${VERSION_FILE}" ]]; then
    CURRENT_VERSION=$(tr -d '[:space:]' < "${VERSION_FILE}")
elif [[ -f "${ETC_VERSION_FILE}" ]]; then
    CURRENT_VERSION=$(tr -d '[:space:]' < "${ETC_VERSION_FILE}")
fi

RUNNING_VERSION=$(ps -eo args | grep -oE 'language_server.*--override_ide_version [^ ]+' | awk '{print $NF}' | head -n 1 || true)
if [[ -z "${RUNNING_VERSION}" ]]; then
    RUNNING_VERSION="${CURRENT_VERSION}"
fi

CURRENT_CLI_VERSION=$("${PERSISTENT_BIN}/agy" --version 2>/dev/null || /usr/local/bin/agy --version 2>/dev/null || echo "unknown")

MANIFEST_CONTENT=$(curl -fsSL "${MANIFEST_URL}")
LATEST_VERSION=$(echo "${MANIFEST_CONTENT}" | grep -i '^version:' | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'" | tr -d '[:space:]')
DEB_URL=$(echo "${MANIFEST_CONTENT}" | grep -oE 'https://[^[:space:]]+Antigravity\.deb' | head -n 1 || true)
APPIMAGE_URL=$(echo "${MANIFEST_CONTENT}" | grep -oE 'https://[^[:space:]]+Antigravity\.AppImage' | head -n 1 || true)

if [[ -n "${TARGET_VERSION}" && "${TARGET_VERSION}" != "latest" ]]; then
    LATEST_VERSION="${TARGET_VERSION}"
fi

echo "Antigravity Engine : running=${RUNNING_VERSION}, staged=${CURRENT_VERSION}, upstream=${LATEST_VERSION}"
echo "Antigravity CLI    : installed=${CURRENT_CLI_VERSION}"

if [[ "${MODE}" == "check" ]]; then
    if [[ "${RUNNING_VERSION}" != "${LATEST_VERSION}" ]]; then
        echo "Update available: ${RUNNING_VERSION} -> ${LATEST_VERSION}"
    else
        echo "Antigravity Engine is up to date (${RUNNING_VERSION})."
    fi
    exit 0
fi

# 1. Update language_server if needed or forced
if [[ "${CURRENT_VERSION}" != "${LATEST_VERSION}" || "${FORCE}" -eq 1 || ! -x "${PERSISTENT_BIN}/language_server" ]]; then
    echo "⟳ Downloading Antigravity Engine v${LATEST_VERSION}..."
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "${TMP_DIR}"' EXIT

    if [[ -n "${DEB_URL}" ]]; then
        curl -fsSL -o "${TMP_DIR}/antigravity.deb" "${DEB_URL}"
        dpkg-deb -x "${TMP_DIR}/antigravity.deb" "${TMP_DIR}/extract"
        EXTRACTED_BIN="${TMP_DIR}/extract/opt/Antigravity/resources/bin/language_server"
    elif [[ -n "${APPIMAGE_URL}" ]]; then
        curl -fsSL -o "${TMP_DIR}/Antigravity.AppImage" "${APPIMAGE_URL}"
        chmod +x "${TMP_DIR}/Antigravity.AppImage"
        (cd "${TMP_DIR}" && ./Antigravity.AppImage --appimage-extract >/dev/null 2>&1)
        EXTRACTED_BIN="${TMP_DIR}/squashfs-root/resources/bin/language_server"
    else
        echo "Error: Could not find package URL in manifest" >&2
        exit 1
    fi

    if [[ ! -f "${EXTRACTED_BIN}" ]]; then
        echo "Error: Extracted language_server binary not found" >&2
        exit 1
    fi

    install -m 755 "${EXTRACTED_BIN}" "${PERSISTENT_BIN}/language_server.new"
    mv -f "${PERSISTENT_BIN}/language_server.new" "${PERSISTENT_BIN}/language_server"
    echo "${LATEST_VERSION}" > "${VERSION_FILE}"
    sudo mkdir -p /etc/antigravity 2>/dev/null || true
    echo "${LATEST_VERSION}" | sudo tee "${ETC_VERSION_FILE}" >/dev/null 2>&1 || true
    echo "✓ Staged Antigravity Engine v${LATEST_VERSION} in ${PERSISTENT_BIN}/language_server"
else
    echo "✓ Antigravity Engine v${LATEST_VERSION} already staged in ${PERSISTENT_BIN}/language_server"
fi

# 2. Update agy CLI in persistent bin
if [[ ! -x "${PERSISTENT_BIN}/agy" ]]; then
    if [[ -x /usr/local/bin/agy ]]; then
        cp -f /usr/local/bin/agy "${PERSISTENT_BIN}/agy.new" && mv -f "${PERSISTENT_BIN}/agy.new" "${PERSISTENT_BIN}/agy"
        chmod 755 "${PERSISTENT_BIN}/agy"
    else
        curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- --dir "${PERSISTENT_BIN}"
    fi
fi

echo "⟳ Checking agy CLI for updates..."
"${PERSISTENT_BIN}/agy" update || true

# Ensure symlinks in /usr/local/bin point to persistent binaries
sudo ln -sfn "${PERSISTENT_BIN}/language_server" /usr/local/bin/language_server 2>/dev/null || ln -sfn "${PERSISTENT_BIN}/language_server" /usr/local/bin/language_server || true
sudo ln -sfn "${PERSISTENT_BIN}/agy" /usr/local/bin/agy 2>/dev/null || ln -sfn "${PERSISTENT_BIN}/agy" /usr/local/bin/agy || true
sudo ln -sfn /usr/local/bin/agy /usr/local/bin/antigravity 2>/dev/null || ln -sfn /usr/local/bin/agy /usr/local/bin/antigravity || true
sudo ln -sfn "${PERSISTENT_BIN}/agy-upgrade" /usr/local/bin/agy-upgrade 2>/dev/null || ln -sfn "${PERSISTENT_BIN}/agy-upgrade" /usr/local/bin/agy-upgrade || true

if [[ "${MODE}" == "stage" ]]; then
    echo "✓ Binaries staged. Run 'start-antigravity' or 'agy-upgrade --restart' when ready to switch."
    exit 0
fi

echo "⟳ Restarting Antigravity daemon..."
exec /usr/local/bin/start-antigravity
EOF
chmod 755 /usr/local/bin/agy-upgrade

# 4. Install antigravity-host-bridge daemon for native HostBridgeService (GetUpdateStatus / ApplyUpdate)
cat << 'EOF' > /usr/local/bin/antigravity-host-bridge
#!/usr/bin/env python3
"""Local HostBridgeService daemon for Antigravity in Kubernetes DevContainers."""

import http.server
import os
import re
import subprocess
import time
import urllib.request

PORT = int(os.environ.get("HOST_BRIDGE_PORT", "52423"))
TOKEN = os.environ.get("HOST_BRIDGE_TOKEN", "devcontainer-host-bridge-secret")
MANIFEST_URL = "https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/manifest/latest-x64-linux.yml"
VERSION_PATHS = ["/workspaces/.persistent/bin/version", "/etc/antigravity/version"]
CACHE_TTL_SECONDS = 900

_cache = {"latest_version": "", "fetched_at": 0.0}


def parse_version(v: str) -> tuple[int, ...]:
    parts = re.findall(r"\d+", v or "")
    return tuple(int(x) for x in parts) if parts else (0,)


def get_current_version() -> str:
    for p in VERSION_PATHS:
        try:
            with open(p, "r", encoding="utf-8") as f:
                val = f.read().strip()
                if val:
                    return val
        except OSError:
            pass
    return "0.0.0"


def get_latest_version() -> str:
    now = time.time()
    if _cache["latest_version"] and (now - _cache["fetched_at"] < CACHE_TTL_SECONDS):
        return _cache["latest_version"]
    try:
        req = urllib.request.Request(MANIFEST_URL, headers={"User-Agent": "antigravity-host-bridge/1.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            body = resp.read().decode("utf-8", "ignore")
        for line in body.splitlines():
            if line.lower().startswith("version:"):
                ver = line.split(":", 1)[1].strip().strip("'\"")
                if ver:
                    _cache["latest_version"] = ver
                    _cache["fetched_at"] = now
                    return ver
    except Exception:
        pass
    return _cache["latest_version"] or get_current_version()


def encode_varint(val: int) -> bytes:
    out = bytearray()
    while val > 0x7F:
        out.append((val & 0x7F) | 0x80)
        val >>= 7
    out.append(val & 0x7F)
    return bytes(out)


def encode_str(field_num: int, s: str) -> bytes:
    b = s.encode("utf-8")
    return encode_varint((field_num << 3) | 2) + encode_varint(len(b)) + b


def encode_bool(field_num: int, val: bool) -> bytes:
    return encode_varint((field_num << 3) | 0) + (b"\x01" if val else b"\x00")


class HostBridgeHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        auth = self.headers.get("Authorization", "")
        if TOKEN and auth != f"Bearer {TOKEN}":
            self.send_response(401)
            self.end_headers()
            return

        length = int(self.headers.get("Content-Length", "0"))
        if length > 0:
            self.rfile.read(length)

        if self.path.endswith("/GetUpdateStatus"):
            curr = get_current_version()
            latest = get_latest_version()
            avail = parse_version(latest) > parse_version(curr)
            inner = encode_str(1, curr) + encode_str(2, latest) + encode_bool(3, avail)
            payload = encode_varint((1 << 3) | 2) + encode_varint(len(inner)) + inner
        elif self.path.endswith("/ApplyUpdate"):
            _cache["fetched_at"] = 0.0
            upgrade_bin = "/workspaces/.persistent/bin/agy-upgrade"
            if not os.path.exists(upgrade_bin):
                upgrade_bin = "/usr/local/bin/agy-upgrade"
            with open("/tmp/agy-upgrade.log", "ab") as logf:
                subprocess.Popen(
                    [upgrade_bin, "--restart"],
                    stdout=logf,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
            payload = encode_bool(1, True)
        else:
            payload = b""

        self.send_response(200)
        self.send_header("Content-Type", "application/proto")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), HostBridgeHandler)
    server.serve_forever()
EOF
chmod 755 /usr/local/bin/antigravity-host-bridge

# 5. Create start-antigravity Launcher
cat << 'EOF' > /usr/local/bin/start-antigravity
#!/bin/bash
set -e

PERSISTENT_BIN="/workspaces/.persistent/bin"
mkdir -p ~/.local/share/keyrings ~/.gemini/antigravity ~/.gemini/antigravity-cli ~/.local/bin "${PERSISTENT_BIN}"

# Disable Microsoft's dummy systemctl shim if present so agy remote-control uses its native container fallback
if [ -f /usr/local/bin/systemctl ] && grep -q "is not running in this container" /usr/local/bin/systemctl 2>/dev/null; then
    sudo mv /usr/local/bin/systemctl /usr/local/bin/systemctl.devcontainer-shim.bak 2>/dev/null || true
fi

# Make /usr/local/bin group-writable by vscode so agy update works without sudo
sudo chgrp vscode /usr/local/bin 2>/dev/null || true
sudo chmod 775 /usr/local/bin 2>/dev/null || true

# Reconcile image binaries vs persistent binaries (newest version wins)
IMAGE_VER=$(cat /etc/antigravity/version 2>/dev/null | tr -d '[:space:]' || echo "0.0.0")
PERSIST_VER=$(cat "${PERSISTENT_BIN}/version" 2>/dev/null | tr -d '[:space:]' || echo "0.0.0")

if [ ! -x "${PERSISTENT_BIN}/language_server" ]; then
    if [ -f /usr/local/bin/language_server ]; then
        cp -f /usr/local/bin/language_server "${PERSISTENT_BIN}/language_server.tmp" && mv -f "${PERSISTENT_BIN}/language_server.tmp" "${PERSISTENT_BIN}/language_server"
        chmod 755 "${PERSISTENT_BIN}/language_server"
        echo "${IMAGE_VER}" > "${PERSISTENT_BIN}/version"
        PERSIST_VER="${IMAGE_VER}"
    fi
elif [ -f /usr/local/bin/language_server ] && [ ! -L /usr/local/bin/language_server ]; then
    HIGHEST_VER=$(printf '%s\n%s\n' "${IMAGE_VER}" "${PERSIST_VER}" | sort -V | tail -n 1)
    if [ "${HIGHEST_VER}" = "${IMAGE_VER}" ] && [ "${IMAGE_VER}" != "${PERSIST_VER}" ]; then
        cp -f /usr/local/bin/language_server "${PERSISTENT_BIN}/language_server.tmp" && mv -f "${PERSISTENT_BIN}/language_server.tmp" "${PERSISTENT_BIN}/language_server"
        chmod 755 "${PERSISTENT_BIN}/language_server"
        if [ -f /usr/local/bin/agy ] && [ ! -L /usr/local/bin/agy ]; then
            cp -f /usr/local/bin/agy "${PERSISTENT_BIN}/agy.tmp" && mv -f "${PERSISTENT_BIN}/agy.tmp" "${PERSISTENT_BIN}/agy"
            chmod 755 "${PERSISTENT_BIN}/agy"
        fi
        echo "${IMAGE_VER}" > "${PERSISTENT_BIN}/version"
        PERSIST_VER="${IMAGE_VER}"
    fi
fi

if [ ! -x "${PERSISTENT_BIN}/agy" ] && [ -f /usr/local/bin/agy ]; then
    cp -f /usr/local/bin/agy "${PERSISTENT_BIN}/agy.tmp" && mv -f "${PERSISTENT_BIN}/agy.tmp" "${PERSISTENT_BIN}/agy"
    chmod 755 "${PERSISTENT_BIN}/agy"
fi

for helper in agy-upgrade antigravity-host-bridge start-antigravity; do
    if [ ! -x "${PERSISTENT_BIN}/${helper}" ] && [ -f "/usr/local/bin/${helper}" ]; then
        cp -f "/usr/local/bin/${helper}" "${PERSISTENT_BIN}/${helper}.tmp" && mv -f "${PERSISTENT_BIN}/${helper}.tmp" "${PERSISTENT_BIN}/${helper}"
        chmod 755 "${PERSISTENT_BIN}/${helper}"
    fi
done

# Ensure /etc/antigravity/version matches persistent version
if [ -n "${PERSIST_VER}" ] && [ "${PERSIST_VER}" != "0.0.0" ]; then
    sudo mkdir -p /etc/antigravity 2>/dev/null || true
    echo "${PERSIST_VER}" | sudo tee /etc/antigravity/version >/dev/null 2>&1 || true
fi

# Point /usr/local/bin symlinks at persistent binaries
for bin_name in language_server agy agy-upgrade antigravity-host-bridge start-antigravity; do
    if [ -x "${PERSISTENT_BIN}/${bin_name}" ]; then
        ln -sfn "${PERSISTENT_BIN}/${bin_name}" "/usr/local/bin/${bin_name}" 2>/dev/null || sudo ln -sfn "${PERSISTENT_BIN}/${bin_name}" "/usr/local/bin/${bin_name}" || true
    fi
done
ln -sfn /usr/local/bin/agy /usr/local/bin/antigravity 2>/dev/null || sudo ln -sfn /usr/local/bin/agy /usr/local/bin/antigravity || true

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

if ! pgrep -f gnome-keyring-daemon >/dev/null 2>&1; then
    eval $(echo "" | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null || true)
    export GNOME_KEYRING_CONTROL
fi

# Ensure local HostBridgeService daemon is running on 127.0.0.1:52423
HOST_BRIDGE_BIN="${PERSISTENT_BIN}/antigravity-host-bridge"
if [ ! -x "${HOST_BRIDGE_BIN}" ]; then
    HOST_BRIDGE_BIN="/usr/local/bin/antigravity-host-bridge"
fi
if [ -x "${HOST_BRIDGE_BIN}" ] && ! fuser 52423/tcp >/dev/null 2>&1; then
    nohup "${HOST_BRIDGE_BIN}" >/tmp/antigravity-host-bridge.log 2>&1 &
fi

# Graceful termination of old language_server to cleanly flush SQLite databases
OLD_PIDS=$(pgrep -f "language_server.*--standalone" || true)
if [ -n "$OLD_PIDS" ]; then
    echo "Stopping existing language_server (PID: $OLD_PIDS)..."
    kill -15 $OLD_PIDS 2>/dev/null || true
    for i in {1..10}; do
        if ! kill -0 $OLD_PIDS 2>/dev/null; then
            break
        fi
        sleep 0.5
    done
    if kill -0 $OLD_PIDS 2>/dev/null; then
        kill -9 $OLD_PIDS 2>/dev/null || true
        sleep 0.5
    fi
fi

# Ensure ports are released
while fuser 52424/tcp >/dev/null 2>&1 || fuser 52425/tcp >/dev/null 2>&1; do
    sleep 0.5
done

AGY_VERSION=$(cat "${PERSISTENT_BIN}/version" 2>/dev/null || cat /etc/antigravity/version 2>/dev/null || echo "2.24.0")
LS_BIN="${PERSISTENT_BIN}/language_server"
if [ ! -x "${LS_BIN}" ]; then
    LS_BIN="/usr/local/bin/language_server"
fi

nohup "${LS_BIN}" \
  --standalone \
  --override_ide_name antigravity \
  --subclient_type hub \
  --override_ide_version "${AGY_VERSION}" \
  --override_user_agent_name antigravity \
  --https_server_port 52425 \
  --http_server_port 52424 \
  --csrf_token devcontainer-secret \
  --host_bridge_url http://127.0.0.1:52423 \
  --host_bridge_token devcontainer-host-bridge-secret \
  --app_data_dir antigravity \
  --api_server_url https://generativelanguage.googleapis.com \
  --cloud_code_endpoint https://daily-cloudcode-pa.googleapis.com \
  --enable_sidecars > ~/.gemini/antigravity/language_server.log 2>&1 &

sleep 2
NEW_PID=$(pgrep -f "language_server.*--standalone" || true)
if [ -n "$NEW_PID" ] && kill -0 $NEW_PID 2>/dev/null; then
    echo "Antigravity Hub daemon v${AGY_VERSION} successfully started (PID: ${NEW_PID}) on port 52424 (HTTPS 52425)"
else
    echo "Error: language_server failed to start! Check ~/.gemini/antigravity/language_server.log"
    exit 1
fi
EOF
chmod 755 /usr/local/bin/start-antigravity

echo "Antigravity Remote Control & Hub Feature v1.7.0 installed successfully!"
