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

** Do not ask me to run that command. Publishing is always your call. **
```

Do NOT run `gh release edit ... --draft=false` under any circumstances.
