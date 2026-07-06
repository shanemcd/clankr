# Deployment Checklist for PR #55742 Update

## ✅ Completed Steps

- [x] Fetched PR #55742 from upstream
- [x] Fixed Dockerfile for Podman compatibility (removed --chmod from COPY)
- [x] Building new image: `quay.io/shanemcd/hermes-agent:vertex-55742`
- [x] Updated all documentation to reference PR #55742

## 🔄 In Progress

- [ ] Build completing...

## ⏳ Next Steps (After Build Completes)

### 1. Push Image to Registry

```bash
podman push quay.io/shanemcd/hermes-agent:vertex-55742
```

### 2. Update Kubernetes Deployment

Edit `k8s/overlays/crc/kustomization.yaml`:

```yaml
images:
- name: docker.io/nousresearch/hermes-agent
  newName: quay.io/shanemcd/hermes-agent
  newTag: vertex-55742  # <-- Update from 'vertex' to 'vertex-55742'
```

Apply:
```bash
kubectl apply -k k8s/overlays/crc
```

### 3. Update Podman Quadlet Units

Edit both files:
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

Update running deployment:
```bash
podman pull quay.io/shanemcd/hermes-agent:vertex-55742
cp quadlet/hermes*-pod.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user restart hermes-gateway-pod hermes-dashboard-pod
```

### 4. Test the Update

```bash
# Podman
podman exec hermes-gateway hermes chat -q "Test message"
podman logs hermes-gateway 2>&1 | grep -i "vertex\|anthropic"

# Kubernetes
kubectl exec -n hermes-agent deployment/hermes-gateway -- hermes chat -q "Test message"
kubectl logs -n hermes-agent deployment/hermes-gateway | grep -i "vertex\|anthropic"
```

### 5. Tag as Latest (Optional)

Once verified working:

```bash
podman tag quay.io/shanemcd/hermes-agent:vertex-55742 quay.io/shanemcd/hermes-agent:vertex
podman push quay.io/shanemcd/hermes-agent:vertex
```

## Differences from PR #27356

PR #55742 improvements:
- ✅ Beta header already correct (no manual patch needed)
- ✅ Reads `vertex.project_id` and `vertex.region` from config.yaml
- ✅ More recent codebase (includes latest security fixes)
- ✅ Better error messages for missing dependencies
