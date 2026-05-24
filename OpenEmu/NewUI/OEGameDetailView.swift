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

import AVKit
import SwiftUI
import OpenEmuKit

struct OEGameDetailView: View {

    let game: OEDBGame
    let onBack: () -> Void
    let onPlay: () -> Void
    var onSelectGame: ((OEDBGame) -> Void)? = nil

    @State private var heroImage: NSImage?
    @State private var coverImage: NSImage?
    @State private var metadata: ScreenScraperResult?
    @State private var raSessionInfo: [String: Any]?
    @ObservedObject private var store = OELibraryStore.shared

    private var systemName: String { game.system?.name ?? "" }

    private var saveStates: [OEDBSaveState] {
        game.roms.flatMap { Array($0.saveStates) }
            .sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }

    private var otherGames: [OEDBGame] {
        guard let system = game.system else { return [] }
        return store.games(for: system)
            .filter { $0.objectID != game.objectID }
            .prefix(12).map { $0 }
    }

    private var formattedPlayTime: String {
        let total = game.playTime
        let h = Int(total / 3600)
        let m = Int(total.truncatingRemainder(dividingBy: 3600) / 60)
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "—"
    }

    private var lastPlayedText: String {
        guard let date = game.lastPlayed else { return "Never" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private var releaseYear: String {
        guard let date = metadata?.releaseDate else { return "" }
        if let range = date.range(of: #"\d{4}"#, options: .regularExpression) {
            return String(date[range])
        }
        return date
    }

    private var heroSubtitle: String {
        var parts: [String] = []
        if let dev = metadata?.developer, !dev.isEmpty { parts.append(dev) }
        if !releaseYear.isEmpty { parts.append(releaseYear) }
        if let genre = metadata?.genres.first, !genre.isEmpty { parts.append(genre) }
        return parts.joined(separator: " · ")
    }

    private var raUnlocked: Int? {
        (raSessionInfo?[OERetroAchievementsUnlockedCountKey] as? NSNumber)?.intValue
    }
    private var raTotal: Int? {
        (raSessionInfo?[OERetroAchievementsAchievementCountKey] as? NSNumber)?.intValue
    }
    private var raUnlockedPoints: Int? {
        (raSessionInfo?[OERetroAchievementsUnlockedPointsKey] as? NSNumber)?.intValue
    }
    private var raTotalPoints: Int? {
        (raSessionInfo?[OERetroAchievementsTotalPointsKey] as? NSNumber)?.intValue
    }
    private var raAchievements: [[String: Any]] {
        let all = raSessionInfo?[OERetroAchievementsAchievementsKey] as? [[String: Any]] ?? []
        let earned = all.filter { ($0[OERetroAchievementsStateKey] as? NSNumber)?.intValue ?? 0 >= 1 }
        let locked = all.filter { ($0[OERetroAchievementsStateKey] as? NSNumber)?.intValue ?? 0 == 0 }
        return Array((earned + locked).prefix(8))
    }

    var body: some View {
        ZStack(alignment: .top) {
            OEColors.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    heroSection
                    statsSection
                    screenshotsSection
                    aboutAndAchievementsSection
                    aboutFullSection
                    achievementsSection
                    if !saveStates.isEmpty { saveStatesSection }
                    if !otherGames.isEmpty { moreSection }
                    Spacer(minLength: 40)
                }
            }

            detailNavBar
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            loadImages()
            loadMetadata()
        }
    }

    // MARK: - Nav bar

