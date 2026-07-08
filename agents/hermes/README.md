# Hermes Agent

[Hermes Agent](https://github.com/NousResearch/hermes-agent) with Claude on Vertex AI support.

Hermes Agent doesn't natively support Claude models on Vertex AI. This setup uses a custom image built from [PR #55742](https://github.com/NousResearch/hermes-agent/pull/55742) that adds `AnthropicVertex` SDK support.

## Deployment Options

- **OpenShell sandbox** via NemoClaw (`openshell/`)
- **Kubernetes/OpenShift** via Kustomize (`k8s/`)
- **Local Podman** via Quadlet (`quadlet/`)

The Quadlet and Kubernetes deployments use the custom image at `quay.io/shanemcd/hermes-agent:vertex-55742`.

## OpenShell Sandbox (NemoClaw)

See [`openshell/README.md`](openshell/README.md). Runs Hermes inside an NVIDIA OpenShell sandbox with network policy enforcement, credential injection, and Landlock restrictions. No real credentials exist inside the sandbox.

## Kubernetes/OpenShift

```bash
# Get GCP ADC credentials
gcloud auth application-default login

# Create namespace and Vertex credentials secret
kubectl create namespace hermes-agent
kubectl create secret generic vertex-credentials \
  -n hermes-agent \
  --from-file=application_default_credentials.json=$HOME/.config/gcloud/application_default_credentials.json

# Create secrets from template
cp k8s/overlays/crc/secrets.yaml.example k8s/overlays/crc/secrets.yaml
# Edit secrets.yaml with your credentials

# Deploy
kubectl apply -k k8s/overlays/crc

# Verify
kubectl exec -n hermes-agent deployment/hermes-gateway -- hermes chat -q "Hello"
```

The base config in `k8s/base/configmap.yaml` seeds `config.yaml` on first boot. Hermes modifies it at runtime. Set `HERMES_FORCE_CONFIG=true` on the init container to force a re-seed.

## Local Podman (Quadlet)

See [`quadlet/README.md`](quadlet/README.md). Runs Hermes as a Podman pod with gateway and dashboard containers managed by systemd Quadlet units.

## Vertex AI Integration

With `provider: vertex` in `config.yaml`, the runtime:

1. Reads `vertex.project_id` and `vertex.region` from config (or env vars)
2. Creates an `AnthropicVertex` client authenticated via ADC
3. Routes requests to Vertex AI's Claude endpoint

Environment variables (priority order):

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_VERTEX_PROJECT_ID` | GCP project ID |
| `GOOGLE_CLOUD_PROJECT` | GCP project ID (fallback) |
| `VERTEX_REGION` | Vertex region (default: `global`) |
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to ADC JSON |

When PR #55742 is merged upstream, the custom image will no longer be needed.

## Building the Custom Image

```bash
cd hermes-agent
git fetch origin pull/55742/head:vertex-support
git checkout vertex-support
git rebase main
podman build -t quay.io/shanemcd/hermes-agent:vertex-55742 -f Dockerfile .
podman push quay.io/shanemcd/hermes-agent:vertex-55742
```

Update the image tag in `k8s/overlays/crc/kustomization.yaml` and both `quadlet/*.container` files after pushing a new build.

## Constraints

- **No horizontal scaling.** `strategy: Recreate`, `replicas: 1`. Hermes stores state in `/opt/data` and is not safe for concurrent access.
- **OpenShift UID.** `HOME=/opt/data` avoids permission errors with OpenShift's random UID assignment.
- **Dashboard auth.** The dashboard refuses to bind to `0.0.0.0` without basic auth configured. Set `dashboard.basic_auth` before exposing.
