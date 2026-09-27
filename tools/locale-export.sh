#!/usr/bin/env bash
# Export every phrase (and the German example) for translators into release/locale/
# Runs Lua 5.1 in the project's Docker image.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec docker run --rm -u "$(id -u):$(id -g)" -v "$REPO":/work -w /work goblinomics-lua lua tools/locale_export.lua
