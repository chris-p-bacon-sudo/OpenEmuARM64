Release a core plugin update or hotfix. Usage: `/release-core <CoreName> <NewVersion>`

Example: `/release-core Flycast 2.5`

Use this command when:
- A bug fix has been merged to main that affects a specific core (plist data, game core code, BIOS registry)
- You want to ship that fix to users without a full app release

This command covers **in-repo built cores** (Flycast, Dolphin, 4DO, etc.) — cores whose source code lives in this repository and are built from Xcode. For buildbot-sourced core updates, see `docs/core-update-process.md` instead.

---

## !! HARD RULE — NO EXCEPTIONS !!

**NEVER publish a GitHub Release.**
Never run `gh release edit ... --draft=false`, never change a prerelease to a full release,
never push tags that trigger release workflows. Publishing is always the user's action.

---

## Step 1 — Confirm prerequisites

```bash
git checkout main
git fetch origin && git merge origin/main
```

Confirm:
- The fix being released is already merged to `main`
- The working tree is clean
- `gh auth status` passes
- Developer ID cert is in keychain: `security find-identity -v | grep "Developer ID Application"`

If any of these fail, stop and report what needs to be fixed.

## Step 2 — Create a release branch

```bash
git checkout -b chore/<corename-lowercase>-<version>-release
# e.g. chore/flycast-2.5-release
```

## Step 3 — Bump the core version

Edit `<CoreName>/Info.plist`:
- Increment `CFBundleVersion` to the new version string

Verify with:
```bash
plutil -lint <CoreName>/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" <CoreName>/Info.plist
```

**Watch out for `$(CURRENT_PROJECT_VERSION)`.** Some cores (BSNES is the
known case) have `<string>$(CURRENT_PROJECT_VERSION)</string>` in
`Info.plist` instead of a literal version. For those, editing only the
plist won't change the built binary — Xcode substitutes the value at
build time from `CURRENT_PROJECT_VERSION` in the project file. The
Step 7b guardrail will catch this (the zip's `CFBundleVersion` will
come back as the old version, not what you wrote here). When that
happens, you also need to bump `CURRENT_PROJECT_VERSION` in
`<CoreName>/<CoreName>.xcodeproj/project.pbxproj` (or the relevant
xcconfig). Detect this case before building:

```bash
grep -q '\$(CURRENT_PROJECT_VERSION)' <CoreName>/Info.plist \
  && echo "WARNING: Info.plist uses CURRENT_PROJECT_VERSION — also bump it in the project file" \
  || echo "Plist uses literal version — single edit is enough"
```

## Step 4 — Build the main workspace in Release (produces frameworks the core needs)

```bash
xcodebuild \
  -workspace OpenEmu-metal.xcworkspace \
  -scheme OpenEmu \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -5
```

If this fails, stop and report the errors. Do not continue.

## Step 5 — Build the core in Release

Build via the workspace's `OpenEmu + <CoreName>` scheme — not the bare
`<CoreName>` scheme. The bare scheme isn't configured for the build
action on every core (4DO is one example) and will fail with
`Scheme <CoreName> is not currently configured for the build action`.
The combo scheme always builds both the host app and the plugin together,
producing both into the same `OpenEmu-metal-*` DerivedData tree.

```bash
xcodebuild \
  -workspace OpenEmu-metal.xcworkspace \
  -scheme "OpenEmu + <CoreName>" \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  ONLY_ACTIVE_ARCH=YES \
  build 2>&1 | tail -10
```

If the build fails, stop and report the errors.

## Step 6 — Locate the built plugin

The plugin is built into the same `OpenEmu-metal-*` DerivedData tree as
the host app, not into a per-core `<CoreName>-*` tree:

```bash
PLUGIN=$(find ~/Library/Developer/Xcode/DerivedData/OpenEmu-metal-* \
  -name "<CoreName>.oecoreplugin" \
  -path "*/Release/*" \
  -not -path "*.dSYM*" \
  2>/dev/null | head -1)
echo "Plugin: $PLUGIN"
```

Verify the built version matches the target:
```bash
/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLUGIN/Contents/Info.plist"
```

## Step 7 — Sign and zip the plugin

```bash
codesign --force --sign "Developer ID Application" \
  --options runtime --timestamp \
  "$PLUGIN" && echo "Signed OK"

ZIP="/tmp/<CoreName>.oecoreplugin.zip"
ditto -c -k --keepParent "$PLUGIN" "$ZIP"
wc -c < "$ZIP" | tr -d ' '   # note the byte count — needed for the appcast
```

### Step 7b — Verify the zip contents match the target version

