# Custom DevContainer Features

Repository for custom DevContainer Features published to the internal Zot OCI registry (`registry.k8s.mrv.thebends.org`).

---

## 🚀 Available Features

### 1. `antigravity-remote-control` (`v1.9.0`)
Installs the Google Antigravity `language_server` (extracted from the upstream `.deb`), native `agy` CLI, local `HostBridgeService` (`127.0.0.1:52423`) for UI-triggered updates, `agy-upgrade` for persistent in-place upgrades stored in `/workspaces/.persistent/bin`, and automatic Web Hub onboarding, Remote Control registration, and token synchronization via `start-antigravity`.

#### Usage in `.devcontainer/devcontainer.json`:

```json
{
  "name": "My Workspace",
  "image": "mcr.microsoft.com/devcontainers/python:3.14-bookworm",
  "features": {
    "registry.k8s.mrv.thebends.org/devcontainers/antigravity-remote-control:1": {
      "enableRemoteControl": true,
      "enableLocalInterface": true,
      "hostname": "my-workspace"
    }
  },
  "postStartCommand": "/usr/local/bin/start-antigravity"
}
```

#### Feature Options & Runtime Overrides:

| Option | Default | Runtime Env Override | Description |
| :--- | :--- | :--- | :--- |
| `version` | `"latest"` | — | Target `language_server` engine version installed at image build time |
| `enableRemoteControl` | `true` | `ANTIGRAVITY_ENABLE_REMOTE_CONTROL` | Reconciles `userSettings.remoteControlEnabled` in `~/.gemini/config/config.json` so the Web Hub `language_server` connects directly to `https://antigravity.google.com` |
| `enableLocalInterface` | `true` | `ANTIGRAVITY_ENABLE_LOCAL_INTERFACE` | Binds the local Web Hub server to ports `52424` (HTTP) / `52425` (HTTPS); when `false`, uses ephemeral loopback ports |
| `hostname` | `""` | `ANTIGRAVITY_HOSTNAME` | Sets `userSettings.remoteControlHostname` in `~/.gemini/config/config.json` (the instance name shown on `https://antigravity.google.com`) |

#### In-Place Persistent Upgrades (`agy-upgrade`):
```bash
agy-upgrade --check    # Compare running, staged, and upstream versions
agy-upgrade --stage    # Download & stage latest binaries to /workspaces/.persistent/bin without restarting
agy-upgrade --restart  # Stage latest binaries and gracefully restart language_server
```

---

## 🔑 Authentication & Remote Control Workflow (`agy` + `start-antigravity`)

1. **Authenticate via the CLI inside the container**:
   Launch `agy` interactively, open the printed Google OAuth URL in your browser, paste the verification code back, and exit (`Ctrl+D` twice or `/exit`):
   ```bash
   kubectl exec -it -n devcontainers deployment/ws-<workspace-name> -c workspace -- agy
   ```
2. **Sync Token, Reconcile Remote Control & Restart Daemon (`start-antigravity`)**:
   `agy` writes the OAuth token to `~/.gemini/antigravity-cli/antigravity-oauth-token`. Run `start-antigravity` to symlink that token into `~/.gemini/antigravity/`, mark Web Hub onboarding complete, reconcile `remoteControlEnabled` / `remoteControlHostname` in `~/.gemini/config/config.json`, and restart `language_server`:
   ```bash
   kubectl exec -n devcontainers deployment/ws-<workspace-name> -c workspace -- start-antigravity
   ```

> **Important — Do NOT run `agy remote-control start` on Web Hub containers:**
> Running `agy remote-control start` launches a **second, separate** server (`agy remote-control serve`) backed by `~/.gemini/antigravity-cli/` instead of the Web Hub `language_server` backed by `~/.gemini/antigravity/`. That causes `https://antigravity.google.com` to route to a split-brain store with separate conversations and sidecars.
>
> In Web Hub mode (`--subclient_type hub`), the browser UI also hides the Remote Control settings panel until `userSettings.remoteControlEnabled` is `true` in `~/.gemini/config/config.json`. `start-antigravity` (`v1.9.0+`) sets this automatically from `enableRemoteControl` and `hostname`.
>
> **Manual override on older (`< v1.9.0`) container images without rebuilding:**
> ```bash
> kubectl exec -n devcontainers deployment/ws-<workspace-name> -c workspace -- sh -c '
>   tmp=$(mktemp) &&
>   jq ".userSettings.remoteControlEnabled = true | .userSettings.remoteControlHostname = \"<workspace-name>\"" \
>     ~/.gemini/config/config.json > "$tmp" &&
>   chmod 600 "$tmp" && mv "$tmp" ~/.gemini/config/config.json
> '
> ```
> (`language_server` watches `~/.gemini/config/config.json` via `fsnotify` and connects immediately without a restart.)

---

## 📦 Publishing Updates to Zot Registry

To publish feature updates to the Zot OCI registry:

```bash
npx @devcontainers/cli features publish ./src/antigravity-remote-control \
  --registry registry.k8s.mrv.thebends.org \
  --namespace devcontainers
```
