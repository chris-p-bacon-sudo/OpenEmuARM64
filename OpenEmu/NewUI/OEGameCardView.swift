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

/// A single game cover card used in horizontal scroll rows and the library grid.
struct OEGameCardView: View {
    let game: OEDBGame
    let width: CGFloat
    let onPlay: () -> Void

    @State private var isHovered = false
    @State private var coverImage: NSImage?

    var aspectRatio: CGFloat {
        guard let system = game.system else { return 0.72 }
        return OESystemAspectRatio.ratio(for: system.systemIdentifier)
    }

    var coverHeight: CGFloat { width / aspectRatio }

    var lastPlayedText: String? {
        guard let date = game.lastPlayed else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                // Cover art
                Group {
                    if let img = coverImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        OEPlaceholderCoverView(game: game, width: width)
                    }
                }
                .frame(width: width, height: coverHeight)
                .clipShape(RoundedRectangle(cornerRadius: OERadius.card))
                .shadow(color: .black.opacity(0.45), radius: 9, y: 6)

                // Hover play affordance
                if isHovered {
                    RoundedRectangle(cornerRadius: OERadius.card)
                        .fill(Color.black.opacity(0.35))
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(14)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                        .onTapGesture { onPlay() }
                }
            }
            .frame(width: width, height: coverHeight)
            .onHover { isHovered = $0 }
            .offset(y: isHovered ? -3 : 0)
            .animation(.easeOut(duration: 0.18), value: isHovered)

            // Metadata below cover
            VStack(alignment: .leading, spacing: 2) {
                Text(game.displayName ?? "")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(OEColors.textPrimary)
                    .lineLimit(1)

                if let played = lastPlayedText {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(OEColors.success)
                            .frame(width: 4, height: 4)
                        Text(played)
                            .font(.system(size: 11))
                            .foregroundColor(OEColors.textSecondary)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .onAppear { loadCover() }
    }

    private func loadCover() {
        Task.detached(priority: .userInitiated) {
            let img = await OECoverLoader.cover(for: game)
            await MainActor.run { coverImage = img }
        }
    }
}

/// Placeholder cover rendered from the game's system color + abbreviated title.
struct OEPlaceholderCoverView: View {
    let game: OEDBGame
    let width: CGFloat

    var body: some View {
        let colors = OESystemColors.colors(for: game.system?.systemIdentifier ?? "unknown")
        ZStack {
            LinearGradient(
                colors: [colors.primary, colors.secondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String(game.displayName.prefix(2)).uppercased())
                .font(.system(size: width * 0.22, weight: .black))
                .foregroundColor(colors.accent.opacity(0.9))
        }
    }
}

/// System-specific color palettes matching the design.
enum OESystemColors {
    struct Palette {
        let primary: Color
        let secondary: Color
        let accent: Color
    }

    static func colors(for systemIdentifier: String) -> Palette {
        let id = systemIdentifier.lowercased()
        if id.contains("nes") && !id.contains("snes") {
            return Palette(primary: Color(hex: 0x1d4ed8), secondary: Color(hex: 0xdc2626), accent: .white)
        } else if id.contains("snes") {
            return Palette(primary: Color(hex: 0x5b3a99), secondary: Color(hex: 0x3b82f6), accent: Color(hex: 0xa78bfa))
        } else if id.contains("n64") {
            return Palette(primary: Color(hex: 0x1f6f3a), secondary: Color(hex: 0xffd23f), accent: .white)
        } else if id.contains("gba") {
            return Palette(primary: Color(hex: 0x3b2a8a), secondary: Color(hex: 0x7dd3fc), accent: .white)
        } else if id.contains("genesis") || id.contains("megadrive") {
            return Palette(primary: Color(hex: 0x0a0a0a), secondary: Color(hex: 0x1a1a1a), accent: Color(hex: 0xdc2626))
        } else if id.contains("ps1") || id.contains("psx") || id.contains("playstation") {
            return Palette(primary: Color(hex: 0x0b0d12), secondary: Color(hex: 0x1a1d26), accent: Color(hex: 0x9ca3af))
        } else {
            return Palette(primary: Color(hex: 0x1c1c1e), secondary: Color(hex: 0x2a2a2e), accent: .white)
        }
    }
}

/// System cover art aspect ratios.
enum OESystemAspectRatio {
    static func ratio(for systemIdentifier: String) -> CGFloat {
        let id = systemIdentifier.lowercased()
        if id.contains("nes") && !id.contains("snes") { return 0.72 }
        if id.contains("snes")    { return 1.37 }
        if id.contains("n64")     { return 1.10 }
        if id.contains("gba")     { return 1.55 }
        if id.contains("genesis") { return 0.70 }
        if id.contains("ps1") || id.contains("psx") || id.contains("playstation") { return 0.72 }
        return 0.75
    }
}

/// Thin async cover art loader that hits the existing OE box image cache.
enum OECoverLoader {
    static func cover(for game: OEDBGame) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume(returning: game.boxImage?.image)
            }
        }
    }
}
