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

/// Full-bleed hero section for the most recently played game.
/// Fixed at 380pt tall — background art fills it, text overlays the bottom.
struct OEHeroView: View {
    let game: OEDBGame
    let currentIndex: Int
    let totalCount: Int
    let onResume: () -> Void
    let onDotTap: (Int) -> Void

    @State private var heroImage: NSImage?
    @State private var coverImage: NSImage?

    var systemName: String { game.system?.name ?? "" }

    var lastPlayedText: String {
        guard let date = game.lastPlayed else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return "Played \(f.localizedString(for: date, relativeTo: Date()))"
    }

    var totalPlayText: String {
        let h = game.playTime / 3600
        return h > 0 ? String(format: "%.1fh total", h) : ""
    }

    var body: some View {
        // Use GeometryReader so we have explicit sizing for the background
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                // Background art
                Group {
                    if let img = heroImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .opacity(0.6)
                    } else {
                        OEColors.background
                    }
                }

                // Top dim
                LinearGradient(
                    colors: [.black.opacity(0.45), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 80)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // Bottom fade to bg
                LinearGradient(
                    colors: [.clear, OEColors.background],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 200)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                // Hero content — cover box + text
                HStack(alignment: .bottom, spacing: 28) {
                    // Floating cover art — flat 2D with drop shadow
                    if let cover = coverImage {
                        Image(nsImage: cover)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 170)
                            .cornerRadius(5)
                            .shadow(color: .black.opacity(0.65), radius: 24, y: 12)
                    }

                    // Text block
                    VStack(alignment: .leading, spacing: 10) {
                        // Tag
                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(OEColors.accent)
                                .frame(width: 18, height: 1.5)
                            Text("CONTINUE PLAYING")
                                .font(.system(size: 10.5, weight: .bold))
                                .kerning(1.5)
                                .foregroundColor(OEColors.accent)
                        }

                        // Title
                        Text(game.displayName)
                            .font(.system(size: 44, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .shadow(color: .black.opacity(0.5), radius: 12)

                        // Metadata
                        HStack(spacing: 10) {
                            Text(systemName)
                            if !lastPlayedText.isEmpty {
                                dot
                                Text(lastPlayedText)
                            }
                            if !totalPlayText.isEmpty {
                                dot
                                Text(totalPlayText)
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))

                        // Actions
                        HStack(spacing: 10) {
                            Button(action: onResume) {
                                Label("Resume", systemImage: "play.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.05))
                                    .padding(.horizontal, 22)
                                    .frame(height: 36)
                                    .background(Color.white)
                                    .cornerRadius(18)
                                    .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }

                    Spacer(minLength: 0)

                    // Tappable page dots
                    if totalCount > 1 {
                        HStack(spacing: 6) {
                            ForEach(0..<totalCount, id: \.self) { idx in
                                Button { onDotTap(idx) } label: {
                                    Capsule()
                                        .fill(idx == currentIndex ? Color.white : Color.white.opacity(0.35))
                                        .frame(width: idx == currentIndex ? 22 : 6, height: 6)
                                        .animation(.easeInOut(duration: 0.2), value: currentIndex)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 52)
            }
        }
        .frame(height: 380)
        .onAppear { loadImages() }
    }

    private var dot: some View {
        Text("•").foregroundColor(.white.opacity(0.4))
    }

    private func loadImages() {
        Task.detached(priority: .userInitiated) {
            // Cover art: box art as floating element
            let cover = await OECoverLoader.cover(for: game)
            await MainActor.run { coverImage = cover }

            // Background art: fanart from ScreenScraper (cached), falls back to box art
            let bg = await OEHeroArtFetcher.shared.heroArt(for: game)
            await MainActor.run { heroImage = bg }
        }
    }
}
