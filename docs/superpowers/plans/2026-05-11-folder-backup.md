# Folder Backup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Google Drive sync UI with a user-selectable folder backup that mirrors save states, battery saves, and BIOS files — works with iCloud Drive, Dropbox, or any local path, no entitlements required.

**Architecture:** New singleton `OEFolderBackupManager` owns all backup logic (FSEventStream + copy helpers + pre-launch check + restore). `PrefCloudSyncController` UI is replaced wholesale with a folder picker while Google Drive code stays in the file. `OEGameDocument.performPreLaunchSyncCheckIfNeeded` is refactored to chain Google Drive → folder backup.

**Tech Stack:** Swift 5, AppKit, FSEventStream (CoreServices), FileManager, NSOpenPanel, UserDefaults, NotificationCenter.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `OpenEmu/OEFolderBackupManager.swift` | Singleton: path mapping, FSEventStream, initial sync, atomic copy, pre-launch check, restore |
| Modify | `OpenEmu/PrefCloudSyncController.swift` | Replace GDrive UI body; GDrive methods stay in file untouched |
| Modify | `OpenEmu/OEGameDocument.swift` | Cherry-pick fixes + refactor pre-launch check to chain GDrive → folder backup |
| Modify | `OpenEmu/OECredentialStore.swift` | Cherry-pick: add `persist()` call after credential migration |
| Modify | `OpenEmu/AppDelegate.swift` | Add `OEFolderBackupManager.shared.start()` |
| Modify | `OpenEmu/OpenEmu.xcodeproj/project.pbxproj` | Register new file in Sources build phase |

**Path mapping rule (exact mirror):**
- `{supportDir}/Save States/…` ↔ `{backup}/Save States/…`
- `{supportDir}/{core}/Battery Saves/…` ↔ `{backup}/{core}/Battery Saves/…`
- `{supportDir}/BIOS/…` ↔ `{backup}/BIOS/…`

---

## Task 0: Branch setup + cherry-picks

**Files:**
- Modify: `OpenEmu/OECredentialStore.swift`
- Modify: `OpenEmu/OEGameDocument.swift`

- [ ] **Step 1: Create feature branch**

```bash
git checkout main && git pull
git checkout -b feat/folder-backup
```

- [ ] **Step 2: Cherry-pick the pre-release regression fixes**

```bash
git cherry-pick 52d22e41
```

This brings in three independent fixes from the abandoned iCloud branch:
1. `OECredentialStore.swift`: `persist()` called after credential migration (fixes silent credential loss on first `get()` call)
2. `OEGameDocument.swift`: CoreData context fix — re-fetches `rom` in `mainThreadContext` for both branches of the save-state write path
3. `OEGameDocument.swift`: RA hardcore modal converted from blocking `runModal()` to `beginSheetModal` (fixes App Hang reports)

Expected: clean apply, no conflicts. If conflicts arise, resolve by accepting the incoming changes for all three files — the fixes are intentional improvements over what's on main.

- [ ] **Step 3: Verify cherry-pick applied correctly**

```bash
grep -n "persist()" OpenEmu/OECredentialStore.swift
# Expected: line ~267 shows persist() call inside if migrated > 0 block

grep -n "mainThreadContext" OpenEmu/OEGameDocument.swift | head -5
# Expected: two hits around line 1892-1893

grep -n "beginSheetModal" OpenEmu/OEGameDocument.swift
# Expected: one hit around line 1207
```

- [ ] **Step 4: Build check**

```bash
./Scripts/verify.sh 2>&1 | grep -E "PASS|FAIL"
```

Expected: all PASS. If analyze fails on a pre-existing issue unrelated to these files, note it and continue.

---

## Task 1: Create OEFolderBackupManager — skeleton, path mapping, copy helpers

**Files:**
- Create: `OpenEmu/OEFolderBackupManager.swift`

- [ ] **Step 1: Create the file**

```bash
touch "OpenEmu/OEFolderBackupManager.swift"
```

- [ ] **Step 2: Write the full file**

Paste the following into `OpenEmu/OEFolderBackupManager.swift`:

