# Custom DevContainer Features

Repository for custom DevContainer Features published to the internal Zot OCI registry (`registry.k8s.mrv.thebends.org`).

---

## 🚀 Available Features

### 1. `antigravity-remote-control`
Installs and launches the Google Antigravity `language_server` Web Hub daemon alongside the official `agy` CLI inside DevContainers with persistent token synchronization.

#### Usage in `.devcontainer/devcontainer.json`:

```json
{
  "name": "My Workspace",
  "image": "mcr.microsoft.com/devcontainers/python:3.11",
  "features": {
    "registry.k8s.mrv.thebends.org/devcontainers/antigravity-remote-control:1": {}
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

## 🔑 Authentication Workflow (`agy auth login`)

1. **Authenticate via the CLI inside the container**:
   ```bash
   kubectl exec -it -n devcontainers deployment/ws-<workspace-name> -c workspace -- agy auth login
   ```
2. **Sync Token & Restart Daemon (`start-antigravity`)**:
   On a fresh container where `~/.gemini/antigravity-cli/antigravity-oauth-token` did not exist at initial boot, run `start-antigravity` after completing `agy auth login` so the token symlinks are created in `~/.gemini/antigravity/` and `language_server` restarts with the new credentials:
   ```bash
   kubectl exec -n devcontainers deployment/ws-<workspace-name> -c workspace -- start-antigravity
   ```

---

## 📦 Publishing Updates to Zot Registry

To publish feature updates to the Zot OCI registry:

```bash
npx @devcontainers/cli features publish ./src/antigravity-remote-control \
  --registry registry.k8s.mrv.thebends.org \
  --namespace devcontainers
```
