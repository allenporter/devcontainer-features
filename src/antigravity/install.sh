#!/bin/bash
set -e

PORT="${PORT:-52425}"
HTTP_PORT="${HTTPPORT:-43635}"
INTERNAL_HTTPS_PORT=$((PORT - 1))
INTERNAL_HTTP_PORT=$((HTTP_PORT - 1))

echo "======================================================="
echo " Installing Antigravity DevContainer Feature v1.0.11"
echo "   HTTPS Port : ${PORT} (Proxy to ${INTERNAL_HTTPS_PORT})"
echo "   HTTP Port  : ${HTTP_PORT} (Proxy to ${INTERNAL_HTTP_PORT})"
echo "======================================================="

# Install Linux D-Bus, secret-service keyring, and python3 for host-rewrite proxy
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends \
    dbus-x11 gnome-keyring libsecret-1-0 curl ca-certificates jq python3
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

# Create Host-Header rewriting HTTP proxy
cat << 'EOF' > /usr/local/bin/antigravity-proxy
#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.request
import sys

TARGET_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 43634
LISTEN_PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 43635

class ProxyHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        self.proxy_request("GET")

    def do_POST(self):
        self.proxy_request("POST")

    def do_PUT(self):
        self.proxy_request("PUT")

    def do_DELETE(self):
        self.proxy_request("DELETE")

    def do_OPTIONS(self):
        self.proxy_request("OPTIONS")

    def proxy_request(self, method):
        url = f"http://127.0.0.1:{TARGET_PORT}{self.path}"
        headers = {k: v for k, v in self.headers.items()}
        headers["Host"] = f"localhost:{TARGET_PORT}"

        body = None
        if "Content-Length" in self.headers:
            length = int(self.headers["Content-Length"])
            body = self.rfile.read(length)

        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req) as resp:
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() not in ["transfer-encoding", "content-length"]:
                        self.send_header(k, v)
                resp_bytes = resp.read()
                self.send_header("Content-Length", str(len(resp_bytes)))
                self.end_headers()
                self.wfile.write(resp_bytes)
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            for k, v in e.headers.items():
                if k.lower() not in ["transfer-encoding", "content-length"]:
                    self.send_header(k, v)
            resp_bytes = e.read()
            self.send_header("Content-Length", str(len(resp_bytes)))
            self.end_headers()
            self.wfile.write(resp_bytes)
        except Exception as ex:
            self.send_error(500, str(ex))

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", LISTEN_PORT), ProxyHandler)
    server.serve_forever()
EOF
chmod +x /usr/local/bin/antigravity-proxy

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
pkill -9 -f antigravity-proxy || true
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
nohup /usr/local/bin/antigravity-proxy "${INTERNAL_HTTP_PORT}" "${HTTP_PORT}" >/dev/null 2>&1 &

echo "Antigravity daemon & Host-rewrite proxy started on HTTP port ${HTTP_PORT}!"
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
