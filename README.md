# Custom DevContainer Features

Repository for custom DevContainer Features published to the internal Zot OCI registry (`registry.k8s.mrv.thebends.org`).

---

## 🚀 Available Features

### 1. `antigravity-remote-control` (`v1.8.0`)
Installs the Google Antigravity `language_server` (extracted from the upstream `.deb`), native `agy` CLI, local `HostBridgeService` (`127.0.0.1:52423`) for UI-triggered updates, `agy-upgrade` for persistent in-place upgrades stored in `/workspaces/.persistent/bin`, and automatic Web Hub onboarding/token synchronization via `start-antigravity`.

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

## 🔑 Authentication Workflow (`agy` + `start-antigravity`)

1. **Authenticate via the CLI inside the container**:
   Launch `agy` interactively, open the printed Google OAuth URL in your browser, paste the verification code back, and exit (`Ctrl+D` twice or `/exit`):
   ```bash
   kubectl exec -it -n devcontainers deployment/ws-<workspace-name> -c workspace -- agy
   ```
2. **Sync Token, Complete Onboarding & Restart Daemon (`start-antigravity`)**:
   `agy` writes the OAuth token to `~/.gemini/antigravity-cli/antigravity-oauth-token`. Run `start-antigravity` to symlink that token into `~/.gemini/antigravity/`, restart `language_server`, and mark Web Hub onboarding complete (with container-incompatible terminal sandbox disabled on fresh setups):
   ```bash
   kubectl exec -n devcontainers deployment/ws-<workspace-name> -c workspace -- start-antigravity
   ```
3. *(Optional)* **Register with Antigravity Remote Control**:
   ```bash
   kubectl exec -n devcontainers deployment/ws-<workspace-name> -c workspace -- agy remote-control start --name <workspace-name>
   ```

---

## 📦 Publishing Updates to Zot Registry

To publish feature updates to the Zot OCI registry:

```bash
npx @devcontainers/cli features publish ./src/antigravity-remote-control \
  --registry registry.k8s.mrv.thebends.org \
  --namespace devcontainers
```
