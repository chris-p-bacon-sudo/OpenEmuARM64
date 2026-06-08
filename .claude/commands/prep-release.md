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

**`.github/SECURITY.md`** — update the supported versions table so the new version is listed as supported and the old "latest" row is replaced:
```bash
sed -i '' "s/| [0-9][0-9.]* (latest) | ✅ |/| NEW_VERSION (latest) | ✅ |/" .github/SECURITY.md
sed -i '' "s/| < [0-9][0-9.]* | ❌ |/| < NEW_VERSION | ❌ |/" .github/SECURITY.md
```

Verify by grepping all three files and reporting the new values.

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

**Contributor credits:** For each commit that references a PR number, look up that PR's body for `Fixes #N` / `Related to #N` patterns, then look up those issues to find the original reporter. If the reporter is not `nickybmon`, append `(thanks @username, #N)` to the bullet. If the fix came from Sentry telemetry (no user-filed issue), omit the credit — there's no one to thank. Use `gh issue view N --repo nickybmon/OpenEmu-Silicon --json author` to get the reporter.

After writing the file, print its contents so the user can see the draft.

## Step 4.5 — Check for unreleased core updates

Before building, check whether any in-repo cores have source changes that haven't been released yet. This catches cores that need a `/release-core` run before or alongside this app release.

Find the most recent cores release tag and compare each core's source directory against it:

```bash
LAST_CORES_TAG=$(git tag --sort=-version:refname | grep '^cores-' | head -1)
echo "Last cores tag: $LAST_CORES_TAG"

for dir in 4DO Dolphin DeSmuME Flycast GenesisPlus mGBA Mednafen Nestopia PPSSPP Snes9x mupen64plus; do
  [ -d "$dir" ] || continue
  changes=$(git log "${LAST_CORES_TAG}..HEAD" --oneline --no-merges -- "$dir/" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$changes" -gt 0 ]; then
    ver=$(plutil -p "$dir/Info.plist" 2>/dev/null | grep CFBundleVersion | awk -F'"' '{print $4}')
    appcast_name=$(echo "$dir" | tr '[:upper:]' '[:lower:]')
    live_ver=$(grep -m1 'sparkle:version=' "Appcasts/${appcast_name}.xml" 2>/dev/null | grep -o '"[^"]*"' | tr -d '"')
    if [ "$ver" = "$live_ver" ]; then
      echo "NEEDS RELEASE: $dir — $changes commit(s) since $LAST_CORES_TAG, plist=$ver, appcast=$live_ver (version not yet bumped)"
    else
      echo "NEEDS RELEASE: $dir — $changes commit(s) since $LAST_CORES_TAG, plist=$ver, appcast=$live_ver"
    fi
  fi
done
```

If any cores show up as needing a release, report them to the user and ask whether to proceed with the app release now and handle the cores separately, or pause here. Do not block the app release — cores and app releases are independent — but make sure the user is aware.

Also remind the user: if any of the currently-deployed cores haven't had a `package-core.sh` run since they were last released, their dSYMs may not be in Sentry. To backfill: `./Scripts/upload-core-dsyms.sh` (builds all cores in Release and uploads their dSYMs). Only worth doing if you suspect a gap — routine releases via `/release-core` handle this automatically.

## Step 5 — Build check

Use Release config — Debug config has a pre-existing codesign issue with the test target.

```bash
xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmu \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -5
```

If the build fails, stop and report the errors. Do not continue.

Do NOT commit the version bump yet. The version bump files (plist, pbxproj, SECURITY.md, notes) stay as working-tree changes and are picked up by the release script's final commit in Step 7.

## Step 6 — Pre-flight checklist

```bash
xcrun notarytool history --keychain-profile "OpenEmu" &>/dev/null && echo "OK: notarytool" || echo "MISSING: notarytool credentials — run: xcrun notarytool store-credentials OpenEmu"
gh auth status &>/dev/null && echo "OK: gh CLI" || echo "MISSING: gh not authenticated — run: gh auth login"
security find-identity -v | grep -q "Developer ID Application" && echo "OK: Developer ID cert" || echo "MISSING: Developer ID certificate not in keychain"
command -v sentry-cli &>/dev/null && (sentry-cli info &>/dev/null && echo "OK: sentry-cli" || echo "WARNING: sentry-cli not authenticated — run: sentry-cli login") || echo "WARNING: sentry-cli not installed (dSYMs won't upload)"
```

If any required check (notarytool, gh, Developer ID) fails, stop and tell the user what to fix. sentry-cli is a warning only.

## Step 7 — Run the release script

Run the release script. This step takes 10–20 minutes (archive + notarization + DMG). Use a 600-second timeout. If the command times out, tell the user to run it manually from their terminal — the prep work is all done.

```bash
./Scripts/release.sh VERSION Releases/notes-VERSION.md
```

The script will:
1. Archive the app (Release config, Developer ID signed, hardened runtime)
2. Re-sign all binaries, notarize with Apple, staple the ticket
3. Create a DMG from the stapled `.app`
4. Update `Casks/openemu-silicon.rb` with the new version and DMG SHA256
5. Run `sign_update` to get the EdDSA signature
6. Prepend a new entry to `appcast.xml` with the correct signature and length
7. Commit to a `chore/release-vVERSION` branch and open a **draft PR** targeting main
8. Push the version tag so the GitHub Release download URL is valid immediately
9. Create a **draft** GitHub Release and upload the DMG

The appcast does not go live until the PR is merged. CI version checks run on the PR first.

## Step 8 — Report and hand off

After the script completes, report:
- Build number and version shipped
- PR URL for the release branch
- Direct link to the draft release: `https://github.com/nickybmon/OpenEmu-Silicon/releases`

Then tell the user:

```
Draft release vVERSION is ready.

Next steps:
1. Let CI pass on the PR
2. Review and test the DMG
3. Merge the PR — this makes the Sparkle update live for users
4. Publish the GitHub Release:
   gh release edit vVERSION --draft=false --repo nickybmon/OpenEmu-Silicon

** Do not ask me to run that last command. Publishing is always your call. **
```

Do NOT run `gh release edit ... --draft=false` under any circumstances.
