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

// MARK: - Design-spec pill button

/// Dark frosted-glass pill button matching the Paper design exactly.
/// bg #FFFFFF0A, border #FFFFFF1A 0.5px, blur 8pt, h28, px12, 12pt semibold.
private struct OEPillButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color(hex: 0xFFFFFF, opacity: 0.04))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: 0xFFFFFF, opacity: 0.10), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared section header

struct OESectionHeader: View {
    let title: String
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(OEColors.textPrimary)
            Spacer()
            if let action = onSeeAll {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text("See all")
                        Image(systemName: "chevron.right").imageScale(.small)
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(OEColors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, OESpacing.rowPadding)
    }
}

// MARK: - Continue Playing (icon strip — SGDB icons)

struct OEContinuePlayingRow: View {
    let games: [OEDBGame]
    let onSelectGame: (OEDBGame) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(Array(games.prefix(12)), id: \.objectID) { game in
                    OEGameIconCell(game: game) { onSelectGame(game) }
                }
            }
            .padding(.horizontal, OESpacing.rowPadding)
            .padding(.vertical, 4)
        }
    }
}

struct OEGameIconCell: View {
    let game: OEDBGame
    let onTap: () -> Void

    @State private var icon: NSImage?
    @State private var fallbackCover: NSImage?

    private var ageText: String {
        guard let date = game.lastPlayed else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if let img = icon ?? fallbackCover {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 72)
                            .clipped()
                    } else {
                        OEPlaceholderCoverView(game: game, cardHeight: 72)
                            .frame(width: 72, height: 72)
                    }
                }
                .frame(width: 72, height: 72)
                .cornerRadius(14)
                .shadow(color: .black.opacity(0.45), radius: 8, y: 4)

                Text(game.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(OEColors.textPrimary)
                    .lineLimit(2)
                    .frame(width: 72, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !ageText.isEmpty {
                    Text(ageText)
                        .font(.system(size: 10))
                        .foregroundColor(OEColors.textTertiary)
                        .lineLimit(1)
                        .frame(width: 72, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear { loadArt() }
    }

    private func loadArt() {
        fallbackCover = OECoverLoader.cover(for: game)
        let md5 = game.defaultROM?.md5Hash?.lowercased() ?? ""
        let name = game.displayName
        guard !md5.isEmpty else { return }
        Task(priority: .userInitiated) {
            icon = await OEHeroArtFetcher.shared.iconArt(md5: md5, displayName: name)
        }
    }
}

// MARK: - Recent Saves (hero art backgrounds)

struct OERecentSavesSection: View {
    let saves: [OEDBSaveState]
    let onResume: (OEDBSaveState) -> Void
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OESectionHeader(title: "Recent Saves", onSeeAll: onSeeAll)

            GeometryReader { geo in
                let gap: CGFloat = 10
                let usable = geo.size.width - OESpacing.rowPadding * 2 - gap
                let wideW = (usable * 0.608).rounded()
                let narrowW = usable - wideW

                let top = Array(saves.prefix(2))
                let bottom = saves.count > 2 ? Array(saves[2..<min(4, saves.count)]) : []

                VStack(spacing: gap) {
                    if !top.isEmpty {
                        HStack(spacing: gap) {
                            OEHomeSaveCard(state: top[0], onResume: { onResume(top[0]) })
                                .frame(width: wideW)
                            if top.count > 1 {
                                OEHomeSaveCard(state: top[1], onResume: { onResume(top[1]) })
                                    .frame(width: narrowW)
                            }
                        }
                    }
                    if !bottom.isEmpty {
                        HStack(spacing: gap) {
                            OEHomeSaveCard(state: bottom[0], onResume: { onResume(bottom[0]) })
                                .frame(width: narrowW)
                            if bottom.count > 1 {
                                OEHomeSaveCard(state: bottom[1], onResume: { onResume(bottom[1]) })
                                    .frame(width: wideW)
                            }
                        }
                    }
                }
                .padding(.horizontal, OESpacing.rowPadding)
            }
            .frame(height: saves.count > 2 ? 508 : 244)
        }
    }
}

struct OEHomeSaveCard: View {
    let state: OEDBSaveState
    let onResume: () -> Void

