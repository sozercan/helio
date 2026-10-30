#!/usr/bin/env bash
# Prints the feed metadata AltStore/SideStore need from a built Helio.app: bundle id,
# version, minimum iOS, entitlements and privacy usage strings. macOS only (plutil, codesign).
set -euo pipefail

app="$1"

# Unsigned builds have no entitlements; codesign then prints nothing.
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
