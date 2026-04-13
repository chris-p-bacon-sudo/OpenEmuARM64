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
import OpenEmuKit
import Sparkle.SUStandardVersionComparator
import OSLog

final class CoreUpdater: NSObject {
    
    enum Errors: Error {
        case noDownloadableCoreForIdentifierError
        case newCoreCheckAlreadyPendingError
    }
    
    static let shared = CoreUpdater()
    
    @objc dynamic private(set) var coreList: [CoreDownload] = []
    
    var completionHandler: ((_ plugin: OECorePlugin?, Error?) -> Void)?
    var coreIdentifier: String?
    var alert: OEAlert?
    var coreDownload: CoreDownload?
    
    private var coresDict: [String : CoreDownload] = [:]
    private var autoInstall = false
    private var lastCoreListURLTask: URLSessionDataTask?
    private var pendingUserInitiatedDownloads: Set<CoreDownload> = []
    
    // Backup directory
    private var coresDirectory: URL {
        let paths = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
        let appSupportDir = URL(fileURLWithPath: paths.first!).appendingPathComponent("OpenEmu")
        return appSupportDir.appendingPathComponent("Cores")
    }
    
    override init() {
        super.init()
        cleanObsoleteLibretroCores()
        syncInstalledCores()
    }
    
    private func cleanObsoleteLibretroCores() {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: coresDirectory, includingPropertiesForKeys: nil) else { return }
        
