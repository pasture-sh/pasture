#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if command -v xcodegen >/dev/null 2>&1; then
  echo "Regenerating Xcode project via xcodegen..."
  xcodegen generate
else
  echo "xcodegen not found; using existing .xcodeproj"
fi

"$ROOT_DIR/scripts/test_ios_sim.sh"
"$ROOT_DIR/scripts/build_macos_helper.sh"

echo "All automated checks passed."
