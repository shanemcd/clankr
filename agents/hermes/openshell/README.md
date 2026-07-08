# OpenShell Sandbox (NemoClaw)

Runs Hermes inside an [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell) sandbox with network policy enforcement, credential injection via the proxy, and Landlock filesystem restrictions. Inference routes through the OpenShell gateway to Vertex AI. No real credentials exist inside the sandbox.

## Prerequisites

- OpenShell gateway running (Quadlet unit at `~/.config/containers/systemd/openshell-gateway.container`)
- `openshell` CLI installed
- A NemoClaw Hermes base image (`localhost/nemoclaw-hermes:latest`)
- OpenShell providers configured (see below)

## 1. Create OpenShell Providers

```bash
# Vertex AI (inference)
gcloud auth application-default login
openshell provider create \
  --name vertex-prod \
  --type google-vertex-ai \
  --from-gcloud-adc \
  --config VERTEX_AI_PROJECT_ID=your-gcp-project \
  --config VERTEX_AI_REGION=global

# Enable providers v2 (required for Vertex routing)
openshell settings set --global --key providers_v2_enabled --value true --yes

# Set inference routing
openshell inference set --provider vertex-prod --model claude-opus-4-6

# Discord bot
openshell provider create --name discord --type generic \
  --credential "DISCORD_BOT_TOKEN=your-bot-token"

# GitHub
openshell provider create --name github --type github \
  --credential "GITHUB_TOKEN=your-github-pat"

# Hermes dashboard auth
openshell provider create --name hermes-dashboard --type generic \
  --credential "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=your-password"

# GitLab (optional, for internal instances)
openshell provider create --name gitlab --type generic \
  --credential "GITLAB_TOKEN=your-gitlab-pat"

# Google Workspace (optional, read-only Gmail/Calendar)
# First authenticate: gws auth login --readonly -s gmail,calendar
# Then store the credentials (decrypt if needed):
openshell provider create --name gws --type generic \
  --credential "GWS_CLIENT_ID=your-client-id" \
  --credential "GWS_CLIENT_SECRET=your-client-secret" \
  --credential "GWS_REFRESH_TOKEN=your-refresh-token"

# Atlassian (optional, Jira/Confluence via MCP)
# Use an OAuth access token from an existing Atlassian MCP auth flow.
openshell provider create --name atlassian --type generic \
  --credential "ATLASSIAN_ACCESS_TOKEN=your-oauth-access-token"
```

## 2. Prepare Site-Specific Files

```bash
cd agents/hermes/openshell

# Network policy (from template)
cp policy.yaml.example policy.yaml
# Edit policy.yaml to add your internal GitLab, MCP servers, etc.

# GitLab CLI config (optional)
cp glab-config.yml.example glab-config.yml
# Edit with your GitLab hostname

# Internal CA certs (optional, for TLS interception of internal hosts)
# Extract your org's CA chain and save it:
echo | openssl s_client -connect gitlab.internal:443 -showcerts 2>/dev/null \
  | awk '/BEGIN CERT/,/END CERT/' > extra-ca-certs.pem
# Or create an empty file if not needed:
touch extra-ca-certs.pem
```

## 3. Build the Sandbox Image

```bash
cd agents/hermes/openshell

# Without internal GitLab:
podman build -t nemoclaw-hermes-configured:latest .

# With internal GitLab credential helper:
podman build --build-arg GITLAB_HOST=gitlab.internal.example \
  -t nemoclaw-hermes-configured:latest .
```

## 4. Create and Launch the Sandbox

The sandbox create command backgrounds the entrypoint and waits for SSH to become available before configuring Hermes.

```bash
SANDBOX_NAME=hermes
POLICY="$HOME/github/shanemcd/clankr/agents/hermes/openshell/policy.yaml"

openshell sandbox create \
  --name "$SANDBOX_NAME" \
  --from localhost/nemoclaw-hermes-configured:latest \
  --provider vertex-prod \
  --provider discord \
  --provider hermes-dashboard \
  --provider github \
  --provider gws \
  --provider atlassian \
  --policy "$POLICY" \
  --no-tty \
  -- /usr/local/bin/nemoclaw-start &

# Wait for SSH to be reachable
SSH_CMD=(ssh -o "ProxyCommand=openshell ssh-proxy --gateway-name tot --name $SANDBOX_NAME"
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
  sandbox@openshell-hermes)
until "${SSH_CMD[@]}" 'true' 2>/dev/null; do sleep 5; done

# Configure Hermes (NemoClaw's hash check prevents baking this into the image)
"${SSH_CMD[@]}" 'hermes config set model.default claude-opus-4-6 && \
  hermes config set model.provider anthropic && \
  hermes config set platforms.discord.enabled true && \
  hermes config set web.backend ddgs'
```

