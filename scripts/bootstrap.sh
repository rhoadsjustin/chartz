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

xcodegen generate
echo "Done. Open Chartz.xcodeproj and pick a destination."