    @State private var heroImage: NSImage?
    @State private var cover: NSImage?

    private var game: OEDBGame? { state.rom?.game }

    private var subtitleText: String {
        var parts: [String] = []
        if let sys = game?.system?.name { parts.append(sys) }
        parts.append(state.displayName)
        return parts.joined(separator: " · ")
    }

    private var timestampText: String {
        guard let date = state.timestamp else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hero art background (SGDB hero)
            GeometryReader { geo in
                ZStack {
                    if let img = heroImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else {
                        Color(hex: 0x0A0F1E)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .frame(height: 164)

            // Footer — matches design: bg #151A2E, h80, px14
            HStack(spacing: 10) {
                if let img = cover {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 58, height: 48)
                        .clipped()
                        .cornerRadius(3)
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(game?.displayName ?? "Unknown")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: 0xF5F5F7))
                        .lineLimit(1)
                    Text(subtitleText)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: 0xF5F5F7, opacity: 0.45))
                        .lineLimit(1)
                    if !timestampText.isEmpty {
                        Text(timestampText)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: 0xF5F5F7, opacity: 0.30))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                OEPillButton(label: "Resume", action: onResume)
            }
            .padding(.horizontal, 14)
            .frame(height: 80)
            .background(Color(hex: 0x151A2E))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { loadImages() }
    }

    private func loadImages() {
        if let g = game { cover = OECoverLoader.cover(for: g) }
        let md5 = game?.defaultROM?.md5Hash?.lowercased() ?? ""
        let name = game?.displayName ?? ""
        guard !md5.isEmpty else { return }
        Task(priority: .userInitiated) {
            heroImage = await OEHeroArtFetcher.shared.heroArt(md5: md5, displayName: name)
        }
    }
}

// MARK: - Browse by Genre

struct GenreDef {
    let name: String
    let bgColor: Color
}

private let kGenres: [GenreDef] = [
    GenreDef(name: "Action",     bgColor: Color(hex: 0x6b1111)),
    GenreDef(name: "RPG",        bgColor: Color(hex: 0x0f1f4a)),
    GenreDef(name: "Platformer", bgColor: Color(hex: 0x0d3518)),
    GenreDef(name: "Adventure",  bgColor: Color(hex: 0x103028)),
    GenreDef(name: "Racing",     bgColor: Color(hex: 0x3b2800)),
    GenreDef(name: "Fighting",   bgColor: Color(hex: 0x2a0f4a)),
]

struct OEBrowseByGenreSection: View {
    let games: [OEDBGame]
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OESectionHeader(title: "Browse by Genre", onSeeAll: onSeeAll)

            GeometryReader { geo in
                let gap: CGFloat = 10
                let usable = geo.size.width - OESpacing.rowPadding * 2
                let tileW = ((usable - gap * 5) / 6).rounded()

                HStack(spacing: gap) {
                    ForEach(Array(kGenres.enumerated()), id: \.offset) { idx, genre in
                        OEGenreTile(
                            genre: genre,
                            representativeGame: games.count > idx ? games[idx] : nil
                        )
                        .frame(width: tileW, height: 104)
                    }
                }
                .padding(.horizontal, OESpacing.rowPadding)
            }
            .frame(height: 104)
        }
    }
}

struct OEGenreTile: View {
    let genre: GenreDef
    let representativeGame: OEDBGame?

    @State private var cover: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            genre.bgColor

            if let img = cover {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 80)
                    .clipped()
                    .opacity(0.55)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(false)
            }

            LinearGradient(
                colors: [genre.bgColor, genre.bgColor.opacity(0.3)],
                startPoint: .bottom, endPoint: .top
            )
            .frame(height: 52)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            Text(genre.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onAppear {
            if let g = representativeGame { cover = OECoverLoader.cover(for: g) }
        }
    }
}

// MARK: - Recently Added (SGDB hero art)

struct OERecentlyAddedSection: View {
    let games: [OEDBGame]
    let onPlay: (OEDBGame) -> Void
    let onSelectGame: (OEDBGame) -> Void
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OESectionHeader(title: "Recently Added", onSeeAll: onSeeAll)