    private var detailNavBar: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)
            .ignoresSafeArea()

            HStack(spacing: 0) {
                Spacer().frame(width: 140)
                breadcrumb
                Spacer()
                HStack(spacing: 8) {
                    glassButton(icon: "magnifyingglass") {}
                    OEUserAvatar(size: 28)
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                }
                .padding(.trailing, 16)
            }
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(systemName)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.65))
            }
            .buttonStyle(.plain)

            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))

            Text(game.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
        }
    }

    // MARK: - Hero (EL-0, 400pt)

    private var heroSection: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
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

                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                LinearGradient(colors: [.clear, OEColors.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: 260)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                HStack(alignment: .bottom, spacing: 28) {
                    if let cover = coverImage {
                        let coverH = OESystemAspectRatio.cardHeight(for: game.system?.systemIdentifier ?? "")
                        Image(nsImage: cover)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: coverH)
                            .cornerRadius(5)
                            .shadow(color: .black.opacity(0.65), radius: 24, y: 12)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        if let system = game.system {
                            HStack(spacing: 8) {
                                OESystemBadge(system: system, size: 18)
                                Text(systemName.uppercased())
                                    .font(.system(size: 10.5, weight: .bold))
                                    .kerning(0.8)
                                    .foregroundColor(.white.opacity(0.55))
                            }
                        }

                        Text(game.displayName)
                            .font(.system(size: 52, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .shadow(color: .black.opacity(0.5), radius: 12)

                        let subtitle = heroSubtitle
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.4), radius: 8)
                        }

                        HStack(spacing: 10) {
                            Button(action: onPlay) {
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

                            Button {} label: {
                                Label("Save States", systemImage: "square.and.arrow.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.horizontal, 18)
                                    .frame(height: 36)
                                    .background(Color.white.opacity(0.12))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, OESpacing.rowPaddingDetail)
                .padding(.bottom, 52)
            }
        }
        .frame(height: OESpacing.heroHeight)
    }

    // MARK: - Stats Bar (G2-0)
    // Cells are content-width, left-aligned; the right half of the bar stays empty (matches Paper)

    private var statsSection: some View {
        HStack(spacing: 0) {
            statCell(label: "Play Time", value: formattedPlayTime)
            statCell(label: "Save States", value: "\(game.saveStateCount) saves")
            lastPlayedStatCell
            achievementsStatCell
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OEColors.background)
        .overlay(
            Rectangle().fill(OEColors.border).frame(height: 0.5),
            alignment: .bottom
        )
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.08 * 11)
                .foregroundColor(Color(hex: 0xEDEDEE, opacity: 0.40))
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.5)
                .foregroundColor(OEColors.textPrimary)
        }
        .padding(.leading, OESpacing.rowPaddingDetail)
        .padding(.trailing, 28)
        .padding(.vertical, 22)
        .overlay(
            Rectangle().fill(OEColors.border).frame(width: 0.5),
            alignment: .trailing
        )
    }

    private var lastPlayedStatCell: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LAST PLAYED")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.08 * 11)
                .foregroundColor(Color(hex: 0xEDEDEE, opacity: 0.40))
            HStack(spacing: 6) {
                if game.lastPlayed != nil {
                    Circle().fill(OEColors.success).frame(width: 6, height: 6)
                }
                Text(lastPlayedText)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.5)
                    .foregroundColor(OEColors.textPrimary)
            }
        }
        .padding(.leading, OESpacing.rowPaddingDetail)
        .padding(.trailing, 28)
        .padding(.vertical, 22)
        .overlay(
            Rectangle().fill(OEColors.border).frame(width: 0.5),
            alignment: .trailing
        )
    }

    private var achievementsStatCell: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ACHIEVEMENTS")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.08 * 11)
                .foregroundColor(Color(hex: 0xEDEDEE, opacity: 0.40))
            let value: String = {
                if let u = raUnlocked, let t = raTotal { return "\(u) / \(t)" }
                return "—"
            }()
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.5)
                .foregroundColor(OEColors.textPrimary)
        }
        .padding(.leading, OESpacing.rowPaddingDetail)
        .padding(.trailing, 28)
        .padding(.vertical, 22)
    }

    // MARK: - Gameplay Screenshots (GH-0)

    private var screenshotsSection: some View {
        let videoURL = metadata?.videoURL
        let screenshotURLs = metadata?.screenshotURLs ?? []
        let hasContent = videoURL != nil || !screenshotURLs.isEmpty

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Gameplay")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(OEColors.textPrimary)
                Spacer()
                if hasContent { seeAllButton("See All") }
            }
            .frame(height: 40)
            .padding(.horizontal, OESpacing.rowPaddingDetail)

            Spacer().frame(height: 28)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let videoURL {
                        OEVideoThumbnail(url: videoURL).asView()
                    }
                    if screenshotURLs.isEmpty && videoURL == nil {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(OEColors.surface)
                                .frame(width: 272, height: 153)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(OEColors.border, lineWidth: 0.5))
                        }
                    } else {
                        ForEach(Array(screenshotURLs.enumerated()), id: \.offset) { index, url in
                            OEScreenshotThumbnail(url: url, label: "Screenshot \(index + 1)")
                        }
                    }
                }
                .padding(.horizontal, OESpacing.rowPaddingDetail)
            }
            .frame(height: 153)
        }
        .padding(.top, OESpacing.sectionTopPad)
        .padding(.bottom, OESpacing.sectionGap)
    }

    // MARK: - About + Achievements Condensed (K9-0)

    private var aboutAndAchievementsSection: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column — About
            VStack(alignment: .leading, spacing: 16) {
                Text("About")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(OEColors.textPrimary)

                let desc = metadata?.gameDescription ?? game.gameDescription
                if let desc, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 13))
                        .foregroundColor(OEColors.textSecondary)
                        .lineSpacing(5)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                simpleMetadataList
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Vertical divider
            Rectangle()
                .fill(OEColors.border)
                .frame(width: 1)
                .padding(.vertical, 4)

            // Right column — Achievements
            achievementsColumn
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, OESpacing.rowPaddingDetail)
        }
        .padding(.horizontal, OESpacing.rowPaddingDetail)
        .padding(.top, OESpacing.sectionTopPad)
        .padding(.bottom, OESpacing.sectionGap)
    }

    private var simpleMetadataList: some View {
        VStack(spacing: 10) {
            simpleMetaRow("Developer", value: metadata?.developer ?? "—")
            simpleMetaRow("Released",  value: metadata?.releaseDate ?? "—")
            simpleMetaRow("Genre",     value: metadata?.genres.first ?? "—")
            simpleMetaRow("Platform",  value: game.system?.name ?? "—")
        }
    }

    private func simpleMetaRow(_ label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.06 * 12)
                .foregroundColor(Color(hex: 0xEDEDEE, opacity: 0.40))
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(OEColors.textSecondary)
                .lineLimit(1)
            Spacer()
        }
    }

    private var achievementsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Achievements")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.3)
                    .foregroundColor(OEColors.textPrimary)
                Spacer()
                if let unlocked = raUnlocked, let total = raTotal {
                    Text("\(unlocked) / \(total)")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0xEDEDEE, opacity: 0.40))
                }
            }

            if let unlocked = raUnlocked, let total = raTotal {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(OEColors.border).frame(height: 4)
                        RoundedRectangle(cornerRadius: 2).fill(OEColors.accent)
                            .frame(width: total > 0 ? geo.size.width * CGFloat(unlocked) / CGFloat(total) : 0, height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.top, 10)

                VStack(spacing: 0) {
                    ForEach(Array(raAchievements.prefix(4).enumerated()), id: \.offset) { _, ach in
                        condensedAchievementRow(ach)
                    }
                }
                .padding(.top, 12)
            } else {
                Text("Play the game to load achievements.")
                    .font(.system(size: 13))
                    .foregroundColor(OEColors.textTertiary)
                    .italic()
                    .padding(.top, 12)
            }
        }
    }

    private func condensedAchievementRow(_ info: [String: Any]) -> some View {
        let state = (info[OERetroAchievementsStateKey] as? NSNumber)?.intValue ?? 0
        let isEarned = state == 2
        let badgeURLStr = (isEarned ? info[OEAchievementBadgeURLKey] : info[OERetroAchievementsBadgeLockedURLKey]) as? String
        let title = info[OEAchievementTitleKey] as? String ?? "Untitled"
        let description = info[OEAchievementDescriptionKey] as? String ?? ""

        return HStack(alignment: .center, spacing: 12) {
            OERemoteImage(urlString: badgeURLStr, size: 36)
                .opacity(isEarned ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isEarned ? OEColors.textPrimary : OEColors.textTertiary)
                    .lineLimit(1)
                if !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(OEColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(isEarned ? "Earned" : "Locked")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isEarned ? OEColors.success : Color(hex: 0xEDEDEE, opacity: 0.30))
        }
        .frame(height: 36)
    }

    // MARK: - About Full (LW-0) — full description + bordered metadata table

    private var aboutFullSection: some View {
        let rom = game.defaultROM
        let fileSizeStr: String = {
            guard let bytes = rom?.fileSize?.int64Value, bytes > 0 else { return "—" }
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }()
        let md5Str: String = {
            guard let md5 = rom?.md5, !md5.isEmpty else { return "—" }
            return "MD5: \(md5.prefix(8))…"
        }()

        return HStack(alignment: .top, spacing: 40) {
            // Left — full description
            VStack(alignment: .leading, spacing: 16) {
                let desc = metadata?.gameDescription ?? game.gameDescription
                if let desc, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 13))
                        .foregroundColor(OEColors.textSecondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right — bordered metadata table
            VStack(spacing: 0) {
                metaRowRight("Developer", value: metadata?.developer ?? "—")
                metaRowRight("Publisher",  value: metadata?.publisher ?? "—")
                metaRowRight("Released",   value: metadata?.releaseDate ?? "—")
                metaRowRight("Genre",      value: metadata?.genres.isEmpty == false ? metadata!.genres.joined(separator: " · ") : "—")
                metaRowRight("Players",    value: metadata?.players ?? "—")
                metaRowRight("Region",     value: metadata?.region ?? "—")
                metaRowRight("ROM hash",   value: md5Str, isLast: false)
                metaRowRight("File size",  value: fileSizeStr, isLast: true)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 18)
            .background(Color(hex: 0xFFFFFF, opacity: 0.024))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xFFFFFF, opacity: 0.078), lineWidth: 0.5))
            .frame(width: 420)
        }
        .padding(.horizontal, OESpacing.rowPaddingDetail)
        .padding(.top, OESpacing.sectionTopPad)
        .padding(.bottom, OESpacing.sectionGap)
    }

    private func metaRowRight(_ label: String, value: String, isLast: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: 0xEDEDEE, opacity: 0.50))
            Spacer()
            Text(value)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(OEColors.textPrimary)
                .lineLimit(1)
        }
        .padding(.vertical, 12)
        .overlay(
            Group {
                if !isLast {
                    Rectangle().fill(Color(hex: 0xFFFFFF, opacity: 0.059)).frame(height: 0.5)
                }
            },
            alignment: .bottom
        )
    }

    // MARK: - Achievements Full (N0-0)

    private var achievementsSection: some View {
        let unlocked = raUnlocked ?? 0
        let total    = raTotal    ?? 0
        let points   = raUnlockedPoints ?? 0
        let totalPts = raTotalPoints    ?? 0
        let hasData  = raSessionInfo != nil

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                Text("Achievements")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(OEColors.textPrimary)
                Spacer()
                if hasData { pillButton("View all") }
            }
            .padding(.horizontal, OESpacing.rowPaddingDetail)

            HStack {
                Text(hasData
                     ? "\(unlocked) OF \(total) EARNED · \(points) OF \(totalPts) POINTS"
                     : "ACHIEVEMENTS")
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(0.6)
                    .foregroundColor(OEColors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, OESpacing.rowPaddingDetail)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(OEColors.border).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(OEColors.accent)
                        .frame(width: total > 0 ? geo.size.width * CGFloat(unlocked) / CGFloat(total) : 0,
                               height: 4)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, OESpacing.rowPaddingDetail)

            if hasData && !raAchievements.isEmpty {
                let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(raAchievements.enumerated()), id: \.offset) { _, ach in
                        achievementCard(ach)
                    }
                }
                .padding(.horizontal, OESpacing.rowPaddingDetail)
            } else {
                let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<6, id: \.self) { _ in placeholderAchievementCard }
                }
                .padding(.horizontal, OESpacing.rowPaddingDetail)
            }
        }
        .padding(.top, OESpacing.sectionTopPad)
        .padding(.bottom, OESpacing.sectionGap)
    }

    private var placeholderAchievementCard: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(OEColors.surface)
                .frame(width: 48, height: 48)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(OEColors.border, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(OEColors.surface).frame(width: 100, height: 11)
                RoundedRectangle(cornerRadius: 3).fill(OEColors.surface).frame(width: 140, height: 9)
            }
            Spacer()
        }
        .padding(12)
        .background(OEColors.surface)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(OEColors.border, lineWidth: 0.5))
    }

    // MARK: - Save States (Q3-0)

    private var saveStatesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Save States")
                        .font(.system(size: 20, weight: .bold))
                        .tracking(-0.5)
                        .foregroundColor(OEColors.textPrimary)
                    Text("\(saveStates.count) saved · synced via iCloud".uppercased())
                        .font(.system(size: 12, weight: .medium))
                        .kerning(0.03 * 12)
                        .foregroundColor(Color(hex: 0xEDEDEE, opacity: 0.50))
                }
                Spacer()
                pillButton("Manage")
            }
            .padding(.horizontal, OESpacing.rowPaddingDetail)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(saveStates.prefix(8)), id: \.objectID) { state in
                        OESaveStateCard(state: state)
                    }
                }
                .padding(.horizontal, OESpacing.rowPaddingDetail)
                .padding(.vertical, 4)
            }
        }
        .padding(.top, OESpacing.sectionTopPad)
        .padding(.bottom, OESpacing.sectionGap)
    }

    // MARK: - More for system (TN-0)

    private var moreSection: some View {
        let cardH = OESystemAspectRatio.cardHeight(for: game.system?.systemIdentifier ?? "")
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("More for \(systemName)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(OEColors.textPrimary)
                Spacer()
                seeAllButton("See all")
            }
            .padding(.horizontal, OESpacing.rowPaddingDetail)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OESpacing.cardGapSNES) {
                    ForEach(otherGames, id: \.objectID) { g in
                        OEGameCardView(game: g, cardHeight: cardH, onSelect: { onSelectGame?(g) }) {
                            onSelectGame?(g)
                        }
                    }
                }
                .padding(.horizontal, OESpacing.rowPaddingDetail)
                .padding(.vertical, 4)
            }
        }
        .padding(.top, OESpacing.sectionTopPad)
        .padding(.bottom, OESpacing.sectionGap)
    }

    // MARK: - Achievement card

    private func achievementCard(_ info: [String: Any]) -> some View {
        let state = (info[OERetroAchievementsStateKey] as? NSNumber)?.intValue ?? 0
        let isEarned = state == 2
        let badgeURLStr = (isEarned ? info[OEAchievementBadgeURLKey] : info[OERetroAchievementsBadgeLockedURLKey]) as? String
        let title = info[OEAchievementTitleKey] as? String ?? "Untitled"
        let description = info[OEAchievementDescriptionKey] as? String ?? ""
        let points = (info[OEAchievementPointsKey] as? NSNumber)?.intValue ?? 0
        let earnedDate = info["OERetroAchievementsEarnedDateKey"] as? String
        let percentStr = info["OERetroAchievementsPercentKey"] as? String

        return HStack(alignment: .top, spacing: 10) {
            OERemoteImage(urlString: badgeURLStr, size: 64)
                .opacity(isEarned ? 1 : 0.35)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isEarned ? OEColors.textPrimary : OEColors.textTertiary.opacity(0.6))
                    .lineLimit(2)
                if !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(OEColors.textTertiary)
                        .lineLimit(2)
                }
                HStack(spacing: 4) {
                    if isEarned, let date = earnedDate {
                        Text("Earned · \(date)")
                            .font(.system(size: 11))
                            .foregroundColor(OEColors.textTertiary)
                    }
                    if let pct = percentStr {
                        Text("· \(pct)% of players")
                            .font(.system(size: 11))
                            .foregroundColor(OEColors.textTertiary)
                    }
                }
            }

            Spacer()

            Text("\(points) PTS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isEarned ? OEColors.accent : OEColors.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OEColors.surface)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(OEColors.border, lineWidth: 0.5))
        .opacity(isEarned ? 1 : 0.6)
    }

    // MARK: - Shared helpers

    private func seeAllButton(_ label: String) -> some View {
        Button {} label: {
            HStack(spacing: 3) {
                Text(label).font(.system(size: 12.5, weight: .medium))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(OEColors.accent)
        }
        .buttonStyle(.plain)
        .padding(.trailing, OESpacing.rowPaddingDetail)
    }

    private func pillButton(_ label: String) -> some View {
        Button {} label: {
            HStack(spacing: 3) {
                Text(label).font(.system(size: 12.5, weight: .medium))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(OEColors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(OEColors.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(OEColors.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func glassButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(Color(hex: 0x141416).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func loadImages() {
        Task.detached(priority: .userInitiated) {
            let cover = await OECoverLoader.cover(for: game)
            await MainActor.run { coverImage = cover }

            let bg = await OEHeroArtFetcher.shared.heroArt(for: game)
            await MainActor.run { heroImage = bg }
        }
    }

    private func loadMetadata() {
        raSessionInfo = OERetroAchievementsDataStore.shared.sessionInfo(forGame: game)

        Task {
            let result = await OEGameMetadataCache.shared.fetchOrCacheMetadata(for: game)
            await MainActor.run { metadata = result }
        }
    }
}

// MARK: - Screenshot Thumbnail

struct OEScreenshotThumbnail: View {
    let url: URL
    let label: String

    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    OEColors.surface
                }
            }
            .frame(width: 272, height: 153)
            .clipped()
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(OEColors.border, lineWidth: 0.5))

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.55))
                .cornerRadius(4)
                .padding(8)
        }
        .onAppear { loadImage() }
    }

    private func loadImage() {
        Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url),
                  let img = NSImage(data: data) else { return }
            await MainActor.run { image = img }
        }
    }
}

