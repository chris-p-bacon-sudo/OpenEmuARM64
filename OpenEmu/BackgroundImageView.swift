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

/// Modern frosted-glass panel used as content cards in the setup assistant.
/// Replaces the old nine-part stretched image approach with a system-native
/// NSVisualEffectView embedded in a layer-backed container.
final class BackgroundImageView: NSView {

    // Kept for XIB compatibility — no longer used for drawing
    @IBInspectable var background: NSImage?
    @IBInspectable var image: NSImage?

    private var didSetup = false

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        let fx = NSVisualEffectView()
        fx.material = .hudWindow
        fx.blendingMode = .withinWindow
        fx.state = .active
        fx.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fx, positioned: .below, relativeTo: nil)

        NSLayoutConstraint.activate([
            fx.leadingAnchor.constraint(equalTo: leadingAnchor),
            fx.trailingAnchor.constraint(equalTo: trailingAnchor),
            fx.topAnchor.constraint(equalTo: topAnchor),
            fx.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
