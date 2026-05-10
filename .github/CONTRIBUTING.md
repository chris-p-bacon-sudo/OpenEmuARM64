# Contributing to OpenEmu-Silicon

Issues, PRs, and testing feedback are all welcome.

## Reporting bugs

Use the **Bug report** issue template. Include:
- Your Mac model and chip (e.g. M2 MacBook Pro)
- macOS version
- Which system and game you were running
- What happened vs. what you expected

## Contributing code

1. Check open issues for good starting points
2. Branch from `main`: `git checkout main && git checkout -b fix/your-description`
3. Make your change — keep it focused on one issue
4. Build before committing: `xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmu -configuration Debug -destination 'platform=macOS,arch=arm64' build`
5. Open a PR against `main` with a clear description of what it fixes — reference the issue with `Fixes #N`

See `AGENTS.md` for the full workflow and coding rules.

## Working on the libretro bridge

The libretro bridge is a way to load some emulator cores from pre-built libretro binaries instead of building them from source. See [The Libretro Bridge](https://github.com/nickybmon/OpenEmu-Silicon/wiki/The-Libretro-Bridge) on the wiki for what it is and why this fork uses it.

Bridge work is tracked on the [project board](https://github.com/users/nickybmon/projects/5) using the `Phase` field. Open issues with a `Phase` value are good places to pick up work.

A few specifics:

- **Branch from `feat/libretro-bridge` while it exists** (not `main`) — that branch carries the SDK changes the translator depends on. After it merges to `main`, branch from `main` like everything else.
- **PRs against the bridge branch should target `feat/libretro-bridge`**, not `main`, until the integration branch is gone.
- **Coordinate before touching `OpenEmu-SDK/OpenEmuBase/OEGameCore.h/.m`** — that file is the base class for every core in the project and is the highest-conflict file in the repo. Open an issue or comment on an existing PR before changing it.

The standard build command above is the gate for any bridge PR — if `xcodebuild` doesn't pass, the PR isn't ready.
