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

/// Cover Art preferences pane.
/// ScreenScraper has been replaced by IGDB (screenshots + cover fallback) and
/// SteamGridDB (hero art + icons) — no login required.
final class PrefScreenScraperController: NSViewController {

    private let headerLabel = NSTextField(labelWithString: "")
    private let descLabel   = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 468, height: 200))
        buildUI()
    }

    private func buildUI() {
        headerLabel.stringValue = "Cover Art"
        headerLabel.font = .boldSystemFont(ofSize: 15)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)

        descLabel.stringValue = "Cover art and screenshots are fetched automatically — no account or login required.\n\n• Box art: OpenVGDB (built-in database) → IGDB fallback\n• Hero backgrounds: SteamGridDB\n• Screenshots: IGDB\n• Last resort: libretro-thumbnails"
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descLabel)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            headerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            descLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
            descLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            descLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),
        ])
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

    var viewSize: NSSize { NSSize(width: 468, height: 200) }
}
