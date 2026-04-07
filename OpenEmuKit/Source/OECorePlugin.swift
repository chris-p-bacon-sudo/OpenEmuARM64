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
// ...

import Foundation

@objc(OECoreSyncManager)
public class OECoreSyncManager: NSObject, XMLParserDelegate {
    @objc public static let shared = OECoreSyncManager()
    
    private let localCoresPath: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("OpenEmu/Cores/Libs", isDirectory: true)
    }()
    
    private let remoteURL = URL(string: "https://raw.githubusercontent.com/pystIC/OpenEmuARM64-metal4-shaders-core-updates/main/oecores.xml")!
    
    private var currentElement = ""
    private var currentCoreID = ""
    private var currentCoreName = ""
    private var currentURL = ""
    private var parsedCores: [[String: String]] = []
    private var cachedCores: [OECorePlugin]?
    
    @objc public func syncCores() -> [OECorePlugin] {
        if let cached = cachedCores { return cached }
        var plugins: [OECorePlugin] = []
        try? FileManager.default.createDirectory(at: localCoresPath, withIntermediateDirectories: true)
        let contents = try? FileManager.default.contentsOfDirectory(at: localCoresPath, includingPropertiesForKeys: nil)
        for url in contents ?? [] where url.pathExtension == "dylib" {
            let coreID = url.deletingPathExtension().lastPathComponent
            if let plugin = registerCore(id: coreID, url: url) {
                plugins.append(plugin)
            }
        }
        cachedCores = plugins
        return plugins
    }
    
    private func registerCore(id: String, url: URL) -> OECorePlugin? {
        // Instantiate the ObjC Translator dynamically
        guard let translatorClass = NSClassFromString("OELibretroCoreTranslator") as? NSObject.Type else {
            print("Failed to find OELibretroCoreTranslator class in Objective-C runtime!")
            return nil
        }
        
        // We must mock OECorePlugin. OpenEmu expects a physical NSBundle with an Info.plist natively to parse capabilities. 
        // We generate a faux wrapper here dynamically around the `.dylib`.
        let fakeBundlePath = localCoresPath.appendingPathComponent("\(id).oecoreplugin")
        try? FileManager.default.createDirectory(at: fakeBundlePath, withIntermediateDirectories: true)
        
        let infoPlistPath = fakeBundlePath.appendingPathComponent("Info.plist")
        
        let prefix = id.components(separatedBy: "_").first ?? id
        let systemId = "openemu.system.\(prefix.lowercased())"
        
        let plist: [String: Any] = [
            "CFBundleIdentifier": id,
            "OEGameCoreClass": "OELibretroCoreTranslator", // The C-bridge class hooks in here!
            "OEGameCorePlayerCount": 4,
            "OELibretroCorePath": url.path, // Custom translation key so the bridge knows exactly what dylib to load via dlopen
            "OEGameCoreSystemIdentifiers": [systemId]
        ]
        (plist as NSDictionary).write(to: infoPlistPath, atomically: true)
        
        if let plugin = OECorePlugin.corePlugin(bundleAtURL: fakeBundlePath) {
            print("Successfully mocked OECorePlugin wrapper for \(id)")
            return plugin
        }
        
        return nil
    }
    
    @objc public func updateRegistry() {
        URLSession.shared.dataTask(with: remoteURL) { data, response, error in
            guard let data = data else { return }
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.parse()
        }.resume()
    }
    
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "core" {
            currentCoreID = attributeDict["id"] ?? ""
            currentCoreName = attributeDict["name"] ?? ""
            currentURL = ""
        }
    }
    
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "url" {
            currentURL += string
        }
    }
    
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "core" {
            parsedCores.append(["id": currentCoreID, "url": currentURL.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        if elementName == "cores" {
            downloadMissingCores()
        }
    }
    
    private func downloadMissingCores() {
        try? FileManager.default.createDirectory(at: localCoresPath, withIntermediateDirectories: true)
        
        for coreInfo in parsedCores {
            guard let id = coreInfo["id"], let urlString = coreInfo["url"], let url = URL(string: urlString) else { continue }
            
            // Check if we need to unzip
            let isZip = urlString.hasSuffix(".zip")
            let destinationURL = localCoresPath.appendingPathComponent("\(id).dylib")
            
            if !FileManager.default.fileExists(atPath: destinationURL.path) {
                print("Downloading missing libretro core: \(id) from \(urlString)")
                let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                    guard let tempURL = tempURL, error == nil else { return }
                    if isZip {
                        // Normally we would use SSZipArchive or NSTask to unzip
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                        process.arguments = ["-o", tempURL.path, "-d", self.localCoresPath.path]
                        try? process.run()
                        process.waitUntilExit()
                    } else {
                        try? FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    }
                    DispatchQueue.main.async { self.cachedCores = nil }
                }
                task.resume()
            }
        }
    }
}