```swift
// Copyright (c) 2024, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the OpenEmu Team nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Cocoa
import os.log

private let log = OSLog(subsystem: "org.openemu.OpenEmu", category: "FolderBackup")
private let kBackupFolderPathKey = "OEBackupFolderPath"
private let kLastBackupDateKey   = "OELastBackupDate"

extension Notification.Name {
    static let OEFolderBackupStatusDidChange = Notification.Name("OEFolderBackupStatusDidChange")
}

@objc enum OEFolderBackupStatus: Int {
    case noFolderSelected  // No folder configured.
    case idle              // Folder configured, monitoring active.
    case syncing           // Initial sync or restore in progress.
    case failed            // Last copy operation failed.
}

// MARK: - OEFolderBackupManager

/// Backs up battery saves, save states, and BIOS files to a user-chosen folder.
///
/// The backup mirrors the OpenEmu Application Support directory structure exactly:
///   local:  `~/Library/Application Support/OpenEmu/Save States/…`
///   backup: `{backupFolder}/Save States/…`
///
/// If the user points the backup folder at a location inside iCloud Drive
/// (`~/Library/Mobile Documents/`), macOS syncs it transparently — no entitlements needed.
@objc final class OEFolderBackupManager: NSObject {

    // MARK: - Singleton

    @objc static let shared = OEFolderBackupManager()

    // MARK: - Public state

    @objc private(set) var status: OEFolderBackupStatus = .noFolderSelected {
        didSet {
            guard status != oldValue else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .OEFolderBackupStatusDidChange, object: self)
            }
        }
    }

    @objc var backupFolderURL: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: kBackupFolderPathKey) else { return nil }
            return URL(fileURLWithPath: path)
        }
        set {
            UserDefaults.standard.set(newValue?.path, forKey: kBackupFolderPathKey)
        }
    }

    @objc var isEnabled: Bool { backupFolderURL != nil && status != .noFolderSelected }

    @objc private(set) var lastBackupDate: Date? {
        get { UserDefaults.standard.object(forKey: kLastBackupDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: kLastBackupDateKey) }
    }

    // MARK: - Private

    private var eventStream: FSEventStreamRef?

    private override init() { super.init() }

    // MARK: - Lifecycle

    /// Call once after the library database has loaded. No-op if no folder is configured.
    @objc func start() {
        guard backupFolderURL != nil else {
            status = .noFolderSelected
            return
        }
        status = .syncing
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.performInitialSync()
            DispatchQueue.main.async {
                self?.status = .idle
                self?.startFSEventStream()
            }
        }
    }

    @objc func stop() {
        stopFSEventStream()
        if backupFolderURL == nil { status = .noFolderSelected }
    }

    // MARK: - Folder selection

    /// Presents an NSOpenPanel. On selection: stops current monitoring, saves the new folder,
    /// runs initial sync, then starts FSEventStream. Calls completion(true) on success.
    @objc func chooseFolder(relativeTo window: NSWindow, completion: @escaping (_ selected: Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Backup Folder"
        panel.message = "Choose a folder to back up your save states, battery saves, and BIOS files. Pick a folder inside iCloud Drive to sync automatically across your Macs."

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else {
                completion(false)
                return
            }
            self?.stop()
            self?.backupFolderURL = url
            self?.start()
            completion(true)
        }
    }

    /// Clears the saved folder and stops monitoring.
    @objc func removeFolder() {
        stop()
        backupFolderURL = nil
        status = .noFolderSelected
        os_log(.info, log: log, "Backup folder removed.")
    }

    // MARK: - FSEventStream (outbound: local → backup)

    private func startFSEventStream() {
        guard eventStream == nil, backupFolderURL != nil else { return }
        let supportDir = URL.oeApplicationSupportDirectory
        var watchURLs: [URL] = [
            supportDir.appendingPathComponent("Save States"),
            supportDir.appendingPathComponent("BIOS"),
        ]
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: supportDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) {
            for dir in contents {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
                guard isDir.boolValue else { continue }
                let bs = dir.appendingPathComponent("Battery Saves")
                if FileManager.default.fileExists(atPath: bs.path) { watchURLs.append(bs) }
            }
        }

        let paths = watchURLs.map { $0.path } as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info else { return }
            let mgr = Unmanaged<OEFolderBackupManager>.fromOpaque(info).takeUnretainedValue()
            let rawPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            let urls = rawPaths.prefix(numEvents).map { URL(fileURLWithPath: $0) }
            mgr.handleFSEvents(at: Array(urls))
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            os_log(.error, log: log, "Failed to create FSEventStream.")
            return
        }
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue as CFString)
        FSEventStreamStart(stream)
        eventStream = stream
        os_log(.info, log: log, "FSEventStream watching %d director(ies).", watchURLs.count)
    }

    private func stopFSEventStream() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
    }

    private func handleFSEvents(at urls: [URL]) {
        guard let backupFolder = backupFolderURL else { return }
        let fm = FileManager.default
        var roots = Set<URL>()
        for url in urls {
            guard !url.lastPathComponent.hasPrefix(".") else { continue }
            guard let root = saveItemRoot(for: url) else { continue }
            guard fm.fileExists(atPath: root.path) else { continue }
            roots.insert(root)
        }
        for localURL in roots {
            guard let dest = backupURL(for: localURL, backupFolder: backupFolder) else { continue }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.copyToBackupIfNewer(from: localURL, to: dest)
            }
        }
    }

    // MARK: - Initial sync

    private func performInitialSync() {
        guard let backupFolder = backupFolderURL else { return }
        let supportDir = URL.oeApplicationSupportDirectory
        let fm = FileManager.default
        os_log(.info, log: log, "Starting initial sync to %@", backupFolder.path)

        var sourceDirs: [URL] = [
            supportDir.appendingPathComponent("Save States"),
            supportDir.appendingPathComponent("BIOS"),
        ]
        if let contents = try? fm.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) {
            for dir in contents {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: dir.path, isDirectory: &isDir)
                guard isDir.boolValue else { continue }
                let bs = dir.appendingPathComponent("Battery Saves")
                if fm.fileExists(atPath: bs.path) { sourceDirs.append(bs) }
            }
        }

        for sourceDir in sourceDirs {
            guard let enumerator = fm.enumerator(
                at: sourceDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: .skipsHiddenFiles
            ) else { continue }

            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                if ext == "oesavestate" {
                    enumerator.skipDescendants()
                    guard let dest = backupURL(for: fileURL, backupFolder: backupFolder) else { continue }
                    copyToBackupIfNewer(from: fileURL, to: dest)
                } else {
                    let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    guard !isDir else { continue }
                    guard let dest = backupURL(for: fileURL, backupFolder: backupFolder) else { continue }
                    copyToBackupIfNewer(from: fileURL, to: dest)
                }
            }
        }
        os_log(.info, log: log, "Initial sync complete.")
    }

    // MARK: - File copy helpers

    private func copyToBackupIfNewer(from localURL: URL, to destURL: URL) {
        let localDate = (try? localURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let destDate  = (try? destURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let l = localDate, let d = destDate, d >= l { return }
        copyFile(from: localURL, to: destURL, direction: "→")
    }

    private func copyFile(from src: URL, to dest: URL, direction: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = dest.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString)
        do {
            try fm.copyItem(at: src, to: temp)
            try fm.replaceItem(at: dest, withItemAt: temp, backupItemName: nil, options: [])
            lastBackupDate = Date()
            os_log(.debug, log: log, "%@ %@", direction, src.lastPathComponent)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.status == .failed else { return }
                self.status = .idle
            }
        } catch {
            try? fm.removeItem(at: temp)
            os_log(.error, log: log, "Copy failed (%@ %@): %@", direction, src.lastPathComponent, error.localizedDescription)
            DispatchQueue.main.async { [weak self] in self?.status = .failed }
        }
    }

    // MARK: - Pre-launch check

    /// Checks whether the backup folder contains a newer save for the given game.
    /// Completion is always called on the main thread.
    @objc func checkForNewerBackup(
        systemIdentifier: String,
        gameName: String,
        completion: @escaping (_ shouldRestore: Bool, _ newestDate: Date?) -> Void
    ) {
        guard let backupFolder = backupFolderURL else {
            completion(false, nil)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { completion(false, nil); return }
            let backupDate = self.newestBackupDate(backupFolder: backupFolder, systemIdentifier: systemIdentifier, gameName: gameName)
            guard let backupDate else {
                DispatchQueue.main.async { completion(false, nil) }
                return
            }
            let localDate = self.newestLocalDate(systemIdentifier: systemIdentifier, gameName: gameName)
            let backupIsNewer = backupDate > (localDate ?? .distantPast)
            os_log(.debug, log: log, "Pre-launch '%@': backup=%@, local=%@, newer=%d",
                   gameName, backupDate.description, localDate?.description ?? "none", backupIsNewer)
            DispatchQueue.main.async { completion(backupIsNewer, backupDate) }
        }
    }

    /// Copies saves for the given game from the backup folder to local OpenEmu directories.
    @objc func restoreFromBackup(
        systemIdentifier: String,
        gameName: String,
        completion: @escaping (_ success: Bool) -> Void
    ) {
        guard let backupFolder = backupFolderURL else { completion(false); return }
        let systemShort = systemIdentifier.replacingOccurrences(of: "openemu.system.", with: "")
        let safeName    = gameName.replacingOccurrences(of: "/", with: "_")
        let fm = FileManager.default

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { completion(false); return }

            // Save states
            let backupStateDir = backupFolder
                .appendingPathComponent("Save States")
                .appendingPathComponent(systemShort)
                .appendingPathComponent(safeName)
            if let states = try? fm.contentsOfDirectory(at: backupStateDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                for f in states where f.pathExtension.lowercased() == "oesavestate" {
                    if let local = self.localURL(for: f, backupFolder: backupFolder) {
                        self.copyFile(from: f, to: local, direction: "←")
                    }
                }
            }

            // Battery saves — search {backup}/{core}/Battery Saves/ for all cores
            if let coreDirs = try? fm.contentsOfDirectory(at: backupFolder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) {
                for coreDir in coreDirs {
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: coreDir.path, isDirectory: &isDir)
                    guard isDir.boolValue else { continue }
                    let bsDir = coreDir.appendingPathComponent("Battery Saves")
                    guard fm.fileExists(atPath: bsDir.path),
                          let files = try? fm.contentsOfDirectory(at: bsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { continue }
                    for f in files where f.deletingPathExtension().lastPathComponent == safeName {
                        if let local = self.localURL(for: f, backupFolder: backupFolder) {
                            self.copyFile(from: f, to: local, direction: "←")
                        }
                    }
                }
            }

            DispatchQueue.main.async { completion(true) }
        }
    }

    // MARK: - Path mapping

    /// Maps a URL inside the OpenEmu support directory to its counterpart in the backup folder.
    private func backupURL(for localURL: URL, backupFolder: URL) -> URL? {
        let supportPath = URL.oeApplicationSupportDirectory.standardized.path
        let localPath   = localURL.standardized.path
        guard localPath.hasPrefix(supportPath) else { return nil }
        var relative = String(localPath.dropFirst(supportPath.count))
        if !relative.hasPrefix("/") { relative = "/" + relative }
        return URL(fileURLWithPath: backupFolder.standardized.path + relative)
    }

    /// Maps a URL inside the backup folder to its counterpart in the OpenEmu support directory.
    private func localURL(for backupURL: URL, backupFolder: URL) -> URL? {
        let folderPath = backupFolder.standardized.path
        let backupPath = backupURL.standardized.path
        guard backupPath.hasPrefix(folderPath) else { return nil }
        var relative = String(backupPath.dropFirst(folderPath.count))
        if !relative.hasPrefix("/") { relative = "/" + relative }
        return URL(fileURLWithPath: URL.oeApplicationSupportDirectory.standardized.path + relative)
    }

    /// Walks up the path to find an `.oesavestate` bundle root; returns the URL itself for flat files.
    private func saveItemRoot(for url: URL) -> URL? {
        var candidate = url
        while candidate.pathComponents.count > 1 {
            if candidate.pathExtension.lowercased() == "oesavestate" { return candidate }
            let parent = candidate.deletingLastPathComponent()
            if parent == candidate { break }
            candidate = parent
        }
        return url.pathExtension.isEmpty ? nil : url
    }

    // MARK: - Date helpers

    private func newestBackupDate(backupFolder: URL, systemIdentifier: String, gameName: String) -> Date? {
        let systemShort = systemIdentifier.replacingOccurrences(of: "openemu.system.", with: "")
        let safeName    = gameName.replacingOccurrences(of: "/", with: "_")
        let fm = FileManager.default
        var dates: [Date] = []

        // Save states
        let stateDir = backupFolder
            .appendingPathComponent("Save States")
            .appendingPathComponent(systemShort)
            .appendingPathComponent(safeName)
        if let states = try? fm.contentsOfDirectory(at: stateDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) {
            for f in states where f.pathExtension.lowercased() == "oesavestate" {
                if let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate { dates.append(d) }
            }
        }

        // Battery saves
        if let coreDirs = try? fm.contentsOfDirectory(at: backupFolder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) {
            for coreDir in coreDirs {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: coreDir.path, isDirectory: &isDir)
                guard isDir.boolValue else { continue }
                let bsDir = coreDir.appendingPathComponent("Battery Saves")
                guard fm.fileExists(atPath: bsDir.path),
                      let files = try? fm.contentsOfDirectory(at: bsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else { continue }
                for f in files where f.deletingPathExtension().lastPathComponent == safeName {
                    if let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate { dates.append(d) }
                }
            }
        }
        return dates.max()
    }

    private func newestLocalDate(systemIdentifier: String, gameName: String) -> Date? {
        let systemShort = systemIdentifier.replacingOccurrences(of: "openemu.system.", with: "")
        let safeName    = gameName.replacingOccurrences(of: "/", with: "_")
        let supportDir  = URL.oeApplicationSupportDirectory
        let fm = FileManager.default
        var dates: [Date] = []

        // Save states
        let stateDir = supportDir
            .appendingPathComponent("Save States")
            .appendingPathComponent(systemShort)
            .appendingPathComponent(safeName)
        if let states = try? fm.contentsOfDirectory(at: stateDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) {
            for f in states where f.pathExtension.lowercased() == "oesavestate" {
                if let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate { dates.append(d) }
            }
        }

        // Battery saves
        if let coreDirs = try? fm.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) {
            for coreDir in coreDirs {
                let bsDir = coreDir.appendingPathComponent("Battery Saves")
                guard fm.fileExists(atPath: bsDir.path),
                      let files = try? fm.contentsOfDirectory(at: bsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else { continue }
                for f in files where f.deletingPathExtension().lastPathComponent == safeName {
                    if let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate { dates.append(d) }
                }
            }
        }
        return dates.max()
    }
}
```

