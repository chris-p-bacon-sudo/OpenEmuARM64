# Scripts/archived/

These scripts were used at some point in the project's history but are no longer part of any active workflow. They are kept for reference rather than deleted — they document approaches that were tried and can serve as starting points if the task comes up again.

None of these are called by CI, by slash commands, or by AGENTS.md. Do not add references to them in new workflows without first checking whether a more current approach exists.

---

| Script | What it did | Why archived |
|---|---|---|
| `apply_icon.sh` | Copied the app icon PNG to the asset catalog (hardcoded paths) | One-shot used during the ARM64 port era; icon is in place |
| `generate_icon.swift` | Generated an app icon set from a source PNG using AppKit | One-shot icon generation; done once during the fork setup |
| `process_icon.swift` | Post-processed the generated icon (padding, background) | Same pipeline as `generate_icon.swift`; done once |
| `make_dark_icons.py` | Created dark-background variants of the system plugin icons | One-shot UI theming task; icons are in place |
| `fix_narrowing_v2.py` | Patched C++ implicit narrowing warnings in Nestopia for clang on ARM64 | One-shot ARM64 port migration; all narrowing warnings are fixed |
| `fast_relink.sh` | Re-linked binaries with updated dylib paths (hardcoded paths, `install_name_tool`) | Explicit comment in the script: "for historical reference only"; superseded by Xcode build system |
| `clone-cores.sh` | Interactive menu to clone an emulator core repo from its canonical GitHub location | Predates the flattened-monorepo approach; cores are now flat directories in the main repo |
| `build-and-bundle-cores.sh` | Batch-built, signed, and zipped all core plugins for a release | Predates GitHub Actions; superseded by `release-core.yml` and `release-cores-batch.sh` |
| `release-cores-batch.sh` | One-time batch script used for the cores-v1.2.0 release | Single-use batch; per-core releases now use `/release-core <Name> <Ver>` |
| `add_cloud_pref.rb` | Added the iCloud sync preference toggle to the Xcode project file | One-shot project setup during the cloud sync feature integration |
| `add_files.rb` | Added files to the Xcode project via the Xcodeproj Ruby gem | General-purpose project file mutation tool; no longer needed for routine work |
| `OpenEmuWiper.applescript` | Cleaned OpenEmu preferences, caches, and core data stores via macOS automation | Manual reset utility; useful for QA but not part of any automated workflow |
