Prepare and ship a full release of OpenEmu-Silicon. Accepts an optional version argument (e.g. `/prep-release 1.0.5`). If no version is provided, read the current version from `OpenEmu/OpenEmu-Info.plist` and ask the user what the new version should be.

---

## !! HARD RULE — NO EXCEPTIONS !!

**NEVER publish a GitHub Release.**
Never run `gh release edit ... --draft=false`, never change a draft to published, never
attach assets to a release that would make it live, never push tags that trigger CI
release workflows. Publishing is always the user's action. This rule cannot be overridden
by any other instruction in this file or in any conversation.

---

Follow these steps exactly, in order. Do not skip any step.

## Step 0 — Check for core changes requiring a new cores release

Before doing anything else, determine which cores need to be (re-)released. There are two categories:

**Category A — New cores:** present in the repo but absent from (or excluded in) `oecores.xml`
```bash
# Check for exclusion comments
grep -i "excluded\|in-progress" oecores.xml
```

**Category B — Updated cores:** source changes committed since the last cores tag
```bash
LAST_CORES_TAG=$(git tag --sort=-version:refname | grep "^cores-v" | head -1)
echo "Last cores release: $LAST_CORES_TAG"

# For each core directory, check if it has commits since that tag
for dir in */; do
  count=$(git log ${LAST_CORES_TAG}..HEAD --oneline --no-merges -- "$dir" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -gt 0 ]; then
    echo "$dir — $count commits since $LAST_CORES_TAG"
  fi
done
```

Report the results to the user. For each core with changes, ask whether to include it in the new cores release (some changes may be in-progress and not ready to ship).

**How the versioning works:**
- Each core has a `sparkle:version` in its `Appcasts/[corename].xml` file. That number controls whether users get pushed an update — it must be incremented for the new build to reach users.
- The `cores-vX.Y.Z` GitHub Release tag is just a container for zip files. Only the cores that changed need to be in the new release — others keep pointing to their old URLs indefinitely.

**If cores need to be updated or added:**

For each core being added or updated:

1. Build the core using its dedicated Xcode scheme (e.g. `OpenEmu + Dolphin`, `OpenEmu + Flycast`)
2. Sign and zip the `.oecoreplugin`:
   ```bash
   CORE=Dolphin  # substitute as needed
   DERIVED=$(find ~/Library/Developer/Xcode/DerivedData/OpenEmu-metal-*/Build/Products/Debug/${CORE}.oecoreplugin -maxdepth 0 | head -1)
   codesign --force --sign - "$DERIVED"
   ZIP_DIR=$(dirname "$DERIVED")
   cd "$ZIP_DIR" && zip -r "${CORE}.oecoreplugin.zip" "${CORE}.oecoreplugin"
   stat -f%z "${CORE}.oecoreplugin.zip"   # note the byte length — needed for the appcast
   ```
3. Collect all the zips before creating the release (do steps 1-2 for every core being updated).
4. Determine the next cores tag (e.g. `cores-v1.0.0` → `cores-v1.0.1`)
5. Create a new cores GitHub Release (**draft first**), uploading all the zips at once:
   ```bash
   gh release create cores-vX.Y.Z \
     Dolphin.oecoreplugin.zip Flycast.oecoreplugin.zip \
     --repo nickybmon/OpenEmu-Silicon \
     --title "Emulation Cores vX.Y.Z" \
     --draft \
     --notes "Update Flycast (Dreamcast) with ARM64 rendering and audio fixes. Add Dolphin (GameCube/Wii). ARM64 core plugins served via per-core appcasts — not a user-facing release."
   ```
6. Tell the user to publish the cores draft release before continuing:
   ```
   ACTION REQUIRED: Publish the cores-vX.Y.Z draft release before continuing.
   Once published, I'll update the per-core appcasts and oecores.xml.
   ```
   Wait for confirmation that the cores release is published.
