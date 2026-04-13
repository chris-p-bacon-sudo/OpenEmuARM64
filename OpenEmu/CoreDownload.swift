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

final class CoreDownload: NSObject {
    
    weak var delegate: CoreDownloadDelegate?
    
    var name = ""
    var systemIdentifiers: [String] = []
    var systemNames: [String] = []
    var version = ""
    var bundleIdentifier = ""
    
    var hasUpdate = false
    var canBeInstalled = false
    
    private(set) var isDownloading = false
    @objc private(set) dynamic var progress: Double = 0
    
    var appcastItem: CoreAppcastItem?
    
    private var downloadSession: URLSession?
    
    convenience init(plugin: OECorePlugin) {
        self.init()
        updateProperties(with: plugin)
    }
    
    func start() {
        guard let appcastItem = appcastItem, !isDownloading else { return }
        
        assert(downloadSession == nil, "There shouldn't be a previous download session.")
        
        let downloadSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        downloadSession.sessionDescription = bundleIdentifier
        self.downloadSession = downloadSession
        
        let downloadTask = downloadSession.downloadTask(with: appcastItem.fileURL)
        
        DLog("Starting core download (\(downloadSession.sessionDescription ?? ""))")
        
        downloadTask.resume()
        
        isDownloading = true
        delegate?.coreDownloadDidStart(self)
    }
    
    func cancel() {
        DLog("Cancelling core download (\(downloadSession?.sessionDescription ?? ""))")
        downloadSession?.invalidateAndCancel()
    }
    
    private func updateProperties(with plugin: OECorePlugin) {
        name = plugin.displayName
        version = plugin.version
        hasUpdate = false
        canBeInstalled = false
        
        var systemNames: [String] = []
        for systemIdentifier in plugin.systemIdentifiers {
            if let plugin = OESystemPlugin.systemPlugin(forIdentifier: systemIdentifier) {
               let systemName = plugin.systemName
                systemNames.append(systemName)
            }
        }
        
        self.systemNames = systemNames
        systemIdentifiers = plugin.systemIdentifiers
        bundleIdentifier = plugin.bundleIdentifier
    }
}

