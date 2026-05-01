## Summary

<!-- One to three bullets: what does this PR fix or add? -->

-

## What changed

<!-- Per-file or per-component breakdown. Explain the why, not just the what. -->

## How to test locally

```bash
# 1. Check out this PR
gh pr checkout <N> --repo nickybmon/OpenEmu-Silicon

# 2. Build — replace scheme with the one that covers your change:
#    App-only change:   -scheme OpenEmu
#    Flycast core:      -scheme "OpenEmu + Flycast"   (add `clean` — C++ won't recompile incrementally)
#    Mednafen core:     -scheme "OpenEmu + Mednafen"  -configuration Release  (Debug is blocked at compile time)
#    Other core:        -scheme "OpenEmu + <CoreName>"
xcodebuild \
  -workspace OpenEmu-metal.xcworkspace \
  -scheme OpenEmu \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -20

# 3. If a core changed, install it (DerivedData is shadowed by the installed plugin):
#    cp -R ~/Library/Developer/Xcode/DerivedData/OpenEmu-metal-*/Build/Products/Debug/<Name>.oecoreplugin \
#          ~/Library/Application\ Support/OpenEmu/Cores/<Name>.oecoreplugin
#    codesign --force --sign - ~/Library/Application\ Support/OpenEmu/Cores/<Name>.oecoreplugin

# 4. Launch
open ~/Library/Developer/Xcode/DerivedData/OpenEmu-metal-*/Build/Products/Debug/OpenEmu.app
```

<!-- Add any PR-specific setup here (BIOS files, permissions to revoke first, specific ROM needed, etc.) -->

## QA Spec

- [ ] Build succeeds with no new errors or warnings
- [ ] <!-- primary test case -->
- [ ] No regression in <!-- related area -->

## Linked issues

Fixes #
