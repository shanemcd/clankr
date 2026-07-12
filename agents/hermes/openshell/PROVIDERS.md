# OpenShell Providers and Hermes Configuration

## Provider Summary

| Provider | Type | Credentials | Purpose |
|----------|------|-------------|---------|
| `vertex-prod` | `google-vertex-ai` | `GOOGLE_VERTEX_AI_TOKEN` (auto-refreshed) | Inference (Claude on Vertex AI) |
| `discord` | `generic` | `DISCORD_BOT_TOKEN` | Discord messaging |
| `hermes-dashboard` | `generic` | `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` | Dashboard auth |
| `github` | `github` | `GITHUB_TOKEN` (clankrshq), `GITHUB_READONLY_TOKEN` (shanemcd read-only PAT) | Git operations, gh CLI |
| `gitlab-redhat` | `generic` | `GITLAB_TOKEN` | Internal GitLab access |
| `gws` | `generic` | `GWS_CLIENT_ID`, `GWS_CLIENT_SECRET`, `GWS_REFRESH_TOKEN` | Google Workspace (Gmail, Calendar) |
| `atlassian` | `generic` | `ATLASSIAN_ACCESS_TOKEN`, `ATLASSIAN_BASIC_AUTH`, `JIRA_API_TOKEN`, `JIRA_EMAIL` | Atlassian MCP + Jira REST API |
| `slack` | `generic` | `SLACK_APP_TOKEN`, `SLACK_BOT_TOKEN` | Slack messaging |
| `signal` | `generic` | `SIGNAL_HTTP_URL`, `SIGNAL_ACCOUNT`, `SIGNAL_ALLOWED_USERS` | Signal messaging (but these are overridden by `--env` since the supervisor reads them via `os.getenv()` before dotenv loads) |

## How Credentials Flow

Providers store secrets in the OpenShell gateway. The sandbox process sees only `openshell:resolve:env:KEY` placeholders. The proxy resolves them to real values in outbound HTTP traffic at egress.

```
Provider credential (real value, in gateway store)
    → Sandbox env var (placeholder: openshell:resolve:env:v123_KEY)
        → HTTP request header/body (placeholder string)
            → OpenShell proxy (rewrites placeholder to real value)
                → Upstream service (receives real credential)
```

### What the proxy CAN rewrite

- HTTP headers (Authorization, PRIVATE-TOKEN, custom headers)
- HTTP Basic auth (base64-decoded, placeholder found, resolved, re-encoded)
- HTTP request bodies (with `request_body_credential_rewrite: true` on the endpoint)
- WebSocket text frames (with `websocket_credential_rewrite: true`)

### What the proxy CANNOT rewrite

