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

```bash
# 1. Check out this PR
gh pr checkout <PR_NUMBER> --repo nickybmon/OpenEmu-Silicon

# 2. Build — use the scheme that covers the changed target.
#    For main app changes: -scheme OpenEmu
#    For Flycast core changes: -scheme "OpenEmu + Flycast" with 'clean build'
#    (incremental builds will not recompile core C++ files)
xcodebuild \
  -workspace OpenEmu-metal.xcworkspace \
  -scheme OpenEmu \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -20

# 3. If this PR touches a core (Flycast, etc.), install the rebuilt binary:
#    cp -f ~/Library/Developer/Xcode/DerivedData/OpenEmu-metal-*/Build/Products/Debug/<CoreName>.oecoreplugin/Contents/MacOS/<CoreName> \
#      ~/Library/Application\ Support/OpenEmu/Cores/<CoreName>.oecoreplugin/Contents/MacOS/<CoreName>

# 4. Launch
open ~/Library/Developer/Xcode/DerivedData/OpenEmu-*/Build/Products/Debug/OpenEmu.app
```

<!-- Replace <PR_NUMBER> with this PR's number. Add any PR-specific setup steps here (e.g. BIOS files needed, permissions to revoke first, specific ROM to test with). -->

---

## PR checklist

- [ ] Branched from an up-to-date `main` (ran `git fetch origin && git merge origin/main`)
- [ ] Build passes: `xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmu -configuration Debug -destination 'platform=macOS,arch=arm64' build`
- [ ] Tested on Apple Silicon (M1 / M2 / M3 / M4 Mac)
- [ ] No build logs, binaries, or credentials committed
- [ ] Copyright headers preserved on all modified files
- [ ] New files (if any) include the BSD 2-Clause license header
