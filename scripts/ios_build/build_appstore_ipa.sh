#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_FILE="$ROOT/Trump.xcodeproj/project.pbxproj"
ARCHIVE_PATH="$ROOT/build/Trump.xcarchive"
EXPORT_PATH="$ROOT/build/ipa-appstore"

cd "$ROOT"

fallback_args=()
if [[ "${ASC_ALLOW_LOCAL_FALLBACK:-0}" == "1" ]]; then
  fallback_args+=(--allow-local-fallback)
fi

ruby scripts/ios_build/next_app_store_build.rb --apply "${fallback_args[@]}"

"$GODOT_BIN" --headless --path . --export-pack "iOS" Trump.pck

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
xcodebuild \
  -project Trump.xcodeproj \
  -scheme Trump \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist Trump/export_options.plist

echo "IPA ready: $EXPORT_PATH/Trump.ipa"
