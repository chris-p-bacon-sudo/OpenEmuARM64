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
import OpenEmuKit

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
    private let hardcoreDivider = NSBox()
    private let hardcoreCheckbox = NSButton(checkboxWithTitle: "Hardcore mode (recommended)", target: nil, action: nil)
    private let hardcoreSubtitle = NSTextField(wrappingLabelWithString: "")

    private let supportedDivider = NSBox()
    private let supportedLabel   = NSTextField(labelWithString: "")
    private let supportedGrid    = NSStackView()

    private var hardcoreObserver: Any?

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 468, height: 580))
        buildUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSavedCredentials()
        updateStatus()
        populateSupportedSystems()

        // Resync the checkbox when hardcore state is changed externally — most
        // importantly when the user cancels the reset prompt mid-session and
        // OEGameDocument rolls the preference back to false (#446).
        hardcoreObserver = NotificationCenter.default.addObserver(
            forName: .OERAHardcoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let enabled = (note.userInfo?[OEHardcoreEnabledKey] as? Bool)
                ?? UserDefaults.standard.bool(forKey: RAHardcoreEnabledKey)
            self?.hardcoreCheckbox.state = enabled ? .on : .off
        }
    }

    deinit {
        if let observer = hardcoreObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateStatus()
        // Cover the case where the preference was changed while this view
        // wasn't loaded (e.g. another controller wrote to UserDefaults). The
        // observer above handles in-session changes; this handles the gap.
        hardcoreCheckbox.state = UserDefaults.standard.bool(forKey: RAHardcoreEnabledKey) ? .on : .off
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

        hardcoreDivider.boxType = .separator
        hardcoreDivider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hardcoreDivider)

        hardcoreCheckbox.target = self
        hardcoreCheckbox.action = #selector(toggleHardcore(_:))
        hardcoreCheckbox.state = UserDefaults.standard.bool(forKey: RAHardcoreEnabledKey) ? .on : .off
        hardcoreCheckbox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hardcoreCheckbox)

        hardcoreSubtitle.stringValue = "Disables save state loading, rewind, frame advance, and cheats. Required for ranked achievements."
        hardcoreSubtitle.font = .systemFont(ofSize: 11)
        hardcoreSubtitle.textColor = .secondaryLabelColor
        hardcoreSubtitle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hardcoreSubtitle)

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

            hardcoreDivider.topAnchor.constraint(equalTo: registerLabel.bottomAnchor, constant: 24),
            hardcoreDivider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            hardcoreDivider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),
            hardcoreDivider.heightAnchor.constraint(equalToConstant: 1),

            hardcoreCheckbox.topAnchor.constraint(equalTo: hardcoreDivider.bottomAnchor, constant: 16),
            hardcoreCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            hardcoreCheckbox.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            hardcoreSubtitle.topAnchor.constraint(equalTo: hardcoreCheckbox.bottomAnchor, constant: 4),
            hardcoreSubtitle.leadingAnchor.constraint(equalTo: hardcoreCheckbox.leadingAnchor, constant: 20),
            hardcoreSubtitle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),
        ])

        // ── Supported Systems ────────────────────────────────────────────────
        supportedDivider.boxType = .separator
        supportedDivider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(supportedDivider)

        supportedLabel.stringValue = "Supported Systems"
        supportedLabel.font = .boldSystemFont(ofSize: 13)
        supportedLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(supportedLabel)

        supportedGrid.orientation = .vertical
        supportedGrid.alignment = .leading
        supportedGrid.spacing = 4
        supportedGrid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(supportedGrid)

        NSLayoutConstraint.activate([
            supportedDivider.topAnchor.constraint(equalTo: hardcoreSubtitle.bottomAnchor, constant: 24),
            supportedDivider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            supportedDivider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),
            supportedDivider.heightAnchor.constraint(equalToConstant: 1),

            supportedLabel.topAnchor.constraint(equalTo: supportedDivider.bottomAnchor, constant: 16),
            supportedLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            supportedLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            supportedGrid.topAnchor.constraint(equalTo: supportedLabel.bottomAnchor, constant: 12),
            supportedGrid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            supportedGrid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),
        ])
    }

    private func populateSupportedSystems() {
        var supportedIDs = Set<String>()
        for plugin in OECorePlugin.allPlugins {
            for sysID in plugin.systemIdentifiers {
                if plugin.supportsRetroAchievements(forSystemIdentifier: sysID) {
                    supportedIDs.insert(sysID)
                }
            }
        }

        let systems: [(name: String, icon: NSImage)] = supportedIDs
            .compactMap { id -> (String, NSImage)? in
                guard let sys = OESystemPlugin.systemPlugin(forIdentifier: id) else { return nil }
                var name = sys.systemName
                    .replacingOccurrences(of: #"\s*\([^)]+\)"#, with: "", options: .regularExpression)
                // OpenEmu models Game Boy and Game Boy Color as one system (openemu.system.gb);
                // Gambatte detects the cartridge type and earns GBC achievements. Show both.
                if id == "openemu.system.gb" { name = "Game Boy / Game Boy Color" }
                return (name, sys.systemIcon)
            }
            .sorted { $0.0 < $1.0 }

        let columns = 3
        for rowStart in stride(from: 0, to: systems.count, by: columns) {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = 8
            rowStack.distribution = .fillEqually
            rowStack.translatesAutoresizingMaskIntoConstraints = false

            for i in rowStart ..< min(rowStart + columns, systems.count) {
                let (name, icon) = systems[i]

                let imageView = NSImageView()
                imageView.image = icon
                imageView.imageScaling = .scaleProportionallyDown
                imageView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                ])

                let nameLabel = NSTextField(labelWithString: name)
                nameLabel.font = .systemFont(ofSize: 12)
                nameLabel.lineBreakMode = .byTruncatingTail
                nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                let cell = NSStackView(views: [imageView, nameLabel])
                cell.orientation = .horizontal
                cell.spacing = 6
                cell.alignment = .centerY
                cell.translatesAutoresizingMaskIntoConstraints = false

                rowStack.addArrangedSubview(cell)
            }
            // Pad partial last row so fillEqually keeps columns consistent
            if rowStart + columns > systems.count {
                for _ in systems.count ..< rowStart + columns {
                    rowStack.addArrangedSubview(NSView())
                }
            }
            supportedGrid.addArrangedSubview(rowStack)
        }
    }

    @objc private func toggleHardcore(_ sender: NSButton) {
        let enabled = (sender.state == .on)
        UserDefaults.standard.set(enabled, forKey: RAHardcoreEnabledKey)
        NotificationCenter.default.post(
            name: .OERAHardcoreDidChange,
            object: nil,
            userInfo: [OEHardcoreEnabledKey: enabled]
        )
    }

    // MARK: - Credential Management

    private func loadSavedCredentials() {
        usernameField.stringValue = UserDefaults.standard.string(forKey: "RAUsername") ?? ""
        if OECredentialStore.shared.has(.retroAchievementsToken) {
            passwordField.placeholderString = "••••••••  (saved)"
        }
    }

    private func updateStatus() {
        let username = UserDefaults.standard.string(forKey: "RAUsername") ?? ""
        let isSignedIn = !username.isEmpty && OECredentialStore.shared.has(.retroAchievementsToken)
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
                OECredentialStore.shared.set(token, forKey: .retroAchievementsToken)
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
        OECredentialStore.shared.remove(.retroAchievementsToken)
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

    var viewSize: NSSize { NSSize(width: 468, height: 580) }
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