- Values read locally by `os.getenv()` (e.g., Signal config, since the adapter checks env vars before making HTTP requests)
- Values in files read locally (unless the file contents are subsequently sent over HTTP)
- TLS-skipped connections (`tls: skip` endpoints bypass the proxy's L7 inspection)


## In-cluster gateway bootstrap (KubeVirt / CRC)

The Hermes VM uses `http://openshell.openshell.svc.cluster.local:8080`. The host CLI default gateway (`tot`) is a **separate** store — configuring providers on `tot` does not affect the VM.

```bash
oc port-forward -n openshell svc/openshell 18080:8080

# Always pass --gateway-endpoint for in-cluster work:
openshell provider list --gateway-endpoint http://127.0.0.1:18080
openshell inference get --gateway-endpoint http://127.0.0.1:18080

# Vertex inference (required for replies)
gcloud auth application-default login
openshell provider create --gateway-endpoint http://127.0.0.1:18080 \
  --name vertex-prod --type google-vertex-ai --from-gcloud-adc \
  --config VERTEX_AI_PROJECT_ID=itpc-gcp-hcm-pe-eng-claude \
  --config VERTEX_AI_REGION=global
# or: openshell provider update vertex-prod --gateway-endpoint http://127.0.0.1:18080 --config ...

openshell inference set --gateway-endpoint http://127.0.0.1:18080 \
  --provider vertex-prod --model claude-opus-4-6
```

Re-run after gateway reinstalls. ADC token refresh is handled by the gateway once `vertex-prod` exists.

### Platforms on the VM image

- **Slack**: enabled (primary contact channel)
- **Discord**: disabled in image config; rotating `DISCORD_BOT_TOKEN` on the in-cluster gateway is separate from VM wiring
- **Signal**: enabled when `SIGNAL_*` literals are passed at create time; needs in-cluster signal-cli ([openshell-kubevirt `signal/`](https://github.com/shanemcd/openshell-kubevirt/tree/main/signal)) — do not use `host.containers.internal` (OpenShell SSRF)

## Creating Providers

### Vertex AI (inference)

```bash
gcloud auth application-default login
openshell provider create \
  --name vertex-prod \
  --type google-vertex-ai \
  --from-gcloud-adc \
  --config VERTEX_AI_PROJECT_ID=your-gcp-project \
  --config VERTEX_AI_REGION=global

openshell settings set --global --key providers_v2_enabled --value true --yes
openshell inference set --provider vertex-prod --model claude-opus-4-6
```

The gateway auto-refreshes the Vertex OAuth token. No manual token management needed.

### GitHub (dual tokens)

```bash
# Primary token (clankrshq bot account, read-write)
openshell provider create --name github --type github \
  --credential "GITHUB_TOKEN=your-github-pat"

# Secondary read-only token (shanemcd fine-grained PAT)
openshell provider update github \
  --credential "GITHUB_READONLY_TOKEN=$(secret-tool lookup service openshell key github-shanemcd-readonly)"
```

The default `GITHUB_TOKEN` (clankrshq) is used for `gh` CLI and git operations. The shanemcd read-only token is available as `GITHUB_SHANEMCD_READONLY_TOKEN` in the sandbox.

### Google Workspace

```bash
# Authenticate with read-only scopes
gws auth login --readonly -s gmail,calendar

# Decrypt and store credentials
# The gws CLI stores encrypted creds at ~/.config/gws/credentials.enc
# Decrypt using the key at ~/.config/gws/.encryption_key
# Store client_id, client_secret, refresh_token separately

openshell provider create --name gws --type generic \
  --credential "GWS_CLIENT_ID=your-client-id" \
  --credential "GWS_CLIENT_SECRET=your-client-secret" \
  --credential "GWS_REFRESH_TOKEN=your-refresh-token"
```

The gws CLI inside the sandbox reads a credentials file (`gws-credentials.json`) containing placeholder values. When gws refreshes its token, it POSTs to `oauth2.googleapis.com/token`. The proxy rewrites the placeholders in the POST body via `request_body_credential_rewrite: true` on the oauth2 endpoint in the policy.

### Atlassian (MCP + Jira)

```bash
# OAuth access token (for Atlassian MCP, 40 tools including Jira/Confluence)
# Get from Claude's OAuth flow: ~/.claude/.credentials.json
openshell provider create --name atlassian --type generic \
  --credential "ATLASSIAN_ACCESS_TOKEN=your-oauth-token"

# Jira API token (for jirahhh CLI, Basic auth)
openshell provider update atlassian \
  --credential "JIRA_API_TOKEN=your-jira-pat" \
  --credential "JIRA_EMAIL=your-email"

# Pre-encoded Basic auth (for Atlassian MCP if using personal API token)
openshell provider update atlassian \
  --credential "ATLASSIAN_BASIC_AUTH=$(echo -n 'email:token' | base64)"
```

The Atlassian OAuth access token expires (~8 hours). Refresh by re-running the OAuth flow on the host and updating the provider. The Jira API token does not expire.

### Slack

```bash
# Create app at api.slack.com/apps with Socket Mode
# Required bot scopes: chat:write, channels:read, channels:history,
#   groups:read, groups:history, im:read, im:write, im:history,
#   users:read, files:read, files:write, app_mentions:read
# Required events: message.im, message.channels, message.groups, app_mention

openshell provider create --name slack --type generic \
  --credential "SLACK_APP_TOKEN=$(secret-tool lookup service openshell key redhat-slack-app-token)" \
  --credential "SLACK_BOT_TOKEN=$(secret-tool lookup service openshell key redhat-slack-bot-token)"
```

`SLACK_ALLOWED_USERS` goes in `hermes.env` (not the provider) because Hermes reads it via `os.getenv()` locally, not through HTTP.

### Signal

Signal config values (`SIGNAL_HTTP_URL`, `SIGNAL_ACCOUNT`, `SIGNAL_ALLOWED_USERS`) go in `hermes.env` / `openshell sandbox create --env`, **not** a provider. The Signal adapter reads them via `os.getenv()` before dotenv loads. Provider placeholders won't work because Hermes needs literal values to discover and connect to signal-cli.

**CRC / KubeVirt:** run signal-cli in-cluster (not on the host):

```bash
# From shanemcd/openshell-kubevirt
export KUBECONFIG=~/.crc/machines/crc/kubeconfig
./signal/link.sh HermesCRC
```

Then pass:

```bash
--env "SIGNAL_HTTP_URL=http://signal-cli.default.svc.cluster.local:8080" \
--env "SIGNAL_ACCOUNT=+1XXXXXXXXXX" \
--env "SIGNAL_ALLOWED_USERS=+1XXXXXXXXXX"
```

Allow that Service in sandbox policy (`signal-cli.default.svc.cluster.local:8080`). See [`openshell-kubevirt/signal/README.md`](https://github.com/shanemcd/openshell-kubevirt/blob/main/signal/README.md).

**Host podman (legacy, not for OpenShell VM sandboxes):**

```bash
podman run -d --name signal-cli \
  -p 8081:3000 \
  -v signal-cli-native:/var/lib/signal-cli \
  --tmpfs /tmp:exec \
  registry.gitlab.com/packaging/signal-cli/signal-cli-native:latest \
  daemon --http 0.0.0.0:3000
```

Link via `signal-cli-link` at `~/.local/bin/signal-cli-link`. `host.containers.internal` is blocked by OpenShell SSRF — use the in-cluster Service instead for Hermes on CRC.

## Hermes Configuration

### Build-time config (`hermes-config.py`)

Settings baked into the image at build time. Modifies `config.yaml` directly and regenerates NemoClaw config hashes.

Hermes ≥0.18 ignores `model.base_url` for `provider: anthropic` unless the host looks like Anthropic/Azure/…/anthropic — `inference.local` fails that guard and falls back to `api.anthropic.com` (denied by OpenShell). Use `custom` + `anthropic_messages` instead.

Also clear any `providers` / `custom_providers` entry named `custom`: Hermes prefers that block over `model.api_mode` and will silently use `chat_completions` (wrong path for Vertex Claude).

```python
SETTINGS = {
    "model": {
        "default": "claude-opus-4-6",
        "provider": "custom",
        "base_url": "https://inference.local",
        "api_key": "sk-OPENSHELL-PROXY-REWRITE",
        "api_mode": "anthropic_messages",
    },
    "platforms": {
        "discord": {"enabled": False},
        "signal": {"enabled": True},
        "slack": {"enabled": True},
    },
    "web": {"backend": "ddgs"},
}

# Lean VM image: no remote MCP servers; clear hijacking provider blocks.
cfg["mcp_servers"] = {}
cfg.pop("providers", None)
cfg.pop("custom_providers", None)
```

If you re-add remote MCP later, put credentials in headers (not `env:`) so the proxy can rewrite them at egress:

```python
MCP_SERVERS = {
    "Atlassian": {
        "url": "https://mcp.atlassian.com/v1/mcp",
        "headers": {
            "Authorization": "Bearer openshell:resolve:env:ATLASSIAN_ACCESS_TOKEN",
        },
    },
}
```

### Runtime env vars (`hermes.env`)

Site-specific, gitignored. Appended to `/sandbox/.hermes/.env` at image build time.

```bash
_HERMES_FORCE_GITHUB_TOKEN=openshell:resolve:env:GITHUB_TOKEN
_HERMES_FORCE_GH_TOKEN=openshell:resolve:env:GITHUB_TOKEN
GITHUB_SHANEMCD_READONLY_TOKEN=openshell:resolve:env:GITHUB_READONLY_TOKEN
# Literal OpenShell rewrite token — not openshell:resolve:env:ANTHROPIC_API_KEY
ANTHROPIC_API_KEY=sk-OPENSHELL-PROXY-REWRITE
ANTHROPIC_BASE_URL=https://inference.local
SLACK_ALLOWED_USERS=your-slack-member-id
SIGNAL_HTTP_URL=http://signal-cli.default.svc.cluster.local:8080
SIGNAL_ACCOUNT=+1XXXXXXXXXX
SIGNAL_ALLOWED_USERS=+1XXXXXXXXXX
PATH=/opt/hermes/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

### Credential helpers

| Tool | Credential method | How it works |
|------|------------------|--------------|
| `git` (GitHub) | `git-credential-openshell GITHUB_TOKEN` | Credential helper returns placeholder as password, proxy rewrites Basic auth header |
| `git` (GitLab) | `git-credential-openshell GITLAB_TOKEN` | Same pattern |
| `glab` | `glab-config.yml` with placeholder token | glab reads token, sends in header, proxy rewrites |
| `gws` | `gws-credentials.json` with placeholder client_id/secret/refresh_token | Token refresh POST body rewritten by proxy via `request_body_credential_rewrite` |
| `jirahhh` | `jirahhh-config.yaml` with placeholder email/token | Basic auth header rewritten by proxy |
| `oc/kubectl` | `kubeconfig` with exec credential plugin | Reads `CRC_CLUSTER_AUTH` env var (base64-encoded token, injected via `--env` at sandbox creation) |

### Sandbox creation

```bash
openshell-hermes-sandbox-create  # script at ~/.local/bin/
```

The script:
1. Deletes existing sandbox
2. Creates sandbox with all providers and policy
3. Passes `--env CRC_CLUSTER_AUTH=$(oc whoami -t | base64 -w0)` for CRC access
4. Waits for SSH readiness
5. No post-startup SSH config needed (everything baked into image)

## NemoClaw Config Hashes

NemoClaw validates config integrity at startup. The hash file (`/sandbox/.hermes/.config-hash`) contains:
```
<sha256 of config.yaml>  /sandbox/.hermes/config.yaml
<sha256 of .env>  /sandbox/.hermes/.env
# nemoclaw-hermes-mcp-state-v1 intended=<mcp_digest> applied=<mcp_digest>
```

The MCP digest is SHA256 of the canonicalized JSON of the `mcp_servers` section. `update-config-hashes.py` regenerates all three lines at build time after `hermes-config.py` modifies the config.

If the hash doesn't match at startup, NemoClaw refuses to start with `HERMES_MCP_CONFIG_DRIFT`. This is why config changes must happen at build time (via the Python scripts) rather than at runtime.
