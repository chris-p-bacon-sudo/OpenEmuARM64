# Plan: `openemu-ai` Setup & Evaluation

This file tracks the detailed steps for the `openemu-ai` branch setup, validation, and documentation updates.

## Tasks

### Phase 1: Environment Audit & Setup
- [x] Run initial Xcode build check to check for missing toolchains.
- [x] Run `xcodebuild -downloadComponent MetalToolchain` to resolve shader compilation requirements.
- [x] Initialize local gitignored credentials by copying template files:
  - [ScreenScraperDevCredentials.swift](file:///Users/kike/Documents/OpenEmu-Silicon/OpenEmu/ScreenScraperDevCredentials.swift)
  - [OEGoogleDriveSecrets.swift](file:///Users/kike/Documents/OpenEmu-Silicon/OpenEmu/OEGoogleDriveSecrets.swift)
- [x] Run build verification to confirm `** BUILD SUCCEEDED **`.

### Phase 2: Documentation Alignment
- [x] Evaluate [AGENTS.md](file:///Users/kike/Documents/OpenEmu-Silicon/AGENTS.md) against active toolchain versions (Xcode 26.5, Swift 6.3.2).
- [x] Update [AGENTS.md](file:///Users/kike/Documents/OpenEmu-Silicon/AGENTS.md) with:
  - Correct compiler and IDE versions.
  - Added MAME core to the supported systems table.
  - Correct repository folder names for Supervision (`Potator-Core`) and Game Gear/Sega (`GenesisPlus`).
  - Pre-requisite step details for copying template credential files.
  - Generalized rules to avoid committing secrets/credentials.

### Phase 3: Planning Framework Setup
- [x] Design in-repo planning structure (root [PLAN.md](file:///Users/kike/Documents/OpenEmu-Silicon/PLAN.md) + `planning/` directory).
- [x] Create [PLAN.md](file:///Users/kike/Documents/OpenEmu-Silicon/PLAN.md) at the root.
- [x] Create this file ([planning/openemu-ai-setup.md](file:///Users/kike/Documents/OpenEmu-Silicon/planning/openemu-ai-setup.md)) to document current branch achievements.
- [x] Verify the complete repository with `./Scripts/verify.sh`.
