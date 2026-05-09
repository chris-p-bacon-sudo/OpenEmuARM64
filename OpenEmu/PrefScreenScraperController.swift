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

/// Preferences pane for ScreenScraper cover art credentials.
final class PrefScreenScraperController: NSViewController {

    // MARK: - UI Elements

    private let headerLabel     = NSTextField(labelWithString: "")
    private let descLabel       = NSTextField(wrappingLabelWithString: "")
    private let usernameLabel   = NSTextField(labelWithString: "Username")
    private let usernameField   = NSTextField()
    private let passwordLabel   = NSTextField(labelWithString: "Password")
    private let passwordField   = NSSecureTextField()
    private let saveButton      = NSButton()
    private let clearButton     = NSButton()
    private let statusLabel     = NSTextField(labelWithString: "")
    private let registerLabel   = NSTextField(labelWithString: "")

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 468, height: 360))
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
        // Header
        headerLabel.stringValue = "Cover Art"
        headerLabel.font = .boldSystemFont(ofSize: 15)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)

        // Description
        descLabel.stringValue = "OpenEmu looks up cover art in three places: first the built-in OpenVGDB database, then ScreenScraper (if you're signed in below), and finally libretro-thumbnails as a last resort. Signing in to ScreenScraper gives the best coverage — registration is free."
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descLabel)

        // Username label + field
        usernameLabel.font = .systemFont(ofSize: 13)
        usernameLabel.alignment = .right
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(usernameLabel)

        usernameField.placeholderString = "screenscraper.fr username"
        usernameField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(usernameField)

        // Password label + field
        passwordLabel.font = .systemFont(ofSize: 13)
        passwordLabel.alignment = .right
        passwordLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordLabel)

        passwordField.placeholderString = "screenscraper.fr password"
        passwordField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordField)

        // Save button
        saveButton.title = "Save"
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .regular
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(saveCredentials)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(saveButton)

        // Clear button
        clearButton.title = "Clear"
        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .regular
        clearButton.target = self
        clearButton.action = #selector(clearCredentials)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(clearButton)

        // Status
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // Register link
        registerLabel.stringValue = "Register at screenscraper.fr — it's free."
        registerLabel.font = .systemFont(ofSize: 11)
        registerLabel.textColor = .tertiaryLabelColor
        registerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(registerLabel)

        // Layout
        NSLayoutConstraint.activate([
            // Header
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            headerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            // Description
            descLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 10),
            descLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            descLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            // Username row
            usernameLabel.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 28),
            usernameLabel.trailingAnchor.constraint(equalTo: view.leadingAnchor, constant: 156),
            usernameLabel.widthAnchor.constraint(equalToConstant: 80),

            usernameField.centerYAnchor.constraint(equalTo: usernameLabel.centerYAnchor),
            usernameField.leadingAnchor.constraint(equalTo: usernameLabel.trailingAnchor, constant: 8),
            usernameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            // Password row
            passwordLabel.topAnchor.constraint(equalTo: usernameField.bottomAnchor, constant: 12),
            passwordLabel.trailingAnchor.constraint(equalTo: usernameLabel.trailingAnchor),
            passwordLabel.widthAnchor.constraint(equalToConstant: 80),

            passwordField.centerYAnchor.constraint(equalTo: passwordLabel.centerYAnchor),
            passwordField.leadingAnchor.constraint(equalTo: passwordLabel.trailingAnchor, constant: 8),
            passwordField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            // Buttons
            saveButton.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 20),
            saveButton.trailingAnchor.constraint(equalTo: passwordField.trailingAnchor),
            saveButton.widthAnchor.constraint(equalToConstant: 80),

            clearButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            clearButton.widthAnchor.constraint(equalToConstant: 80),

            // Status
            statusLabel.topAnchor.constraint(equalTo: saveButton.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            // Register link
            registerLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            registerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            registerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),
        ])
    }

    // MARK: - Credential Management

    private func loadSavedCredentials() {
        usernameField.stringValue = UserDefaults.standard.string(forKey: "ScreenScraperUsername") ?? ""
        // Password is stored encrypted — show placeholder only, don't pre-fill for security
        if OECredentialStore.shared.has(.screenScraperPassword) {
            passwordField.placeholderString = "••••••••  (saved)"
        }
    }

    private func updateStatus() {
        let username = UserDefaults.standard.string(forKey: "ScreenScraperUsername") ?? ""
        let isSignedIn = !username.isEmpty && OECredentialStore.shared.has(.screenScraperPassword)

        if isSignedIn {
            Task { @MainActor in
                if let fetchError = ScreenScraperClient.shared.lastFetchError,
                   let description = fetchError.errorDescription {
                    // A previous game lookup failed — surface the error so the user knows.
                    self.statusLabel.stringValue = description
                    self.statusLabel.textColor = NSColor(red: 0.87, green: 0.20, blue: 0.18, alpha: 1)
                } else if ScreenScraperClient.shared.hasVerifiedCredentials {
                    self.statusLabel.stringValue = "✓  Signed in as \(username)"
                    self.statusLabel.textColor = NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)
                } else {
                    // Credentials are stored but haven't been verified this session yet.
                    // Silently verify in the background so the pane shows the correct state
                    // without the user needing to hit Save.
                    self.statusLabel.stringValue = "Verifying…"
                    self.statusLabel.textColor = .secondaryLabelColor
                    self.silentlyVerify(username: username)
                }
            }
        } else {
            statusLabel.stringValue = "Not signed in — ScreenScraper will be skipped. OpenVGDB and libretro-thumbnails are still active."
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    // MARK: - Actions

    /// Called on pane load when credentials exist but haven't been confirmed this session.
    /// Fires a lightweight API call in the background and updates the status label with the result.
    private func silentlyVerify(username: String) {
        guard let password = OECredentialStore.shared.get(.screenScraperPassword) else { return }
        Task { @MainActor in
            do {
                let ok = try await ScreenScraperClient.shared.verifyCredentials(username: username, password: password)
                if ok {
                    ScreenScraperClient.shared.clearLastFetchError()
                    self.statusLabel.stringValue = "✓  Signed in as \(username)"
                    self.statusLabel.textColor = NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)
                } else {
                    self.statusLabel.stringValue = "ScreenScraper rejected these credentials. Re-enter your password and save."
                    self.statusLabel.textColor = NSColor(red: 0.87, green: 0.20, blue: 0.18, alpha: 1)
                }
            } catch {
                // Network unavailable — don't show an error for a background check, just go neutral.
                self.statusLabel.stringValue = "Could not reach ScreenScraper — check your connection."
                self.statusLabel.textColor = .secondaryLabelColor
            }
        }
    }

    @objc private func saveCredentials() {
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
        let password = passwordField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !username.isEmpty else {
            statusLabel.stringValue = "Username cannot be empty."
            statusLabel.textColor = NSColor(red: 0.87, green: 0.20, blue: 0.18, alpha: 1)
            return
        }
        guard !password.isEmpty else {
            statusLabel.stringValue = "Password cannot be empty."
            statusLabel.textColor = NSColor(red: 0.87, green: 0.20, blue: 0.18, alpha: 1)
            return
        }

        UserDefaults.standard.set(username, forKey: "ScreenScraperUsername")
        OECredentialStore.shared.set(password, forKey: .screenScraperPassword)
        passwordField.stringValue = ""
        passwordField.placeholderString = "••••••••  (saved)"

        saveButton.isEnabled = false
        clearButton.isEnabled = false
        statusLabel.stringValue = "Verifying credentials…"
        statusLabel.textColor = .secondaryLabelColor

        Task { @MainActor in
            do {
                let ok = try await ScreenScraperClient.shared.verifyCredentials(username: username, password: password)
                if ok {
                    // Clear any prior fetch error so the pane reflects the fresh verification.
                    ScreenScraperClient.shared.clearLastFetchError()
                    statusLabel.stringValue = "✓  Signed in as \(username)"
                    statusLabel.textColor = NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)
                } else {
                    statusLabel.stringValue = "ScreenScraper rejected these credentials. Check your username and password."
                    statusLabel.textColor = NSColor(red: 0.87, green: 0.20, blue: 0.18, alpha: 1)
                }
            } catch {
                statusLabel.stringValue = "Could not reach ScreenScraper — check your connection."
                statusLabel.textColor = NSColor(red: 0.87, green: 0.20, blue: 0.18, alpha: 1)
            }
            saveButton.isEnabled = true
            clearButton.isEnabled = true
        }
    }

    @objc private func clearCredentials() {
        UserDefaults.standard.removeObject(forKey: "ScreenScraperUsername")
        OECredentialStore.shared.remove(.screenScraperPassword)
        usernameField.stringValue = ""
        passwordField.stringValue = ""
        passwordField.placeholderString = "screenscraper.fr password"
        updateStatus()
    }
}

// MARK: - PreferencePane

extension PrefScreenScraperController: PreferencePane {

    var icon: NSImage? {
        if #available(macOS 11.0, *) {
            return NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Cover Art")
        }
        return NSImage(named: NSImage.slideshowTemplateName)
    }

    var panelTitle: String { "Cover Art" }

    var viewSize: NSSize { NSSize(width: 468, height: 360) }
}