            GeometryReader { geo in
                let gap: CGFloat = 10
                let usable = geo.size.width - OESpacing.rowPadding * 2
                let cardW = ((usable - gap * 2) / 3).rounded()

                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(games.prefix(3)), id: \.objectID) { game in
                        OERecentlyAddedCard(
                            game: game,
                            width: cardW,
                            onPlay: { onPlay(game) },
                            onSelect: { onSelectGame(game) }
                        )
                        .frame(width: cardW)
                    }
                }
                .padding(.horizontal, OESpacing.rowPadding)
            }
            .frame(height: 244)
        }
    }
}

struct OERecentlyAddedCard: View {
    let game: OEDBGame
    let width: CGFloat
    let onPlay: () -> Void
    let onSelect: () -> Void

    @State private var heroImage: NSImage?
    @State private var cover: NSImage?

    private var addedText: String {
        guard let date = game.importDate else { return "Added recently" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return "Added \(f.localizedString(for: date, relativeTo: Date()))"
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                // Hero art fills the art area
                ZStack(alignment: .topLeading) {
                    GeometryReader { geo in
                        ZStack {
                            if let img = heroImage {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                            } else if let img = cover {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                            } else {
                                OEPlaceholderCoverView(game: game, cardHeight: geo.size.height)
                                    .frame(width: geo.size.width, height: geo.size.height)
                            }
                        }
                    }
                    .frame(height: 164)

                    // "New" badge — design: bg #00000073, border #FFFFFF1F 1px, blur
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                        Text("New")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .padding(12)
                }
                .frame(height: 164)

                // Footer — bg #0E1020, h80, px12
                HStack(spacing: 8) {
                    if let img = cover {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 67, height: 48)
                            .clipped()
                            .cornerRadius(3)
                            .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.displayName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: 0xF5F5F7))
                            .lineLimit(1)
                        Text(game.system?.name ?? "")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: 0xF5F5F7, opacity: 0.45))
                            .lineLimit(1)
                        Text(addedText)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: 0xF5F5F7, opacity: 0.30))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    OEPillButton(label: "Play", action: onPlay)
                }
                .padding(.horizontal, 12)
                .frame(height: 80)
                .background(Color(hex: 0x0E1020))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onAppear { loadArt() }
    }

    private func loadArt() {
        cover = OECoverLoader.cover(for: game)
        let md5 = game.defaultROM?.md5Hash?.lowercased() ?? ""
        let name = game.displayName
        guard !md5.isEmpty else { return }
        Task(priority: .userInitiated) {
            heroImage = await OEHeroArtFetcher.shared.heroArt(md5: md5, displayName: name)
        }
    }
}

// MARK: - Most Played (SGDB grid/poster art)

struct OEMostPlayedSection: View {
    let games: [OEDBGame]
    let onPlay: (OEDBGame) -> Void
    let onSelectGame: (OEDBGame) -> Void
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(OEColors.accent)
                    Text("FAVORITES")
                        .font(.system(size: 9.5, weight: .bold))
                        .kerning(1.4)
                        .foregroundColor(OEColors.accent)
                }
                .padding(.horizontal, OESpacing.rowPadding)

                HStack(alignment: .bottom) {
                    Text("Most Played")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(OEColors.textPrimary)
                    Spacer()
                    Button(action: onSeeAll) {
                        HStack(spacing: 3) {
                            Text("See all")
                            Image(systemName: "chevron.right").imageScale(.small)
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(OEColors.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, OESpacing.rowPadding)
            }

            GeometryReader { geo in
                let gap: CGFloat = 12
                let usable = geo.size.width - OESpacing.rowPadding * 2
                let cardW = ((usable - gap * 4) / 5).rounded()

                HStack(spacing: gap) {
                    ForEach(Array(games.prefix(5)), id: \.objectID) { game in
                        OEPosterCard(
                            game: game,
                            width: cardW,
                            onPlay: { onPlay(game) },
                            onSelect: { onSelectGame(game) }
                        )
                        .frame(width: cardW)
                    }
                }
                .padding(.horizontal, OESpacing.rowPadding)
            }
            .frame(height: 414)
        }
    }
}