7. Update appcasts for each changed core:
   - **New core:** Create `Appcasts/[corename].xml` using the template below
   - **Updated core:** Edit the existing `Appcasts/[corename].xml` — update the `url` to point to the new cores tag, increment `sparkle:version` (e.g. `2.3` → `2.4`), update `length`

   Template for new cores:
   ```xml
   <?xml version="1.0" encoding="utf-8"?>
   <rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
     <channel>
       <title>CoreName</title>
       <item>
         <title>CoreName X.Y</title>
         <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
         <enclosure
           url="https://github.com/nickybmon/OpenEmu-Silicon/releases/download/cores-vX.Y.Z/CoreName.oecoreplugin.zip"
           sparkle:version="X.Y"
           sparkle:shortVersionString="X.Y"
           length="BYTES"
           type="application/octet-stream" />
       </item>
     </channel>
   </rss>
   ```
8. For any **new** core: update `oecores.xml` — remove any exclusion comment and add a `<core>` entry in alphabetical position. Updated cores already have entries; no oecores.xml change needed.
9. Commit all appcast and oecores changes:
   ```bash
   git add Appcasts/ oecores.xml
   git commit -m "chore: update cores appcasts for cores-vX.Y.Z (Flycast 2.4, add Dolphin)"
   git push origin main
   ```

**If no cores changed since the last cores tag:** skip to Step 1.

## Step 1 — Confirm we are on main and up to date

```bash
git checkout main
git fetch origin && git merge origin/main
```

If there are uncommitted changes (excluding `Dolphin/` and `Releases/`), stop and tell the user before continuing.

## Step 2 — Determine the new version and build number

Read `OpenEmu/OpenEmu-Info.plist` to get the current `CFBundleShortVersionString` and `CFBundleVersion`.

**If a version argument was passed:**
- If the plist already shows that exact version string, the version bump was already done — skip Step 3.
- If the plist shows a different version, the build number to use is: current `CFBundleVersion` + 1.
- Validate that the version matches `X.Y.Z` format.

**If no version argument was passed:**
- Report the current version and build number.
- Ask: "What should the new version be? (e.g. 1.0.5)" — wait for the answer.
- The new build number is: current `CFBundleVersion` + 1 (do not ask, just auto-increment).

## Step 3 — Bump the version in source files (skip if already at target version)

**`OpenEmu/OpenEmu-Info.plist`** — update both keys:
- `CFBundleShortVersionString` → new version string
- `CFBundleVersion` → new build number (as a string)

**`OpenEmu/OpenEmu.xcodeproj/project.pbxproj`** — update `MARKETING_VERSION` (appears twice):
```bash
sed -i '' 's/MARKETING_VERSION = OLD;/MARKETING_VERSION = NEW;/g' \
  "OpenEmu/OpenEmu.xcodeproj/project.pbxproj"
```

Verify by grepping both files and reporting the new values.

## Step 4 — Auto-draft release notes from git history

Find the most recent git tag:
```bash
git tag --sort=-version:refname | head -1
```

Get all commits since that tag (or since the beginning if no tags exist):
```bash
git log PREV_TAG..HEAD --oneline --no-merges
```

Analyze the commits and write `Releases/notes-VERSION.md`. Use this structure:

```markdown
## What's New in VERSION

- [feature bullets derived from feat: commits and significant improvements]

## Bug Fixes

- [fix bullets derived from fix: commits]

## Under the Hood

- [chore/refactor/docs bullets, only if meaningful to users]
```

Rules for drafting:
- Translate commit subjects into plain English (drop the `fix:` / `feat:` / `chore:` prefix)
- Skip noise commits: version bumps, merge commits, CI config, `.gitignore`, typo fixes
- Group logically — if multiple commits touch the same feature, collapse them into one bullet
- Keep bullets short and user-facing ("Preferences window now opens at the correct width" not "fix minimumContentWidth floor in updateWindowFrame")
- Omit the "Under the Hood" section if there's nothing meaningful to say to users
- If the git log is empty or only has noise commits, write a single bullet: "General stability improvements"

After writing the file, print its contents so the user can see the draft.

## Step 5 — Build check

