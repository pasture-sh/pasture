#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_SPEC="$ROOT_DIR/project.yml"
PACKAGE_RESOLVED="$ROOT_DIR/Pasture.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

if [[ ! -f "$PROJECT_SPEC" ]]; then
  echo "Missing project spec at $PROJECT_SPEC"
  exit 1
fi

if [[ ! -f "$PACKAGE_RESOLVED" ]]; then
  echo "Missing Package.resolved at $PACKAGE_RESOLVED"
  exit 1
fi

project_version="$(
  awk '
    $1 == "Loom:" { in_loom = 1; next }
    in_loom && $1 == "exactVersion:" { print $2; exit }
  ' "$PROJECT_SPEC"
)"

resolved_version="$(
  awk '
    /"identity"[[:space:]]*:[[:space:]]*"loom"/ { in_loom = 1 }
    in_loom && /"version"[[:space:]]*:/ {
      gsub(/[",]/, "", $3)
      print $3
      exit
    }
  ' "$PACKAGE_RESOLVED"
)"

if [[ -z "$project_version" || -z "$resolved_version" ]]; then
  echo "Failed to resolve Loom versions from project files."
  exit 1
fi

if [[ "$project_version" != "$resolved_version" ]]; then
  echo "Loom version mismatch: project.yml pins $project_version but Package.resolved has $resolved_version"
  exit 1
fi

for required in \
  "product: LoomKit" \
  "product: LoomCloudKit" \
  "PastureCloudKitContainerIdentifier:"; do
  if ! rg -q "$required" "$PROJECT_SPEC"; then
    echo "Missing Loom integration requirement in project.yml: $required"
    exit 1
  fi
done

echo "Loom integration is internally consistent at version $project_version."
