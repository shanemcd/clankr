# Updating to a New Hermes Image

This document describes how to update the deployment to use a newly built image.

## Build Process

The custom Vertex AI image is built from PR #55742:

```bash
cd hermes-agent
git fetch origin pull/55742/head:vertex-support
git checkout vertex-support
podman build -t quay.io/shanemcd/hermes-agent:vertex-55742 -f Dockerfile .
```

## Push to Registry

```bash
podman push quay.io/shanemcd/hermes-agent:vertex-55742
```

## Update Deployments

### Kubernetes/OpenShift

Update the image tag in `k8s/overlays/crc/kustomization.yaml`:

```yaml
images:
- name: docker.io/nousresearch/hermes-agent
  newName: quay.io/shanemcd/hermes-agent
  newTag: vertex-55742  # <-- Update this
```

Then apply:

```bash
kubectl apply -k k8s/overlays/crc
```

### Local Podman

Update the image in both container unit files:
- `quadlet/hermes-gateway-pod.container`
- `quadlet/hermes-dashboard-pod.container`

Change:
```ini
Image=quay.io/shanemcd/hermes-agent:vertex
```

To:
```ini
Image=quay.io/shanemcd/hermes-agent:vertex-55742
```

Then:

```bash
# Pull new image
podman pull quay.io/shanemcd/hermes-agent:vertex-55742

# Copy updated units
cp quadlet/hermes*.{pod,container} ~/.config/containers/systemd/
systemctl --user daemon-reload

# Restart services
systemctl --user restart hermes-gateway-pod hermes-dashboard-pod
```

## Tagging Strategy

- `vertex-55742` - Specific PR build (immutable)
- `vertex-latest` - Latest working build (can be updated)
- `vertex` - Stable production build

For production, use specific tags. For development, use `latest` or PR-specific tags.
