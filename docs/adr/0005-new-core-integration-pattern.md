# ADR-0005: New core integration follows the flat vendored source pattern

## Status

Accepted

## Context

In early 2026 we began work to add Mupen64Plus-Next as a second N64 emulator core — a higher-accuracy alternative to the existing Mupen64Plus plugin. This created the first real test of *how* to add a new emulator core to OpenEmu-Silicon from scratch. We tried three approaches over several months before landing on the correct one.

### Approach 1 — Libretro bridge (issue #464, PR #478, branch `fix/libretro-gl-shared-context`)

**What we tried:** Run `mupen64plus-libretro-nx` (the libretro/RetroArch port of Mupen64Plus-Next) through the existing `OELibretroCoreTranslator` bridge that already loads libretro `.dylib` cores. The appeal was that no new Xcode project was needed — just plug in the core's shared library like RetroArch does.

**What we built:** End-to-end GL hardware-render infrastructure: shared CGL context, staging-texture FBO blit pattern, `OERenderDelegate` protocol additions, `bind_hw_render` callback handling, symbol-interception hooks (including vendored Facebook fishhook). The bridge itself was proven working — a forced red-frame probe produced a visible red flash on screen, confirming the full pipeline from GL draw → IOSurface → Metal compositor.

**Where it stopped:** GLideN64 (the video plugin inside mupen64plus-libretro-nx) never rendered into our FBO. Disassembly of the compiled `.dylib` revealed that `_bindFBO` — the internal function GLideN64 routes all `glBindFramebuffer` calls through — skips the bind when its internal draw-state cache says the FBO is already current. Our setup seeded that cache to the right value at `glsm_state_setup` time, but GLideN64's own internal rendering passes left a different FBO current afterward. The restore-to-output step never fired. VI register reads returned blank state. Every frame went black.

The root cause was fully diagnosed (see issue #464 comments). The fix path was known (seed the draw-state differently or implement the `bind_hw_render` callback that RetroArch uses to reset per-frame state). The branch was kept open as `WIP` because fixing it required reading RetroArch's `gl3.c` driver carefully and making a targeted change — work that was deferred.

**Key learning:** The libretro bridge is architecturally sound for GL cores. The specific blocker is a GLSM draw-state seeding issue that affects GLideN64 only. This is solvable but the libretro path is fundamentally more complex than the native approach because the core's internal rendering is designed to run under RetroArch's driver model, not OpenEmu's.

---

### Approach 2 — mupen64plus-libretro-nx as a git submodule (branch `feat/mupen64plus-next-direct`, early state)

**What we tried:** Pull the `mupen64plus-libretro-nx` source repository in as a git submodule inside `Mupen64Plus-Next/`, then build it as a native Xcode target using OpenEmu's ObjC bridge layer — similar to the flat-source pattern but pulling from the libretro repo rather than copying from the existing Mupen64Plus core.

**Where it stopped immediately:** The `mupen64plus-libretro-nx` source is written against the libretro API surface. Its build system, internal includes, and the way it exposes entry points (`retro_init`, `retro_run`, etc.) are all structured for the libretro runtime, not for direct Xcode compilation. Extracting the N64 emulation logic from its libretro harness would require either porting the GLSM layer (the same problem as Approach 1) or substantial source surgery. This approach was abandoned after reading the source structure. The submodule was removed from the branch.

**Key learning:** A libretro-format source repo cannot be dropped into an Xcode project and compiled as a native plugin without significant adaptation. Source origin (libretro vs. upstream mupen64plus) matters.

---

### Approach 3 — Flat vendored source, Xcode project derived from the working core (current, accepted)

**What we tried:** Mirror exactly the pattern that every other core in this repo uses — the same pattern the original OpenEmu contributors established for the original Mupen64Plus core and every other plugin in the codebase.

The pattern:
1. All source committed flat as regular files in the core directory. No git submodules. No external dependencies at build time.
2. Source directories (`mupen64plus-core`, `GLideN64`, `mupen64plus-rsp-cxd4`, `mupen64plus-rsp-hle`, `angrylion-rdp-plus`, `png`) are copied verbatim from the existing working core.
3. The Xcode project is a copy of the working core's `project.pbxproj` with exactly five string substitutions: product name, `.oecoreplugin` filename, ObjC class `.h` / `.m` filenames, and prefix header filename.
4. A new `ObjC class pair` (`MupenNextGameCore.h` / `MupenNextGameCore.m`) with the class renamed but implementation otherwise identical to the working core.
5. A new `Info.plist` with the correct `OEGameCoreClass`, `SUFeedURL`, and `OEProjectURL`.
6. A workspace entry and scheme file pointing at the new `.xcodeproj`.

**Result:** Clean build on the first attempt. `verify.sh --core Mupen64Plus-Next` passes build, plutil, codesign, install, and hash check. OpenEmu recognises it as a separate N64 core option.

**The source is currently identical to the existing Mupen64Plus core.** The two cores are functionally equivalent at this point. The value of the new entry point is that it can be updated to newer `mupen64plus-core` / `GLideN64` sources independently, without touching the stable existing Mupen64Plus plugin. Source upgrade is a separate future step: replace files in the `mupen64plus-core/` and `GLideN64/` subdirectories, fix any compile errors from API differences, ship.

---

## Decision

New cores are added using the flat vendored source pattern (Approach 3). This is not a new policy — it is the existing policy established by the original OpenEmu contributors and documented in ADR-0001. The work here confirms that this applies to new cores added to the Silicon fork, not just the ones we inherited.

Specifically:
- Source is copied from an existing working core and committed flat.
- The Xcode project is derived from the working core's `.pbxproj` with targeted substitutions only — not rebuilt from scratch, not manually authored.
- All source paths in the `.pbxproj` are local relative paths (`mupen64plus-core`, `GLideN64`, etc.) from `$(SRCROOT)` — never `../OtherCore/` cross-references.
- The libretro bridge (`OELibretroCoreTranslator`) remains available for loading pre-compiled libretro `.dylib` cores. It is not the path for adding new natively compiled cores.

## Consequences

**Easier:**
- Adding a new core is mechanical: copy source, copy `.pbxproj`, apply five substitutions, verify build.
- Source upgrades are surgical: replace files in the relevant subdirectory, fix compile errors, done.
- No new infrastructure is needed. The build system, CI, install scripts, and release tooling all work without modification.
- The two N64 cores can be updated independently. Mupen64Plus stays stable while Mupen64Plus-Next tracks newer upstream.

**Harder:**
- New cores that don't share a source lineage with an existing core require sourcing and vendoring the source from scratch. There is no shortcut via submodules or libretro repos.
- If two cores share source, they carry duplicate copies. Disk space is cheap; this is acceptable.
- The libretro bridge black-screen issue (#464) is not resolved by this ADR. That work is independently parked — the branch and PR are preserved as a reference if we revisit GL libretro cores.

## References

- Issue #464 — full diagnostic trail for the libretro bridge + GLideN64 black screen
- PR #478 — WIP branch with the shared GL context + staging texture infrastructure (closed, not merged)
- Branch `feat/mupen64plus-next-direct` — the accepted implementation
- ADR-0001 — the monorepo / flat core pattern this extends
