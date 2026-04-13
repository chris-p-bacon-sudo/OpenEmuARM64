// Copyright (c) 2021, OpenEmu Team
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

import Foundation
import OpenEmuBase


public class OECorePlugin: OEPlugin {
    
    override public class var pluginExtension: String {
        "oecoreplugin"
    }
    
    override public class var pluginFolder: String {
        "Cores"
    }
    
    @objc public class var allPlugins: [OECorePlugin] {
        // Trigger dynamic core sync and merge results
        let dynamicCores = OECoreSyncManager.shared.syncCores()
        
        // swiftlint:disable:next force_cast
        let standardPlugins = plugins() as! [OECorePlugin]
        
        return standardPlugins + dynamicCores
    }
    
    required init(bundleAtURL bundleURL: URL, name: String?) throws {
        try super.init(bundleAtURL: bundleURL, name: name)
        
        // invalidate global cache
        Self.cachedRequiredFiles = nil
    }
    
    public static func corePlugin(bundleAtURL bundleURL: URL) -> OECorePlugin? {
        return try? plugin(bundleAtURL: bundleURL)
    }
    
    public static func corePlugin(bundleIdentifier identifier: String) -> OECorePlugin? {
        return allPlugins.first(where: {
            $0.bundleIdentifier.caseInsensitiveCompare(identifier) == .orderedSame
        })
    }
    
    public static func corePlugins(forSystemIdentifier identifier: String) -> [OECorePlugin] {
        return allPlugins.filter { $0.systemIdentifiers.contains(identifier) }
    }
    
    // MARK: -
    
    typealias Controller = OEGameCoreController
    
    private var _controller: Controller?
    public var controller: OEGameCoreController! {
        if _controller == nil {
            if let principalClass = bundle.principalClass {
                _controller = newPluginController(with: principalClass)
            } else {
                // If the bundle has no executable (e.g. dummy dylib wrappers), instantiate the base Controller.
                // The base Controller will read OEGameCoreClass natively from the plist we generated.
                _controller = Controller(bundle: bundle)
            }
        }
        return _controller
    }
    
    private func newPluginController(with bundleClass: AnyClass) -> Controller? {
        guard let bundleClass = bundleClass as? Controller.Type else { return nil }
        return bundleClass.init(bundle: bundle)
    }
    
    // MARK: -
    
    private static var cachedRequiredFiles: [[String: Any]]?
    public static var requiredFiles: [[String: Any]] {
        if cachedRequiredFiles == nil {
            var files: [[String: Any]] = []
            for plugin in allPlugins {
                files.append(contentsOf: plugin.requiredFiles)
            }
            
            cachedRequiredFiles = files
        }
        
        return cachedRequiredFiles!
    }
    
    public var gameCoreClass: AnyClass? {
        return controller?.gameCoreClass
    }
    
    public var bundleIdentifier: String {
        // swiftlint:disable:next force_cast
        return infoDictionary["CFBundleIdentifier"] as! String
    }
    
    public var systemIdentifiers: [String] {
        return infoDictionary[OEGameCoreSystemIdentifiersKey] as? [String] ?? []
    }
    
    public var coreOptions: [String: [String: Any]] {
        return infoDictionary[OEGameCoreOptionsKey] as? [String: [String: Any]] ?? [:]
    }
    
    public var requiredFiles: [[String: Any]] {
        var allRequiredFiles: [[String: Any]] = []
        
        for value in coreOptions.values {
            if let object = value[OEGameCoreRequiredFilesKey] as? [[String: Any]] {
                allRequiredFiles.append(contentsOf: object)
            }
        }
        
        return allRequiredFiles
    }
    
    // MARK: -
    