- [ ] **Step 3: Build check**

```bash
./Scripts/verify.sh 2>&1 | grep -E "PASS|FAIL"
```

The file isn't in the project yet so this still builds the old target. Proceed to Task 2.

- [ ] **Step 4: Commit**

```bash
git add OpenEmu/OEFolderBackupManager.swift
git commit -m "feat: add OEFolderBackupManager — path mapping, FSEventStream, initial sync, pre-launch check (assisted by Claude)"
```

---

## Task 2: Add OEFolderBackupManager.swift to project.pbxproj

**Files:**
- Modify: `OpenEmu/OpenEmu.xcodeproj/project.pbxproj`

The project file needs four entries. Use the GUIDs below exactly (generated for this plan).

- `BUILD_FILE_GUID`     = `CEA508990AF842369046D92D`
- `FILE_REF_GUID`       = `9964A7D7B3C4438D9BE62654`

- [ ] **Step 1: Add PBXBuildFile entry**

Find the line:
```
		DFDDE95A9D47B0C0B525780A /* OESaveSyncManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = 6F74677D2124A2E934C10038 /* OESaveSyncManager.swift */; };
```

Insert BEFORE it:
```
		CEA508990AF842369046D92D /* OEFolderBackupManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = 9964A7D7B3C4438D9BE62654 /* OEFolderBackupManager.swift */; };
```