struct OEPosterCard: View {
    let game: OEDBGame
    let width: CGFloat
    let onPlay: () -> Void
    let onSelect: () -> Void

    @State private var gridImage: NSImage?
    @State private var fallbackCover: NSImage?

    private var playTimeText: String {
        let h = Int(game.playTime / 3600)
        let m = Int(game.playTime.truncatingRemainder(dividingBy: 3600) / 60)
        if h > 0 { return "\(h) hrs played" }
        if m > 0 { return "\(m)m played" }
        return ""
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                // SGDB grid/poster art (342pt tall as per design)
                ZStack(alignment: .bottom) {
                    GeometryReader { geo in
                        ZStack {
                            if let img = gridImage ?? fallbackCover {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                            } else {
                                OEPlaceholderCoverView(game: game, cardHeight: geo.size.height)
                                    .frame(width: geo.size.width, height: geo.size.height)
                            }
                        }
                    }
                    .frame(height: 342)

                    // Subtle bottom gradient
                    LinearGradient(
                        colors: [.black.opacity(0.35), .clear],
                        startPoint: .bottom, endPoint: .top
                    )
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                }
                .frame(height: 342)

                // Footer — bg #0C0C1A, h72, px14
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(game.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if !playTimeText.isEmpty {
                            Text("\(game.system?.name ?? "") · \(playTimeText)")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.45))
                                .lineLimit(1)
                        } else {
                            Text(game.system?.name ?? "")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.45))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    OEPillButton(label: "Play", action: onPlay)
                }
                .padding(.horizontal, 14)
                .frame(height: 72)
                .background(Color(hex: 0x0C0C1A))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onAppear { loadArt() }
    }

    private func loadArt() {
        fallbackCover = OECoverLoader.cover(for: game)
        let md5 = game.defaultROM?.md5Hash?.lowercased() ?? ""
        let name = game.displayName
        guard !md5.isEmpty else { return }
        Task(priority: .userInitiated) {
            gridImage = await OEHeroArtFetcher.shared.gridArt(md5: md5, displayName: name)
        }
    }
}

// MARK: - Rediscover Banner

struct OERediscoverBanner: View {
    let game: OEDBGame
    let onPlay: () -> Void

    @State private var heroImage: NSImage?
    @State private var cover: NSImage?

    private var playedAgoText: String {
        guard let date = game.lastPlayed else { return "Not yet played" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return "Played \(f.localizedString(for: date, relativeTo: Date()))"
    }

    private var saveCountText: String {
        let n = game.saveStateCount
        return n == 1 ? "1 save" : "\(n) saves"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                ZStack {
                    if let img = heroImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .blur(radius: 18)
                            .opacity(0.45)
                            .clipped()
                    } else if let img = cover {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .blur(radius: 24)
                            .opacity(0.35)
                            .clipped()
                    } else {
                        Color(hex: 0x141416)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .frame(height: 136)

            Color.black.opacity(0.55)

            HStack(spacing: 14) {
                if let img = cover {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(playedAgoText.uppercased())
                        .font(.system(size: 9.5, weight: .bold))
                        .kerning(1.2)
                        .foregroundColor(.white.opacity(0.5))
                    Text(game.displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(game.system?.name ?? "")
                        if game.saveStateCount > 0 {
                            Text("·")
                            Text(saveCountText)
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.55))
                }

                Spacer()

                Button(action: onPlay) {
                    Label("Play Now", systemImage: "play.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                        .background(Color.white)
                        .cornerRadius(17)
                }
                .buttonStyle(.plain)
                .padding(.trailing, OESpacing.rowPadding)
            }
            .padding(.horizontal, OESpacing.rowPadding)
        }
        .frame(height: 136)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, OESpacing.rowPadding)
        .onAppear { loadImages() }
    }

    private func loadImages() {
        cover = OECoverLoader.cover(for: game)
        let md5 = game.defaultROM?.md5Hash?.lowercased() ?? ""
        let name = game.displayName
        guard !md5.isEmpty else { return }
        Task(priority: .background) {
            heroImage = await OEHeroArtFetcher.shared.heroArt(md5: md5, displayName: name)
        }
    }
}
