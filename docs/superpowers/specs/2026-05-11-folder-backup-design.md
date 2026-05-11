# Folder Backup — Design Spec
_2026-05-11_

## Problem

Users have no way to back up save states, battery saves, or BIOS files to a location they control. The existing Google Drive sync requires OAuth setup and ongoing maintenance of a Google Cloud project. Users on iCloud Drive, Dropbox, or any other service have no supported path.

## Solution

A user-selectable backup folder. The user picks any folder on their filesystem via an `NSOpenPanel`. If they choose a location inside iCloud Drive (`~/Library/Mobile Documents/`), macOS handles cloud sync transparently — no iCloud entitlements required. Works equally with Dropbox, Google Drive local folder, external disk, or any local path.

## Scope

**In:** Save states (`.oesavestate`), battery saves (`.sav`, `.srm`, `.rtc`, `.eep`, `.nv`, `.state`), BIOS files.  
**Out:** ROMs (copyright-sensitive).

## Architecture

### New file: `OEFolderBackupManager.swift`

Singleton. Owns all backup logic.

**Lifecycle**
- `start()` — called from AppDelegate alongside `OESaveSyncManager.shared.startMonitoring()`. Reads saved folder URL from UserDefaults. If configured: runs initial sync, then starts FSEventStream. If not configured: no-op.
- `stop()` — stops FSEventStream. Called on app termination.

**Outbound (local → backup)**
- FSEventStream on Save States directory + all `{core}/Battery Saves` directories + BIOS directory.
- On event: resolve to item root (promote file inside `.oesavestate` to bundle root), map to backup path, atomic write (`copyItem` to temp → `replaceItem`).
- Initial sync on first enable: walk all three source trees, copy anything where local mod date > backup mod date (or backup file doesn't exist).

**Pre-launch check**
- `checkForNewerBackup(systemIdentifier:gameName:completion:)` — scans backup folder for files matching the game, compares mod dates, calls completion on main thread with `(shouldSync: Bool, Date?)`.
- Same prompt pattern as Google Drive: "A newer save for X is available in your backup folder (from date). Restore before playing?"

**Restore**
- `restoreFromBackup(systemIdentifier:gameName:completion:)` — copies matching files from backup folder to local OpenEmu directories using atomic write.

**Public API used by the pref pane**
```swift
var backupFolderURL: URL?       // get/set, persisted to UserDefaults
var isEnabled: Bool             // true when folder configured + monitoring active
var lastBackupDate: Date?       // persisted to UserDefaults
func chooseFolder(relativeTo: NSWindow, completion: @escaping (Bool) -> Void)
```

**Path mapping**

| Local | Backup |
|---|---|
| `…/OpenEmu/Save States/{system}/{game}/{name}.oesavestate` | `{backup}/Save States/{system}/{game}/{name}.oesavestate` |
| `…/OpenEmu/{core}/Battery Saves/{file}` | `{backup}/Battery Saves/{core}/{file}` |
| `…/OpenEmu/BIOS/{file}` | `{backup}/BIOS/{file}` |

### Modified: `PrefCloudSyncController.swift`

UI replaced with folder backup UI. Google Drive code stays in the file, unreachable from UI.

**New UI elements:**
- Header: "Backup Folder"
- Description: explains iCloud Drive / any folder
- Status dot + label (Active / No folder selected)
- Folder path field (read-only, shows selected path or "None")
- "Choose Folder…" button → calls `OEFolderBackupManager.shared.chooseFolder(...)`
- "Open in Finder" button (hidden when no folder set)
- Last backed up label
- Note label explaining iCloud Drive path

**Pane size:** 468 × 300 (smaller than current 480 — folder picker UI is simpler than GDrive auth flow)

### Modified: `OEGameDocument.swift`

`performPreLaunchSyncCheckIfNeeded` updated to chain: Google Drive check → **folder backup check** → launch.

`performICloudSyncCheck` replaced with `performFolderBackupSyncCheck` using the same `[weak self]` closure pattern established in the adversarial review fixes.

### Modified: `AppDelegate.swift`

```swift
OESaveSyncManager.shared.startMonitoring()
OEFolderBackupManager.shared.start()   // new
```

### Modified: `OpenEmu.entitlements`

Remove iCloud entitlements added by the abandoned branch — not needed for folder-based approach.

### Modified: `project.pbxproj`

Add `OEFolderBackupManager.swift` to Sources build phase.

## What stays untouched

`OESaveSyncManager.swift` — Google Drive logic is preserved entirely. Nothing is deleted.

## Error handling

- Folder permissions revoked after selection: `NSFileCoordinator` write fails → log error, set status to `.failed`, notify pref pane via `OEFolderBackupStatusDidChange` notification. No crash.
- Backup folder on disconnected drive: same path — fail gracefully, surface in UI.
- Initial sync failure on individual file: log and continue — don't block the rest of the sync.

## Cherry-picks from `claude/icloud-save-backup-LFaQZ` (before new work)

These fixes are independent of iCloud and should land on main first:
- `52d22e41` — credential store `persist()` fix + CoreData context fix + RA hardcore async modal
- `[weak self]` additions to `OEGameDocument` sync closures (from `e927c54c`, OEGameDocument hunks only)