- [ ] **Step 2: Add PBXFileReference entry**

Find the line:
```
		6F74677D2124A2E934C10038 /* OESaveSyncManager.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = OESaveSyncManager.swift; sourceTree = "<group>"; };
```

Insert AFTER it:
```
		9964A7D7B3C4438D9BE62654 /* OEFolderBackupManager.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = OEFolderBackupManager.swift; sourceTree = "<group>"; };
```

- [ ] **Step 3: Add to PBXGroup (Cloud Sync group)**

Find the line:
```
				6F74677D2124A2E934C10038 /* OESaveSyncManager.swift */,
```
(inside the Cloud Sync group, next to PrefCloudSyncController)

Insert AFTER it:
```
				9964A7D7B3C4438D9BE62654 /* OEFolderBackupManager.swift */,
```

- [ ] **Step 4: Add to Sources build phase**

Find the line:
```
				DFDDE95A9D47B0C0B525780A /* OESaveSyncManager.swift in Sources */,
```

Insert AFTER it:
```
				CEA508990AF842369046D92D /* OEFolderBackupManager.swift in Sources */,
```

- [ ] **Step 5: Build check — confirms the file compiles**

```bash
./Scripts/verify.sh 2>&1 | grep -E "PASS|FAIL"
```

Expected: all PASS. If there are Swift errors in OEFolderBackupManager.swift, fix them before continuing.

