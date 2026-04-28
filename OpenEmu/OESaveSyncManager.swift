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
import Security
import Network
import os.log

private let log = OSLog(subsystem: "org.openemu.OpenEmuARM64", category: "SaveSync")

// MARK: - Sync Status

/// Represents the current state of the Save Sync Manager.
@objc
enum OESyncStatus: Int {
    case idle        // No sync running.
    case connecting  // Authenticating with Google Drive.
    case syncing     // Uploading or downloading.
    case success     // Last sync completed successfully.
    case failed      // Last sync failed.
}

// MARK: - Delegate

/// Implement this protocol to receive sync status updates (e.g., for UI).
@objc
protocol OESaveSyncManagerDelegate: AnyObject {
    func saveSyncManager(_ manager: OESaveSyncManager, didChangeStatus status: OESyncStatus, message: String?)
}

// MARK: - OESaveSyncManager

/// Singleton that manages cloud synchronisation of OpenEmu saves (battery saves + save states)
/// with Google Drive using the hidden App Data folder.
///
/// ## Lifecycle
/// Call `startMonitoring()` once the library database has loaded.
/// Call `checkForNewerCloudSave(...)` just before a game launches.
/// The manager uploads changed local files automatically via FSEventStream.
@objc
final class OESaveSyncManager: NSObject {
    
    // MARK: - Singleton
    
    @objc static let shared = OESaveSyncManager()
    
    // MARK: - Delegate
    
    @objc weak var delegate: OESaveSyncManagerDelegate?
    
    // MARK: - State
    
    @objc private(set) var syncStatus: OESyncStatus = .idle {
        didSet {
            guard syncStatus != oldValue else { return }
            DispatchQueue.main.async {
                self.delegate?.saveSyncManager(self, didChangeStatus: self.syncStatus, message: self.syncStatusMessage)
                NotificationCenter.default.post(name: .OESaveSyncStatusDidChange, object: self)
            }
        }
    }
    
    @objc private(set) var syncStatusMessage: String? = nil
    
    /// `true` when the user has successfully signed in to Google Drive.
    @objc var isSignedIn: Bool { accessToken != nil }
    
    // MARK: - OAuth Tokens
    
    private var accessToken: String?
    private var refreshToken: String? {
        get { keychainRead(account: "refreshToken") }
        set { keychainWrite(value: newValue, account: "refreshToken") }
    }
    private var tokenExpiryDate: Date?
    
    // MARK: - FSEventStream
    
    private var eventStream: FSEventStreamRef?
    private var monitoredURLs: [URL] = []
    
    // MARK: - OAuth Listener
    
    private var oauthListener: NWListener?
    
    // MARK: - Background Sync
    
    private var backgroundTimer: Timer?
    
