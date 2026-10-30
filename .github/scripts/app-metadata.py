#!/usr/bin/env python3
"""Prints the feed metadata AltStore/SideStore need from a built Helio.app: bundle id,
version, minimum iOS, entitlements and privacy usage strings."""

import json
import plistlib
import subprocess
import sys

app = sys.argv[1]
with open(f"{app}/Info.plist", "rb") as f:
  info = plistlib.load(f)

# Unsigned builds have no entitlements; codesign then prints nothing.
signed = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", app], capture_output=True)
entitlements = sorted(plistlib.loads(signed.stdout)) if signed.stdout.strip() else []

json.dump({
  "bundleIdentifier": info["CFBundleIdentifier"],
  "version": info["CFBundleShortVersionString"],
  "buildVersion": info["CFBundleVersion"],
  "minOSVersion": info["MinimumOSVersion"],
  "entitlements": entitlements,
  "privacy": {k: v for k, v in info.items() if k.startswith("NS") and k.endswith("UsageDescription")},
}, sys.stdout, indent=2)
print()
