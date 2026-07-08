#!/usr/bin/env python3
"""Configure Hermes settings and MCP servers at image build time.

Modifies config.yaml directly instead of shelling out to `hermes config set`,
which avoids issues with HOME detection. Run update-config-hashes.py after
this to regenerate NemoClaw's integrity hashes.
"""
import yaml

CONFIG_PATH = "/sandbox/.hermes/config.yaml"

SETTINGS = {
    "model": {
        "default": "claude-opus-4-6",
        "provider": "anthropic",
    },
    "platforms": {
        "discord": {"enabled": True},
    },
    "web": {
        "backend": "ddgs",
    },
}

MCP_SERVERS = {
    "Atlassian": {
        "url": "https://mcp.atlassian.com/v1/mcp",
        "headers": {
            "Authorization": "Bearer openshell:resolve:env:ATLASSIAN_ACCESS_TOKEN",
        },
    },
}


def deep_merge(base, override):
    for k, v in override.items():
        if k in base and isinstance(base[k], dict) and isinstance(v, dict):
            deep_merge(base[k], v)
        else:
            base[k] = v


def main():
    with open(CONFIG_PATH) as f:
        cfg = yaml.safe_load(f)

    deep_merge(cfg, SETTINGS)
    cfg["mcp_servers"] = MCP_SERVERS

    with open(CONFIG_PATH, "w") as f:
        yaml.dump(cfg, f, default_flow_style=False)

    print("Hermes config updated:")
    for k, v in SETTINGS.items():
        print(f"  {k}: {v}")
    print(f"  mcp_servers: {list(MCP_SERVERS.keys())}")


if __name__ == "__main__":
    main()
