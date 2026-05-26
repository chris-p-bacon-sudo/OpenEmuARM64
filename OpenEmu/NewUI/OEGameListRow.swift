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

// Column widths: thumbnail slot 56 | title auto | developer 160 | genre 100 | last played 120 | play time 80

struct OEColumnHeaders: View {
    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 56)
            Text("Title")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
            Text("Developer").frame(width: 160, alignment: .leading)
            Text("Genre").frame(width: 100, alignment: .leading)
            Text("Last Played").frame(width: 120, alignment: .leading)
            Text("Play Time").frame(width: 80, alignment: .leading)
        }
        .frame(height: 32)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(OEColors.textTertiary)
        .padding(.horizontal, OESpacing.rowPadding)
    }
}

struct OEGameListRow: View {
    let game: OEDBGame
    var onSelect: (() -> Void)? = nil
    let onPlay: () -> Void

    @State private var isHovered = false
    @State private var coverImage: NSImage?
    @State private var metadata: ScreenScraperResult?

    private var lastPlayedText: String? {
        guard let date = game.lastPlayed else { return nil }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private var formattedPlayTime: String {
        let total = game.playTime
        let h = Int(total / 3600)
        let m = Int(total.truncatingRemainder(dividingBy: 3600) / 60)
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "—"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Thumbnail slot — 56pt wide, portrait art 36×50
            ZStack {
                Group {
                    if let img = coverImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 50)
                            .cornerRadius(OERadius.card)
                    } else {
                        OEPlaceholderCoverView(game: game, cardHeight: 50)
                            .cornerRadius(OERadius.card)
                    }
                }

                if isHovered {
                    RoundedRectangle(cornerRadius: OERadius.card)
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 36, height: 50)
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.72))
                        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                        .clipShape(Circle())
                        .onTapGesture { onPlay() }
                }
            }
            .frame(width: 56)

            // Title + save state count
            VStack(alignment: .leading, spacing: 2) {
                Text(game.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(OEColors.textPrimary)
                    .lineLimit(1)
                Text("\(game.saveStateCount) save states")
                    .font(.system(size: 11))
                    .foregroundColor(OEColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)

            // Developer
            Text(metadata?.developer ?? "—")
                .frame(width: 160, alignment: .leading)
                .font(.system(size: 12.5))
                .foregroundColor(OEColors.textPrimary)
                .lineLimit(1)

            // Genre
            Text(metadata?.genres.first ?? "—")
                .frame(width: 100, alignment: .leading)
                .font(.system(size: 12.5))
                .foregroundColor(OEColors.textPrimary)
                .lineLimit(1)

            // Last Played
            lastPlayedCell
                .frame(width: 120, alignment: .leading)

            // Play Time
            Text(formattedPlayTime)
                .frame(width: 80, alignment: .leading)
                .font(.system(size: 12.5))
                .foregroundColor(OEColors.textPrimary)
        }
        .frame(height: 64)
        .foregroundColor(OEColors.textPrimary)
        .background(isHovered ? OEColors.surfaceHover : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect?() }
        .onAppear {
            loadCover()
            loadMetadata()
        }
    }

    private var lastPlayedCell: some View {
        Group {
            if let text = lastPlayedText {
                HStack(spacing: 5) {
                    Circle().fill(OEColors.success).frame(width: 4, height: 4)
                    Text(text)
                        .font(.system(size: 12.5))
                        .foregroundColor(OEColors.textPrimary)
                        .lineLimit(1)
                }
            } else {
                Text("—")
                    .font(.system(size: 12.5))
                    .foregroundColor(OEColors.textPrimary)
            }
        }
    }

    private func loadCover() {
        coverImage = OECoverLoader.cover(for: game)
    }

    private func loadMetadata() {
        let md5 = game.defaultROM?.md5Hash?.lowercased() ?? ""
        let displayName = game.displayName
        let systemID = game.system?.systemIdentifier
        let romExt = game.defaultROM?.fileName.flatMap {
            let ext = URL(fileURLWithPath: $0).pathExtension
            return ext.isEmpty ? nil : ext
        }
        Task {
            let result = await OEGameMetadataCache.shared.fetchOrCacheMetadata(md5: md5, displayName: displayName, systemID: systemID, romExt: romExt)
            metadata = result
        }
    }
}
