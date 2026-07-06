# clankr

Config and deployment for my autonomous agents.

## Agents

| Agent | Channel | Inference | Deployment | Details |
|-------|---------|-----------|------------|---------|
| [Hermes Agent](agents/hermes/) | Discord | Claude on Vertex AI | Quadlet, Kubernetes | Custom Vertex AI image from PR #55742 |
| [OpenClaw](agents/openclaw/) | Discord (`@clankr`) | OpenRouter | Quadlet | Built on NemoClaw sandbox base |

## Structure

```
agents/
  hermes/
    quadlet/        Podman systemd units
    k8s/            Kustomize manifests (base + CRC overlay)
    README.md
  openclaw/
    quadlet/        Podman systemd unit
    Containerfile   Custom image definition
    README.md
```

Each agent directory is self-contained with its own README, deployment configs, and (where needed) image build files.

## License

MIT
