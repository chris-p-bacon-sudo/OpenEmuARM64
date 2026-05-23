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

enum OENavTab: String, CaseIterable, Identifiable {
    case home          = "Home"
    case recentlyPlayed = "Recently Played"
    case recentlyAdded  = "Recently Added"
    case favorites      = "Favorites"
    case saveStates     = "Save States"
    case search         = "Search"

    var id: String { rawValue }
}

/// The frosted-glass pill navigation bar that sits in the title bar area.
struct OENavBar: View {
    @Binding var selectedTab: OENavTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(OENavTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(selectedTab == tab ? OEColors.textPrimary : OEColors.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(
                            Group {
                                if selectedTab == tab {
                                    RoundedRectangle(cornerRadius: 999)
                                        .fill(Color.white.opacity(0.12))
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(height: 32)
        .background(OEColors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 999)
                .stroke(OEColors.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 999))
    }
}

/// Traffic lights placeholder (AppKit handles the real ones; this is just spacing).
struct OEWindowControls: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: 0xff5f57)).frame(width: 12, height: 12)
            Circle().fill(Color(hex: 0xfebc2e)).frame(width: 12, height: 12)
            Circle().fill(Color(hex: 0x28c840)).frame(width: 12, height: 12)
        }
    }
}
