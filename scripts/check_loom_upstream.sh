#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_SPEC="$ROOT_DIR/project.yml"
FAIL_IF_OUTDATED="${1:-}"

local_version="$(
  awk '
    $1 == "Loom:" { in_loom = 1; next }
    in_loom && $1 == "exactVersion:" { print $2; exit }
  ' "$PROJECT_SPEC"
)"

if [[ -z "$local_version" ]]; then
  echo "Failed to read Loom version from project.yml"
  exit 1
fi

latest_version="$(
  git ls-remote --tags --refs https://github.com/EthanLipnik/Loom \
    | awk -F/ '{print $NF}' \
    | rg '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -n 1
)"

if [[ -z "$latest_version" ]]; then
  echo "Failed to resolve the latest Loom tag from upstream."
  exit 1
fi

echo "Local Loom version:   $local_version"
echo "Upstream Loom version: $latest_version"

if [[ "$local_version" == "$latest_version" ]]; then
  echo "Loom is up to date."
  exit 0
fi

echo "Loom update available."

if [[ "$FAIL_IF_OUTDATED" == "--fail-if-outdated" ]]; then
  exit 1
fi
