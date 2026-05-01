// Copyright (c) 2021, OpenEmu Team
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

/// Background for the setup wizard.
///
/// Uses two assets:
///   - "setup_background": wide grid/nebula scene (no logo)
///   - "setup_logo":       transparent-background OpenEmu logo
final class SetupAssistantBackgroundView: NSView {

    private var bgLayer: CALayer?
    private var logoView: NSImageView?

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    override func layout() {
        super.layout()
        guard !bounds.isEmpty else { return }

        if bgLayer != nil {
            relayout()
        } else {
            setupLayers()
        }
    }

    private func relayout() {
        bgLayer?.frame = layer!.bounds
    }

    private func setupLayers() {
        guard let rootLayer = layer else { return }

        let bgImage = NSImage(named: "setup_background") ?? NSImage(named: "about_background")
        if let img = bgImage {
            let bg = CALayer()
            bg.frame = rootLayer.bounds
            bg.contentsGravity = .resizeAspectFill
            bg.contentsScale = 1
            bg.contents = img
            rootLayer.addSublayer(bg)
            bgLayer = bg
        }

        // NSImageView with AutoLayout — avoids coordinate-flip ambiguity
        if let logoImg = NSImage(named: "setup_logo") {
            let iv = NSImageView()
            iv.image = logoImg
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iv)
            logoView = iv

            NSLayoutConstraint.activate([
                iv.centerXAnchor.constraint(equalTo: centerXAnchor),
                iv.topAnchor.constraint(equalTo: topAnchor, constant: 28),
                iv.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.30),
                iv.heightAnchor.constraint(equalTo: iv.widthAnchor,
                                           multiplier: logoImg.size.height / logoImg.size.width),
            ])
        }
    }
}