- [ ] **Step 6: Commit**

```bash
git add OpenEmu/OpenEmu.xcodeproj/project.pbxproj
git commit -m "chore: add OEFolderBackupManager.swift to Xcode project (assisted by Claude)"
```

---

## Task 3: Replace PrefCloudSyncController UI

**Files:**
- Modify: `OpenEmu/PrefCloudSyncController.swift`

Replace the UI body. **Do not delete any existing Google Drive properties or methods** — they stay in the file, just no longer called from `buildUI` or `updateStatus`. The plan shows only what changes.

- [ ] **Step 1: Replace the stored UI properties block**

Find the existing `// MARK: - UI Elements` / `// MARK: - Google Drive UI` block (the declarations: `headerLabel`, `descLabel`, `signInButton`, etc.) and replace it with:

```swift
    // MARK: - Google Drive UI (retained for future re-enablement)

    private let headerLabel       = NSTextField(labelWithString: "")
    private let descLabel         = NSTextField(wrappingLabelWithString: "")
    private let signInButton      = NSButton()
    private let signOutButton     = NSButton()
    private let divider           = NSBox()
    private let statusDot         = NSTextField(labelWithString: "●")
    private let statusLabel       = NSTextField(labelWithString: "")
    private let syncNowButton     = NSButton()
    private let syncInfoLabel     = NSTextField(wrappingLabelWithString: "")
    private let loadingIndicator  = NSProgressIndicator()
    private let scrollView        = NSScrollView()
    private let tableView         = NSTableView()
    private var cloudFiles: [OESaveSyncManager.DriveFile] = []

    // MARK: - Backup Folder UI

    private let bkHeaderLabel     = NSTextField(labelWithString: "")
    private let bkDescLabel       = NSTextField(wrappingLabelWithString: "")
    private let bkStatusDot       = NSTextField(labelWithString: "●")
    private let bkStatusLabel     = NSTextField(labelWithString: "")
    private let bkFolderPathLabel = NSTextField(labelWithString: "")
    private let bkChooseButton    = NSButton()
    private let bkOpenFinderButton = NSButton()
    private let bkRemoveButton    = NSButton()
    private let bkLastSyncedLabel = NSTextField(labelWithString: "")
    private let bkNoteLabel       = NSTextField(wrappingLabelWithString: "")
    private var bkStatusToken: NSObjectProtocol?
```

