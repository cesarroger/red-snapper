#!/usr/bin/env python3
"""Adds (or replaces) one release in appcast.xml, the feed Sparkle checks for updates.

Usage: update_appcast.py <version> <build> <download-url> '<sign_update output>'
where the sign_update output looks like: sparkle:edSignature="..." length="..."
"""
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape

APPCAST = Path(__file__).resolve().parent.parent / "appcast.xml"
REPO = "https://github.com/cesarroger/red-snapper"
SKELETON = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>RED SNAPPER</title>
    <link>{repo}</link>
    <description>RED SNAPPER updates</description>
    <language>en</language>
  </channel>
</rss>
""".format(repo=REPO)


def main() -> None:
    version, build, url, signature_line = sys.argv[1:5]
    signature = re.search(r'sparkle:edSignature="([^"]+)"', signature_line).group(1)
    length = re.search(r'length="(\d+)"', signature_line).group(1)

    item = f"""    <item>
      <title>Version {escape(version)}</title>
      <pubDate>{datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000')}</pubDate>
      <sparkle:version>{escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>{REPO}/releases/tag/v{escape(version)}</sparkle:releaseNotesLink>
      <enclosure url="{escape(url)}" sparkle:edSignature="{signature}" length="{length}" type="application/octet-stream"/>
    </item>
"""
    feed = APPCAST.read_text() if APPCAST.exists() else SKELETON
    # Rebuilding the same build number replaces its entry instead of duplicating it.
    feed = re.sub(r"    <item>\n(?:(?!</item>).)*?<sparkle:version>" + re.escape(build)
                  + r"</sparkle:version>.*?</item>\n", "", feed, flags=re.S)
    # Newest release first.
    anchor = "    <language>en</language>\n"
    feed = feed.replace(anchor, anchor + item, 1)
    APPCAST.write_text(feed)
    print(f"appcast.xml: added version {version} (build {build})")


if __name__ == "__main__":
    main()
