#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_SPEC="$ROOT_DIR/project.yml"
PROJECT_PATH="$ROOT_DIR/Pasture.xcodeproj"
PACKAGE_RESOLVED="$ROOT_DIR/Pasture.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

has_required_text() {
  local pattern="$1"
  local file="$2"

  if command -v rg >/dev/null 2>&1; then
    rg -Fq "$pattern" "$file"
  else
    grep -Fq "$pattern" "$file"
  fi
}

if [[ ! -f "$PROJECT_SPEC" ]]; then
  echo "Missing project spec at $PROJECT_SPEC"
  exit 1
fi

if [[ ! -f "$PACKAGE_RESOLVED" ]]; then
  if [[ ! -f "$PROJECT_PATH/project.pbxproj" ]]; then
    echo "Project not found at $PROJECT_PATH"
    exit 1
  fi

  echo "Package.resolved not found; resolving Swift packages first..."
  xcodebuild -project "$PROJECT_PATH" -resolvePackageDependencies >/dev/null
fi

if [[ ! -f "$PACKAGE_RESOLVED" ]]; then
  echo "Missing Package.resolved at $PACKAGE_RESOLVED even after resolving packages."
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
  if ! has_required_text "$required" "$PROJECT_SPEC"; then
    echo "Missing Loom integration requirement in project.yml: $required"
    exit 1
  fi
done

echo "Loom integration is internally consistent at version $project_version."
