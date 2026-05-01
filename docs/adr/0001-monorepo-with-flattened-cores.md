# ADR-0001: Monorepo with flattened emulator cores

## Status

Accepted

## Context

The original OpenEmu project used a multi-repo structure: a main app repo, separate repos per emulator core plugin under the OpenEmu GitHub organization, and a shared OpenEmu-SDK repo. Each core had its own maintainers and release cadence. Submodules linked everything together.

This fork (OpenEmu-Silicon) began as a solo effort to port everything to Apple Silicon (arm64). The question arose: should this project maintain the same multi-repo structure, or consolidate into a single repo?

Factors considered:
- **Team size.** This project has one primary maintainer. Multi-repo coordination overhead (cross-repo PRs, submodule sync, per-repo CI setup) scales with team size; it does not provide value with a single maintainer.
- **Core maintenance model.** The emulator cores in this fork are mostly frozen upstream forks. The work is ARM64 compatibility fixes and macOS version updates, not active feature development on the cores themselves. There is no reason for a core to have independent contributors or a separate issue tracker.
- **Git submodules.** Active submodule tracking requires discipline to keep in sync and creates confusion when contributors forget to `git submodule update`. For frozen-ish cores, the friction outweighs the benefits.
- **Independent core releases.** A meaningful benefit of the original structure was being able to ship a core update without a full app release. This benefit is preserved in the current setup via `cores-v*` tags, per-core appcast files under `Appcasts/`, and the `CoreUpdater` mechanism — without requiring separate repos.

## Decision

All emulator cores, the main app, OpenEmu-SDK, OpenEmuKit, and OpenEmu-Shaders live in a single repository (`nickybmon/OpenEmu-Silicon`). Cores are regular tracked directories — not active git submodules. They can receive fixes via normal PRs.

Independent core releases are handled at the release layer: `gh workflow run release-core.yml` builds and ships a single core plugin independently, updating its `Appcasts/<CoreName>.xml`. The `CoreUpdater` mechanism delivers these to users without requiring a full app update.

## Consequences

**Easier:**
- All work happens in one place — no cross-repo coordination
- CI/CD is simpler (one workflow file set manages everything)
- Issues and PRs have a single tracker and a single history
- Onboarding a contributor means cloning one repo

**Harder:**
- Pulling upstream fixes from an original core's repo requires a manual cherry-pick or merge, not `git submodule update`
- If a core ever becomes actively maintained upstream with frequent commits, the flat structure makes tracking that harder

**Risk accepted:**
If a core in this repo diverges significantly from its upstream, re-merging upstream changes could be complex. This is accepted given the current maintenance model (ARM64/macOS compatibility fixes, not upstream feature tracking).
