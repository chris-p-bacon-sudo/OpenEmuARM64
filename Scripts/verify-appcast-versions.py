#!/usr/bin/env python3
# verify-appcast-versions.py
#
# Lint that the topmost <enclosure> in every Appcasts/*.xml advertises a
# sparkle:version equal to the CFBundleVersion baked inside its referenced
# GitHub release asset. Catches the cores-v1.2.0 class of bug regardless
# of how the appcast got into that state — script, hand-edit, copy-paste,
# anything.
#
# Why "topmost only": Sparkle picks the highest version from the channel
# and offers that as the available update. A stale historical entry whose
# version is wrong is not user-visible because Sparkle never picks it.
# The active entry is the one that hits real users, so it's the one that
# must be true.
#
# Usage:
#     ./Scripts/verify-appcast-versions.py
#
# Designed to run in GitHub Actions, but works locally too. Requires:
#   - `gh` CLI authenticated (CI provides GH_TOKEN automatically)
#   - Python 3.9+
#
# Exit codes:
#   0 — every appcast's topmost entry matches its referenced asset
#   1 — at least one mismatch (or a download/parse failure)

import os
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


SPARKLE_NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
APPCASTS_DIR = Path(__file__).resolve().parent.parent / 'Appcasts'


def first_enclosure(appcast_path):
    """Return (url, sparkle:version) of the first <enclosure> in the channel,
    or None if the channel has no items."""
    tree = ET.parse(appcast_path)
    root = tree.getroot()
    # The structure is <rss><channel><item><enclosure ... /></item>...</channel></rss>
    for item in root.iter('item'):
        for enclosure in item.iter('enclosure'):
            url = enclosure.get('url')
            version = enclosure.get(f'{{{SPARKLE_NS}}}version')
            if url and version:
                return (url, version)
    return None


def parse_release_url(url):
    """Extract (owner, repo, tag, asset) from a GitHub release-asset URL."""
    m = re.match(
        r'https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/(.+)$',
        url,
    )
    if not m:
        return None
    return m.groups()


def download_asset(owner, repo, tag, asset, dest_path):
    """Download a release asset using `gh` for auth + private-repo support."""
    result = subprocess.run(
        [
            'gh', 'release', 'download', tag,
            '-R', f'{owner}/{repo}',
            '-p', asset,
            '-O', str(dest_path),
            '--clobber',
        ],
        capture_output=True,
        text=True,
    )
    return result.returncode == 0, result.stderr


def cfbundleversion_in_zip(zip_path):
    """Open the zip's *.oecoreplugin/Contents/Info.plist and return
    CFBundleVersion (or None if it can't be found)."""
    with zipfile.ZipFile(zip_path) as zf:
        candidates = [
            n for n in zf.namelist()
            if n.endswith('.oecoreplugin/Contents/Info.plist')
        ]
        if len(candidates) != 1:
            return None
        with zf.open(candidates[0]) as plist_f:
            return plistlib.load(plist_f).get('CFBundleVersion')


def lint_appcast(appcast_path):
    """Return a list of human-readable failure strings (empty = OK)."""
    enc = first_enclosure(appcast_path)
    if enc is None:
        # Empty channel (e.g. desmume.xml has only a comment, no item).
        # Nothing to verify; skip silently.
        return []

    url, advertised = enc
    parsed = parse_release_url(url)
    if parsed is None:
        return [f'  enclosure URL is not a GitHub release asset: {url}']

    owner, repo, tag, asset = parsed

    with tempfile.NamedTemporaryFile(suffix='.zip', delete=False) as tmp:
        tmp_path = tmp.name
    try:
        ok, stderr = download_asset(owner, repo, tag, asset, tmp_path)
        if not ok:
            return [
                f'  could not download {url}\n'
                f'    gh stderr: {stderr.strip()}'
            ]
        actual = cfbundleversion_in_zip(tmp_path)
        if actual is None:
            return [
                f'  could not read CFBundleVersion from {url}\n'
                f'    (zip does not contain exactly one '
                f'*.oecoreplugin/Contents/Info.plist)'
            ]
        if actual != advertised:
            return [
                f'  {url}\n'
                f'    appcast advertises sparkle:version="{advertised}"\n'
                f'    zip\'s CFBundleVersion=    "{actual}"'
            ]
        return []
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def main():
    if not APPCASTS_DIR.is_dir():
        print(f'no Appcasts directory at {APPCASTS_DIR}', file=sys.stderr)
        return 1

    appcasts = sorted(APPCASTS_DIR.glob('*.xml'))
    if not appcasts:
        print(f'no *.xml files under {APPCASTS_DIR}', file=sys.stderr)
        return 1

    failures = {}
    for appcast in appcasts:
        result = lint_appcast(appcast)
        if result:
            failures[appcast.name] = result

    print(f'verified {len(appcasts)} appcasts')

    if not failures:
        print('OK: every topmost enclosure matches its referenced binary.')
        return 0

    print('')
    print('FAIL: appcast advertises a version that does not match the')
    print('      CFBundleVersion baked inside its referenced release asset.')
    print('')
    for name, lines in failures.items():
        print(f'{name}:')
        for line in lines:
            print(line)
        print('')
    print('This is the cores-v1.2.0 class of bug. If this PR is merged,')
    print('every user already on the older version will see an update prompt,')
    print('download the zip, install it, still report the older version')
    print('internally, and loop on the same prompt forever.')
    print('')
    print('Fix: rebuild the bundle with CFBundleVersion bumped to the')
    print('version the appcast claims, re-upload as a new release asset,')
    print('then update the appcast. Do not edit the appcast to match the')
    print('wrong zip.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