- [ ] **Step 2: Update `loadView` size**

Change:
```swift
        view = NSView(frame: NSRect(x: 0, y: 0, width: 468, height: 480))
```
to:
```swift
        view = NSView(frame: NSRect(x: 0, y: 0, width: 468, height: 320))
```

- [ ] **Step 3: Update `viewDidLoad`**

Replace the existing `viewDidLoad` body with:

```swift
    override func viewDidLoad() {
        super.viewDidLoad()
        updateBackupStatus()

        bkStatusToken = NotificationCenter.default.addObserver(
            forName: .OEFolderBackupStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateBackupStatus()
        }
    }
```

- [ ] **Step 4: Update `deinit`**

Replace with:
```swift
    deinit {
        if let token = syncStatusToken  { NotificationCenter.default.removeObserver(token) }
        if let token = bkStatusToken    { NotificationCenter.default.removeObserver(token) }
    }
```

- [ ] **Step 5: Replace `buildUI()` body**

Keep the method signature `private func buildUI()`. Replace its entire body with:

```swift
        // ── Header ──────────────────────────────────────────────────
        bkHeaderLabel.stringValue = "Backup Folder"
        bkHeaderLabel.font = .boldSystemFont(ofSize: 15)
        bkHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bkHeaderLabel)

        // ── Description ─────────────────────────────────────────────
        bkDescLabel.stringValue = "Automatically back up save states, battery saves, and BIOS files to any folder. Choose a folder inside iCloud Drive to sync across your Macs, or use Dropbox, an external drive, or any local path."
        bkDescLabel.font = .systemFont(ofSize: 12)
        bkDescLabel.textColor = .secondaryLabelColor
        bkDescLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bkDescLabel)

        // ── Status row ───────────────────────────────────────────────
        bkStatusDot.font = .systemFont(ofSize: 14)
        bkStatusDot.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bkStatusDot)

        bkStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        bkStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bkStatusLabel)

        // ── Folder path ──────────────────────────────────────────────
        bkFolderPathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        bkFolderPathLabel.textColor = .secondaryLabelColor
        bkFolderPathLabel.lineBreakMode = .byTruncatingMiddle
        bkFolderPathLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bkFolderPathLabel)

        // ── Buttons ──────────────────────────────────────────────────
        bkChooseButton.title = "Choose Folder…"
        bkChooseButton.bezelStyle = .rounded
        bkChooseButton.controlSize = .regular
        bkChooseButton.font = .systemFont(ofSize: 13)
        bkChooseButton.target = self
        bkChooseButton.action = #selector(chooseBackupFolder)
        bkChooseButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bkChooseButton)

        bkOpenFinderButton.title = "Show in Finder"
        bkOpenFinderButton.bezelStyle = .rounded
        bkOpenFinderButton.controlSize = .regular
        bkOpenFinderButton.font = .systemFont(ofSize: 13)
        bkOpenFinderButton.target = self
        bkOpenFinderButton.action = #selector(openBackupInFinder)
        bkOpenFinderButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bkOpenFinderButton)

        bkRemoveButton.title = "Remove"
        bkRemoveButton.bezelStyle = .rounded
        bkRemoveButton.controlSize = .regular
        bkRemoveButton.font = .systemFont(ofSize: 13)
        bkRemoveButton.target = self
        bkRemoveButton.action = #selector(removeBackupFolder)
        bkRemoveButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bkRemoveButton)

        // ── Last synced ──────────────────────────────────────────────
        bkLastSyncedLabel.font = .systemFont(ofSize: 11)
        bkLastSyncedLabel.textColor = .secondaryLabelColor
        bkLastSyncedLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bkLastSyncedLabel)

        // ── Note ─────────────────────────────────────────────────────
        bkNoteLabel.stringValue = "ROMs are not included in the backup."
        bkNoteLabel.font = .systemFont(ofSize: 11)
        bkNoteLabel.textColor = .tertiaryLabelColor
        bkNoteLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bkNoteLabel)

        // ── Layout ───────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            bkHeaderLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            bkHeaderLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            bkHeaderLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            bkDescLabel.topAnchor.constraint(equalTo: bkHeaderLabel.bottomAnchor, constant: 8),
            bkDescLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            bkDescLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            bkStatusDot.topAnchor.constraint(equalTo: bkDescLabel.bottomAnchor, constant: 18),
            bkStatusDot.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),

            bkStatusLabel.centerYAnchor.constraint(equalTo: bkStatusDot.centerYAnchor),
            bkStatusLabel.leadingAnchor.constraint(equalTo: bkStatusDot.trailingAnchor, constant: 6),
            bkStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            bkFolderPathLabel.topAnchor.constraint(equalTo: bkStatusDot.bottomAnchor, constant: 10),
            bkFolderPathLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            bkFolderPathLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            bkChooseButton.topAnchor.constraint(equalTo: bkFolderPathLabel.bottomAnchor, constant: 14),
            bkChooseButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 34),

            bkOpenFinderButton.centerYAnchor.constraint(equalTo: bkChooseButton.centerYAnchor),
            bkOpenFinderButton.leadingAnchor.constraint(equalTo: bkChooseButton.trailingAnchor, constant: 8),

            bkRemoveButton.centerYAnchor.constraint(equalTo: bkChooseButton.centerYAnchor),
            bkRemoveButton.leadingAnchor.constraint(equalTo: bkOpenFinderButton.trailingAnchor, constant: 8),

            bkLastSyncedLabel.topAnchor.constraint(equalTo: bkChooseButton.bottomAnchor, constant: 12),
            bkLastSyncedLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            bkLastSyncedLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            bkNoteLabel.topAnchor.constraint(equalTo: bkLastSyncedLabel.bottomAnchor, constant: 8),
            bkNoteLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            bkNoteLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),
        ])
```

