#!/usr/bin/env bash
# release.sh — Full local release: archive → sign → notarize → DMG → appcast → GitHub draft
#
# Usage:
#   ./Scripts/release.sh <version>              # e.g. 1.0.4
#   ./Scripts/release.sh <version> [notes.md]  # optional release notes file
#
# What it does:
#   1. Archives the app with xcodebuild
#   2. Calls notarize.sh (re-sign, notarize, DMG, staple)
#   3. Runs sign_update to get the EdDSA signature
#   4. Prepends a new entry to appcast.xml
#   5. Creates a draft GitHub Release and uploads the DMG
#   6. Commits and pushes the updated appcast
#
# What it does NOT do:
#   - Publish the GitHub Release (stays as draft — you review and publish manually)
#   - Bump version numbers in the Xcode project (do that before running this script)
#
# Requirements:
#   - xcrun notarytool credentials stored: xcrun notarytool store-credentials OpenEmu
#   - gh CLI authenticated: gh auth status
#   - Developer ID cert in your keychain

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
APPCAST="$REPO_ROOT/appcast.xml"
DMG="$REPO_ROOT/Releases/OpenEmu-Silicon.dmg"
IDENTITY="Developer ID Application"

die() { echo ""; echo "ERROR: $*" >&2; exit 1; }
step() { echo ""; echo "══════════════════════════════════════"; echo "  $*"; echo "══════════════════════════════════════"; }

# ── Args ──────────────────────────────────────────────────────────────────────
[ $# -ge 1 ] || die "Usage: $0 <version> [release-notes.md]"
VERSION="$1"
NOTES_FILE="${2:-}"

# Validate version format
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version must be in format X.Y.Z (e.g. 1.0.4)"

# ── Find sign_update ──────────────────────────────────────────────────────────
SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData \
  -path "*/artifacts/sparkle/Sparkle/bin/sign_update" \
  -not -path "*/old_dsa_scripts/*" \
  2>/dev/null | head -1)

# Fallback: search the repo's SPM cache
if [ -z "$SIGN_UPDATE" ]; then
  SIGN_UPDATE=$(find "$REPO_ROOT" -path "*/Sparkle/bin/sign_update" \
    -not -path "*/old_dsa_scripts/*" 2>/dev/null | head -1)
fi

[ -n "$SIGN_UPDATE" ] || die "sign_update not found. Build the project in Xcode first to resolve the Sparkle package."
echo "sign_update: $SIGN_UPDATE"

# ── Preflight checks ─────────────────────────────────────────────────────────
step "Preflight checks"

# Check notarytool credentials
xcrun notarytool history --keychain-profile "OpenEmu" &>/dev/null \
  || die "No notarytool credentials found. Run: xcrun notarytool store-credentials OpenEmu"
echo "OK: notarytool credentials"

# Check gh CLI
gh auth status &>/dev/null || die "gh CLI not authenticated. Run: gh auth login"
echo "OK: gh CLI authenticated"

# Check sentry-cli auth (non-fatal — warns but doesn't abort)
if command -v sentry-cli &>/dev/null; then
  if ! sentry-cli info &>/dev/null; then
    echo "WARNING: sentry-cli is not authenticated. dSYM upload will fail."
    echo "         Run: sentry-cli login  (or set SENTRY_AUTH_TOKEN env var)"
  else
    echo "OK: sentry-cli authenticated"
  fi
fi

# Check cert
security find-identity -v | grep -q "Developer ID Application" \
  || die "Developer ID Application certificate not found in keychain."
echo "OK: Developer ID certificate"

# Warn if working tree is dirty (non-appcast files)
DIRTY=$(git -C "$REPO_ROOT" status --porcelain | grep -v "appcast.xml" | grep -v "Releases/" | grep -v "Dolphin/" || true)
if [ -n "$DIRTY" ]; then
  echo ""
  echo "WARNING: Working tree has uncommitted changes:"
  echo "$DIRTY"
  echo ""
  read -r -p "Continue anyway? [y/N] " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

# ── 1. Archive ────────────────────────────────────────────────────────────────
step "1/5  Archiving OpenEmu (Release)"

ARCHIVE_PATH="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/OpenEmu-Silicon-$VERSION.xcarchive"
mkdir -p "$(dirname "$ARCHIVE_PATH")"

