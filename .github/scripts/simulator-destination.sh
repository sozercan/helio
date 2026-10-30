#!/usr/bin/env bash
# Prints an xcodebuild destination for an iPhone simulator on the newest installed iOS
# runtime (26 or later, the deployment target). Runner images vary: simulator names change
# with each Xcode and some images ship without an iOS runtime, so nothing is hard-coded.
# Installs the runtime and creates a device when needed. Diagnostics go to stderr.
set -euo pipefail

min_major=26

# Newest available iOS runtime at or above min_major, as JSON. For equal versions prefer the
# general runtime over device-specific ones, which have longer identifiers.
latest_runtime() {
  xcrun simctl list runtimes available --json | jq -c --argjson min "$min_major" '
    [.runtimes[] | select(.platform == "iOS")
      | select((.version | split(".")[0] | tonumber) >= $min)]
    | sort_by([(.version | split(".") | map(tonumber)), -(.identifier | length)]) | last // empty'
}

runtime=$(latest_runtime)
if [ -z "$runtime" ]; then
  echo "No iOS $min_major+ simulator runtime installed; downloading it" >&2
  xcodebuild -downloadPlatform iOS >&2
  runtime=$(latest_runtime)
fi
if [ -z "$runtime" ]; then
  echo "::error::No iOS $min_major+ simulator runtime available" >&2
  exit 1
fi

runtime_id=$(jq -r .identifier <<<"$runtime")
udid=$(xcrun simctl list devices available --json | jq -r --arg rt "$runtime_id" '
  [.devices[$rt][]? | select(.name | startswith("iPhone"))] | first | .udid // empty')

if [ -z "$udid" ]; then
  device_type=$(jq -r '[.supportedDeviceTypes[] | select(.productFamily == "iPhone")] | last | .identifier' <<<"$runtime")
  echo "No iPhone simulator on $runtime_id; creating one ($device_type)" >&2
  udid=$(xcrun simctl create "CI iPhone" "$device_type" "$runtime_id")
fi

echo "Using $(xcrun simctl list devices | grep "$udid" | sed 's/^ *//') on $runtime_id" >&2
echo "platform=iOS Simulator,id=$udid"
