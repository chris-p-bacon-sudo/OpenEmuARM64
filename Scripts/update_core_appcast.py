#!/usr/bin/env python3
# update_core_appcast.py — Prepend a new release entry to a per-core appcast
#
# Usage:
#   python3 Scripts/update_core_appcast.py <appcast.xml> <core_name> <version> \
#       <download_url> <length>
#
# Arguments:
#   appcast.xml    Path to the core's appcast file (e.g. Appcasts/flycast.xml)
#   core_name      Display name of the core (e.g. Flycast)
#   version        Version string — also used as sparkle:version (e.g. 2.5)
#   download_url   Full URL to the .oecoreplugin.zip on GitHub Releases
#   length         Byte size of the zip file
#
# Core appcasts use a simpler format than the main app appcast:
#   - No EdDSA signature (the app has disable-library-validation entitlement)
#   - No description/release notes block
#   - version string doubles as both sparkle:version and sparkle:shortVersionString

import sys
import re


def main():
    if len(sys.argv) != 6:
        print(
            'Usage: update_core_appcast.py <appcast.xml> <core_name> <version> '
            '<download_url> <length>',
            file=sys.stderr,
        )
        sys.exit(1)

    appcast_path = sys.argv[1]
    core_name = sys.argv[2]
    version = sys.argv[3]
    download_url = sys.argv[4]
    length = sys.argv[5]

    new_item = f"""    <item>
      <title>{core_name} {version}</title>
      <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
      <enclosure
        url="{download_url}"
        sparkle:version="{version}"
        sparkle:shortVersionString="{version}"
        length="{length}"
        type="application/octet-stream" />
    </item>"""

    with open(appcast_path, 'r') as f:
        content = f.read()

    # Insert after <title>CoreName</title> opening of the channel
    insert_after = re.search(r'(<title>[^<]*</title>\s*)', content)
    if not insert_after:
        print(f'ERROR: could not find insertion point in {appcast_path}', file=sys.stderr)
        sys.exit(1)

    pos = insert_after.end()
    content = content[:pos] + new_item + '\n' + content[pos:]

    with open(appcast_path, 'w') as f:
        f.write(content)

    print(f'Prepended {core_name} {version} entry to {appcast_path}')


if __name__ == '__main__':
    main()