    private var isMarkedDeprecatedInInfoPlist: Bool {
        if infoDictionary[OEGameCoreDeprecatedKey] as? Bool != true {
            return false
        }
        
        func isValidVersionString(_ string: String) -> Bool {
            if string.isEmpty { return false }
            let validCharacters: Set<Character> = [".", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
            return Set(string).isSubset(of: validCharacters)
        }
        
        guard let minMacOSVer = self.infoDictionary[OEGameCoreDeprecatedMinMacOSVersionKey] as? String,
              isValidVersionString(minMacOSVer)
        else { return true }
        
        let macOSVerComponents = minMacOSVer.components(separatedBy: ".")
        if macOSVerComponents.count < 2 {
            return true
        }
        let minMacOSVerParsed = OperatingSystemVersion(majorVersion: Int(macOSVerComponents[0])!,
                                                       minorVersion: Int(macOSVerComponents[1])!,
                                                       patchVersion: macOSVerComponents.count > 2 ? Int(macOSVerComponents[2])! : 0)
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(minMacOSVerParsed) {
            return true
        }
        return false
    }
    
    override public var isDeprecated: Bool {
        if isOutOfSupport {
            return true
        }
        return isMarkedDeprecatedInInfoPlist
    }
    
    override public var isOutOfSupport: Bool {
        // plugins deprecated 2017-11-04
        let bundleFileName = bundle.bundleURL.lastPathComponent
        let deprecatedPlugins = [
            "Dolphin-Core.oecoreplugin",
            "NeoPop.oecoreplugin",
            "TwoMbit.oecoreplugin",
            "VisualBoyAdvance.oecoreplugin",
            "Yabause.oecoreplugin",
        ]
        if deprecatedPlugins.contains(bundleFileName) {
            return true
        }
        
        // beta-era plugins
        if let appcastURL = infoDictionary["SUFeedURL"] as? String,
           appcastURL.contains("openemu.org/update") {
            return true
        }
        
        // plugins marked as deprecated in the Info.plist keys
        if isMarkedDeprecatedInInfoPlist,
           let deadline = infoDictionary[OEGameCoreSupportDeadlineKey] as? Date,
           Date().compare(deadline) == .orderedDescending {
            // we are past the support deadline; return true to remove the core
            prepareForRemoval()
            return true
        }
        
        // missing value for required key 'CFBundleIdentifier' in Info.plist
        if infoDictionary["CFBundleIdentifier"] as? String == nil {
            return true
        }
        
        return false
    }
    
    private func prepareForRemoval() {
        let replacements = infoDictionary[OEGameCoreSuggestedReplacement] as? [String: String]
        
        let defaults = UserDefaults.standard
        for systemIdentifier in systemIdentifiers {
            let prefKey = "defaultCore." + systemIdentifier
            if let currentCore = defaults.string(forKey: prefKey),
               currentCore == bundleIdentifier {
                if let replacement = replacements?[systemIdentifier] {
                    defaults.set(replacement, forKey: prefKey)
                } else {
                    defaults.removeObject(forKey: prefKey)
                }
            }
        }
    }
}

public extension OECorePlugin {
    
    func requiredFiles(forSystemIdentifier systemIdentifier: String) -> [[String: Any]]? {
        let options = coreOptions[systemIdentifier]
        return options?[OEGameCoreRequiredFilesKey] as? [[String: Any]] ?? nil
    }
    
    func requiresFiles(forSystemIdentifier systemIdentifier: String) -> Bool {
        let options = coreOptions[systemIdentifier]
        return options?[OEGameCoreRequiresFilesKey] as? Bool ?? false
    }
    
    func supportsCheatCode(forSystemIdentifier systemIdentifier: String) -> Bool {
        let options = coreOptions[systemIdentifier]
        return options?[OEGameCoreSupportsCheatCodeKey] as? Bool ?? false
    }
    
    func hasGlitches(forSystemIdentifier systemIdentifier: String) -> Bool {
        let options = coreOptions[systemIdentifier]
        return options?[OEGameCoreHasGlitchesKey] as? Bool ?? false
    }
    
    func saveStatesNotSupported(forSystemIdentifier systemIdentifier: String) -> Bool {
        let options = coreOptions[systemIdentifier]
        return options?[OEGameCoreSaveStatesNotSupportedKey] as? Bool ?? false
    }
    
    func supportsMultipleDiscs(forSystemIdentifier systemIdentifier: String) -> Bool {
        let options = coreOptions[systemIdentifier]
        return options?[OEGameCoreSupportsMultipleDiscsKey] as? Bool ?? false
    }
    
    func supportsRewinding(forSystemIdentifier systemIdentifier: String) -> Bool {
        let options = coreOptions[systemIdentifier]
        return options?[OEGameCoreSupportsRewindingKey] as? Bool ?? false
    }
    
