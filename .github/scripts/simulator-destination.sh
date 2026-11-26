#!/usr/bin/env bash
set -euo pipefail

min_major=26

runtimes() {
  xcrun simctl list runtimes available --json | jq -c --argjson min "$min_major" '
    [.runtimes[] | select(.platform == "iOS")
      | select((.version | split(".")[0] | tonumber) >= $min)]
    | sort_by([(if (.identifier | test("SimRuntime\\.iOS-[0-9-]+$")) then 1 else 0 end),
        (.version | split(".") | map(tonumber))]) | reverse | .[]'
}

iphone_on() {
  local runtime=$1 runtime_id udid device_type
  runtime_id=$(jq -r .identifier <<<"$runtime")
  udid=$(xcrun simctl list devices available --json | jq -r --arg rt "$runtime_id" '
    [.devices[$rt][]? | select(.name | startswith("iPhone")) | select(.name | test("Duo") | not)] | first | .udid // empty')
  if [ -z "$udid" ]; then
    device_type=$(jq -r '[.supportedDeviceTypes[] | select(.productFamily == "iPhone") | select(.name | test("Duo") | not)] | last | .identifier // empty' <<<"$runtime")
    [ -z "$device_type" ] && return 0
    echo "No iPhone simulator on $runtime_id; creating one ($device_type)" >&2
    udid=$(xcrun simctl create "CI iPhone" "$device_type" "$runtime_id") || return 0
  fi
  [ -n "$udid" ] || return 0
  echo "$udid $runtime_id"
}

pick() {
  local runtime found
  while IFS= read -r runtime; do
    [ -z "$runtime" ] && continue
    found=$(iphone_on "$runtime")
    if [ -n "$found" ]; then
      echo "$found"
      return 0
    fi
  done < <(runtimes)
}

found=$(pick)
if [ -z "$found" ]; then
  echo "No iOS $min_major+ simulator runtime with a regular iPhone installed; downloading it" >&2
  xcodebuild -downloadPlatform iOS >&2
  found=$(pick)
fi
if [ -z "$found" ]; then
  echo "::error::No iOS $min_major+ simulator runtime with a regular iPhone available" >&2
  exit 1
fi

udid=${found%% *}
runtime_id=${found#* }
echo "Using $(xcrun simctl list devices | grep "$udid" | sed 's/^ *//') on $runtime_id" >&2
echo "platform=iOS Simulator,id=$udid"
