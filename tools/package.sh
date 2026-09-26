#!/usr/bin/env bash
# Build the release layout locally with the BigWigs packager, without uploading.
# Output lands in release/ (gitignored). Pass extra packager flags as arguments,
# e.g. tools/package.sh -o to keep the existing .release directory.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
curl -fsSL https://raw.githubusercontent.com/BigWigsMods/packager/v2/release.sh | bash -s -- -d -z -r "$REPO/release" "$@"
echo
echo "Packaged addon folders:"
ls -1 release | grep -v '\.zip$' || true