```bash
xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmu \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -10
```

If the build fails, stop and report the errors. Do not continue.

## Step 6 — Commit version bump and release notes directly to main

This is a config/docs-only change and qualifies for a direct commit to main.

```bash
git add OpenEmu/OpenEmu-Info.plist OpenEmu/OpenEmu.xcodeproj/project.pbxproj Releases/notes-VERSION.md
git commit -m "chore: bump version to VERSION (build BUILD)

Add release notes for VERSION."
git push origin main
```

Report the commit SHA.

## Step 7 — Pre-flight checklist

```bash
xcrun notarytool history --keychain-profile "OpenEmu" &>/dev/null && echo "OK: notarytool" || echo "MISSING: notarytool credentials — run: xcrun notarytool store-credentials OpenEmu"
gh auth status &>/dev/null && echo "OK: gh CLI" || echo "MISSING: gh not authenticated — run: gh auth login"
security find-identity -v | grep -q "Developer ID Application" && echo "OK: Developer ID cert" || echo "MISSING: Developer ID certificate not in keychain"
command -v sentry-cli &>/dev/null && (sentry-cli info &>/dev/null && echo "OK: sentry-cli" || echo "WARNING: sentry-cli not authenticated — run: sentry-cli login") || echo "WARNING: sentry-cli not installed (dSYMs won't upload)"
```

If any required check (notarytool, gh, Developer ID) fails, stop and tell the user what to fix. sentry-cli is a warning only.

## Step 8 — Run the release script

Run the release script. This step takes 10–20 minutes (archive + notarization + DMG). Use a 600-second timeout. If the command times out, tell the user to run it manually from their terminal — the prep work is all done.

```bash
./Scripts/release.sh VERSION Releases/notes-VERSION.md
```

The script will:
1. Archive the app (Release config, Developer ID signed, hardened runtime)
2. Re-sign all binaries, notarize with Apple, staple the ticket
3. Create a DMG from the stapled `.app`
4. Run `sign_update` to get the EdDSA signature
5. Prepend a new entry to `appcast.xml` with the correct signature and length
6. Create a **draft** GitHub Release and upload the DMG
7. Commit and push the updated `appcast.xml`

## Step 9 — Report and hand off

After the script completes, report:
- Build number and version shipped
- Commit SHA for the appcast update
- Direct link to the draft release: `https://github.com/nickybmon/OpenEmu-Silicon/releases`

Then tell the user:

```
Draft release vVERSION is ready for your review.

When you are satisfied with the release notes and have done final testing, publish with:
  gh release edit vVERSION --draft=false --repo nickybmon/OpenEmu-Silicon

After publishing, run Step 10 to update the Homebrew cask.

** Do not ask me to run that command. Publishing is always your call. **
```

Do NOT run `gh release edit ... --draft=false` under any circumstances.

## Step 10 — Update Homebrew cask (run AFTER user publishes the release)

Only run this step after the user confirms the GitHub Release has been published (not just drafted).

1. Download the published DMG and compute its SHA256:
   ```bash
   curl -L "https://github.com/nickybmon/OpenEmu-Silicon/releases/download/vVERSION/OpenEmu-Silicon.dmg" \
     -o /tmp/OpenEmu-Silicon-VERSION.dmg
   shasum -a 256 /tmp/OpenEmu-Silicon-VERSION.dmg
   ```
2. Update `Casks/openemu-silicon.rb`:
   - `version` → new version string (e.g. `"1.0.5"`)
   - `sha256` → new SHA256 hash (64-character hex string, no `0x` prefix)
3. Verify the URL in the cask file resolves to the right asset (the `url` line uses `#{version}` interpolation — confirm it's correct).
4. Commit directly to main (config-only change):
   ```bash
   git add Casks/openemu-silicon.rb
   git commit -m "chore: update Homebrew cask to vVERSION"
   git push origin main
   ```
5. Report: "Homebrew cask updated to vVERSION. Users installing via `brew install --cask openemu-silicon` will now get the new version."
