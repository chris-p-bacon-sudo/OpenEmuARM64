# ADR-0002: Commit pre-built vendor frameworks alongside source

## Status

Accepted

## Context

The project depends on two third-party C libraries: **XADMaster** (archive extraction) and **UniversalDetector** (character encoding detection). These are used by the ROM importer.

The repo contains both:
- `Vendor/XADMaster/` and `Vendor/UniversalDetector/` — full source trees with Xcode projects
- `OpenEmu/XADMaster.framework/` and `OpenEmu/UniversalDetector.framework/` — pre-compiled macOS framework bundles (Mach-O arm64 + x86_64)

This was audited in May 2026: the `.framework` bundles in `OpenEmu/` are compiled outputs of the `Vendor/` source trees. The relationship is one-way (source → binary). They are not redundant copies — they serve different purposes.

## Decision

Both the source trees (`Vendor/`) and the compiled framework bundles (`OpenEmu/*.framework/`) are committed to the repository.

- **Source trees are kept** so they can be audited, rebuilt, or patched if needed without fetching from external sources.
- **Pre-built binaries are committed** so the main app can build without requiring contributors to compile the dependencies from scratch. This keeps the build self-contained.

The frameworks are treated as build inputs, not build outputs — they are checked in and not regenerated on every build.

## Consequences

**Easier:**
- `xcodebuild` builds succeed without any dependency fetch step
- Source is available for auditing or patching without fetching from GitHub
- New contributors can build immediately after cloning

**Harder:**
- When updating XADMaster or UniversalDetector to a new version, both the source tree and the compiled frameworks must be updated together
- Framework bundles are binary files — diffs are not human-readable and PRs touching them must be reviewed by building from source and comparing behavior
- Repo size is larger than if only source were tracked

**What to do on update:**
1. Update `Vendor/<LibraryName>/` source
2. Build the framework for arm64 (and x86_64 if universal is required)
3. Replace `OpenEmu/<LibraryName>.framework/` with the new build
4. Open a PR with both changes; describe what changed and why