Add `--provider gitlab` or other providers as needed. Only providers listed at creation time have their credentials available for proxy rewriting.

## 5. Access the Dashboard

```bash
# Port forward through the gateway
openshell forward service hermes --target-port 18789 --local 18789

# Or via SSH tunnel (lower latency)
ssh -o "ProxyCommand=openshell ssh-proxy --gateway-name tot --name hermes" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  -N -L 18789:127.0.0.1:18789 sandbox@openshell-hermes

# Dashboard at http://localhost:18789
```

## Management

```bash
# View logs
openshell logs hermes
openshell logs hermes --source sandbox --tail

# Hot-reload network policy (no restart needed)
openshell policy set hermes --policy path/to/policy.yaml

# Attach a new provider to a running sandbox
openshell provider create --name my-provider --type generic --credential "KEY=value"
openshell sandbox provider attach hermes my-provider

# SSH into the sandbox
ssh -o "ProxyCommand=openshell ssh-proxy --gateway-name tot --name hermes" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  sandbox@openshell-hermes

# Delete and recreate
openshell sandbox delete hermes
# Then repeat step 4
```

## MCP Servers

Remote MCP servers can be added to Hermes inside the sandbox. Store credentials as OpenShell provider credentials, include the provider at sandbox creation time, and reference them with `openshell:resolve:env:KEY` placeholders in the MCP headers.

```bash
# 1. Create a provider with the MCP credential
openshell provider create --name my-mcp --type generic \
  --credential "MCP_ACCESS_TOKEN=your-token"

# 2. Include --provider my-mcp in your sandbox create command

# 3. Add the MCP host to policy.yaml with protocol: rest
#    (enables TLS interception and credential rewriting)

# 4. Configure in Hermes via SSH or the dashboard config.yaml:
```

```yaml
# In /sandbox/.hermes/config.yaml
mcp_servers:
  MyMCP:
    url: https://mcp.example.com/v1/mcp
    headers:
      Authorization: "Bearer openshell:resolve:env:MCP_ACCESS_TOKEN"
```

The `headers:` key (not `env:`) is required for remote HTTP MCP servers. The proxy rewrites the placeholder in the Authorization header at egress.

Providers must be included at sandbox creation time (`--provider` flag), not just attached afterward, for their credentials to be resolvable by the proxy.

## Credential Flow

No real credentials exist inside the sandbox. All secrets use OpenShell resolver placeholders (`openshell:resolve:env:KEY`). The OpenShell proxy intercepts outbound HTTP requests and replaces placeholders with real values at egress. This applies to:

- Inference API keys (Vertex AI, via gateway-managed token refresh)
- Git credentials (via `git-credential-openshell` helper)
- GitLab CLI tokens (via `glab-config.yml`)
- Google Workspace CLI (via `gws-credentials.json` with `request_body_credential_rewrite` for token refresh)
- MCP server auth headers
- Discord bot tokens
- GitHub PATs

## Files

| File | Committed | Purpose |
|------|-----------|---------|
| `Containerfile` | Yes | Builds the sandbox image layer |
| `SOUL.md` | Yes | Agent identity and runtime context |
| `hermes.env` | Yes | Environment variable placeholders |
| `git-credential-openshell` | Yes | Generic git credential helper for OpenShell |
| `policy.yaml.example` | Yes | Network policy template |
| `glab-config.yml.example` | Yes | GitLab CLI config template |
| `gws-credentials.json` | Yes | GWS OAuth placeholder credentials |
| `policy.yaml` | No (gitignored) | Site-specific network policy |
| `glab-config.yml` | No (gitignored) | Site-specific GitLab config |
| `extra-ca-certs.pem` | No (gitignored) | Internal CA certificates |