This is the guardrail against the cores-v1.2.0 class of bug, where the
appcast advertised a version that the zipped artifact didn't actually
contain (because the plist bump didn't take, or an old zip got reused).
Stop here if it fails — the appcast must never claim a version that
isn't in the zip.

**Note:** since `chore/release-skill-version-precondition`,
`Scripts/update_core_appcast.py` ALSO enforces this check automatically
whenever `--sign-zip` is passed (Step 10 below). The manual check here
is kept as defense-in-depth and to surface the failure earlier in the
pipeline (before signing/uploading rather than after).

```bash
VERIFY_DIR=$(mktemp -d)
ditto -x -k "$ZIP" "$VERIFY_DIR"
ZIP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" \
  "$VERIFY_DIR/<CoreName>.oecoreplugin/Contents/Info.plist")
echo "Zip CFBundleVersion: $ZIP_VERSION (expected: <NewVersion>)"
[ "$ZIP_VERSION" = "<NewVersion>" ] || { echo "MISMATCH — stop"; exit 1; }
rm -rf "$VERIFY_DIR"
```

If this fails, the most likely causes are: the plist bump in Step 3 was
saved to the wrong path, the build cached an old binary, or
`CURRENT_PROJECT_VERSION` in the project file overrides the literal in
Info.plist. Investigate before continuing — do not edit the appcast to
match a wrong zip.

### Step 7c — Upload dSYM to Sentry

```bash
if command -v sentry-cli &>/dev/null; then
  DERIVED_DATA=$(find ~/Library/Developer/Xcode/DerivedData \
    -maxdepth 1 -name "OpenEmu-metal-*" -type d 2>/dev/null | head -1)
  if [ -n "$DERIVED_DATA" ]; then
    DSYM="$DERIVED_DATA/Build/Products/Release/<CoreName>.oecoreplugin.dSYM"
    if [ -d "$DSYM" ]; then
      sentry-cli debug-files upload \
        --org openemu-silicon \
        --project openemu-silicon \
        "$DSYM" && echo "dSYM uploaded to Sentry" \
        || echo "WARNING: dSYM upload failed — check sentry-cli auth"
    else
      echo "WARNING: dSYM not found at $DSYM — build may not have produced one"
    fi
  else
    echo "WARNING: DerivedData for OpenEmu-metal not found — skipping dSYM upload"
  fi
else
  echo "WARNING: sentry-cli not installed — install with: brew install getsentry/tools/sentry-cli"
fi
```

Non-fatal: warns but does not abort the release.

## Step 8 — Determine the release tag

Check existing cores releases:
```bash
gh release list --repo nickybmon/OpenEmu-Silicon | grep "^Emulation Cores"
```

- If this is the only core being updated, create a new `cores-vX.Y.Z` tag (increment the patch).
- If multiple cores are being updated together, they can share one release.

Convention: `cores-v1.0.0` → `cores-v1.0.1` for a single-core hotfix. `cores-v1.1.0` → `cores-v1.2.0` for a batch update with notable changes.

## Step 9 — Create the GitHub Release (prerelease)

Core releases are always created as `--prerelease`. This keeps them off the main releases page but leaves them reachable by appcast URLs.

```bash
NEXT_TAG="cores-vX.Y.Z"   # determined above

gh release create "$NEXT_TAG" "$ZIP" \
  --repo nickybmon/OpenEmu-Silicon \
  --title "Emulation Cores vX.Y.Z" \
  --prerelease \
  --notes "<CoreName> <NewVersion> — <one-line description of what changed>.

Distributed via the in-app core updater — not a user-facing download. If you are looking to install OpenEmu-Silicon, see the [latest release](https://github.com/nickybmon/OpenEmu-Silicon/releases/latest)."
```

Note the asset URL — it will be:
```
https://github.com/nickybmon/OpenEmu-Silicon/releases/download/<NEXT_TAG>/<CoreName>.oecoreplugin.zip
```

## Step 10 — Update the appcast

Edit `Appcasts/<corename-lowercase>.xml`:
- Add a new `<item>` at the top of the `<channel>` for the new version
- Keep the previous item as a fallback (do not remove it)

The new item format:
```xml
<item>
  <title><CoreName> <NewVersion></title>
  <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
  <enclosure
    url="https://github.com/nickybmon/OpenEmu-Silicon/releases/download/<NEXT_TAG>/<CoreName>.oecoreplugin.zip"
    sparkle:version="<NewVersion>"
    sparkle:shortVersionString="<NewVersion>"
    length="<BYTE_COUNT_FROM_STEP_7>"
    type="application/octet-stream" />
</item>
```

Verify the XML is valid:
```bash
xmllint --noout Appcasts/<corename>.xml && echo "Valid XML"
```

## Step 11 — Commit, push, and open a PR

```bash
git add <CoreName>/Info.plist Appcasts/<corename-lowercase>.xml
git commit -m "chore: bump <CoreName> to <NewVersion>, update appcast for <NEXT_TAG>

<One sentence describing the fix being shipped.>

Related to #<issue-number>
Assisted by Claude (Sonnet 4.6)"

git push -u origin chore/<corename-lowercase>-<version>-release
```

Open a PR targeting `main`. The PR description must include:
- What fix is being shipped and why
- The new version and release tag
- How to verify the update is offered in-app (check Preferences → Cores)
- A QA checklist covering: update offered, update installs, the specific fix works, previous behavior no longer occurs

## Step 12 — Post a user-facing issue comment (if fixing a user-reported bug)

If the fix resolves a GitHub issue reported by someone other than `nickybmon`, post a comment on that issue **after the PR is merged**. Draft the comment and show it to the owner before posting — issue comments appear in the owner's voice.

The comment should:
- Be written in plain English, no jargon
- Briefly explain what the bug was and why it happened
- Confirm it's fixed and how to get the fix (open OpenEmu → the update will be offered automatically)
- Thank the reporter

Do not post this comment until the PR is merged and the appcast is live on `main`.

## Step 13 — After PR is merged: verify the update pipeline is live

Once the PR merges:
```bash
# Confirm the appcast on main has the new version
curl -s https://raw.githubusercontent.com/nickybmon/OpenEmu-Silicon/main/Appcasts/<corename-lowercase>.xml | grep "sparkle:version"
```

The new version should appear at the top. If it does, the update will be offered to users on their next OpenEmu launch.

Report the final state: PR merged, appcast live, release tag, issue comment posted (or not applicable).
