/*
 Copyright (c) 2026, OpenEmu Team

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Cocoa
import Sentry

enum SentryService {

    private static let dsn = "https://387777a8153aae33cb514deea3601946@o4511164820815872.ingest.us.sentry.io/4511164891529216"

    // UserDefaults keys
    private static let consentKey    = "OESentryCrashReportingEnabled"
    private static let hasPromptedKey = "OESentryCrashReportingPrompted"

    /// Call once at the top of applicationDidFinishLaunching.
    /// On first launch, shows a consent prompt. On subsequent launches,
    /// starts Sentry automatically if the user previously opted in.
    static func configureIfNeeded() {
        let defaults = UserDefaults.standard

        if !defaults.bool(forKey: hasPromptedKey) {
            showConsentPrompt()
            return
        }

        if defaults.bool(forKey: consentKey) {
            start()
        }
    }

    // MARK: - Game Context

    /// Attaches game/system/core info to every subsequent crash report.
    /// Call after a game document is fully set up (system plugin + core plugin resolved).
    static func setGameContext(gameName: String, systemIdentifier: String, coreIdentifier: String) {
        SentrySDK.configureScope { scope in
            scope.setContext(value: [
                "game": gameName,
                "system": systemIdentifier,
                "core": coreIdentifier,
            ], key: "emulation")
        }
    }

    /// Clears game context when emulation ends so stale info doesn't attach to future crashes.
    static func clearGameContext() {
        SentrySDK.configureScope { scope in
            scope.removeContext(key: "emulation")
        }
    }

    /// Records a breadcrumb — a timestamped event visible in the crash report trail.
    static func addBreadcrumb(message: String, category: String, level: SentryLevel = .info) {
        let crumb = Breadcrumb()
        crumb.message = message
        crumb.category = category
        crumb.level = level
        SentrySDK.addBreadcrumb(crumb)
    }

    // MARK: - Private

    private static func showConsentPrompt() {
        let alert = NSAlert()
        alert.messageText = "Help Improve OpenEmu"
        alert.informativeText = "Would you like to automatically send crash reports when OpenEmu crashes? This helps the team find and fix bugs faster.\n\nNo personal data, game files, or save data is ever included."
        alert.addButton(withTitle: "Send Crash Reports")
        alert.addButton(withTitle: "Don't Send")
        alert.alertStyle = .informational

        guard let window = NSApp.mainWindow ?? NSApp.keyWindow else {
            persistConsent(alert.runModal() == .alertFirstButtonReturn)
            return
        }

        alert.beginSheetModal(for: window) { response in
            persistConsent(response == .alertFirstButtonReturn)
        }
    }

    private static func persistConsent(_ opted: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(opted, forKey: consentKey)
        defaults.set(true,  forKey: hasPromptedKey)
        if opted { start() }
    }

    private static func start() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        SentrySDK.start { options in
            options.dsn         = dsn
            options.debug       = false
            options.releaseName = "openemu-silicon@\(version)+\(build)"
            options.environment = "production"
            options.tracesSampleRate = 0   // crash reports only — no performance tracing
        }
    }
}