// MARK: - Video Thumbnail

struct OEVideoThumbnail: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = context.coordinator.player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator {
        let player: AVPlayer
        init(url: URL) {
            let item = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.play()
        }
    }
}

extension OEVideoThumbnail {
    func asView() -> some View {
        self.frame(width: 272, height: 153)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(OEColors.border, lineWidth: 0.5))
    }
}

// MARK: - Remote Image

struct OERemoteImage: View {
    let urlString: String?
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(OEColors.surface)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onAppear { loadImage() }
    }

    private func loadImage() {
        guard let urlString, let url = URL(string: urlString) else { return }
        Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url),
                  let img = NSImage(data: data) else { return }
            await MainActor.run { image = img }
        }
    }
}

// MARK: - Save State Card

struct OESaveStateCard: View {
    let state: OEDBSaveState

    @State private var screenshot: NSImage?

    private var isAutoSave: Bool { state.name == OEDBSaveState.autosaveName }
    private var isQuickSave: Bool { state.name.hasPrefix(OEDBSaveState.quicksaveName) }

    private var slotLabel: String {
        if isAutoSave  { return "AUTOSAVE" }
        if isQuickSave { return "QUICK" }
        // If numeric, prefix with SLOT
        if let _ = Int(state.name) { return "SLOT \(state.name)" }
        return state.name.uppercased()
    }

