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
npx @devcontainers/cli features publish ./src/antigravity \
  --registry registry.k8s.mrv.thebends.org \
  --namespace devcontainers
```
