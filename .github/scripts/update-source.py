#!/usr/bin/env python3
"""Adds a release to the AltStore/SideStore source feed served from gh-pages.

Creates the feed if it doesn't exist yet. Newest version first; re-running for a version
that's already listed replaces that entry, so a re-tagged release doesn't duplicate it.
"""

import argparse
import json
import pathlib

REPO = "https://github.com/sozercan/helio"
ICON = "https://raw.githubusercontent.com/sozercan/helio/main/App/Helio/Assets.xcassets/appIcons/iconStandard.appiconset/iconStandard.png"
TINT = "F5A623"
DESCRIPTION = (
  "Helio is a privacy-focused, open-source Reddit client for iOS and Mac. No analytics, no "
  "tracking, no ads. It needs your own Reddit API client ID; see the README for setup. "
  "Sideloaded builds can't use iCloud, so data stays on the device."
)


def new_source(bundle_id):
  return {
    "name": "Helio",
    "identifier": f"{bundle_id}.source",
    "subtitle": "Privacy-focused Reddit client",
    "description": DESCRIPTION,
    "iconURL": ICON,
    "website": REPO,
    "tintColor": TINT,
    "apps": [
      {
        "name": "Helio",
        "bundleIdentifier": bundle_id,
        "developerName": "Sertac Ozercan",
        "subtitle": "Privacy-focused Reddit client",
        "localizedDescription": DESCRIPTION,
        "iconURL": ICON,
        "tintColor": TINT,
        "category": "social",
        "screenshots": [],
        "versions": [],
        "appPermissions": {"entitlements": [], "privacy": {}},
      }
    ],
    "news": [],
  }


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--source", required=True, type=pathlib.Path)
  parser.add_argument("--metadata", required=True, type=pathlib.Path,
                      help="JSON from app-metadata.py for the released build")
  parser.add_argument("--date", required=True)
  parser.add_argument("--url", required=True)
  parser.add_argument("--size", required=True, type=int)
  parser.add_argument("--notes", required=True, type=pathlib.Path)
  args = parser.parse_args()

  meta = json.loads(args.metadata.read_text())
  bundle_id = meta["bundleIdentifier"]
  source = json.loads(args.source.read_text()) if args.source.exists() else new_source(bundle_id)
  app = next(a for a in source["apps"] if a["bundleIdentifier"] == bundle_id)

  # AltStore checks a release's entitlements against what the feed declares.
  app["appPermissions"] = {"entitlements": meta["entitlements"], "privacy": meta["privacy"]}

  version = meta["version"]
  entry = {
    "version": version,
    "buildVersion": meta["buildVersion"],
    "date": args.date,
    "localizedDescription": args.notes.read_text().strip() or f"Helio {version}",
    "downloadURL": args.url,
    "size": args.size,
    "minOSVersion": meta["minOSVersion"],
  }
  app["versions"] = [entry] + [v for v in app["versions"] if v["version"] != version]

  args.source.write_text(json.dumps(source, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
  main()