    private var slotLabelBackground: Color {
        // AUTOSAVE gets dark pill; numbered SLOT labels get blue
        isAutoSave ? Color(hex: 0x000000, opacity: 0.70) : Color(hex: 0x3B82F6, opacity: 0.93)
    }

    private var formattedTimestamp: String {
        guard let date = state.timestamp else { return "" }
        let cal = Calendar.current
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"
        let timeStr = timeFmt.string(from: date)
        if cal.isDateInToday(date)     { return "Today · \(timeStr)" }
        if cal.isDateInYesterday(date) { return "Yesterday · \(timeStr)" }
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEEE"
        return "\(dayFmt.string(from: date)) · \(timeStr)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let img = screenshot {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        OEColors.surface
                    }
                }
                .frame(width: 281, height: 146)
                .clipped()

                Text(slotLabel)
                    .font(.system(size: 9.5, weight: .heavy))
                    .kerning(0.08 * 9.5)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(slotLabelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 3) {
                // Show slot name as location line when it's a named save; fall back to empty
                let nameStr: String = {
                    if isAutoSave  { return "Auto Save" }
                    if isQuickSave { return "Quick Save" }
                    if let _ = Int(state.name) { return "Slot \(state.name)" }
                    return state.name
                }()
                Text(nameStr)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(OEColors.textPrimary)
                    .lineLimit(1)
                Text(formattedTimestamp)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0xEDEDEE, opacity: 0.50))
            }
            .padding(.top, 10)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 282)
        .background(Color(hex: 0xFFFFFF, opacity: 0.039))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xFFFFFF, opacity: 0.078), lineWidth: 0.5))
        .onAppear { loadScreenshot() }
    }

    private func loadScreenshot() {
        Task.detached(priority: .userInitiated) {
            let img = await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
                DispatchQueue.main.async {
                    continuation.resume(returning: NSImage(contentsOf: state.screenshotURL))
                }
            }
            await MainActor.run { screenshot = img }
        }
    }
}