xcodebuild archive \
  -workspace "$REPO_ROOT/OpenEmu-metal.xcworkspace" \
  -scheme OpenEmu \
  -configuration Release \
  -destination generic/platform=macOS \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=AJC82Q6789 \
  ENABLE_HARDENED_RUNTIME=YES \
  2>&1 | grep -E "^(Archive|error:|warning:|BUILD)" | tail -20

[ -d "$ARCHIVE_PATH" ] || die "Archive not found at expected path: $ARCHIVE_PATH"
echo "Archive: $ARCHIVE_PATH"

# ── 1.5. Upload dSYMs to Sentry ───────────────────────────────────────────────
step "Uploading dSYMs to Sentry (symbolicated crash reports)"

if command -v sentry-cli &>/dev/null; then
  sentry-cli upload-dif \
    --org openemu-silicon \
    --project openemu-silicon \
    "$ARCHIVE_PATH/dSYMs/" \
    || echo "WARNING: dSYM upload to Sentry failed — crash stack traces may be unreadable. Check sentry-cli auth."
else
  echo "WARNING: sentry-cli not installed. Crash stack traces in Sentry will not be symbolicated."
  echo "         Install with: brew install getsentry/tools/sentry-cli"
  echo "         Then authenticate: sentry-cli login"
fi

# ── 2. Notarize (re-sign + notarize + DMG + staple) ──────────────────────────
step "2/5  Re-signing, notarizing, and creating DMG"

"$SCRIPT_DIR/notarize.sh" "$ARCHIVE_PATH"

[ -f "$DMG" ] || die "DMG not found at $DMG after notarize.sh. Check notarize.sh output above."

# ── 3. Sign for Sparkle ───────────────────────────────────────────────────────
step "3/5  Generating Sparkle EdDSA signature"

SIGN_OUTPUT=$("$SIGN_UPDATE" "$DMG" 2>&1)
echo "$SIGN_OUTPUT"

ED_SIG=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
DMG_LENGTH=$(echo "$SIGN_OUTPUT" | grep -o 'length="[0-9]*"' | cut -d'"' -f2)

[ -n "$ED_SIG" ]    || die "Could not parse edSignature from sign_update output."
[ -n "$DMG_LENGTH" ] || die "Could not parse length from sign_update output."

echo "edSignature: $ED_SIG"
echo "length:      $DMG_LENGTH"

# ── 4. Update appcast.xml ─────────────────────────────────────────────────────
step "4/5  Updating appcast.xml"

# Get next sparkle:version (increment max currently in appcast)
CURRENT_MAX=$(grep -o 'sparkle:version="[0-9]*"' "$APPCAST" | grep -o '[0-9]*' | sort -n | tail -1)
NEXT_VERSION=$((CURRENT_MAX + 1))

PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")

