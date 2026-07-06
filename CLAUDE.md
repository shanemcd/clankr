# CLAUDE.md

## Project Overview

Clankr stores configuration and deployment files for autonomous AI agents. Each agent lives in its own directory under `agents/` with deployment configs (Quadlet, Kubernetes) and documentation.

## Structure

- `agents/hermes/` -- Hermes Agent with Claude on Vertex AI. Kustomize base/overlay for Kubernetes, Quadlet for local Podman.
- `agents/openclaw/` -- OpenClaw Discord bot via NemoClaw sandbox base. Quadlet for local Podman.

## Agents

### Hermes Agent (`agents/hermes/`)

- Custom image `quay.io/shanemcd/hermes-agent:vertex-55742` built from upstream PR #55742
- Two containers: gateway (agent runtime) and dashboard (web UI)
- Kubernetes deployment uses Kustomize with a CRC/OpenShift overlay
- Quadlet deployment uses a Podman pod grouping both containers
- State in `/opt/data`, single replica only, `strategy: Recreate`

### OpenClaw (`agents/openclaw/`)

- Image built from `ghcr.io/nvidia/nemoclaw/sandbox-base:latest` with `@openclaw/discord` plugin
- Single container running `openclaw gateway run --force`
- Secrets managed via `secret-tool` and `podman secret`
- OpenRouter model format: `openrouter/<author>/<slug>`

## Common Patterns

- Secrets are never committed. Use `secrets.yaml.example` templates for Kubernetes, `secret-tool` + `podman secret` for Quadlet.
- Quadlet units install to `~/.config/containers/systemd/` and manage via `systemctl --user`.
- Each agent README has a self-contained quick start.
