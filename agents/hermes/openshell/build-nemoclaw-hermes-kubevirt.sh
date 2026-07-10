#!/usr/bin/env bash
# Build localhost/nemoclaw-hermes:kubevirt from shanemcd/NemoClaw kubevirt-sidecar.
# Uses the published hermes-sandbox-base (ARG BASE_IMAGE in agents/hermes/Dockerfile).
set -euo pipefail

NEMOCLAW_SRC="${NEMOCLAW_SRC:-${HOME}/github/shanemcd/NemoClaw}"
IMAGE_TAG="${IMAGE_TAG:-localhost/nemoclaw-hermes:kubevirt}"
BRANCH="${NEMOCLAW_BRANCH:-kubevirt-sidecar}"

cd "$NEMOCLAW_SRC"
git fetch fork "$BRANCH" 2>/dev/null || git fetch origin "$BRANCH" 2>/dev/null || true
git checkout "$BRANCH"

podman build -t "$IMAGE_TAG" -f agents/hermes/Dockerfile .

echo "Built $IMAGE_TAG from $(git rev-parse --short HEAD) ($BRANCH)"
echo "Next: copy openshell-sandbox (OpenShell kubevirt-sidecar) into agents/hermes/openshell/"
echo "      then: podman build -f Containerfile.kubevirt -t localhost/hermes-sandbox-kubevirt:latest ."
