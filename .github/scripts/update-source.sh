#!/usr/bin/env bash
# Adds a release to the AltStore/SideStore source feed served from gh-pages.
#
#   update-source.sh --source source.json --metadata metadata.json --url <ipa url> \
#     --size <ipa bytes> --notes notes.md
#
# Creates the feed if it doesn't exist yet. Newest version first; re-running for a version
# that's already listed replaces that entry, so a re-tagged release doesn't duplicate it.
# --metadata is the output of app-metadata.sh for the released build.
set -euo pipefail

repo="https://github.com/sozercan/helio"
icon="https://raw.githubusercontent.com/sozercan/helio/main/App/Helio/Assets.xcassets/appIcons/iconStandard.appiconset/iconStandard.png"
tint="F5A623"
description="Helio is a privacy-focused, open-source Reddit client for iOS and Mac. No analytics, no tracking, no ads. It needs your own Reddit API client ID; see the README for setup. Sideloaded builds can't use iCloud, so data stays on the device."

while [ $# -gt 0 ]; do
  case "$1" in
    --source) source_file="$2" ;;
    --metadata) metadata_file="$2" ;;
    --url) url="$2" ;;
    --size) size="$2" ;;
    --notes) notes_file="$2" ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift 2
done
: "${source_file:?--source is required}" "${metadata_file:?--metadata is required}"
: "${url:?--url is required}" "${size:?--size is required}" "${notes_file:?--notes is required}"

bundle_id=$(jq -r .bundleIdentifier "$metadata_file")

if [ -f "$source_file" ]; then
  source_json=$(cat "$source_file")
else
  source_json=$(jq -n --arg id "$bundle_id" --arg repo "$repo" --arg icon "$icon" \
    --arg tint "$tint" --arg description "$description" '{
    name: "Helio",
    identifier: "\($id).source",
    subtitle: "Privacy-focused Reddit client",
    description: $description,
    iconURL: $icon,
    website: $repo,
    tintColor: $tint,
    apps: [{
      name: "Helio",
      bundleIdentifier: $id,
      developerName: "Sertac Ozercan",
      subtitle: "Privacy-focused Reddit client",
      localizedDescription: $description,
      iconURL: $icon,
      tintColor: $tint,
      category: "social",
      screenshots: [],
      versions: [],
      appPermissions: {entitlements: [], privacy: {}}
    }],
    news: []
  }')
fi

updated=$(jq --slurpfile meta "$metadata_file" --rawfile notes "$notes_file" --arg url "$url" \
  --argjson size "$size" --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  $meta[0] as $m
  | ($notes | gsub("^\\s+|\\s+$"; "")) as $notes
  | if any(.apps[]; .bundleIdentifier == $m.bundleIdentifier) then . else
      error("No app with bundle id \($m.bundleIdentifier) in the source") end
  | .apps |= map(
      if .bundleIdentifier != $m.bundleIdentifier then . else
        # AltStore checks a release'"'"'s entitlements against what the feed declares.
        .appPermissions = {entitlements: $m.entitlements, privacy: $m.privacy}
        | .versions = [{
            version: $m.version,
            buildVersion: $m.buildVersion,
            date: $date,
            localizedDescription: (if $notes == "" then "Helio \($m.version)" else $notes end),
            downloadURL: $url,
            size: $size,
            minOSVersion: $m.minOSVersion
          }] + [.versions[] | select(.version != $m.version)]
      end)
' <<<"$source_json")
printf '%s\n' "$updated" > "$source_file"