extension CoreDownload: URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
        DLog("Core download (\(session.sessionDescription ?? "")) did complete: \(error?.localizedDescription ?? "no errors")")
        
        isDownloading = false
        progress = 0
        
        downloadSession?.finishTasksAndInvalidate()
        downloadSession = nil
        
        if let error = error {
            if let delegate = delegate,
               delegate.responds(to: #selector(CoreDownloadDelegate.coreDownloadDidFail(_:withError:))) {
                delegate.coreDownloadDidFail?(self, withError: error)
            } else {
                NSApplication.shared.presentError(error)
            }
        } else {
            delegate?.coreDownloadDidFinish(self)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        
        progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        DLog("Core download (\(session.sessionDescription ?? "")) did finish downloading temporary data.")
        
        let coresFolder = URL.oeApplicationSupportDirectory
            .appendingPathComponent("Cores", isDirectory: true)
        
        // Move the file to a temporary location we control, because 'location' is deleted when this method returns.
        let tempLocation = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".zip")
        do {
            try FileManager.default.moveItem(at: location, to: tempLocation)
        } catch {
            let error = NSError(domain: "OEErrorDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to move downloaded file to temporary location: \(error.localizedDescription)"])
            delegate?.coreDownloadDidFail?(self, withError: error)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                try? FileManager.default.removeItem(at: tempLocation)
                return
            }
            
            defer { try? FileManager.default.removeItem(at: tempLocation) }
            
            guard let fileName = ArchiveHelper.decompressFileInArchive(at: tempLocation, toDirectory: coresFolder) else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let error = NSError(domain: "OEErrorDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decompress core archive"])
                    self.delegate?.coreDownloadDidFail?(self, withError: error)
                }
                return
            }

            var fullPluginURL = coresFolder.appendingPathComponent(fileName)

            if fullPluginURL.pathExtension == "dylib" {
                let fauxPluginURL = coresFolder.appendingPathComponent("\(self.bundleIdentifier).oecoreplugin")
                do {
                    if FileManager.default.fileExists(atPath: fauxPluginURL.path) {
                        try FileManager.default.removeItem(at: fauxPluginURL)
                    }
                    try FileManager.default.createDirectory(at: fauxPluginURL, withIntermediateDirectories: true)
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        let error = NSError(domain: "OEErrorDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create plugin bundle directory: \(error.localizedDescription)"])
                        self.delegate?.coreDownloadDidFail?(self, withError: error)
                    }
                    return
                }

                // Move the extracted dylib into the bundle's root folder without executing NSBundle's rigid 'Contents/MacOS' layout.
                let dylibDestinationURL = fauxPluginURL.appendingPathComponent("libretro.dylib")
                do {
                    try FileManager.default.moveItem(at: fullPluginURL, to: dylibDestinationURL)
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        let error = NSError(domain: "OEErrorDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to move dylib into plugin bundle: \(error.localizedDescription)"])
                        self.delegate?.coreDownloadDidFail?(self, withError: error)
                    }
                    return
                }

                // Resolve system identifiers: prefer what CoreDownload already knows (populated by
                // OELibretroBuildbot.injectCoreDownloads), fall back to the static registry
                // using the ORIGINAL file name (e.g., snes9x_libretro.dylib).
                let originalDylibName = fileName
                let sysIDs: [String] = {
                    if !self.systemIdentifiers.isEmpty { return self.systemIdentifiers }
                    return OELibretroBuildbot.systemIdentifiers(forDylibFilename: originalDylibName)
                }()

                let versionString = self.appcastItem?.version ?? "1.0-Libretro"

                let plist: [String: Any] = [
                    "CFBundleName":                  self.bundleIdentifier,
                    "CFBundleIdentifier":            self.bundleIdentifier,
                    "CFBundleVersion":               versionString,
                    "CFBundleShortVersionString":    versionString,
                    "OEGameCoreClass":               "OELibretroCoreTranslator",
                    "OEGameCorePlayerCount":         4,
                    "OELibretroCorePath":            dylibDestinationURL.path,
                    "OESystemIdentifiers":           sysIDs
                ]

                let plistWriteSuccess = (plist as NSDictionary).write(to: fauxPluginURL.appendingPathComponent("Info.plist"), atomically: true)
                if !plistWriteSuccess {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        let error = NSError(domain: "OEErrorDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to write Info.plist for core plugin bundle"])
                        self.delegate?.coreDownloadDidFail?(self, withError: error)
                    }
                    return
                }
                fullPluginURL = fauxPluginURL
            }
            
            self.adHocSign(fullPluginURL)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                guard let plugin = OECorePlugin.corePlugin(bundleAtURL: fullPluginURL) else {
                    let error = NSError(domain: "OEErrorDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load core plugin after extraction"])
                    self.delegate?.coreDownloadDidFail?(self, withError: error)
                    return
                }
                
                DLog("Core (\(self.bundleIdentifier)) extracted and loaded.")
                
                if self.hasUpdate {
                    plugin.flushBundleCache()
                    self.version = plugin.version
                    self.hasUpdate = false
                    self.canBeInstalled = false
                }
                else if self.canBeInstalled {
                    self.updateProperties(with: plugin)
                }
            }
        }
    }
}

// MARK: - Signing

extension CoreDownload {

    /// Ad-hoc signs the plugin bundle so macOS 26+ will load it.
    /// Downloaded cores arrive unsigned; the OS refuses to dlopen them even
    /// with disable-library-validation unless they carry at least an ad-hoc signature.
    /// Ad-hoc signs the plugin bundle so macOS 26+ will load it.
    /// Downloaded cores arrive unsigned; the OS refuses to dlopen them even
    /// with disable-library-validation unless they carry at least an ad-hoc signature.
    private func adHocSign(_ bundleURL: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["--force", "--deep", "--sign", "-", bundleURL.path]

        let timeoutSeconds: TimeInterval = 30
        let semaphore = DispatchSemaphore(value: 0)
        
        task.terminationHandler = { _ in
            semaphore.signal()
        }

        do {
            try task.run()
            
            let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
            if waitResult == .timedOut {
                DLog("!!! [CoreDownload] codesign TIMED OUT for \(bundleURL.lastPathComponent). Terminating task.")
                task.terminate()
            } else {
                if task.terminationStatus != 0 {
                    DLog("!!! [CoreDownload] codesign FAILED with status \(task.terminationStatus) for \(bundleURL.lastPathComponent)")
                } else {
                    DLog("[CoreDownload] codesign SUCCESS for \(bundleURL.lastPathComponent)")
                }
            }
        } catch {
            DLog("!!! [CoreDownload] Failed to run codesign for \(bundleURL.lastPathComponent): \(error)")
            if task.isRunning {
                task.terminate()
            }
        }
    }
}

@objc protocol CoreDownloadDelegate: NSObjectProtocol {
    @objc func coreDownloadDidStart(_ download: CoreDownload)
    @objc func coreDownloadDidFinish(_ download: CoreDownload)
    @objc optional func coreDownloadDidFail(_ download: CoreDownload, withError error: Error?)
}
