#!/usr/bin/env bash
# Run luacheck inside the Lua 5.1 Docker image (built on first use).
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="goblinomics-lua"
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker build -t "$IMAGE" -f "$REPO/tools/docker/Dockerfile" "$REPO/tools/docker"
fi
exec docker run --rm -v "$REPO":/work -w /work "$IMAGE" luacheck . "$@"
