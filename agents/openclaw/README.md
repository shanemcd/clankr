# OpenClaw

[OpenClaw](https://openclaw.ai/) Discord bot running as a rootless Podman container via Quadlet.

Uses [OpenRouter](https://openrouter.ai/) for inference, with the Discord channel plugin for messaging.

## Prerequisites

- Podman 4.4+ with Quadlet support
- A Discord bot token (from the [Discord Developer Portal](https://discord.com/developers/applications/))
- An OpenRouter API key (from [openrouter.ai](https://openrouter.ai/))

## Setup

### 1. Store secrets

```bash
# Discord bot token
secret-tool store --label='Discord Bot Token' service openshell key discord-bot-token

# OpenRouter API key
secret-tool store --label='OpenRouter API Key' service openshell key openrouter-api-key
```

### 2. Create Podman secrets

```bash
secret-tool lookup service openshell key discord-bot-token | podman secret create discord-bot-token -
secret-tool lookup service openshell key openrouter-api-key | podman secret create openrouter-api-key -
```

### 3. Build the image

```bash
podman build -t nemoclaw-discord:latest -f agents/openclaw/Containerfile agents/openclaw/
```

### 4. Install the Quadlet

```bash
cp agents/openclaw/quadlet/nemoclaw-discord.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start nemoclaw-discord
```

### 5. Pair on Discord

DM the bot on Discord. It will show a pairing code. Approve it:

```bash
podman exec nemoclaw-discord openclaw pairing approve discord <CODE>
```

## Managing the service

```bash
systemctl --user status nemoclaw-discord
systemctl --user restart nemoclaw-discord
systemctl --user stop nemoclaw-discord
journalctl --user -u nemoclaw-discord -f
```

## Model configuration

OpenClaw uses the format `openrouter/<author>/<slug>` for OpenRouter models. To change models:

```bash
podman exec nemoclaw-discord openclaw models set openrouter/anthropic/claude-sonnet-5
podman exec nemoclaw-discord kill -USR1 1
```

Note: config changes inside the container are lost on restart. To persist, update the `Containerfile` and rebuild.

## How it works

The Containerfile extends `ghcr.io/nvidia/nemoclaw/sandbox-base:latest` (which ships OpenClaw pre-installed) by:

1. Installing the `@openclaw/discord` plugin
2. Running `openclaw doctor --fix` to bootstrap config
3. Setting gateway mode, model, and Discord channel config
4. Running `openclaw gateway run --force` as the entrypoint

Secrets are injected at runtime via Podman secrets, never baked into the image.
