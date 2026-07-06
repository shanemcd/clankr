# clankr

Deployment configurations for [Hermes Agent](https://github.com/NousResearch/hermes-agent) with Claude on Vertex AI support.

Supports both:
- **Kubernetes/OpenShift** deployment (via Kustomize)
- **Local Podman** deployment (via Quadlet systemd units)

## What is this?

[Hermes Agent](https://github.com/NousResearch/hermes-agent) doesn't natively support Claude on Vertex AI. This repo provides:

1. **A custom Hermes image** built from [PR #55742](https://github.com/NousResearch/hermes-agent/pull/55742) that adds Vertex AI support
2. **Kubernetes/OpenShift deployment** using Kustomize
3. **Local Podman deployment** using Quadlet (systemd integration)

See [VERTEX_SUPPORT.md](VERTEX_SUPPORT.md) for technical details on how Vertex AI integration works.

## Prerequisites

### For Kubernetes/OpenShift:
- A running Kubernetes or OpenShift cluster (tested on CRC with OpenShift 4.21)
- `kubectl` or `oc` CLI

### For Local Podman:
- Podman 4.4+ with Quadlet support
- systemd

### For Claude on Vertex AI (both):
- GCP credentials with `aiplatform.user` role
- ADC file at `~/.config/gcloud/application_default_credentials.json`

## Quick Start

Choose your deployment method:
- [Kubernetes/OpenShift](#kubernetsopenshift-deployment) - For production or multi-user deployments
- [Local Podman](#local-podman-deployment) - For development or single-user deployments

---

## Kubernetes/OpenShift Deployment

### 1. Get ADC credentials

```bash
gcloud auth application-default login
# This creates ~/.config/gcloud/application_default_credentials.json
```

### 2. Clone this repo

```bash
git clone https://github.com/shanemcd/clankr.git
cd clankr
```

### 3. Create your secrets file

```bash
cp k8s/overlays/crc/secrets.yaml.example k8s/overlays/crc/secrets.yaml
```

Edit `secrets.yaml` with your actual credentials (Discord bot token, GCP project, etc.). This file is gitignored.

### 4. Create the Vertex AI credentials secret

If using Claude via Vertex AI:

```bash
kubectl create namespace hermes-agent

kubectl create secret generic vertex-credentials \
  -n hermes-agent \
  --from-file=application_default_credentials.json=$HOME/.config/gcloud/application_default_credentials.json
```

### 5. Configure Hermes

The base config lives in `k8s/base/configmap.yaml`. Edit it to set your model and provider:

```yaml
data:
  config.yaml: |
    model:
      default: claude-opus-4-6
      provider: vertex
    vertex:
      project_id: ""  # Read from ANTHROPIC_VERTEX_PROJECT_ID env var
      region: global
```

An init container seeds this config to the PVC on first boot. Hermes can modify it at runtime (via `/setup`, `/model`, etc.) and those changes persist across restarts. To reset to the declared config, set `HERMES_FORCE_CONFIG=true` temporarily.

To configure dashboard authentication, deploy first, then run:

```bash
# Generate a password hash
kubectl exec -n hermes-agent deployment/hermes-gateway -- \
  python -c "from plugins.dashboard_auth.basic import hash_password; print(hash_password('your-password'))"

# Then add it to the running config
kubectl exec -n hermes-agent deployment/hermes-gateway -- hermes config set dashboard.basic_auth.username admin
kubectl exec -n hermes-agent deployment/hermes-gateway -- hermes config set dashboard.basic_auth.password_hash 'YOUR_HASH'
```

### 6. Deploy

```bash
kubectl apply -k k8s/overlays/crc
```

### 7. Verify

```bash
kubectl get pods -n hermes-agent
kubectl exec -n hermes-agent deployment/hermes-gateway -- hermes chat -q "Hello"
```

## Layout

```
k8s/
├── base/                            # Shared manifests (no secrets, no platform-specific config)
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── deployment.yaml              # Gateway + Dashboard with init container
│   ├── configmap.yaml               # Initial config.yaml + seed script
│   ├── service.yaml
│   └── pvc.yaml
└── overlays/
    └── crc/                         # CRC/OpenShift overlay
        ├── kustomization.yaml
        ├── deployment-patch.yaml    # Resource limits for CRC
        ├── vertex-patch.yaml        # Vertex AI credential mounts
        ├── route.yaml               # OpenShift Route for dashboard
        ├── secrets.yaml.example     # Template (copy to secrets.yaml)
        └── secrets.yaml             # Your secrets (gitignored)
```

## Claude on Vertex AI

The upstream Hermes Agent does not natively support Claude on Vertex AI. This deployment uses a custom image built from [PR #55742](https://github.com/NousResearch/hermes-agent/pull/55742), which adds `AnthropicVertex` SDK support.

The custom image is published at `quay.io/shanemcd/hermes-agent:vertex`.

To build it yourself:

```bash
git clone https://github.com/NousResearch/hermes-agent.git
cd hermes-agent
git fetch origin pull/55742/head:vertex-support
git checkout vertex-support
git rebase main
podman build -t your-registry/hermes-agent:vertex -f Dockerfile .
podman push your-registry/hermes-agent:vertex
```

Then update `k8s/overlays/crc/kustomization.yaml` to point to your image.

---

## Local Podman Deployment

See [quadlet/README.md](quadlet/README.md) for detailed instructions.

### Quick Start

```bash
# 1. Get ADC credentials
gcloud auth application-default login

# 2. Clone repo
git clone https://github.com/shanemcd/clankr.git
cd clankr

# 3. Set up environment
mkdir -p ~/.config/hermes
cp quadlet/env.example ~/.config/hermes/env
# Edit ~/.config/hermes/env with your GCP project ID

# 4. Make credentials readable
chmod 644 ~/.config/gcloud/application_default_credentials.json

# 5. Create volume
podman volume create hermes-data

# 6. Install Quadlet units
mkdir -p ~/.config/containers/systemd
cp quadlet/hermes*.{pod,container} ~/.config/containers/systemd/
systemctl --user daemon-reload

# 7. Start services
systemctl --user start hermes-gateway-pod hermes-dashboard-pod

# 8. Test
podman exec hermes-gateway hermes chat -q "Hello"

# Dashboard: http://localhost:9119
```

---

## Discord Integration

1. Create a bot at https://discord.com/developers/applications/
2. Under **Bot** settings, enable all three **Privileged Gateway Intents**
3. Under **OAuth2 > URL Generator**, select `bot` scope with `Send Messages` and `Read Message History` permissions
4. Open the generated URL to invite the bot to your server
5. Add `DISCORD_BOT_TOKEN` and `DISCORD_ALLOWED_USERS` to your `secrets.yaml`
6. Redeploy: `kubectl apply -k k8s/overlays/crc`

## Contributing

Contributions are welcome! Please open an issue or PR.

## License

MIT - See [LICENSE](LICENSE)

## Credits

- [Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research
- Vertex AI integration via [PR #55742](https://github.com/NousResearch/hermes-agent/pull/55742)

## Important Notes

- **State safety**: Both deployments use `strategy: Recreate`. Do not increase replicas. Hermes stores state in `/opt/data` and is not safe for concurrent access.
- **OpenShift**: Pods run with a random UID. `HOME` is set to `/opt/data` to avoid permission errors writing to `/`.
- **Config is mutable**: Hermes writes to `config.yaml` at runtime. The init container seeds it from the ConfigMap on first boot only. To force a re-seed, set `HERMES_FORCE_CONFIG=true` on the init container.
- **Dashboard auth**: The dashboard refuses to bind to `0.0.0.0` without basic auth or OAuth configured. Set `dashboard.basic_auth` in `config.yaml` before exposing it.
