#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Pasture.xcodeproj"
SCHEME="Pasture"

if [[ ! -f "$PROJECT_PATH/project.pbxproj" ]]; then
  echo "Project not found at $PROJECT_PATH"
  exit 1
fi

first_iphone_sim_id() {
  xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -showdestinations \
    | awk '/platform:iOS Simulator/ && /name:iPhone/ {print; exit}' \
    | sed -E 's/.*id:([^,]+),.*/\1/'
}

SIM_ID="${IOS_SIMULATOR_ID:-}"
if [[ -z "$SIM_ID" ]]; then
  SIM_ID="$(first_iphone_sim_id)"
fi

if [[ -z "$SIM_ID" ]]; then
  echo "No iPhone simulator destination found."
  exit 1
fi

echo "Running iOS tests on simulator id: $SIM_ID"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  CODE_SIGNING_ALLOWED=NO \
  test
