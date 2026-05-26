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

import SwiftUI

/// Design tokens derived from the Paper designs.
/// All values are from the Direction A (Faithful) artboard.
enum OEColors {
    static let background    = Color(hex: 0x0a0a0c)
    static let surface       = Color.white.opacity(0.06)
    static let surfaceHover  = Color.white.opacity(0.1)
    static let border        = Color.white.opacity(0.08)
    static let accent        = Color(hex: 0x3b82f6)
    static let success       = Color(hex: 0x22c55e)

    static let textPrimary   = Color(hex: 0xf5f5f7)
    static let textSecondary = Color(hex: 0xf5f5f7).opacity(0.6)
    static let textTertiary  = Color(hex: 0xf5f5f7).opacity(0.35)
}

enum OESpacing {
    static let rowPadding: CGFloat        = 32   // home page & library
    static let rowPaddingDetail: CGFloat  = 56   // game detail page
    static let cardGapNES: CGFloat        = 22
    static let cardGapSNES: CGFloat       = 22
    static let sectionGap: CGFloat        = 40   // section bottom margin
    static let sectionTopPad: CGFloat     = 28   // section top padding
    static let heroHeight: CGFloat        = 400  // game detail hero
    static let heroHeightHome: CGFloat    = 520  // home hero
}

enum OERadius {
    static let card: CGFloat    = 4
    static let cardLg: CGFloat  = 6
    static let chip: CGFloat    = 999
    static let systemBadge: CGFloat = 7
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: opacity
        )
    }
}
