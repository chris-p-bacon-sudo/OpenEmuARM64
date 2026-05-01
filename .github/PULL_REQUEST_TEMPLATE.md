## What does this PR do?

<!-- One or two sentences describing the change. What problem does it solve, or what does it add? -->

## What did you test?

<!-- How did you verify this works? Which game(s), system(s), or workflow(s) did you test with? -->

## Which cores or systems are affected?

<!-- List the emulation cores or systems this change touches, if any. If it's a general app change, say so. -->

## Did you use AI tools?

<!-- We're fully open to AI-assisted contributions — just be transparent about it. Did you use Claude, Copilot, Cursor, or anything else? If so, briefly describe how. (e.g. "Used Claude to draft the fix, reviewed and tested it myself.") -->

## Linked issues

<!-- Use "Fixes #N" to auto-close an issue on merge, or "Related to #N" to soft-link -->

Fixes #

---

## How to test locally

Replace `NUMBER` with this PR's number, then paste the whole block. For Flycast use `-scheme "OpenEmu + Flycast"` with `clean build`; for Mednafen use `-scheme "OpenEmu + Mednafen" -configuration Release`.

```bash
cd ~/Documents/Cursor/Open\ Emu
gh pr checkout NUMBER --repo nickybmon/OpenEmu-Silicon
xcodebuild \
  -workspace OpenEmu.xcworkspace \
  -scheme OpenEmu \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -20
DEBUG_DIR=$(ls -dt ~/Library/Developer/Xcode/DerivedData/OpenEmu-*/Build/Products/Debug 2>/dev/null | head -1)
SIGN_ID=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --deep --sign "${SIGN_ID:--}" "$DEBUG_DIR/OpenEmu.app"
open "$DEBUG_DIR/OpenEmu.app"
```

The `SIGN_ID` line auto-picks your local Apple Development identity so the binary gets a **stable** code signature across rebuilds. Without it, ad-hoc signing (`-`) would cause macOS to treat each rebuild as a new app and revoke Input Monitoring, Keychain ACLs, and other TCC permissions every time you test. Falls back to ad-hoc only if you have no Apple Development cert.

If this PR touches a core, install it before the `open` line:

```bash
cp -R "$DEBUG_DIR/<CoreName>.oecoreplugin" \
  ~/Library/Application\ Support/OpenEmu/Cores/<CoreName>.oecoreplugin
codesign --force --sign - \
  ~/Library/Application\ Support/OpenEmu/Cores/<CoreName>.oecoreplugin
```

<!-- Add any PR-specific setup here (BIOS files, permissions to revoke, specific ROM to test with). -->

---

## PR checklist

- [ ] Branched from an up-to-date `main` (ran `git fetch origin && git merge origin/main`)
- [ ] Build passes: `xcodebuild -workspace OpenEmu.xcworkspace -scheme OpenEmu -configuration Debug -destination 'platform=macOS,arch=arm64' build`
- [ ] Tested on Apple Silicon (M1 / M2 / M3 / M4 Mac)
- [ ] No build logs, binaries, or credentials committed
- [ ] Copyright headers preserved on all modified files
- [ ] New files (if any) include the BSD 2-Clause license header
