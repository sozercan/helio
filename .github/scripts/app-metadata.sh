#!/usr/bin/env bash
set -euo pipefail

app="$1"

entitlements='[]'
xml=$(codesign -d --entitlements - --xml "$app" 2>/dev/null || true)
if [ -n "$xml" ]; then
  entitlements=$(plutil -convert json -o - - <<<"$xml" | jq -c 'keys')
fi

plutil -convert json -o - "$app/Info.plist" | jq --argjson entitlements "$entitlements" '{
  bundleIdentifier: .CFBundleIdentifier,
  version: .CFBundleShortVersionString,
  buildVersion: .CFBundleVersion,
  minOSVersion: .MinimumOSVersion,
  entitlements: $entitlements,
  privacy: with_entries(select(.key | test("^NS.*UsageDescription$")))
}'
