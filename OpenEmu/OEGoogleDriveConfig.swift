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

import Foundation

/// Configuration for the Google Drive Save Sync integration.
enum OEGoogleDriveConfig {
    
    // MARK: - OAuth Credentials
    
    // TODO: Inject real credentials before Cloud Sync can function.
    // Strategy options: (a) CI secret → OEGoogleDriveSecrets.swift at build time,
    //                   (b) runtime user-provided credentials in Preferences.
    // See: OEGoogleDriveSecrets.template.swift for the secrets-file pattern.
    // Tracked in: https://github.com/nickybmon/OpenEmu-Silicon/issues/129
    /// Your Google API OAuth 2.0 Client ID.
    static let clientID     = "YOUR_CLIENT_ID_HERE"
    
    /// Your Google API OAuth 2.0 Client Secret.
    static let clientSecret = "YOUR_CLIENT_SECRET_HERE"
    
    // MARK: - OAuth Endpoints
    
    static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenEndpoint         = "https://oauth2.googleapis.com/token"
    static let redirectURI           = "http://127.0.0.1"
    
    // MARK: - API Scopes
    
    /// Requests access to the hidden App Data folder only.
    static let scopes = ["https://www.googleapis.com/auth/drive.appdata"]
    
    // MARK: - API Endpoints
    
    static let driveAPIBaseURL   = "https://www.googleapis.com/drive/v3"
    static let uploadAPIBaseURL  = "https://www.googleapis.com/upload/drive/v3"
    
    // MARK: - App Data Folder
    
    static let appDataFolderName = "appDataFolder"
    
    // MARK: - Keychain
    
    static let keychainService = "com.openemu.GoogleDriveSaveSync"
    
    // MARK: - Sync Settings
    
    /// How long (in seconds) between automated background sync checks when a game is running.
    static let backgroundSyncInterval: TimeInterval = 300  // 5 minutes
    
    /// Maximum file size (in bytes) to upload in a single request (5 MB).
    static let singleUploadMaxBytes: Int = 5 * 1024 * 1024
}