- [ ] **Step 6: Add `updateBackupStatus()` and button action methods**

Add these methods to the `// MARK: - Status Update` section (after existing `updateStatus()` — keep `updateStatus()` intact):

```swift
    private func updateBackupStatus() {
        let mgr   = OEFolderBackupManager.shared
        let green = NSColor(red: 0.2,  green: 0.78, blue: 0.35, alpha: 1)
        let red   = NSColor(red: 0.87, green: 0.20, blue: 0.18, alpha: 1)
        let yellow = NSColor(red: 0.95, green: 0.73, blue: 0.00, alpha: 1)
        let gray  = NSColor.secondaryLabelColor

        let hasFolderURL = mgr.backupFolderURL != nil

        switch mgr.status {
        case .noFolderSelected:
            bkStatusDot.textColor   = gray
            bkStatusLabel.stringValue = "No folder selected"
            bkStatusLabel.textColor   = gray
        case .idle:
            bkStatusDot.textColor   = green
            bkStatusLabel.stringValue = "Active"
            bkStatusLabel.textColor   = green
        case .syncing:
            bkStatusDot.textColor   = yellow
            bkStatusLabel.stringValue = "Syncing…"
            bkStatusLabel.textColor   = yellow
        case .failed:
            bkStatusDot.textColor   = red
            bkStatusLabel.stringValue = "Last backup failed"
            bkStatusLabel.textColor   = red
        @unknown default:
            break
        }

        bkFolderPathLabel.stringValue = mgr.backupFolderURL?.path ?? ""
        bkOpenFinderButton.isHidden = !hasFolderURL
        bkRemoveButton.isHidden     = !hasFolderURL

        if let date = mgr.lastBackupDate {
            bkLastSyncedLabel.stringValue = "Last backed up: \(dateFormatter.string(from: date))"
        } else if hasFolderURL {
            bkLastSyncedLabel.stringValue = "No backup yet"
        } else {
            bkLastSyncedLabel.stringValue = ""
        }
    }

    @objc private func chooseBackupFolder() {
        guard let window = view.window else { return }
        OEFolderBackupManager.shared.chooseFolder(relativeTo: window) { [weak self] _ in
            self?.updateBackupStatus()
        }
    }

    @objc private func openBackupInFinder() {
        guard let url = OEFolderBackupManager.shared.backupFolderURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func removeBackupFolder() {
        OEFolderBackupManager.shared.removeFolder()
        updateBackupStatus()
    }
```

- [ ] **Step 7: Update `viewSize` in PreferencePane extension**

Find:
```swift
    var viewSize: NSSize { NSSize(width: 468, height: 480) }
```
Replace with:
```swift
    var viewSize: NSSize { NSSize(width: 468, height: 320) }
```

- [ ] **Step 8: Build check**