    func supportsFileInsertion(forSystemIdentifier systemIdentifier: String) -> Bool {
        let options = coreOptions[systemIdentifier]
        return options?[OEGameCoreSupportsFileInsertionKey] as? Bool ?? false
    }
    
    func supportsDisplayModeChange(forSystemIdentifier systemIdentifier: String) -> Bool {
        let options = coreOptions[systemIdentifier]
        return options?[OEGameCoreSupportsDisplayModeChangeKey] as? Bool ?? false
    }
    
    func rewindInterval(forSystemIdentifier systemIdentifier: String) -> Int {
        let options = coreOptions[systemIdentifier]
        return options?[OEGameCoreRewindIntervalKey] as? Int ?? 0
    }
    
    func rewindBufferSeconds(forSystemIdentifier systemIdentifier: String) -> Int {
        let options = coreOptions[systemIdentifier]
        return options?[OEGameCoreRewindBufferSecondsKey] as? Int ?? 0
    }
}

public extension OECorePlugin.Architecture {
    // swiftlint:disable:next identifier_name
    static let x86_64 = "x86_64"
    static let arm64 = "arm64"
}

public extension OECorePlugin {
    typealias Architecture = String
    
    var architectures: [Architecture] {
        var architectures: [Architecture] = []
        let executableArchitectures = bundle.executableArchitectures as? [Int] ?? []
        if executableArchitectures.contains(NSBundleExecutableArchitectureX86_64) {
            architectures.append(.x86_64)
        }
        if #available(macOS 11.0, *),
           executableArchitectures.contains(NSBundleExecutableArchitectureARM64) {
            architectures.append(.arm64)
        }
        return architectures
    }
}
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

import Foundation

/// Scans the application-support Cores folder for libretro `.dylib` files that were
/// downloaded by the `CoreDownload` machinery but whose companion `.oecoreplugin`
/// bundle is missing (e.g. after a crash mid-install, or a manually placed dylib).
///
/// For dylibs that already have a valid `.oecoreplugin` next to them the standard
/// `OEPlugin.plugins()` scanner handles registration, so `syncCores()` purposely
/// skips those to avoid duplicates.
///
/// System identifiers are resolved in order:
///  1. From the dylib's companion `.oecoreplugin/Info.plist` if present (written by
///     `CoreDownload` with the correct `OEGameCoreSystemIdentifiers` key).
///  2. From the static dylib-filename → system-ID table embedded below, which mirrors
///     `OELibretroBuildbot.allCores` (kept as a plain dictionary here so this file
///     has no compile-time dependency on the OpenEmu app target).
@objc(OECoreSyncManager)
public class OECoreSyncManager: NSObject {

    @objc public static let shared = OECoreSyncManager()

    /// Application-support Cores folder — same location CoreDownload uses.
    private var coresFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenEmu/Cores", isDirectory: true)
    }

    // Static fallback: dylib filename -> [OpenEmu system identifiers, BIOS requirements]
    // Synchronized with OELibretroBuildbot.allCores
    private static let metadataByDylib: [String: (sysIDs: [String], bios: [[String: Any]]?)] = [
        "melonds_libretro.dylib":            (["openemu.system.nds"], [
            ["Name": "bios7.bin", "Description": "ARM7 BIOS", "MD5": "df692a80a5b1bcbae72ba034cf3af048", "Size": 16384],
            ["Name": "bios9.bin", "Description": "ARM9 BIOS", "MD5": "a39217daabfcf4a30ae9e564f0b240f8", "Size": 4096],
            ["Name": "firmware.bin", "Description": "Firmware", "MD5": "6c361df89e13d46a894a4b4ed6dbd380", "Size": 262144]
        ]),
    ]

    private var cachedPlugins: [OECorePlugin]?

    /// Invalidate the plugin cache (called after a new core is installed).
    @objc public func invalidateCache() {
        cachedPlugins = nil
    }

    /// Returns `OECorePlugin` instances for every libretro dylib that does NOT yet
    /// have a companion `.oecoreplugin` bundle handled by `OEPlugin.plugins()`.
    @objc public func syncCores() -> [OECorePlugin] {
        var result: [OECorePlugin] = []
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: coresFolder, includingPropertiesForKeys: nil
        ) else {
            cachedPlugins = result
            return result
        }

