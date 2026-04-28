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

import Cocoa
import Security

// MARK: - Notification

extension Notification.Name {
    /// Posted on the main thread after a successful RA sign-in or sign-out.
    /// - `userInfo[RACredentialsTokenKey]`: `String` token (absent on sign-out)
    /// - `userInfo[RACredentialsUsernameKey]`: `String` username (absent on sign-out)
    static let OERACredentialsDidChange = Notification.Name("OERACredentialsDidChange")
}

let RACredentialsTokenKey    = "token"
let RACredentialsUsernameKey = "username"

// MARK: - Controller

/// Preferences pane for RetroAchievements account credentials.
final class PrefRetroAchievementsController: NSViewController {

    // MARK: - UI Elements

    private let headerLabel     = NSTextField(labelWithString: "")
    private let descLabel       = NSTextField(wrappingLabelWithString: "")
    private let usernameLabel   = NSTextField(labelWithString: "Username")
    private let usernameField   = NSTextField()
    private let passwordLabel   = NSTextField(labelWithString: "Password")
    private let passwordField   = NSSecureTextField()
    private let signInButton    = NSButton()
    private let signOutButton   = NSButton()
    private let statusLabel     = NSTextField(labelWithString: "")
    private let registerLabel   = NSTextField(labelWithString: "")

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 468, height: 300))
        buildUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSavedCredentials()
        updateStatus()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateStatus()
    }

    // MARK: - Build UI

    private func buildUI() {
        headerLabel.stringValue = "Achievements"
        headerLabel.font = .boldSystemFont(ofSize: 15)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)

        descLabel.stringValue = "Sign in to your RetroAchievements account to earn achievements while playing. Your password is used only to obtain a login token and is never stored on disk."
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descLabel)

        usernameLabel.font = .systemFont(ofSize: 13)
        usernameLabel.alignment = .right
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(usernameLabel)

        usernameField.placeholderString = "retroachievements.org username"
        usernameField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(usernameField)

        passwordLabel.font = .systemFont(ofSize: 13)
        passwordLabel.alignment = .right
        passwordLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordLabel)

        passwordField.placeholderString = "retroachievements.org password"
        passwordField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordField)

        signInButton.title = "Sign In"
        signInButton.bezelStyle = .rounded
        signInButton.controlSize = .regular
        signInButton.keyEquivalent = "\r"
        signInButton.target = self
        signInButton.action = #selector(signIn)
        signInButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(signInButton)

        signOutButton.title = "Sign Out"
        signOutButton.bezelStyle = .rounded
        signOutButton.controlSize = .regular
        signOutButton.target = self
        signOutButton.action = #selector(signOut)
        signOutButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(signOutButton)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        registerLabel.stringValue = "Register at retroachievements.org — it's free."
        registerLabel.font = .systemFont(ofSize: 11)
        registerLabel.textColor = .tertiaryLabelColor
        registerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(registerLabel)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            headerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            descLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 10),
            descLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            descLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            usernameLabel.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 28),
            usernameLabel.trailingAnchor.constraint(equalTo: view.leadingAnchor, constant: 156),
            usernameLabel.widthAnchor.constraint(equalToConstant: 80),

            usernameField.centerYAnchor.constraint(equalTo: usernameLabel.centerYAnchor),
            usernameField.leadingAnchor.constraint(equalTo: usernameLabel.trailingAnchor, constant: 8),
            usernameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            passwordLabel.topAnchor.constraint(equalTo: usernameField.bottomAnchor, constant: 12),
            passwordLabel.trailingAnchor.constraint(equalTo: usernameLabel.trailingAnchor),
            passwordLabel.widthAnchor.constraint(equalToConstant: 80),

            passwordField.centerYAnchor.constraint(equalTo: passwordLabel.centerYAnchor),
            passwordField.leadingAnchor.constraint(equalTo: passwordLabel.trailingAnchor, constant: 8),
            passwordField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            signInButton.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 20),
            signInButton.trailingAnchor.constraint(equalTo: passwordField.trailingAnchor),
            signInButton.widthAnchor.constraint(equalToConstant: 80),

            signOutButton.centerYAnchor.constraint(equalTo: signInButton.centerYAnchor),
            signOutButton.trailingAnchor.constraint(equalTo: signInButton.leadingAnchor, constant: -8),
            signOutButton.widthAnchor.constraint(equalToConstant: 80),

            statusLabel.topAnchor.constraint(equalTo: signInButton.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            registerLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            registerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            registerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),
        ])
    }

    // MARK: - Credential Management

    private func loadSavedCredentials() {
        usernameField.stringValue = UserDefaults.standard.string(forKey: "RAUsername") ?? ""
        if RetroAchievementsCredentials.hasStoredToken() {
            passwordField.placeholderString = "••••••••  (saved)"
        }
    }

    private func updateStatus() {
        let username = UserDefaults.standard.string(forKey: "RAUsername") ?? ""
        let isSignedIn = !username.isEmpty && RetroAchievementsCredentials.hasStoredToken()
        if isSignedIn {
            statusLabel.stringValue = "✓  Signed in as \(username)"
            statusLabel.textColor = NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)
            signInButton.isEnabled = false
            signOutButton.isEnabled = true
        } else {
            statusLabel.stringValue = "Not signed in — achievements will not be tracked."
            statusLabel.textColor = .secondaryLabelColor
            signInButton.isEnabled = true
            signOutButton.isEnabled = false
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        DispatchQueue.main.async {
            self.statusLabel.stringValue = message
            self.statusLabel.textColor = isError
                ? NSColor(red: 0.87, green: 0.20, blue: 0.18, alpha: 1)
                : NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)
            self.signInButton.isEnabled = true
        }
    }

    // MARK: - Actions

    @objc private func signIn() {
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
        let password = passwordField.stringValue

        guard !username.isEmpty else {
            setStatus("Username cannot be empty.", isError: true)
            return
        }
        guard !password.isEmpty else {
            setStatus("Password cannot be empty.", isError: true)
            return
        }

        signInButton.isEnabled = false
        statusLabel.stringValue = "Signing in…"
        statusLabel.textColor = .secondaryLabelColor

        RetroAchievementsAPI.login(username: username, password: password) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let token):
                RetroAchievementsCredentials.storeToken(token)
                UserDefaults.standard.set(username, forKey: "RAUsername")
                self.passwordField.stringValue = ""
                self.passwordField.placeholderString = "••••••••  (saved)"
                self.setStatus("✓  Signed in as \(username)", isError: false)
                self.signOutButton.isEnabled = true
                // Notify any running game sessions so they can log in mid-session
                NotificationCenter.default.post(
                    name: .OERACredentialsDidChange,
                    object: nil,
                    userInfo: [RACredentialsTokenKey: token, RACredentialsUsernameKey: username]
                )
            case .failure(let error):
                self.setStatus(error.localizedDescription, isError: true)
            }
        }
    }

    @objc private func signOut() {
        UserDefaults.standard.removeObject(forKey: "RAUsername")
        RetroAchievementsCredentials.deleteToken()
        usernameField.stringValue = ""
        passwordField.stringValue = ""
        passwordField.placeholderString = "retroachievements.org password"
        updateStatus()
        NotificationCenter.default.post(name: .OERACredentialsDidChange, object: nil)
    }
}

