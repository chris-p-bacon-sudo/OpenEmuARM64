// Copyright (c) 2020, OpenEmu Team
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

/// Layer-backed button that renders clearly over the dark onboarding background.
/// Primary buttons (keyEquivalent = Return) use the system accent colour.
/// Secondary buttons use a subtle white-tinted pill.
final class GlossButton: NSButton {

    @IBInspectable var color: String?

    override func awakeFromNib() {
        super.awakeFromNib()
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        refreshAppearance()
    }

    private func refreshAppearance() {
        let isPrimary = keyEquivalent == "\r"
        let bg: NSColor = isPrimary ? .controlAccentColor : NSColor(white: 1, alpha: 0.20)
        layer?.backgroundColor = bg.cgColor

        let weight: NSFont.Weight = isPrimary ? .semibold : .regular
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: weight),
        ]
        attributedTitle = NSAttributedString(string: title, attributes: attrs)
    }

    override var isHighlighted: Bool {
        didSet { layer?.opacity = isHighlighted ? 0.7 : 1.0 }
    }

    override var isEnabled: Bool {
        didSet {
            layer?.opacity = isEnabled ? 1.0 : 0.4
            refreshAppearance()
        }
    }

    // Re-apply when the system accent colour changes
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }
}