        for dylibURL in contents where dylibURL.pathExtension == "dylib" {
            let stem = dylibURL.deletingPathExtension().lastPathComponent
            
            // CRITICAL: Avoid duplicate registration.
            // If this dylib is already inside a standard .oecoreplugin bundle, ignore it.
            let standardStem = stem.replacingOccurrences(of: "_libretro", with: "")
            let standardBundleID = "org.openemu.libretro.\(standardStem)"
            let standardBundleURL = coresFolder.appendingPathComponent("\(standardBundleID).oecoreplugin")
            let fauxURL = coresFolder.appendingPathComponent("\(stem).oecoreplugin")
            
            if fm.fileExists(atPath: standardBundleURL.path) {
                // remediate clashing faux bundle
                if fm.fileExists(atPath: fauxURL.path) {
                    try? fm.removeItem(at: fauxURL)
                }
                continue
            }

            // Resolve system IDs and BIOS requirements: check companion plist first,
            // then fall back to the local metadata table.
            let (sysIDs, bios): ([String], [[String: Any]]?) = {
                if let plist = NSDictionary(contentsOf: fauxURL.appendingPathComponent("Info.plist")),
                   let ids = plist["OESystemIdentifiers"] as? [String], !ids.isEmpty {
                    
                    // Correctly extract BIOS requirements from the nested options dictionary
                    var bio: [[String: Any]]? = nil
                    if let options = plist["OEGameCoreOptions"] as? [String: Any] {
                        for (_, value) in options {
                            if let dict = value as? [String: Any],
                               let files = dict["OERequiredFiles"] as? [[String: Any]] {
                                bio = files
                                break
                            }
                        }
                    }
                    return (ids, bio)
                }
                
                let metadata = Self.metadataByDylib[dylibURL.lastPathComponent]
                return (metadata?.sysIDs ?? [], metadata?.bios)
            }()

            // Pulse metadata into Info.plist and register the plugin
            if !sysIDs.isEmpty {
                if let plugin = makePlugin(dylib: dylibURL, stem: stem, sysIDs: sysIDs, requiredFiles: bios) {
                    result.append(plugin)
                }
            }
        }

        cachedPlugins = result
        return result
    }


    // MARK: - Private helpers

    private func makePlugin(dylib dylibURL: URL, stem: String, sysIDs: [String], requiredFiles: [[String: Any]]?) -> OECorePlugin? {
        let fauxURL = coresFolder.appendingPathComponent("\(stem).oecoreplugin")
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: fauxURL, withIntermediateDirectories: true)
        } catch {
            print("[OECoreSyncManager] Could not create faux bundle at \(fauxURL.path): \(error)")
            return nil
        }

        // Use the actual core version if available, otherwise fallback.
        // Use the actual core version if available, otherwise fallback.
        let coreVersion = OELibretroCoreTranslator.libraryVersionForCore(at: dylibURL) ?? "1.0-Libretro"

        var plist: [String: Any] = [
            "CFBundleName":                  stem,
            "CFBundleIdentifier":            stem,
            "CFBundleVersion":               coreVersion,
            "CFBundleShortVersionString":    coreVersion,
            "OEGameCoreClass":               "OELibretroCoreTranslator",
            "OEGameCorePlayerCount":         4,
            "OELibretroCorePath":            dylibURL.path,
            "OESystemIdentifiers":           sysIDs,
        ]
        
        // Inject BIOS requirements if we have them
        if let requiredFiles = requiredFiles {
            var options: [String: Any] = [:]
            for sysID in sysIDs {
                options[sysID] = [
                    "OEGameCoreRequiresFiles": true,
                    "OERequiredFiles": requiredFiles
                ]
            }
            plist["OEGameCoreOptions"] = options
        }

        (plist as NSDictionary).write(
            to: fauxURL.appendingPathComponent("Info.plist"),
            atomically: true
        )

        if let plugin = OECorePlugin.corePlugin(bundleAtURL: fauxURL) {
            print("[OECoreSyncManager] Registered orphaned libretro core: \(stem)")
            return plugin
        }
        return nil
    }
}
