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

/// Full-bleed hero section showing the most recently played game.
struct OEHeroView: View {
    let game: OEDBGame
    let onResume: () -> Void
    let onDetails: () -> Void

    @State private var heroImage: NSImage?

    var systemName: String { game.system?.name ?? "" }
    var genreName: String  { (game.gameDescription ?? "").isEmpty ? "" : "" }

    var lastPlayedText: String {
        guard let date = game.lastPlayed else { return "Not yet played" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Played \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    var totalPlayText: String {
        let hours = game.playTime / 3600
        return String(format: "%.1fh total", hours)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
            bottomFade
            content
        }
        .frame(height: OESpacing.heroHeight)
        .onAppear { loadHeroImage() }
    }

    private var background: some View {
        Group {
            if let img = heroImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.65)
            } else {
                let colors = OESystemColors.colors(for: game.system?.systemIdentifier ?? "")
                LinearGradient(
                    colors: [colors.primary.opacity(0.8), OEColors.background],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipped()
    }

    private var bottomFade: some View {
        VStack {
            Spacer()
            LinearGradient(
                colors: [.clear, OEColors.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
        }
    }

    private var content: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                // Tag line
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(OEColors.accent)
                        .frame(width: 6, height: 6)
                        .cornerRadius(3)
                    Text("CONTINUE PLAYING")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.5)
                        .foregroundColor(OEColors.accent)
                }

                // Title
                Text(game.displayName ?? "")
                    .font(.system(size: 44, weight: .heavy, design: .default))
                    .foregroundColor(OEColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 2)

                // Metadata
                HStack(spacing: 10) {
                    Text(systemName)
                    dot
                    Text(lastPlayedText)
                    dot
                    Text(totalPlayText)
                }
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))

                // Actions
                HStack(spacing: 10) {
                    Button(action: onResume) {
                        Label("Resume", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: 0x0a0a0c))
                            .padding(.horizontal, 22)
                            .frame(height: 36)
                            .background(Color.white)
                            .cornerRadius(18)
                            .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDetails) {
                        Text("Details")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 36)
                            .background(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                            .cornerRadius(18)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
            .padding(.leading, 48)
            .padding(.bottom, 80)

            Spacer()

            // Page dots (placeholder — carousel not yet wired)
            HStack(spacing: 6) {
                Capsule().fill(Color.white).frame(width: 22, height: 6)
                Capsule().fill(Color.white.opacity(0.35)).frame(width: 6, height: 6)
                Capsule().fill(Color.white.opacity(0.35)).frame(width: 6, height: 6)
            }
            .padding(.trailing, 48)
            .padding(.bottom, 88)
        }
    }

    private var dot: some View {
        Text("•").foregroundColor(.white.opacity(0.4))
    }

    private func loadHeroImage() {
        Task.detached(priority: .userInitiated) {
            let img = await OECoverLoader.cover(for: game)
            await MainActor.run { heroImage = img }
        }
    }
}

