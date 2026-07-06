# Claude on Vertex AI Support

Hermes Agent does not natively support Claude models on Vertex AI. The upstream `vertex` provider is for Gemini models only. This deployment uses a custom image that adds Claude on Vertex AI support.

## The Problem

Hermes has an `anthropic` provider that uses the `anthropic.Anthropic` SDK client, which requires an `ANTHROPIC_API_KEY`. It also has a `vertex` provider that uses Google's OpenAI-compatible endpoint for Gemini models. There is no built-in way to use Claude models through Vertex AI's Anthropic integration.

## The Solution

[PR #55742](https://github.com/NousResearch/hermes-agent/pull/55742) adds Claude on Vertex AI support by:

1. Adding a `build_anthropic_vertex_client()` function to `agent/anthropic_adapter.py` that creates an `anthropic.AnthropicVertex` SDK client using ADC (Application Default Credentials)
2. Adding Vertex provider initialization to `agent/agent_init.py` that detects `provider == "vertex"` and uses the AnthropicVertex client
3. Adding auto-fallback logic to `hermes_cli/runtime_provider.py`: when `provider: anthropic` is configured but no API key is found, it checks for `VERTEX_PROJECT_ID` / `ANTHROPIC_VERTEX_PROJECT_ID` / `GOOGLE_CLOUD_PROJECT` and automatically routes through Vertex

### Beta Header Handling

PR #55742 correctly handles the beta header - it only sends `_COMMON_BETAS` (thinking and tool streaming), not the `context-1m-2025-08-07` beta which Vertex rejects with HTTP 400. On Vertex AI, the context window is determined by the model itself, not a beta header.

## How It Works

With `provider: vertex` in `config.yaml`, the runtime provider resolution follows this path:

1. Reads `vertex.project_id` and `vertex.region` from config.yaml (or falls back to env vars)
2. `agent_init.py` detects `provider == "vertex"` and creates an `AnthropicVertex` client
3. The client authenticates using ADC (`GOOGLE_APPLICATION_CREDENTIALS`)
4. Requests are routed to the Vertex AI endpoint for Claude models

## Environment Variables

The PR reads these (in priority order):

**Project ID:**
- `VERTEX_PROJECT_ID`
- `ANTHROPIC_VERTEX_PROJECT_ID`
- `GOOGLE_CLOUD_PROJECT`

**Region:**
- `VERTEX_REGION`
- `CLOUD_ML_REGION`
- Default: `global`

**Credentials:**
- `GOOGLE_APPLICATION_CREDENTIALS` (path to ADC JSON)

## Building the Custom Image

```bash
git clone https://github.com/NousResearch/hermes-agent.git
cd hermes-agent

# Apply PR #55742
git fetch origin pull/55742/head:vertex-support
git checkout vertex-support

# Build
podman build -t quay.io/your-user/hermes-agent:vertex -f Dockerfile .
podman push quay.io/your-user/hermes-agent:vertex
```

## Kubernetes Configuration

**config.yaml** (in ConfigMap):
```yaml
model:
  default: claude-opus-4-6
  provider: vertex
vertex:
  project_id: ""  # Will be read from env vars if not set here
  region: global
```

**.env** (in Secret):
```
ANTHROPIC_VERTEX_PROJECT_ID=your-gcp-project-id
GOOGLE_CLOUD_PROJECT=your-gcp-project-id
VERTEX_REGION=global
GOOGLE_CLOUD_LOCATION=global
```

**Vertex credentials** (separate Secret, mounted at `/secrets/vertex/`):
```bash
kubectl create secret generic vertex-credentials \
  -n hermes-agent \
  --from-file=application_default_credentials.json=$HOME/.config/gcloud/application_default_credentials.json
```

The `vertex-patch.yaml` in the CRC overlay mounts this secret and sets `GOOGLE_APPLICATION_CREDENTIALS` to point at it.

## Upstream Status

As of July 2026, PR #55742 is open but not merged. Related issues:
- [#13484](https://github.com/NousResearch/hermes-agent/issues/13484) - Feature request for native Vertex AI support
- [#12639](https://github.com/NousResearch/hermes-agent/issues/12639) - Same request, canonical tracking issue
- [#36253](https://github.com/NousResearch/hermes-agent/pull/36253) - A different PR that adds Vertex for Gemini (closed)

When native support is merged upstream, this custom image will no longer be needed.
