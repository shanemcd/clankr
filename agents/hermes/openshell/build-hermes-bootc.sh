#!/usr/bin/env bash
# Build localhost/hermes-sandbox-bootc:latest via Containerfile.kubevirt.
# Pulls openshell-sandbox with COPY --from a supervisor *image* (not a raw binary).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSHELL_SRC="${OPENSHELL_SRC:-${HOME}/github/clankrshq/OpenShell}"
SUPERVISOR_IMAGE="${OPENSHELL_SUPERVISOR_IMAGE:-localhost/openshell-supervisor:kubevirt}"
BOOTC_TAG="${BOOTC_TAG:-localhost/hermes-sandbox-bootc:latest}"
NEMOCLAW_TAG="${NEMOCLAW_TAG:-localhost/nemoclaw-hermes:kubevirt}"

if ! podman image exists "$NEMOCLAW_TAG"; then
  echo "Missing $NEMOCLAW_TAG — run ./build-nemoclaw-hermes-kubevirt.sh first" >&2
  exit 1
fi

if ! podman image exists "$SUPERVISOR_IMAGE"; then
  echo "Building OpenShell supervisor image → $SUPERVISOR_IMAGE"
  if [[ ! -d "$OPENSHELL_SRC" ]]; then
    echo "OPENSHELL_SRC not found: $OPENSHELL_SRC" >&2
    exit 1
  fi
  (
    cd "$OPENSHELL_SRC"
    # Stages musl openshell-sandbox + builds deploy/docker/Dockerfile.supervisor
    tasks/scripts/docker-build-image.sh supervisor
  )
  # docker-build-image.sh tags openshell/supervisor:<something>; retag for the ARG default.
  src=$(podman images --format '{{.Repository}}:{{.Tag}}' | grep -E '^openshell/supervisor:' | head -1 || true)
  if [[ -z "$src" ]]; then
    echo "Could not find openshell/supervisor:* after build" >&2
    exit 1
  fi
  podman tag "$src" "$SUPERVISOR_IMAGE"
  echo "Tagged $src → $SUPERVISOR_IMAGE"
fi

cd "$SCRIPT_DIR"
podman build \
  --build-arg "OPENSHELL_SUPERVISOR_IMAGE=$SUPERVISOR_IMAGE" \
  -f Containerfile.kubevirt \
  -t "$BOOTC_TAG" \
  .

echo "Built $BOOTC_TAG (supervisor from $SUPERVISOR_IMAGE)"