        for url in contents {
            let pathExtension = url.pathExtension.lowercased()
            
            // 1. Clean obsolete bundles
            if pathExtension == "oecoreplugin" {
                guard let bundle = Bundle(url: url),
                      let info = bundle.infoDictionary,
                      let coreClass = info["OEGameCoreClass"] as? String,
                      coreClass == "OELibretroCoreTranslator"
                else { continue }
                
                let bundleID = bundle.bundleIdentifier ?? ""
                if !bundleID.hasPrefix("org.openemu.libretro.") {
                    if #available(macOS 11.0, *) {
                        Logger.download.info("Deleting obsolete libretro bundle: \(bundleID)")
                    }
                    try? fileManager.removeItem(at: url)
                }
            }
            // 2. Clean loose dylibs that block synthesis
            else if pathExtension == "dylib" {
                if #available(macOS 11.0, *) {
                    Logger.download.info("Deleting loose libretro dylib: \(url.lastPathComponent)")
                }
                try? fileManager.removeItem(at: url)
            }
        }
    }
    
    private func syncInstalledCores() {
        for plugin in OECorePlugin.allPlugins {
            let bundleID = plugin.bundleIdentifier.lowercased()

            let download = coresDict[bundleID] ?? CoreDownload(plugin: plugin)

            // Prioritize the Libretro Buildbot for all supported cores to reach the
            // "Plug and Play" goal, bypassing legacy Sparkle appcasts.
            if let buildbotCore = OELibretroBuildbot.core(forBundleIdentifier: bundleID) {
                download.appcastItem = CoreAppcastItem(
                    url:          buildbotCore.downloadURL,
                    version:      "Nightly",
                    minOSVersion: "11.0"
                )
                // Patch system identifiers for cores installed before the plist key was
                // corrected to OESystemIdentifiers (old installs used OEGameCoreSystemIdentifiers).
                if download.systemIdentifiers.isEmpty {
                    download.systemIdentifiers = buildbotCore.systemIdentifiers
                }
            }

            download.delegate = self
            coresDict[bundleID] = download
        }
        updateCoreList()
    }
    
    private func updateCoreList() {
        willChangeValue(forKey: #keyPath(coreList))
        coreList = coresDict.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        didChangeValue(forKey: #keyPath(coreList))
    }
    
    
    func checkForNewCores(completionHandler handler: ((_ error: Error?) -> Void)? = nil) {
        // Inject libretro buildbot cores for any system not already covered by an
        // installed plugin.  This runs synchronously on the main queue before any
        // network fetch so the "Missing Core" alert can show immediately.
        OELibretroBuildbot.injectCoreDownloads(into: &coresDict, delegate: self)
        updateCoreList()
        
        let buildbotCores = coresDict.values.filter { $0.appcastItem?.version == "Nightly" || $0.appcastItem?.version.hasPrefix("202") == true }
        let group = DispatchGroup()
        
        for download in buildbotCores {
            guard let url = download.appcastItem?.fileURL else { continue }
            group.enter()
            
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            
            let task = URLSession.shared.dataTask(with: request) { _, response, _ in
                defer { group.leave() }
                
                if let httpResponse = response as? HTTPURLResponse,
                   let lastModified = httpResponse.allHeaderFields["Last-Modified"] as? String {
                    
                    // Parse "Wed, 21 Oct 2026 07:28:00 GMT" to a clean short version
                    let formatter = DateFormatter()
                    formatter.dateFormat = "E, d MMM yyyy HH:mm:ss Z"
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    
                    var newVersion = "Nightly"
                    if let date = formatter.date(from: lastModified) {
                        let outFormatter = DateFormatter()
                        outFormatter.dateFormat = "yyyy-MM-dd"
                        newVersion = outFormatter.string(from: date)
                    }
                    
                    DispatchQueue.main.async {
                        download.appcastItem?.version = newVersion
                        if download.version != "" && download.version != "1.0-Libretro" && download.version != newVersion {
                            download.hasUpdate = true
                        }
                    }
                }
            }
            task.resume()
        }
        
        group.notify(queue: .main) {
            self.updateCoreList()
            handler?(nil)
        }
    }
    
    func cancelCheckForNewCores() {
        lastCoreListURLTask?.cancel()
        lastCoreListURLTask = nil
    }
    
    // MARK: - Installing with OEAlert
    
    func installCore(for game: OEDBGame, withCompletionHandler handler: @escaping (_ plugin: OECorePlugin?, _ error: Error?) -> Void) {

        // Force immediate injection of buildbot cores to ensure the downloader always
        // has a source for "Missing Core" prompts even before background polling finishes.
        OELibretroBuildbot.injectCoreDownloads(into: &coresDict, delegate: self)
        updateCoreList()

        let systemIdentifier = game.system?.systemIdentifier ?? ""
        var validPlugins = coreList.filter { $0.systemIdentifiers.contains(systemIdentifier) }
        
        if !validPlugins.isEmpty {
            let download: CoreDownload
            
            if validPlugins.count == 1 {
                download = validPlugins.first!
            } else {
                // Sort by core name alphabetically to match our automatic core picker behavior
                validPlugins.sort {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                
                // Check if a core is set as default in AppDelegate
                var defaultCore: CoreDownload?
                let key = "defaultCore.\(systemIdentifier)"
                if let defaultCoreID = UserDefaults.standard.string(forKey: key) {
                    defaultCore = validPlugins.first(where: { defaultCoreID.caseInsensitiveCompare($0.bundleIdentifier) == .orderedSame })
                }
                
                // Use default core plugin for this system, otherwise just use first found from the sorted list
                if let defaultCore {
                    download = defaultCore
                } else {
                    download = validPlugins.first!
                }
            }
            
            let coreName = download.name
            let message = String(format: NSLocalizedString("OpenEmu uses 'Cores' to emulate games. You need the %@ Core to play %@", comment: ""), coreName, game.displayName)
            installCore(with: download, message: message, completionHandler: handler)
        }
        else {
            handler(nil, Errors.noDownloadableCoreForIdentifierError)
        }
    }
    
    func installCore(for state: OEDBSaveState, withCompletionHandler handler: @escaping (_ plugin: OECorePlugin?, _ error: Error?) -> Void) {
        
        // Ensure the buildbot registry is injected so we can resolve cores for save states
        // even if they aren't currently installed or known to the legacy updater.
        OELibretroBuildbot.injectCoreDownloads(into: &coresDict, delegate: self)
        updateCoreList()
        
        let coreID = state.coreIdentifier.lowercased()
        if let download = coresDict[coreID] {
            let coreName = download.name
            let message = String(format: NSLocalizedString("To launch the save state %@ you will need to install the '%@' Core", comment: ""), state.displayName, coreName)
            installCore(with: download, message: message, completionHandler: handler)
        } else {
            // TODO: create proper error saying that no core is available for the state
            handler(nil, Errors.noDownloadableCoreForIdentifierError)
        }
    }
    
    func installCore(with download: CoreDownload, message: String, completionHandler handler: @escaping (_ plugin: OECorePlugin?, _ error: Error?) -> Void) {
        
        let alert = OEAlert()
        alert.messageText = NSLocalizedString("Missing Core", comment: "")
        alert.informativeText = message
        alert.defaultButtonTitle = NSLocalizedString("Install", comment: "")
        alert.alternateButtonTitle = NSLocalizedString("Cancel", comment: "")
        alert.setDefaultButtonAction(#selector(startInstall), andTarget: self)
        
        coreIdentifier = coresDict.first(where: { $1 == download })?.key
        completionHandler = handler
        
        self.alert = alert
        
        if alert.runModal() == .alertSecondButtonReturn {
            handler(nil, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        }
        
        completionHandler = nil
        coreDownload = nil
        coreIdentifier = nil
        
        self.alert = nil
    }
    
    func installCore(with download: CoreDownload, completionHandler handler: @escaping (_ plugin: OECorePlugin?, _ error: Error?) -> Void) {
        
        let alert = OEAlert()
        
        coreIdentifier = coresDict.first(where: { $1 == download })?.key
        completionHandler = handler
        self.alert = alert
        
        alert.performBlockInModalSession {
            self.startInstall()
        }
        alert.runModal()
        
        completionHandler = nil
        coreDownload = nil
        coreIdentifier = nil
        
        self.alert = nil
    }
    
    // MARK: -
    
    func backupCore(bundleID: String) {
        let fileManager = FileManager.default
        let coreURL = coresDirectory.appendingPathComponent("\(bundleID).oecoreplugin")
        let backupURL = coresDirectory.appendingPathComponent("\(bundleID).oecoreplugin.bak")
        
        // Remove existing backup if any
        try? fileManager.removeItem(at: backupURL)
        
        // Copy current core to backup if it exists
        if fileManager.fileExists(atPath: coreURL.path) {
            do {
                try fileManager.copyItem(at: coreURL, to: backupURL)
                if #available(macOS 11.0, *) {
                    Logger.download.info("Backed up core \(bundleID) to \(backupURL.lastPathComponent)")
                }
            } catch {
                if #available(macOS 11.0, *) {
                    Logger.download.error("Failed to backup core \(bundleID): \(error.localizedDescription)")
                }
            }
        }
    }
    
    func revertCore(bundleID: String, completionHandler: @escaping (Error?) -> Void) {
        let fileManager = FileManager.default
        let coreURL = coresDirectory.appendingPathComponent("\(bundleID).oecoreplugin")
        let backupURL = coresDirectory.appendingPathComponent("\(bundleID).oecoreplugin.bak")
        
        guard fileManager.fileExists(atPath: backupURL.path) else {
            completionHandler(NSError(domain: "OpenEmu", code: 404, userInfo: [NSLocalizedDescriptionKey: "No backup found"]))
            return
        }
        
        do {
            try? fileManager.removeItem(at: coreURL)
            try fileManager.moveItem(at: backupURL, to: coreURL)
            completionHandler(nil)
            
            // Allow re-updating
            if let download = coresDict[bundleID.lowercased()] {
                download.hasUpdate = true
                updateCoreList()
            }
            
        } catch {
            completionHandler(error)
        }
    }
    
    func hasBackup(bundleID: String) -> Bool {
        let backupURL = coresDirectory.appendingPathComponent("\(bundleID).oecoreplugin.bak")
        return FileManager.default.fileExists(atPath: backupURL.path)
    }

    @objc func cancelInstall() {
        coreDownload?.cancel()
        completionHandler = nil
        coreDownload = nil
        alert?.close(withResult: .alertSecondButtonReturn)
        alert = nil
        coreIdentifier = nil
    }
    
    @objc func startInstall() {
        alert?.messageText = NSLocalizedString("Downloading and Installing Core…", comment: "")
        alert?.informativeText = ""
        alert?.defaultButtonTitle = ""
        alert?.setAlternateButtonAction(#selector(cancelInstall), andTarget: self)
        alert?.showsProgressbar = true
        alert?.progress = 0
        
        guard
            let coreID = coreIdentifier,
            let pluginDL = coresDict[coreID]
        else {
            alert?.messageText = NSLocalizedString("Error!", comment: "")
            alert?.informativeText = NSLocalizedString("The core could not be downloaded. Try installing it from the Cores preferences.", comment: "")
            alert?.defaultButtonTitle = NSLocalizedString("OK", comment: "")
            alert?.alternateButtonTitle = ""
            alert?.setDefaultButtonAction(#selector(OEAlert.buttonAction(_:)), andTarget: alert)
            alert?.showsProgressbar = false
            
            return
        }
        
        coreDownload = pluginDL
        
        // Backup before updating
        if coreDownload?.hasUpdate == true {
             if let bundleID = coreDownload?.bundleIdentifier {
                 backupCore(bundleID: bundleID)
             }
        }
        
        coreDownload?.start()
    }
    
    func failInstallWithError(_ error: Error?) {
        alert?.close(withResult: .alertFirstButtonReturn)
        
        completionHandler?(OECorePlugin.corePlugin(bundleIdentifier: coreIdentifier!), error)
        
        alert = nil
        coreIdentifier = nil
        completionHandler = nil
    }
    
    func finishInstall() {
        alert?.close(withResult: .alertFirstButtonReturn)
        
        let startTime = Date()
        
        // Use a polling mechanism to resolve any remaining race conditions.
        // We check every 0.1s for the plugin; once found, we trigger the game start.
        // We cap this at 3 seconds to avoid indefinite hanging.
        func pollForPlugin() {
            guard let coreID = self.coreIdentifier else { return }
            
            // Force invalidation of the dynamic core cache so the plugin manager
            // can pick up the newly extracted dylib immediately.
            OECoreSyncManager.shared.invalidateCache()
            
            if let plugin = OECorePlugin.corePlugin(bundleIdentifier: coreID) {
                self.completionHandler?(plugin, nil)
                self.alert = nil
                self.coreIdentifier = nil
                self.completionHandler = nil
            } else if Date().timeIntervalSince(startTime) < 3.0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: pollForPlugin)
            } else {
                // Time's up; trigger with nil so the document can try its own fallback
                // or show the error.
                self.completionHandler?(nil, nil)
                self.alert = nil
                self.coreIdentifier = nil
                self.completionHandler = nil
            }
        }
        
        pollForPlugin()
    }
    
    // MARK: - Other user-initiated (= with error reporting) downloads
    
    func installCoreInBackgroundUserInitiated(_ download: CoreDownload) {
        assert(download.delegate === self, "download \(download)'s delegate is not the singleton CoreUpdater!?")
        
        pendingUserInitiatedDownloads.insert(download)
        
        download.start()
    }
}

// MARK: - CoreDownload Delegate

private var CoreDownloadProgressContext = 0

extension CoreUpdater: CoreDownloadDelegate {
    
    func coreDownloadDidStart(_ download: CoreDownload) {
        updateCoreList()
        
        download.addObserver(self, forKeyPath: #keyPath(CoreDownload.progress), options: [.new, .old, .initial, .prior], context: &CoreDownloadProgressContext)
    }
    
    func coreDownloadDidFinish(_ download: CoreDownload) {
        // Manually update the dictionary for this core immediately to ensure
        // the UI reflects the "Installed" state even if common plugin scanning is late.
        let key = download.bundleIdentifier.lowercased()
        coresDict[key] = download
        
        syncInstalledCores()
        
        download.removeObserver(self, forKeyPath: #keyPath(CoreDownload.progress), context: &CoreDownloadProgressContext)
        
        if download == coreDownload {
            finishInstall()
        }
        
        pendingUserInitiatedDownloads.remove(download)
    }
    
    func coreDownloadDidFail(_ download: CoreDownload, withError error: Error?) {
        updateCoreList()
        
        if download == coreDownload {
            failInstallWithError(error)
        }
        
        if pendingUserInitiatedDownloads.contains(download),
           let error = error {
            NSApp.presentError(error)
        }
        
        pendingUserInitiatedDownloads.remove(download)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        guard context == &CoreDownloadProgressContext else {
            return super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
        
        if let object = object as? CoreDownload,
           object == coreDownload {
            alert?.progress = coreDownload!.progress
        }
    }
}

extension CoreUpdater {
    
    private func updaterDidFindValidUpdate(for plugin: OECorePlugin, item: CoreAppcastItem) {
        
        let coreID = plugin.bundleIdentifier.lowercased()
        let download = coresDict[coreID]
        download?.hasUpdate = true
        download?.appcastItem = item
        download?.delegate = self
        
        if autoInstall {
            download?.start()
        }
        
        updateCoreList()
    }
}

private final class CoreAppcast {
    
    let url: URL
    var items: [CoreAppcastItem] = []
    
    init(url: URL) {
        self.url = url
    }
    
    func fetch(completionHandler handler: (() -> Void)? = nil) {
        let url = url
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            defer { handler?() }
            
            guard let data else { return }
            
            do {
                self.items = try self.process(data: data)
            } catch { 
                if #available(macOS 11.0, *) {
                    Logger.download.error("Failed to process data for \(url, privacy: .public): \(error, privacy: .public)")
                }
            }
        }
        
        task.resume()
    }
    
    private func process(data: Data) throws -> [CoreAppcastItem] {
        let appcast = try XMLDocument(data: data, options: [])
        let items = try appcast.nodes(forXPath: "/rss/channel/item") as! [XMLElement]
        return items.compactMap { item in
            if let enclosure = item.elements(forName: "enclosure").first,
               let fileURL = enclosure.attribute(forName: "url")?.stringValue,
               let url = URL(string: fileURL),
               let version = enclosure.attribute(forName: "sparkle:version")?.stringValue,
               let minOSVersion = item.elements(forName: "sparkle:minimumSystemVersion").first?.stringValue
            {
                let pubDateString = item.elements(forName: "pubDate").first?.stringValue
                return .init(url: url, version: version, minOSVersion: minOSVersion, pubDate: pubDateString)
            } else {
                return nil
            }
        }
    }
}

struct CoreAppcastItem {
    
    var version: String
    var fileURL: URL
    var minimumSystemVersion: String
    var pubDate: Date?
    
    init(url: URL, version: String, minOSVersion: String, pubDate: String? = nil) {
        fileURL = url
        self.version = version
        minimumSystemVersion = minOSVersion
        if let pubDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "E, d MMM yyyy HH:mm:ss Z"
            self.pubDate = formatter.date(from: pubDate)
        }
    }
    
    var isSupported: Bool {
        return SUStandardVersionComparator.default.compareVersion(minimumSystemVersion, toVersion: Self.osVersionString) != .orderedDescending
    }
    
    private static let osVersionString: String = {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        return "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
    }()
}
