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
import OpenEmuKit

/// A labelled horizontal-scroll row of game cards for one system.
struct OEGameRowView: View {
    let system: OEDBSystem
    let games: [OEDBGame]
    let onPlayGame: (OEDBGame) -> Void
    let onSeeAll: (OEDBSystem) -> Void
    var onSelectGame: ((OEDBGame) -> Void)? = nil

    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var currentIndex = 0   // Index of leftmost visible card

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowHeader
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: OESpacing.cardGapNES) {
                            let cardH = OESystemAspectRatio.cardHeight(for: system.systemIdentifier)
                            ForEach(Array(games.enumerated()), id: \.element.objectID) { idx, game in
                                OEGameCardView(game: game, cardHeight: cardH, onSelect: { onSelectGame?(game) }) { onPlayGame(game) }
                                    .id(idx)
                            }
                        }
                        .padding(.horizontal, OESpacing.rowPadding)
                        .padding(.vertical, 4)
                    }
                    .onAppear { scrollProxy = proxy }
                }

                // Left arrow — appears after scrolling right
                if currentIndex > 0 {
                    scrollButton(systemImage: "chevron.left", leading: true) {
                        currentIndex = max(0, currentIndex - 1)
                        withAnimation(.easeOut(duration: 0.25)) {
                            scrollProxy?.scrollTo(currentIndex, anchor: .leading)
                        }
                    }
                }

                // Right arrow — disappears at end
                if currentIndex < games.count - 1 {
                    scrollButton(systemImage: "chevron.right", leading: false) {
                        currentIndex = min(games.count - 1, currentIndex + 1)
                        withAnimation(.easeOut(duration: 0.25)) {
                            scrollProxy?.scrollTo(currentIndex, anchor: .leading)
                        }
                    }
                }
            }
        }
    }

    private func scrollButton(systemImage: String, leading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.72))
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
        .padding(.horizontal, 12)
    }

    private var rowHeader: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 12) {
                OESystemBadge(system: system, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(system.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(OEColors.textPrimary)
                    Text("\(games.count) games · sorted by recently played")
                        .font(.system(size: 11.5))
                        .foregroundColor(OEColors.textSecondary)
                }
            }
            Spacer()
            Button { onSeeAll(system) } label: {
                HStack(spacing: 4) {
                    Text("See All")
                    Image(systemName: "chevron.right").imageScale(.small)
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(OEColors.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, OESpacing.rowPadding)
        .padding(.bottom, 12)
    }
}

/// System identity badge using the existing `*_library` pixel art from each system plugin.
/// Falls back to colored text if the plugin icon isn't available.
struct OESystemBadge: View {
    let system: OEDBSystem
    let size: CGFloat

    private var icon: NSImage? { system.plugin?.systemIcon }

    var body: some View {
        let colors = OESystemColors.colors(for: system.systemIdentifier)
        ZStack {
            RoundedRectangle(cornerRadius: OERadius.systemBadge)
                .fill(
                    LinearGradient(
                        colors: [colors.primary, colors.primary.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OERadius.systemBadge)
                        .stroke(Color.black.opacity(0.35), lineWidth: 0.5)
                )

            if let img = icon {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.7, height: size * 0.7)
            } else {
                Text(system.shortName ?? "?")
                    .font(.system(size: size * 0.28, weight: .black))
                    .foregroundColor(colors.accent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
    }
}

extension OEDBSystem {
    var shortName: String? {
        let id = systemIdentifier.lowercased()
        if id.contains("nes") && !id.contains("snes") { return "NES" }
        if id.contains("snes")       { return "SNES" }
        if id.contains("n64")        { return "N64"  }
        if id.contains("gba")        { return "GBA"  }
        if id.contains("genesis")    { return "GEN"  }
        if id.contains("ps1") || id.contains("psx") || id.contains("playstation") { return "PS1" }
        return String(name.prefix(4)).uppercased()
    }
}
