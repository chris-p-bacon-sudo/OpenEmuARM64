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

        // An empty unified toolbar makes the title bar area ~52pt tall and
        // AppKit automatically centers the traffic lights in it — no manual
        // button repositioning needed.
        setUpUnifiedToolbar()

        if OELibraryDatabase.default != nil {
            OELibraryStore.shared.reload()
        }

        // Force early initialization so it starts observing RA session notifications
        // before any game is launched — lazy init would miss sessions played before
        // the detail view is first opened.
        _ = OERetroAchievementsDataStore.shared

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(libraryDidLoad),
            name: .libraryDidLoad,
            object: nil
        )
    }

    private func setUpUnifiedToolbar() {
        let toolbar = NSToolbar(identifier: "OENewUI-Toolbar")
        toolbar.showsBaselineSeparator = false
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
        if #available(macOS 11.0, *) {
            window?.toolbarStyle = .unified
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

    func windowWillEnterFullScreen(_ notification: Notification) {
        // The unified toolbar shows a gray background in full screen — hide it.
        window?.toolbar?.isVisible = false
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        window?.toolbar?.isVisible = true
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - AppDelegate hook

extension OENewMainWindowController {
    /// Returns true when the new UI should be used.
    static var isEnabled: Bool { true }
}
