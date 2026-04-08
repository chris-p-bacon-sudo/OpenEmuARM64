// Copyright (c) 2026, OpenEmu Team
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

import AppKit

/// Scans the user's OpenEmu cores directory on every launch and moves any
/// Intel-only (x86_64) core bundles to a `Legacy/` subdirectory.
///
/// This prevents x86-only cores (from a previous OpenEmu installation, a backup
/// restore, or a UserDefaults reset) from conflicting with ARM64 cores and
/// causing "doesn't contain a version for the current architecture" errors.
///
/// Runs on every launch — the scan is lightweight (one pass over the Cores
/// directory) and is a no-op when no x86_64-only cores are present.
/// ARM64 replacements are downloaded automatically by the `checkForNewCores()`
/// call that follows in AppDelegate.
/// Call `runIfNeeded()` before `loadPlugins(with:)` in AppDelegate.
enum OECoreMigration {

    private static var coresDirectory: URL {
        let paths = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
        let appSupport = URL(fileURLWithPath: paths.first!).appendingPathComponent("OpenEmu")
        return appSupport.appendingPathComponent("Cores")
    }

    static func runIfNeeded() {

        let fm = FileManager.default
        let cores = coresDirectory
        let legacy = cores.appendingPathComponent("Legacy")

        guard fm.fileExists(atPath: cores.path) else { return }

        var movedCores: [String] = []

        let items = (try? fm.contentsOfDirectory(at: cores, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.pathExtension == "oecoreplugin" {
            guard let bundle = Bundle(url: item),
                  let archs = bundle.executableArchitectures else { continue }

            let hasARM64 = archs.contains(NSNumber(value: NSBundleExecutableArchitectureARM64))
            guard !hasARM64 else { continue }

            // Intel-only core — move it to Legacy/
            do {
                try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
                let dest = legacy.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.moveItem(at: item, to: dest)
                movedCores.append(item.deletingPathExtension().lastPathComponent)
            } catch {
                // Non-fatal: leave it in place if we can't move it
            }
        }

        guard !movedCores.isEmpty else { return }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Legacy Cores Moved"
            alert.informativeText = """
                OpenEmu-Silicon found \(movedCores.count == 1 ? "an Intel-only core" : "\(movedCores.count) Intel-only cores") \
                that cannot run on Apple Silicon and moved \(movedCores.count == 1 ? "it" : "them") to \
                ~/Library/Application Support/OpenEmu/Cores/Legacy/.

                Moved: \(movedCores.joined(separator: ", "))

                ARM64 replacements will download automatically.
                """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// Re-signs all installed core plugins with an ad-hoc signature on the
    /// first launch of each new app version.
    ///
    /// Defense-in-depth against release-signing regressions: if the shipped app
    /// ever loses its `disable-library-validation` entitlement, cores re-signed
    /// here will still carry a fresh ad-hoc signature so a subsequent fix
    /// release can load them without reinstalling. Runs once per app version
    /// (gated on CFBundleVersion) and is a no-op on subsequent launches.
    static func resignCoresIfNeeded() {
        let versionKey = "OECoresResignedForVersion"
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        guard UserDefaults.standard.string(forKey: versionKey) != currentVersion else { return }

        let fm = FileManager.default
        let cores = coresDirectory
        guard fm.fileExists(atPath: cores.path) else { return }

        let items = (try? fm.contentsOfDirectory(at: cores, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.pathExtension == "oecoreplugin" {
            let task = Process()
            task.launchPath = "/usr/bin/codesign"
            task.arguments = ["--force", "--sign", "-", item.path]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }

        UserDefaults.standard.set(currentVersion, forKey: versionKey)
    }
}
