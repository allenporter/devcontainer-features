# Custom DevContainer Features

Repository for custom DevContainer Features published to the Zot OCI registry (`zot.mrv.thebends.org`).

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
    "zot.mrv.thebends.org/devcontainers/antigravity:1": {}
  },
  "postStartCommand": "/usr/local/bin/start-antigravity"
}
```

---

## 📦 Publishing Updates to Zot Registry

Publish features directly from your local machine to the internal Zot registry:

```bash
npx @devcontainers/cli features publish ./src/antigravity \
  --registry zot.mrv.thebends.org \
  --namespace devcontainers
```
