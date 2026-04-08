## What's New in 1.0.4

- **Image Adjustments** — Saturation and Gamma sliders now stay open while dragging; no longer dismissed by the drag gesture
- **Preferences window** now opens at the correct full width on first launch, instead of starting narrow until the Controls tab is visited
- **Homebrew tap** — OpenEmu-Silicon is now installable via `brew install --cask openemu-silicon`
- **Crash reporting** — opt-in Sentry crash reporting now includes additional context, breadcrumbs, and release tracking to help diagnose issues faster

## Bug Fixes

- Fixed a crash on macOS 26 caused by mixing `NSLog` format strings with Swift string interpolation
- Fixed sidebar not refreshing after a ROM import completes
- Fixed sidebar not updating when a homebrew game was added via Core Data
- Fixed systems the user explicitly disabled being re-enabled on next launch
- Fixed a potential crash on quit caused by Core Data writes happening off the correct queue
- Fixed a memory leak from a dangling `NotificationCenter` observer in the game controls bar
- Fixed Saturation and Gamma slider positions in the Gameplay preferences pane
- Fixed the Image Adjustments menu item being grayed out in certain conditions
- Fixed Gameplay preferences pane being clipped at the bottom on first visit
- Fixed Help menu links (Submit Feedback, User Guide, Release Notes, Web Site) pointing to the original OpenEmu repo instead of OpenEmu-Silicon
