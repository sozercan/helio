#!/usr/bin/env bash
set -euo pipefail

while [ $# -gt 0 ]; do
  case "$1" in
    --appcast) appcast_file="$2" ;;
    --update) update_file="$2" ;;
    --url) url="$2" ;;
    --release-page) release_page="$2" ;;
    --notes) notes_file="$2" ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift 2
done
: "${appcast_file:?--appcast is required}" "${update_file:?--update is required}"
: "${url:?--url is required}" "${release_page:?--release-page is required}" "${notes_file:?--notes is required}"

field() { jq -er ".$1" "$update_file"; }
version=$(field version)
build=$(field buildVersion)
min_os=$(field minOSVersion)
signature=$(field edSignature)
length=$(field length)
notes=$(sed 's/]]>/]]]]><![CDATA[>/g' "$notes_file")
date=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")

cat > "$appcast_file" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Helio</title>
    <link>https://github.com/sozercan/helio/releases</link>
    <description>Updates to Helio for Mac.</description>
    <language>en</language>
    <item>
      <title>Helio $version</title>
      <pubDate>$date</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$min_os</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$release_page</sparkle:fullReleaseNotesLink>
      <description sparkle:format="markdown"><![CDATA[$notes]]></description>
      <enclosure url="$url" length="$length" type="application/octet-stream" sparkle:edSignature="$signature"/>
    </item>
  </channel>
</rss>
EOF
