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
