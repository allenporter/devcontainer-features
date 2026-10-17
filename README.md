# Custom DevContainer Features

Repository for custom DevContainer Features published to the internal Zot OCI registry (`registry.k8s.mrv.thebends.org`).

---

## 🚀 Available Features

### 1. `antigravity`
Installs and launches the Google Antigravity 2.0 `language_server` daemon inside DevContainers with Linux D-Bus token persistence.

#### Usage in `.devcontainer/devcontainer.json`:

```json
{
  "name": "My Workspace",
  "image": "mcr.microsoft.com/devcontainers/python:3.11",
  "features": {
    "registry.k8s.mrv.thebends.org/devcontainers/antigravity:1": {}
  },
  "postStartCommand": "/usr/local/bin/start-antigravity"
}
```

### 2. `antigravity-remote-control` (`v1.7.0`)
Installs the Google Antigravity `language_server` (extracted from the upstream `.deb`), native `agy` CLI, local `HostBridgeService` (`127.0.0.1:52423`) for UI-triggered updates, and `agy-upgrade` for persistent in-place upgrades stored in `/workspaces/.persistent/bin`.

#### Usage in `.devcontainer/devcontainer.json`:

```json
{
  "name": "My Workspace",
  "image": "mcr.microsoft.com/devcontainers/python:3.14-bookworm",
  "features": {
    "registry.k8s.mrv.thebends.org/devcontainers/antigravity-remote-control:1": {}
  },
  "postStartCommand": "/usr/local/bin/start-antigravity"
}
```

#### In-Place Persistent Upgrades (`agy-upgrade`):
```bash
agy-upgrade --check    # Compare running, staged, and upstream versions
agy-upgrade --stage    # Download & stage latest binaries to /workspaces/.persistent/bin without restarting
agy-upgrade --restart  # Stage latest binaries and gracefully restart language_server
```

---

## 🔑 Client Auth Helper (`bin/agy-auth`)

To automatically fetch the OAuth URL, open the browser, and start port-forwarding for any workspace:

```bash
./bin/agy-auth <workspace-name>

# Example:
./bin/agy-auth home-automation
./bin/agy-auth harness-dev
```

---

## 📦 Publishing Updates to Zot Registry

To publish feature updates to the Zot OCI registry:

```bash
npx @devcontainers/cli features publish ./src/antigravity-remote-control \
  --registry registry.k8s.mrv.thebends.org \
  --namespace devcontainers
```