# Build release notes HTML
if [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then
  # Convert simple markdown bullets to HTML (handles -, *, ** bold **)
  NOTES_HTML=$(python3 - "$NOTES_FILE" <<'PYEOF'
import sys, re

with open(sys.argv[1]) as f:
    lines = f.read().splitlines()

out = []
in_ul = False
for line in lines:
    if line.startswith('## '):
        if in_ul: out.append('</ul>'); in_ul = False
        out.append(f'<h3>{line[3:].strip()}</h3>')
    elif re.match(r'^[-*] ', line):
        if not in_ul: out.append('<ul>'); in_ul = True
        item = line[2:].strip()
        item = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', item)
        out.append(f'<li>{item}</li>')
    elif line.strip():
        if in_ul: out.append('</ul>'); in_ul = False
        out.append(f'<p>{line.strip()}</p>')

if in_ul: out.append('</ul>')
print('\n        '.join(out))
PYEOF
)
else
  NOTES_HTML="<p>TODO: add release notes before publishing.</p>"
  echo "NOTE: No release notes file provided. Appcast entry will contain a placeholder."
  echo "      Edit appcast.xml before publishing, or re-run with: $0 $VERSION path/to/notes.md"
fi

# Prepend new <item> to appcast.xml using Python (safer than sed for XML)
python3 - "$APPCAST" "$VERSION" "$NEXT_VERSION" "$PUB_DATE" "$ED_SIG" "$DMG_LENGTH" "$NOTES_HTML" <<'PYEOF'
import sys, re

appcast_path, version, sparkle_version, pub_date, ed_sig, length, notes_html = sys.argv[1:]

new_item = f"""    <item>
      <title>OpenEmu-Silicon {version}</title>
      <description>
        <![CDATA[
        <h2>OpenEmu-Silicon {version}</h2>
        {notes_html}
        ]]>
      </description>
      <pubDate>{pub_date}</pubDate>
      <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
      <enclosure
        url="https://github.com/nickybmon/OpenEmu-Silicon/releases/download/v{version}/OpenEmu-Silicon.dmg"
        sparkle:version="{sparkle_version}"
        sparkle:shortVersionString="{version}"
        sparkle:edSignature="{ed_sig}"
        length="{length}"
        type="application/octet-stream"/>
    </item>"""

with open(appcast_path, 'r') as f:
    content = f.read()

# Insert after the first <channel> block opener (after <language> tag)
insert_after = re.search(r'(<language>[^<]*</language>\s*)', content)
if not insert_after:
    print("ERROR: could not find insertion point in appcast.xml", file=sys.stderr)
    sys.exit(1)

pos = insert_after.end()
content = content[:pos] + new_item + '\n' + content[pos:]

with open(appcast_path, 'w') as f:
    f.write(content)

print(f"Prepended v{version} entry (sparkle:version={sparkle_version}) to appcast.xml")
PYEOF

# ── 5. GitHub Release (draft) + push appcast ──────────────────────────────────
step "5/5  Creating GitHub draft release and pushing appcast"

TAG="v$VERSION"

# Ensure tag exists and is pushed — must happen before gh release create
# so GitHub associates the release with the tag URL instead of "untagged-..."
if ! git -C "$REPO_ROOT" tag -l | grep -qx "$TAG"; then
  echo "Creating git tag $TAG..."
  git -C "$REPO_ROOT" tag "$TAG"
fi
echo "Pushing tag $TAG..."
git -C "$REPO_ROOT" push origin "$TAG"

# Build release notes body for GitHub (use notes file if provided, else placeholder)
if [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then
  GH_NOTES_ARGS=(--notes-file "$NOTES_FILE")
else
  GH_NOTES_ARGS=(--notes "Release notes — edit before publishing.")
fi

# Create or update GitHub draft release
if gh release view "$TAG" --repo nickybmon/OpenEmu-Silicon &>/dev/null; then
  echo "Release $TAG already exists — uploading DMG and updating notes..."
  gh release upload "$TAG" "$DMG" \
    --repo nickybmon/OpenEmu-Silicon \
    --clobber
  gh release edit "$TAG" \
    --repo nickybmon/OpenEmu-Silicon \
    "${GH_NOTES_ARGS[@]}"
else
  echo "Creating draft release $TAG..."
  gh release create "$TAG" "$DMG" \
    --repo nickybmon/OpenEmu-Silicon \
    --title "OpenEmu-Silicon $VERSION" \
    --draft \
    "${GH_NOTES_ARGS[@]}"
fi

echo "DMG uploaded to draft release $TAG."

# Commit and push appcast
git -C "$REPO_ROOT" add "$APPCAST"
git -C "$REPO_ROOT" commit -m "chore: add v$VERSION appcast entry"
git -C "$REPO_ROOT" push origin main

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Release $VERSION prepared — draft is ready to review  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  DMG:     $DMG"
echo "  Appcast: appcast.xml (committed and pushed)"
echo "  Draft:   https://github.com/nickybmon/OpenEmu-Silicon/releases/tag/$TAG"
echo ""
if echo "$NOTES_HTML" | grep -q "TODO"; then
  echo "  ACTION REQUIRED before publishing:"
  echo "  → Edit the release notes in appcast.xml (search for 'TODO')"
  echo "  → Edit the draft release notes on GitHub"
  echo "  → Then publish the draft with: gh release edit $TAG --draft=false --repo nickybmon/OpenEmu-Silicon"
else
  echo "  When ready to publish:"
  echo "  → gh release edit $TAG --draft=false --repo nickybmon/OpenEmu-Silicon"
fi
echo ""
