# Podman Quadlet Deployment

This directory contains systemd unit files for running Hermes Agent locally with Podman Quadlet using a pod (similar to Kubernetes pod architecture).

## Prerequisites

- Podman 4.4+ (with Quadlet support)
- systemd
- GCP credentials at `~/.config/gcloud/application_default_credentials.json`

## Setup

### 1. Create config directory

```bash
mkdir -p ~/.config/hermes
```

### 2. Set up environment file

```bash
cp quadlet/env.example ~/.config/hermes/env
# Edit ~/.config/hermes/env with your values
```

To generate a dashboard password hash:

```bash
podman run --rm -it quay.io/shanemcd/hermes-agent:vertex \
  python -c "from plugins.dashboard_auth.basic import hash_password; print(hash_password('your-password'))"
```

### 3. (Optional) Create custom config template

If you want to customize the initial config:

```bash
cat > ~/.config/hermes/config.yaml.template <<EOF
model:
  default: claude-opus-4-6
  provider: anthropic
# Add any other config here
EOF
```

### 4. Create the shared volume

```bash
podman volume create hermes-data
```

### 5. Install Quadlet units

```bash
# Copy unit files to user systemd directory
mkdir -p ~/.config/containers/systemd
cp quadlet/hermes*.{pod,container} ~/.config/containers/systemd/

# Reload systemd to pick up new units
systemctl --user daemon-reload
```

## Usage

### Start services

```bash
# Start both containers (they run in the same pod)
systemctl --user start hermes-gateway-pod hermes-dashboard-pod

# Services auto-start on login (Quadlet-generated units start automatically)
```

### Check status

```bash
# Pod status
podman pod ps
podman ps --pod

# Service status
systemctl --user status hermes-gateway-pod
systemctl --user status hermes-dashboard-pod

# Container logs
podman logs -f hermes-gateway
podman logs -f hermes-dashboard

# Or via journalctl
journalctl --user -u hermes-gateway-pod -f
journalctl --user -u hermes-dashboard-pod -f
```

### Test Hermes

```bash
podman exec hermes-gateway hermes chat -q "Hello"
```

### Access dashboard

Open http://localhost:9119 in your browser.

### Stop services

```bash
# Stop both containers
systemctl --user stop hermes-gateway-pod hermes-dashboard-pod

# Or stop the entire pod
podman pod stop systemd-hermes
```

## Data Persistence

All Hermes data is stored in the `hermes-data` named volume. To inspect or back up:

```bash
# Inspect volume
podman volume inspect hermes-data

# Get volume path
podman volume inspect hermes-data --format '{{.Mountpoint}}'

# Backup
podman run --rm -v hermes-data:/data:ro -v $(pwd):/backup alpine tar czf /backup/hermes-backup.tar.gz -C /data .

# Restore
podman run --rm -v hermes-data:/data -v $(pwd):/backup alpine tar xzf /backup/hermes-backup.tar.gz -C /data
```

## Troubleshooting

### Config not being created

The first time you start Hermes, it will create a default config. If you need to reset or manually create it:

```bash
podman exec hermes-gateway hermes config set model.provider anthropic
podman exec hermes-gateway hermes config set model.default claude-opus-4-6
```

### Permission issues

If you see permission errors, check SELinux labels:

```bash
# The :Z and :z flags in volume mounts should handle this
# If issues persist, check audit log
sudo ausearch -m avc -ts recent
```

### Container won't start

Check the service logs:

```bash
journalctl --user -u hermes-gateway-pod -n 50
journalctl --user -u hermes-dashboard-pod -n 50

# Or check container logs directly
podman logs hermes-gateway
podman logs hermes-dashboard
```

## Updating

To update to a newer image:

```bash
# Pull new image
podman pull quay.io/shanemcd/hermes-agent:vertex

# Restart services (systemd will use the new image)
systemctl --user restart hermes-gateway-pod hermes-dashboard-pod

# Or restart the entire pod
podman pod restart systemd-hermes
```
