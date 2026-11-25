#!/bin/sh
# One-time setup on your Mac: generates Chartz.xcodeproj from project.yml.
# The renderer (Vendor/MermaidKit) is already in the repo, so there is
# nothing to fetch.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -f Vendor/MermaidKit/Package.swift ]; then
  echo "Vendor/MermaidKit is missing. Check the repo out again." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is not installed. Run: brew install xcodegen" >&2
  exit 1
fi

# The bundle prefix lives in the xcconfig files so Xcode and XcodeGen agree.
# Info.plist needs it too (the iCloud container key), and Xcode does not
# expand build settings in plist keys, so hand it to XcodeGen here.
prefix_from() {
  [ -f "$1" ] && sed -n 's/^[[:space:]]*CHARTZ_BUNDLE_PREFIX[[:space:]]*=[[:space:]]*\([^[:space:]/]*\).*/\1/p' "$1" | tail -1
}
CHARTZ_BUNDLE_PREFIX="$(prefix_from Config/Signing.local.xcconfig || true)"
[ -n "$CHARTZ_BUNDLE_PREFIX" ] || CHARTZ_BUNDLE_PREFIX="$(prefix_from Config/Chartz.xcconfig)"
export CHARTZ_BUNDLE_PREFIX
echo "Bundle id: $CHARTZ_BUNDLE_PREFIX.chartz"

xcodegen generate
echo "Done. Open Chartz.xcodeproj and pick a destination."