```bash
./Scripts/verify.sh 2>&1 | grep -E "PASS|FAIL"
```

Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add OpenEmu/PrefCloudSyncController.swift
git commit -m "feat: replace Google Drive pref UI with folder backup picker (assisted by Claude)"
```

---

## Task 4: Wire OEGameDocument — pre-launch chain + weak-self fixes

**Files:**
- Modify: `OpenEmu/OEGameDocument.swift`

- [ ] **Step 1: Replace `performPreLaunchSyncCheckIfNeeded` and its helper**

Find the entire `performPreLaunchSyncCheckIfNeeded` method (currently a single method starting around line 2291 ending with `}`). Replace the whole method and the closing `}` of the extension with:

```swift
    func performPreLaunchSyncCheckIfNeeded(completion: @escaping () -> Void) {
        guard let systemId = rom?.game?.system?.systemIdentifier,
              let gameName = rom?.game?.displayName else {
            completion()
            return
        }
        // Chain: Google Drive check → folder backup check → launch.
        performGoogleDriveSyncCheck(systemId: systemId, gameName: gameName) { [weak self] in
            guard let self else { completion(); return }
            self.performFolderBackupSyncCheck(systemId: systemId, gameName: gameName, completion: completion)
        }
    }

    private func performGoogleDriveSyncCheck(systemId: String, gameName: String, completion: @escaping () -> Void) {
        let syncManager = OESaveSyncManager.shared
        guard syncManager.isSignedIn else { completion(); return }

        syncManager.checkForNewerCloudSave(
            systemIdentifier: systemId,
            gameName: gameName
        ) { [weak self] shouldSync, cloudDate in
            guard shouldSync else { completion(); return }
            guard let self else { completion(); return }
            self.presentSyncAlert(providerName: "Google Drive", gameName: gameName, cloudDate: cloudDate) { download in
                if download {
                    syncManager.downloadCloudSave(systemIdentifier: systemId, gameName: gameName) { _, _ in
                        completion()
                    }
                } else {
                    completion()
                }
            }
        }
    }

    private func performFolderBackupSyncCheck(systemId: String, gameName: String, completion: @escaping () -> Void) {
        let backupManager = OEFolderBackupManager.shared
        guard backupManager.isEnabled else { completion(); return }

        backupManager.checkForNewerBackup(
            systemIdentifier: systemId,
            gameName: gameName
        ) { [weak self] shouldRestore, backupDate in
            guard shouldRestore else { completion(); return }
            guard let self else { completion(); return }
            self.presentSyncAlert(providerName: "backup folder", gameName: gameName, cloudDate: backupDate) { restore in
                if restore {
                    backupManager.restoreFromBackup(systemIdentifier: systemId, gameName: gameName) { _ in
                        completion()
                    }
                } else {
                    completion()
                }
            }
        }
    }

    private func presentSyncAlert(
        providerName: String,
        gameName: String,
        cloudDate: Date?,
        completion: @escaping (_ download: Bool) -> Void
    ) {
        let dateStr: String
        if let cloudDate {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            dateStr = fmt.string(from: cloudDate)
        } else {
            dateStr = "unknown date"
        }
        let alert = OEAlert()
        alert.messageText = NSLocalizedString("Newer Save Available", comment: "Save Sync alert title")
        alert.informativeText = String(
            format: NSLocalizedString(
                "A newer save for '%@' is available in your %@ (from %@). Restore it before playing?",
                comment: "Save Sync alert body: game name, provider, date"
            ),
            gameName, providerName, dateStr
        )
        alert.defaultButtonTitle   = NSLocalizedString("Restore & Play", comment: "Save Sync: restore and play")
        alert.alternateButtonTitle = NSLocalizedString("Play Without Restoring", comment: "Save Sync: skip restore")
        completion(alert.runModal() == .alertFirstButtonReturn)
    }
}
```

- [ ] **Step 2: Build check**

```bash
./Scripts/verify.sh 2>&1 | grep -E "PASS|FAIL"
```

Expected: all PASS.

- [ ] **Step 3: Commit**

```bash
git add OpenEmu/OEGameDocument.swift
git commit -m "feat: chain folder backup restore check in pre-launch sync flow (assisted by Claude)"
```

---

## Task 5: Wire AppDelegate + final verify

**Files:**
- Modify: `OpenEmu/AppDelegate.swift`

- [ ] **Step 1: Add `OEFolderBackupManager.shared.start()`**

Find:
```swift
        OESaveSyncManager.shared.startMonitoring()
```

Insert immediately after:
```swift
        OEFolderBackupManager.shared.start()
```

- [ ] **Step 2: Final build + verify**

```bash
./Scripts/verify.sh 2>&1 | grep -E "PASS|FAIL"
```

Expected: all PASS.

- [ ] **Step 3: Commit**

```bash
git add OpenEmu/AppDelegate.swift
git commit -m "feat: start OEFolderBackupManager at app launch (assisted by Claude)"
```

---

## Task 6: Ship

- [ ] **Step 1: Run `/ship` to push branch and open PR**

Use the `/ship` slash command. It will run the adversarial gate, push the branch, and open a PR using the project template.

PR title: `feat: folder backup — user-selectable save state and battery save backup`

The PR body should reference Issue #460 with `Closes #460`.
