# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Clankr is a deployment system for Hermes Agent with Claude on Vertex AI support. The repository includes the upstream Hermes Agent as a subdirectory (`hermes-agent/`) along with deployment configurations for both Kubernetes/OpenShift (via Kustomize) and local Podman (via Quadlet).

## Architecture

### Deployment Options

The project supports two deployment methods:

1. **Kubernetes/OpenShift** (via Kustomize in `k8s/`)
2. **Local Podman** (via Quadlet in `quadlet/`)

Both deployments use the same custom Vertex AI image and configuration patterns.

### Kubernetes Deployment Structure

The deployment uses a Kustomize base/overlay pattern:

- **k8s/base/**: Platform-agnostic Kubernetes manifests
  - Two separate deployments: `hermes-gateway` and `hermes-dashboard`
  - Init containers seed config from ConfigMap on first boot
  - Shared PVC (`hermes-data`) mounted at `/opt/data` with `HOME` set to this path for OpenShift random UID compatibility
  - Both deployments use `strategy: Recreate` (not safe for concurrent replicas, stateful operation)

- **k8s/overlays/crc/**: OpenShift CRC-specific overlay
  - Resource limits for CRC environments
  - Vertex AI credential mounting via `vertex-patch.yaml`
  - OpenShift Route for dashboard exposure
  - Custom image from `quay.io/shanemcd/hermes-agent:vertex` (built from PR #55742 to add AnthropicVertex SDK support)

### State Management

- Config is mutable at runtime. Hermes modifies `config.yaml` via `/setup`, `/model`, etc.
- Init container only seeds config on first boot (when `/opt/data/config.yaml` doesn't exist)
- To force config re-seed, set `HERMES_FORCE_CONFIG=true` on init container
- Both deployments share the same PVC, so state persists across restarts but is NOT safe for concurrent access

### Vertex AI Integration

The upstream Hermes Agent doesn't support Claude on Vertex AI natively. This deployment uses a custom image built from PR #55742 which adds `AnthropicVertex` SDK support. The image is published at `quay.io/shanemcd/hermes-agent:vertex`.

### Podman Quadlet Deployment Structure

See `quadlet/README.md` for detailed setup instructions.

- **quadlet/hermes.pod**: Pod definition (similar to k8s pod, groups containers together)
- **quadlet/hermes-gateway-pod.container**: Gateway container in the pod
- **quadlet/hermes-dashboard-pod.container**: Dashboard container in the pod
- **quadlet/env.example**: Template for environment variables

The Quadlet deployment uses:
- Podman pod architecture (both containers share network namespace, port published on pod)
- Named volume `hermes-data` for persistent state shared between containers
- User systemd units (no root required)
- Auto-starts on user login

## Common Commands

### Podman Quadlet Deployment

```bash
# Setup
mkdir -p ~/.config/hermes
cp quadlet/env.example ~/.config/hermes/env
# Edit ~/.config/hermes/env with your credentials

# Create volume
podman volume create hermes-data

# Install units
mkdir -p ~/.config/containers/systemd
cp quadlet/hermes*.{pod,container} ~/.config/containers/systemd/
systemctl --user daemon-reload

# Start services (both run in the same pod)
systemctl --user start hermes-gateway-pod hermes-dashboard-pod

# Check status
podman pod ps
podman ps --pod
podman logs -f hermes-gateway

# Test
podman exec hermes-gateway hermes chat -q "Hello"

# Access dashboard at http://localhost:9119
```

### Kubernetes Deployment

```bash
# Deploy to CRC
kubectl apply -k k8s/overlays/crc

# Verify deployment
kubectl get pods -n hermes-agent
kubectl logs -n hermes-agent deployment/hermes-gateway
kubectl logs -n hermes-agent deployment/hermes-dashboard

# Test Hermes
kubectl exec -n hermes-agent deployment/hermes-gateway -- hermes chat -q "Hello"
```

### Secrets Management

Secrets are defined in `k8s/overlays/crc/secrets.yaml` (gitignored). Copy from `secrets.yaml.example`:

```bash
cp k8s/overlays/crc/secrets.yaml.example k8s/overlays/crc/secrets.yaml
# Edit with your credentials
```

For Vertex AI, create the credentials secret separately:

```bash
kubectl create namespace hermes-agent

kubectl create secret generic vertex-credentials \
  -n hermes-agent \
  --from-file=application_default_credentials.json=$HOME/.config/gcloud/application_default_credentials.json
```

### Configuration

Base config is in `k8s/base/configmap.yaml`. To change model/provider, edit the ConfigMap and redeploy.

Runtime config changes (via `hermes config set`):

```bash
# Generate dashboard password hash
kubectl exec -n hermes-agent deployment/hermes-gateway -- \
  python -c "from plugins.dashboard_auth.basic import hash_password; print(hash_password('your-password'))"

# Set dashboard auth
kubectl exec -n hermes-agent deployment/hermes-gateway -- hermes config set dashboard.basic_auth.username admin
kubectl exec -n hermes-agent deployment/hermes-gateway -- hermes config set dashboard.basic_auth.password_hash 'YOUR_HASH'
```

### Building Custom Image

To rebuild the Vertex AI image:

```bash
cd hermes-agent
git fetch origin pull/55742/head:vertex-support
git checkout vertex-support
git rebase main
podman build -t quay.io/shanemcd/hermes-agent:vertex -f Dockerfile .
podman push quay.io/shanemcd/hermes-agent:vertex
```

Update image reference in `k8s/overlays/crc/kustomization.yaml` under `images:` section.

## Important Constraints

- **No horizontal scaling**: Both deployments use `strategy: Recreate` and `replicas: 1`. Hermes stores state in `/opt/data` and is not safe for concurrent access. Never increase replicas.
- **OpenShift UID handling**: Pods run with random UID on OpenShift. `HOME=/opt/data` avoids permission errors writing to `/`.
- **Dashboard binding**: Dashboard refuses to bind to `0.0.0.0` without basic auth or OAuth configured. Always configure `dashboard.basic_auth` in `config.yaml` before exposing.
- **Config persistence**: The init container seeds config from ConfigMap only on first boot. After that, Hermes owns `config.yaml` and modifies it at runtime. Changes persist across restarts until you force re-seed with `HERMES_FORCE_CONFIG=true`.