// MARK: - PreferencePane

extension PrefRetroAchievementsController: PreferencePane {

    var icon: NSImage? {
        if #available(macOS 11.0, *) {
            return NSImage(systemSymbolName: "trophy", accessibilityDescription: "Achievements")
        }
        return nil
    }

    var panelTitle: String { "Achievements" }

    var viewSize: NSSize { NSSize(width: 468, height: 300) }
}

// MARK: - Keychain Helper

/// Thin wrapper around SecItem for RetroAchievements token storage.
/// Stores the login token (not the password — the password is used only once to obtain the token).
enum RetroAchievementsCredentials {

    private static let service = "com.openemu.RetroAchievements"
    private static let account = "token"

    static func storedToken() -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData:  kCFBooleanTrue!,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func hasStoredToken() -> Bool {
        return storedToken() != nil
    }

    static func storeToken(_ token: String) {
        let deleteQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard let data = token.data(using: .utf8) else { return }
        let addQuery: [CFString: Any] = [
            kSecClass:          kSecClassGenericPassword,
            kSecAttrService:    service,
            kSecAttrAccount:    account,
            kSecValueData:      data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func deleteToken() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - RA API

private enum RetroAchievementsAPI {

    enum LoginError: LocalizedError {
        case networkError(Error)
        case invalidResponse
        case authFailed(String)

        var errorDescription: String? {
            switch self {
            case .networkError(let e): return "Network error: \(e.localizedDescription)"
            case .invalidResponse:     return "Unexpected response from RetroAchievements."
            case .authFailed(let msg): return msg
            }
        }
    }

    /// GET login credentials and return the RA token on success.
    static func login(username: String, password: String,
                      completion: @escaping (Result<String, LoginError>) -> Void) {
        var components = URLComponents(string: "https://retroachievements.org/dorequest.php")!
        components.queryItems = [
            URLQueryItem(name: "r", value: "login2"),
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "p", value: password),
        ]
        guard let url = components.url else {
            completion(.failure(.invalidResponse))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("OpenEmu-Silicon/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[RA] Network error: %@", error.localizedDescription)
                DispatchQueue.main.async { completion(.failure(.networkError(error))) }
                return
            }
            if let raw = data { NSLog("[RA] Raw response: %@", String(data: raw, encoding: .utf8) ?? "<non-utf8>") }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                DispatchQueue.main.async { completion(.failure(.invalidResponse)) }
                return
            }

            if let token = json["Token"] as? String, !token.isEmpty {
                DispatchQueue.main.async { completion(.success(token)) }
            } else {
                let message = (json["Error"] as? String) ?? "Login failed. Check username and password."
                NSLog("[RA] Auth failed: %@", message)
                DispatchQueue.main.async { completion(.failure(.authFailed(message))) }
            }
        }.resume()
    }
}
