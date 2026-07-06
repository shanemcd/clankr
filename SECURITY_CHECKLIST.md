# Security Checklist for Public Release

This file documents the security review before making this repository public.

## ✅ Sensitive Data Removed

- [x] No GCP project IDs in committed files
- [x] No Discord bot tokens in committed files
- [x] No Discord user IDs in committed files
- [x] No password hashes in committed files
- [x] No API keys in committed files
- [x] No ADC credential files in committed files

## ✅ .gitignore Protection

- [x] `secrets.yaml` is gitignored
- [x] `k8s/**/secrets.yaml` is gitignored
- [x] `application_default_credentials.json` is gitignored
- [x] `*.key.json` is gitignored
- [x] `*.credentials.json` is gitignored
- [x] `.env` is gitignored

## ✅ Example Files Sanitized

- [x] `k8s/overlays/crc/secrets.yaml.example` - Contains only placeholders
- [x] `quadlet/env.example` - Contains only placeholders

## ✅ Documentation Quality

- [x] README.md has clear setup instructions
- [x] LICENSE file added (MIT)
- [x] VERTEX_SUPPORT.md explains technical details
- [x] CLAUDE.md provides operational guidance
- [x] quadlet/README.md documents local deployment

## Files Staged for Commit

Run `git status` to verify only these files are included:
- Documentation: README.md, LICENSE, CLAUDE.md, VERTEX_SUPPORT.md
- Kubernetes: k8s/base/*, k8s/overlays/crc/* (except secrets.yaml)
- Podman: quadlet/* (only pod-based files)
- Config: .gitignore

## Post-Publication

After making the repo public:
1. Rotate any credentials that may have been in previous commits
2. Review GitHub security settings
3. Enable Dependabot security alerts
4. Consider adding SECURITY.md for vulnerability reporting