    /// The date and time when the last successful sync operation completed.
    @objc private(set) var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "OELastSaveSyncDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "OELastSaveSyncDate") }
    }
    
    // MARK: - URLSession
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()
    
    // MARK: - Init
    
    private override init() {
        super.init()
    }
    
    // MARK: - Monitoring
    
    /// Begin watching the Battery Saves and Save States directories for all installed cores.
    /// Call once after the library database has loaded.
    @objc func startMonitoring() {
        let supportDir = URL.oeApplicationSupportDirectory
        
        // Save States folder (managed by OELibraryDatabase)
        let saveStatesURL = supportDir.appendingPathComponent("Save States", isDirectory: true)
        
        // Battery Saves live under each core's plugin support folder.
        // e.g. ~/Library/Application Support/OpenEmu/mGBA/Battery Saves
        var urls: [URL] = [saveStatesURL]
        
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: supportDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for dir in contents {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
                if isDir.boolValue {
                    let batterySaves = dir.appendingPathComponent("Battery Saves", isDirectory: true)
                    if FileManager.default.fileExists(atPath: batterySaves.path) {
                        urls.append(batterySaves)
                    }
                }
            }
        }
        
        monitoredURLs = urls
        startFSEventStream(for: urls)
        os_log(.info, log: log, "Save Sync Manager started monitoring %d directories.", urls.count)
        
        startBackgroundTimer()
    }
    
    /// Stop watching all directories (call on app termination or sign-out).
    @objc func stopMonitoring() {
        stopBackgroundTimer()
        
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
        os_log(.info, log: log, "Save Sync Manager stopped monitoring.")
    }
    
    // MARK: - FSEventStream Setup
    
    private func startFSEventStream(for directories: [URL]) {
        stopMonitoring()
        
        let paths = directories.map { $0.path } as CFArray
        let latency: CFTimeInterval = 2.0 // seconds to coalesce events
        
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil, release: nil, copyDescription: nil
        )
        
        let callback: FSEventStreamCallback = { _, callbackInfo, numEvents, eventPaths, _, _ in
            guard let info = callbackInfo else { return }
            let manager = Unmanaged<OESaveSyncManager>.fromOpaque(info).takeUnretainedValue()
            
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            let changedURLs = paths.prefix(numEvents).map { URL(fileURLWithPath: $0) }
            manager.handleFileSystemEvents(at: Array(changedURLs))
        }
        
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            os_log(.error, log: log, "Failed to create FSEventStream.")
            return
        }
        
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue as CFString)
        FSEventStreamStart(stream)
        eventStream = stream
    }
    
    private func handleFileSystemEvents(at urls: [URL]) {
        // Debounce: only upload relevant file types.
        let relevantExtensions: Set<String> = ["sav", "srm", "oesavestate", "state", "rtc", "eep", "nv"]
        let changed = urls.filter { relevantExtensions.contains($0.pathExtension.lowercased()) }
        guard !changed.isEmpty else { return }
        
        os_log(.debug, log: log, "FSEvent: %d relevant file(s) changed, scheduling upload.", changed.count)
        
        for url in changed {
            Task { await self.uploadFile(at: url) }
        }
    }
    
    // MARK: - Background Timer
    
    private func startBackgroundTimer() {
        stopBackgroundTimer()
        
        let interval = OEGoogleDriveConfig.backgroundSyncInterval
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.performFullSyncCheck()
        }
        os_log(.debug, log: log, "Background sync timer started (interval: %.0fs).", interval)
    }
    
    private func stopBackgroundTimer() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
    }
    
    /// Manually triggers a check for all currently monitored folders to see if anything needs uploading or downloading.
    @objc func performFullSyncCheck() {
        guard isSignedIn else { return }
        
        os_log(.info, log: log, "Performing full background sync check...")
        
        // In a real implementation, we might want to iterate over recent games.
        // For now, we rely on FSEvents for uploads, and pre-launch checks for downloads.
        // We can however check if any local files are newer than cloud and haven't been uploaded.
    }
    
    // MARK: - Pre-launch Sync Check
    
    /// Check whether a newer version of the save for the given game exists in the cloud.
    ///
    /// - Parameters:
    ///   - systemIdentifier: e.g. "openemu.system.gba"
    ///   - gameName: Display name of the game.
    ///   - completion: Called on the main thread with `shouldSync: true` if the cloud has a newer file.
    @objc func checkForNewerCloudSave(
        systemIdentifier: String,
        gameName: String,
        completion: @escaping (_ shouldSync: Bool, _ cloudModifiedDate: Date?) -> Void
    ) {
        guard isSignedIn else {
            completion(false, nil)
            return
        }
        
        let cloudPath = standardizedCloudPath(system: systemIdentifier, gameName: gameName)
        
        Task {
            do {
                // Refresh token if necessary before any API call.
                try await ensureValidAccessToken()
                
                let remoteFiles = try await listFiles(inFolder: OEGoogleDriveConfig.appDataFolderName, namePrefix: cloudPath)
                
                // Find the most recently modified remote file.
                let latestRemote = remoteFiles.max { a, b in
                    (a.modifiedTime ?? .distantPast) < (b.modifiedTime ?? .distantPast)
                }
                
                guard let remote = latestRemote, let remoteDate = remote.modifiedTime else {
                    await MainActor.run { completion(false, nil) }
                    return
                }
                
                // Compare with the local file modification date.
                let localModified = localModifiedDate(system: systemIdentifier, gameName: gameName)
                let isCloudNewer = remoteDate > (localModified ?? .distantPast)
                
                os_log(.debug, log: log,
                       "Sync check for '%@': cloud=%@, local=%@, cloudNewer=%d",
                       gameName,
                       remoteDate.description,
                       localModified?.description ?? "none",
                       isCloudNewer)
                
                await MainActor.run { completion(isCloudNewer, remoteDate) }
            } catch {
                os_log(.error, log: log, "Sync pre-launch check failed: %@", error.localizedDescription)
                await MainActor.run { completion(false, nil) }
            }
        }
    }
    
    /// Download the cloud save for the given game into the local Battery Saves / Save States folder.
    @objc func downloadCloudSave(
        systemIdentifier: String,
        gameName: String,
        completion: @escaping (_ success: Bool, _ error: Error?) -> Void
    ) {
        guard isSignedIn else {
            completion(false, OESaveSyncError.notSignedIn)
            return
        }
        
        setStatus(.syncing, message: "Downloading '\(gameName)' from cloud…")
        
        let cloudPath = standardizedCloudPath(system: systemIdentifier, gameName: gameName)
        
        Task {
            do {
                try await ensureValidAccessToken()
                
                let files = try await listFiles(inFolder: OEGoogleDriveConfig.appDataFolderName, namePrefix: cloudPath)
                
                for file in files {
                    guard let fileId = file.id, let fileName = file.name else { continue }
                    let data = try await downloadFile(fileId: fileId)
                    let destination = localSaveURL(forCloudFileName: fileName, system: systemIdentifier, gameName: gameName)
                    try data.write(to: destination, options: .atomic)
                    os_log(.info, log: log, "Downloaded cloud save: %@", fileName)
                }
                
                lastSyncDate = Date()
                setStatus(.success, message: "'\(gameName)' save synced from cloud.")
                await MainActor.run { completion(true, nil) }
            } catch {
                setStatus(.failed, message: "Download failed: \(error.localizedDescription)")
                await MainActor.run { completion(false, error) }
            }
        }
    }
    
    // MARK: - Upload
    
    func uploadFile(at localURL: URL) async {
        guard isSignedIn else { return }
        
        do {
            try await ensureValidAccessToken()
            
            let data = try Data(contentsOf: localURL)
            let cloudName = cloudFileName(for: localURL)
            
            setStatus(.syncing, message: "Uploading \(localURL.lastPathComponent)…")
            
            // Check if a file with this name already exists in Drive (for update vs. create).
            let existing = try await listFiles(inFolder: OEGoogleDriveConfig.appDataFolderName, namePrefix: cloudName)
            
            if let existingFile = existing.first(where: { $0.name == cloudName }), let fileId = existingFile.id {
                try await updateFile(fileId: fileId, data: data, mimeType: mimeType(for: localURL))
                os_log(.debug, log: log, "Updated cloud save: %@", cloudName)
            } else {
                try await createFile(name: cloudName, data: data, mimeType: mimeType(for: localURL))
                os_log(.debug, log: log, "Created cloud save: %@", cloudName)
            }
            
            lastSyncDate = Date()
            setStatus(.success, message: "Uploaded \(localURL.lastPathComponent).")
        } catch {
            os_log(.error, log: log, "Upload failed for %@: %@", localURL.lastPathComponent, error.localizedDescription)
            setStatus(.failed, message: "Upload failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - File Name Helpers
    
    /// Converts a local URL into a standardized cloud path: `[System]/[GameName].[ext]`
    private func cloudFileName(for localURL: URL) -> String {
        // The local path already follows the structure:
        // .../Battery Saves/<game>.sav  => we store as  SystemId/<game>.sav
        // .../Save States/<System>/<ROM>/<state>.oesavestate => SystemId/<ROM>/<state>.oesavestate
        // We embed systemId by walking the path up past known folder names.
        let pathComponents = localURL.pathComponents
        
        if let batteryIndex = pathComponents.firstIndex(of: "Battery Saves") {
            // Parent of "Battery Saves" is the plugin folder (e.g. "mGBA")
            let plugin = batteryIndex > 0 ? pathComponents[batteryIndex - 1] : "Unknown"
            let remaining = pathComponents[(batteryIndex + 1)...].joined(separator: "/")
            return "\(plugin)/\(remaining)"
        }
        if let statesIndex = pathComponents.firstIndex(of: "Save States") {
            let remaining = pathComponents[(statesIndex + 1)...].joined(separator: "/")
            return "SaveStates/\(remaining)"
        }
        return localURL.lastPathComponent
    }
    
    /// Returns the prefix used for cloud files belonging to a specific game.
    private func standardizedCloudPath(system: String, gameName: String) -> String {
        // Strip "openemu.system." prefix if present for a shorter folder name.
        let systemShort = system.replacingOccurrences(of: "openemu.system.", with: "")
        let safeName = gameName.replacingOccurrences(of: "/", with: "_")
        return "\(systemShort)/\(safeName)"
    }
    
    /// Returns the local file modification date for an entire game's save directory.
    private func localModifiedDate(system: String, gameName: String) -> Date? {
        let supportDir = URL.oeApplicationSupportDirectory
        
        // Check Battery Saves across all core plugins.
        var dates: [Date] = []
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: supportDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) {
            for coreDir in contents {
                let batterySaves = coreDir
                    .appendingPathComponent("Battery Saves")
                    .appendingPathComponent("\(gameName).sav")
                if let attrs = try? FileManager.default.attributesOfItem(atPath: batterySaves.path),
                   let date = attrs[.modificationDate] as? Date {
                    dates.append(date)
                }
            }
        }
        
        // Check Save States.
        let systemShort = system.replacingOccurrences(of: "openemu.system.", with: "")
        let stateDir = supportDir
            .appendingPathComponent("Save States")
            .appendingPathComponent(systemShort)
            .appendingPathComponent(gameName)
        
        if let stateFiles = try? FileManager.default.contentsOfDirectory(
            at: stateDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles
        ) {
            for f in stateFiles {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: f.path),
                   let date = attrs[.modificationDate] as? Date {
                    dates.append(date)
                }
            }
        }
        
        return dates.max()
    }
    
    /// Maps a cloud file name back to the local save URL.
    private func localSaveURL(forCloudFileName cloudName: String, system: String, gameName: String) -> URL {
        let supportDir: URL = URL.oeApplicationSupportDirectory

        
        let ext = (cloudName as NSString).pathExtension.lowercased()
        
        if ext == "sav" || ext == "srm" || ext == "rtc" || ext == "eep" || ext == "nv" {
            // Battery save — put under the first matching core's Battery Saves folder.
            let systemShort = system.replacingOccurrences(of: "openemu.system.", with: "")
            let fileName = (cloudName as NSString).lastPathComponent
            let destination = supportDir
                .appendingPathComponent(systemShort)
                .appendingPathComponent("Battery Saves")
                .appendingPathComponent(fileName)
            try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            return destination
        } else {
            // Save state — put under Save States/<systemShort>/<gameName>/
            let systemShort = system.replacingOccurrences(of: "openemu.system.", with: "")
            let stateDir = supportDir
                .appendingPathComponent("Save States")
                .appendingPathComponent(systemShort)
                .appendingPathComponent(gameName)
            try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
            return stateDir.appendingPathComponent((cloudName as NSString).lastPathComponent)
        }
    }
    
    private func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "oesavestate": return "application/octet-stream"
        case "sav", "srm":  return "application/octet-stream"
        default:            return "application/octet-stream"
        }
    }
    
    // MARK: - Status Helper
    
    private func setStatus(_ status: OESyncStatus, message: String?) {
        syncStatusMessage = message
        syncStatus = status
    }
    
    // MARK: - Authentication
    
    /// Starts the Google OAuth2 flow by opening the system browser.
    @objc func signIn() {
        startOAuthListener { [weak self] code, redirectURI in
            guard let self = self, let code = code, let redirectURI = redirectURI else { return }
            
            Task {
                do {
                    try await self.exchangeCodeForTokens(code: code, redirectURI: redirectURI)
                    self.setStatus(.idle, message: "Signed in to Google Drive.")
                    os_log(.info, log: log, "OAuth sign-in successful.")
                } catch {
                    self.setStatus(.failed, message: "Sign-in failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func startOAuthListener(completion: @escaping (String?, String?) -> Void) {
        do {
            let listener = try NWListener(using: .tcp, on: .any)
            self.oauthListener = listener

            // Capture the assigned port when the listener becomes ready so we can pass
            // the exact same redirect URI in both the auth request and the token exchange.
            // listener.port is reliable here; by the time newConnectionHandler fires and
            // the listener is cancelled, it may already be nil.
            var capturedRedirectURI: String = OEGoogleDriveConfig.redirectURI

            listener.stateUpdateHandler = { state in
                if case .ready = state, let port = listener.port {
                    capturedRedirectURI = "http://127.0.0.1:\(port.rawValue)"
                    self.openAuthPage(with: capturedRedirectURI)
                }
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: .main)
                self.receiveOAuthRequest(on: connection) { code in
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 43\r\n\r\nSign-in successful! You can close this tab."
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
                        connection.cancel()
                        listener.cancel()
                        // Use the URI captured at listener-ready time, not listener.port
                        // (which may be nil after cancel()).
                        completion(code, capturedRedirectURI)
                    }))
                }
            }

            listener.start(queue: .main)
        } catch {
            os_log(.error, log: log, "Failed to start OAuth listener: %{public}@", error.localizedDescription)
            completion(nil, nil)
        }
    }
    
    private func receiveOAuthRequest(on connection: NWConnection, completion: @escaping (String?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
            guard let data = data, let request = String(data: data, encoding: .utf8) else {
                completion(nil)
                return
            }
            
            if let range = request.range(of: "code=([^&\\s]+)", options: .regularExpression) {
                let code = String(request[range].dropFirst(5))
                completion(code)
            } else {
                completion(nil)
            }
        }
    }
    
    private func openAuthPage(with redirectURI: String) {
        var components = URLComponents(string: OEGoogleDriveConfig.authorizationEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id",     value: OEGoogleDriveConfig.clientID),
            URLQueryItem(name: "redirect_uri",  value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope",         value: OEGoogleDriveConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type",   value: "offline"),
            URLQueryItem(name: "prompt",         value: "consent"),
        ]
        guard let url = components.url else { return }
        
        setStatus(.connecting, message: "Opening sign-in page…")
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Signs the user out and clears all stored credentials.
    @objc func signOut() {
        accessToken   = nil
        tokenExpiryDate = nil
        refreshToken  = nil   // clears from keychain
        setStatus(.idle, message: nil)
        os_log(.info, log: log, "Signed out of Google Drive.")
    }
    
    /// Call this from `AppDelegate` or a URL handler when the app receives the OAuth redirect.
    @objc func handleOAuthRedirect(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            setStatus(.failed, message: "OAuth redirect missing authorization code.")
            return
        }
        
        Task {
            do {
                try await exchangeCodeForTokens(code: code, redirectURI: OEGoogleDriveConfig.redirectURI)
                setStatus(.idle, message: "Signed in to Google Drive.")
                os_log(.info, log: log, "OAuth sign-in successful.")
            } catch {
                setStatus(.failed, message: "Sign-in failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Token Exchange
    
    private func exchangeCodeForTokens(code: String, redirectURI: String) async throws {
        var request = URLRequest(url: URL(string: OEGoogleDriveConfig.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "code":          code,
            "client_id":     OEGoogleDriveConfig.clientID,
            "client_secret": OEGoogleDriveConfig.clientSecret,
            "redirect_uri":  redirectURI,
            "grant_type":    "authorization_code",
        ]
        request.httpBody = urlEncode(body).data(using: .utf8)
        
        let (data, _) = try await session.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        guard let access = json["access_token"] as? String else {
            throw OESaveSyncError.tokenExchangeFailed
        }
        accessToken = access
        
        if let refresh = json["refresh_token"] as? String {
            refreshToken = refresh
        }
        if let expiry = json["expires_in"] as? TimeInterval {
            tokenExpiryDate = Date().addingTimeInterval(expiry - 60) // 60s buffer
        }
    }
    
    private func ensureValidAccessToken() async throws {
        if let expiry = tokenExpiryDate, expiry > Date(), accessToken != nil {
            return  // Token is still valid.
        }
        guard let refresh = refreshToken else {
            throw OESaveSyncError.notSignedIn
        }
        try await refreshAccessToken(using: refresh)
    }
    
    private func refreshAccessToken(using refreshToken: String) async throws {
        var request = URLRequest(url: URL(string: OEGoogleDriveConfig.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "refresh_token": refreshToken,
            "client_id":     OEGoogleDriveConfig.clientID,
            "client_secret": OEGoogleDriveConfig.clientSecret,
            "grant_type":    "refresh_token",
        ]
        request.httpBody = urlEncode(body).data(using: .utf8)
        
        let (data, _) = try await session.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        guard let access = json["access_token"] as? String else {
            self.refreshToken = nil  // Token revoked — force re-auth.
            throw OESaveSyncError.tokenRefreshFailed
        }
        accessToken = access
        if let expiry = json["expires_in"] as? TimeInterval {
            tokenExpiryDate = Date().addingTimeInterval(expiry - 60)
        }
    }
    
    // MARK: - Google Drive API
    
    public struct DriveFile {
        public var id: String?
        public var name: String?
        public var modifiedTime: Date?
    }
    
    
    /// Returns a list of all files currently stored in the Google Drive appDataFolder.
    public func fetchCloudFileList() async throws -> [DriveFile] {
        try await ensureValidAccessToken()
        let files = try await listFiles(inFolder: OEGoogleDriveConfig.appDataFolderName)
        os_log(.info, log: log, "Fetched %d files from appDataFolder", files.count)
        return files
    }
    
    private func listFiles(inFolder folder: String, namePrefix: String? = nil) async throws -> [DriveFile] {
        var q = "'\(folder)' in parents and trashed = false"
        if let prefix = namePrefix {
            // Escape single quotes in the name.
            let safe = prefix.replacingOccurrences(of: "'", with: "\\'")
            q += " and name contains '\(safe)'"
        }
        
        var components = URLComponents(string: "\(OEGoogleDriveConfig.driveAPIBaseURL)/files")!
        components.queryItems = [
            URLQueryItem(name: "spaces",  value: "appDataFolder"),
            URLQueryItem(name: "fields",  value: "files(id,name,modifiedTime)"),
            URLQueryItem(name: "q",       value: q),
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, context: "listFiles")
        
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let files = (json["files"] as? [[String: Any]]) ?? []
        
        let isoFormatter = ISO8601DateFormatter()
        
        return files.compactMap { dict -> DriveFile? in
            var file = DriveFile()
            file.id   = dict["id"]   as? String
            file.name = dict["name"] as? String
            if let ts = dict["modifiedTime"] as? String {
                file.modifiedTime = isoFormatter.date(from: ts)
            }
            return file
        }
    }
    
    private func downloadFile(fileId: String) async throws -> Data {
        let url = URL(string: "\(OEGoogleDriveConfig.driveAPIBaseURL)/files/\(fileId)?alt=media")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, context: "downloadFile")
        return data
    }
    
    private func createFile(name: String, data: Data, mimeType: String) async throws {
        // Multipart upload: metadata + binary data.
        let boundary = "oebound-\(UUID().uuidString)"
        
        var body = Data()
        let metadata = ["name": name, "parents": [OEGoogleDriveConfig.appDataFolderName]] as [String: Any]
        let metaData = try JSONSerialization.data(withJSONObject: metadata)
        
        body.append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metaData)
        body.append("\r\n--\(boundary)\r\nContent-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--".data(using: .utf8)!)
        
        let url = URL(string: "\(OEGoogleDriveConfig.uploadAPIBaseURL)/files?uploadType=multipart")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        
        let (responseData, response) = try await session.data(for: request)
        try validateResponse(response, data: responseData, context: "createFile")
    }
    
    private func updateFile(fileId: String, data: Data, mimeType: String) async throws {
        let url = URL(string: "\(OEGoogleDriveConfig.uploadAPIBaseURL)/files/\(fileId)?uploadType=media")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        let (responseData, response) = try await session.data(for: request)
        try validateResponse(response, data: responseData, context: "updateFile")
    }
    
    // MARK: - Response Validation
    
    private func validateResponse(_ response: URLResponse, data: Data, context: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            os_log(.error, log: log, "[%@] HTTP %d: %@", context, http.statusCode, body)
            throw OESaveSyncError.apiError(statusCode: http.statusCode, body: body)
        }
    }
    
    // MARK: - Keychain Helpers
    
    private func keychainWrite(value: String?, account: String) {
        let service = OEGoogleDriveConfig.keychainService
        
        // Delete existing entry first.
        let deleteQuery: [CFString: Any] = [
            kSecClass:   kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        guard let value = value, let data = value.data(using: .utf8) else { return }
        
        let addQuery: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account,
            kSecValueData:    data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            os_log(.error, log: log, "Keychain write failed for '%@': %d", account, status)
        }
    }
    
    private func keychainRead(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: OEGoogleDriveConfig.keychainService,
            kSecAttrAccount: account,
            kSecReturnData:  kCFBooleanTrue!,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Utilities
    
    private func urlEncode(_ params: [String: String]) -> String {
        params.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted on the main thread whenever the sync status changes.
    static let OESaveSyncStatusDidChange = Notification.Name("OESaveSyncStatusDidChangeNotification")
}

// MARK: - Errors

enum OESaveSyncError: LocalizedError {
    case notSignedIn
    case tokenExchangeFailed
    case tokenRefreshFailed
    case apiError(statusCode: Int, body: String)
    
    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to Google Drive. Please sign in via Preferences."
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for tokens."
        case .tokenRefreshFailed:
            return "Access token expired and could not be refreshed. Please sign in again."
        case .apiError(let code, let body):
            return "Google Drive API error (HTTP \(code)): \(body)"
        }
    }
}

