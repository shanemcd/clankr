# OpenClaw

[OpenClaw](https://openclaw.ai/) Discord bot (`@clankr`) running inside an [OpenShell](https://github.com/NVIDIA/OpenShell) sandbox with policy-enforced network egress and credential injection.

Uses [OpenRouter](https://openrouter.ai/) for inference (Claude Sonnet 5), with the Discord channel plugin for messaging.

## Prerequisites

- An OpenShell gateway running (see root README)
- A Discord bot token (from the [Discord Developer Portal](https://discord.com/developers/applications/))
- An OpenRouter API key (from [openrouter.ai](https://openrouter.ai/))

## Setup

### 1. Store secrets

```bash
secret-tool store --label='Discord Bot Token' service openshell key discord-bot-token
secret-tool store --label='OpenRouter API Key' service openshell key openrouter-api-key
```

### 2. Create OpenShell providers

```bash
openshell provider create --name openrouter --type generic \
  --credential "OPENROUTER_API_KEY=$(secret-tool lookup service openshell key openrouter-api-key)"

openshell provider create --name discord --type generic \
  --credential "DISCORD_BOT_TOKEN=$(secret-tool lookup service openshell key discord-bot-token)"
```

### 3. Build the image

Two-stage build. First, build the NemoClaw base from source (only needed once):

```bash
git clone --depth 1 https://github.com/NVIDIA/NemoClaw.git /tmp/nemoclaw-src

podman build -t nemoclaw-discord:latest \
  --build-arg NEMOCLAW_MODEL=openrouter/anthropic/claude-sonnet-5 \
  --build-arg NEMOCLAW_PROVIDER_KEY=openrouter \
  --build-arg NEMOCLAW_UPSTREAM_PROVIDER=openrouter \
  --build-arg NEMOCLAW_PRIMARY_MODEL_REF=openrouter/anthropic/claude-sonnet-5 \
  --build-arg NEMOCLAW_INFERENCE_BASE_URL=https://openrouter.ai/api/v1 \
  --build-arg NEMOCLAW_INFERENCE_API=openai-completions \
  -f /tmp/nemoclaw-src/Dockerfile \
  /tmp/nemoclaw-src
```

Then layer on the Discord plugin and config:

```bash
podman build -t nemoclaw-discord-configured:latest \
  -f agents/openclaw/Containerfile agents/openclaw/
```

### 4. Create the sandbox

```bash
openshell sandbox create \
  --name clankr \
  --from localhost/nemoclaw-discord-configured:latest \
  --provider openrouter \
  --provider discord \
  --policy agents/openclaw/policy.yaml \
  --no-tty \
  -- /usr/local/bin/nemoclaw-start
```

The bot should come online on Discord within about 30 seconds.

## Managing the sandbox

```bash
openshell status                          # gateway health
openshell sandbox list                    # list sandboxes
openshell logs clankr                     # view sandbox logs
openshell policy set clankr --policy ...  # hot-reload network policy
openshell sandbox delete clankr           # tear down
```

## Network policy

The policy (`policy.yaml`) controls what the sandbox can reach:

| Rule | Endpoints | Purpose |
|------|-----------|---------|
| `discord_gateway` | `gateway.discord.gg:443` | WebSocket connection (credential rewrite enabled) |
| `discord_api` | `discord.com:443`, `discordapp.com:443` | REST API |
| `discord_cdn` | `cdn.discordapp.com:443`, `media.discordapp.net:443` | Images and attachments |
| `openrouter` | `openrouter.ai:443` | LLM inference |
| `npm_registry` | `registry.npmjs.org:443` | Plugin updates |

All other outbound traffic is denied. Add endpoints with `openshell policy set` for hot-reload.

## Model configuration

OpenRouter models use the format `openrouter/<author>/<slug>`. The model is baked into the Containerfile. To change it, update the `openclaw models set` line in the Containerfile and rebuild.

## How it works

The image is built in two layers:

1. **NemoClaw base** (from upstream Dockerfile): OpenClaw runtime, managed proxy preload scripts (`http-proxy-fix.js`), `nemoclaw-start` entrypoint
2. **Config layer** (from `Containerfile`): Discord plugin, OpenRouter model, channel config, pre-configured owner

The `nemoclaw-start` entrypoint handles privilege separation, proxy setup, gateway auth token generation, and launches the OpenClaw gateway. The OpenShell supervisor wraps this with a network namespace, transparent proxy, Landlock filesystem restrictions, and credential injection.

Credentials (`DISCORD_BOT_TOKEN`, `OPENROUTER_API_KEY`) are injected as opaque placeholders by the OpenShell supervisor. The proxy resolves them at egress time, so the agent process never sees real values.
