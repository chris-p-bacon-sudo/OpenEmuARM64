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
import SwiftUI
import OpenEmuKit

/// Entry point for the new SwiftUI-based OpenEmu UI.
///
/// Activated via launch argument: -OENewUI YES
///
/// Wraps OEHomeView in an NSHostingController and slots into the
/// existing window lifecycle. Game launching is delegated back to the
/// same OEGameDocument path used by the original UI — nothing in the
/// emulation stack changes.
final class OENewMainWindowController: NSWindowController {

    private var gameToLaunch: OEDBGame? {
        didSet { handleGameLaunch() }
    }

    // Binding bridge between SwiftUI and this controller
    private lazy var gameBinding = Binding<OEDBGame?>(
        get: { [weak self] in self?.gameToLaunch },
        set: { [weak self] game in
            self?.gameToLaunch = game
        }
    )

    private lazy var rootViewController: NSHostingController<OEHomeView> = {
        NSHostingController(rootView: OEHomeView(gameToLaunch: gameBinding))
    }()

    // MARK: - Lifecycle

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 960, height: 600)
        window.title = "OpenEmu"
        window.identifier = NSUserInterfaceItemIdentifier("OENewMainWindow")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(calibratedRed: 0.039, green: 0.039, blue: 0.047, alpha: 1)
        window.isMovableByWindowBackground = false
        window.center()

        self.init(window: window)

        // init(window:) does not trigger windowDidLoad — set up content here
        setUp()
    }

    private func setUp() {
        window?.contentViewController = rootViewController
        window?.delegate = self
        window?.styleMask.insert(.fullSizeContentView)
        window?.titlebarAppearsTransparent = true

        // Position traffic lights to vertically center with our 52pt nav bar
        positionTrafficLights()

        // Re-position after content is laid out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.positionTrafficLights()
        }

        if OELibraryDatabase.default != nil {
            OELibraryStore.shared.reload()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(libraryDidLoad),
            name: .libraryDidLoad,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositionTrafficLights),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    /// Centers the traffic light buttons in our 52pt nav bar rather than the
    /// default ~28pt AppKit title bar. This gives a visually balanced look
    /// where the dots, sidebar toggle, and nav pill are all on the same center line.
    @objc private func repositionTrafficLights() {
        positionTrafficLights()
    }

    private func positionTrafficLights() {
        guard let window = window,
              let contentView = window.contentView else { return }

        let navBarHeight: CGFloat = 52
        let viewHeight = contentView.bounds.height
        // In AppKit coordinates (origin bottom-left), the center of our nav bar is
        // at viewHeight - navBarHeight/2 from the bottom.
        let targetCenterY = viewHeight - navBarHeight / 2

        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for type in types {
            guard let btn = window.standardWindowButton(type) else { continue }
            var origin = btn.frame.origin
            origin.y = targetCenterY - btn.frame.height / 2
            btn.setFrameOrigin(origin)
        }
    }

    @objc private func libraryDidLoad() {
        Task { @MainActor in
            OELibraryStore.shared.reload()
        }
    }

    // MARK: - Game launching

    private func handleGameLaunch() {
        guard let game = gameToLaunch else { return }
        gameToLaunch = nil

        let defaults = UserDefaults.standard
        let openInSeparateWindow = defaults.bool(forKey: OEForcePopoutGameWindowKey)
        let fullScreen = defaults.bool(forKey: OEFullScreenGameWindowKey)

        let saveState = game.autosaveForLastPlayedRom

        NSDocumentController.shared.openGameDocument(
            with: game,
            display: openInSeparateWindow,
            fullScreen: fullScreen
        ) { [weak self] document, error in
            guard let self else { return }

            if let error {
                self.presentError(error, modalFor: self.window!, delegate: nil,
                                  didPresent: nil, contextInfo: nil)
                return
            }

            // If playing inline (not a separate window), show the game view
            if !openInSeparateWindow, let document {
                document.gameWindowController = self
            }
        }
    }
}

extension OENewMainWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        positionTrafficLights()
    }

    func windowDidResize(_ notification: Notification) {
        positionTrafficLights()
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - AppDelegate hook

extension OENewMainWindowController {
    /// Returns true when the new UI should be used.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-OENewUI")
    }
}
