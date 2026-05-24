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

// MARK: - Supporting types

enum LibraryContent {
    case system(OEDBSystem)
    case recentlyPlayed
    case favorites
    case allGames
}

extension LibraryContent: Equatable {
    static func == (lhs: LibraryContent, rhs: LibraryContent) -> Bool {
        switch (lhs, rhs) {
        case (.system(let a), .system(let b)): return a.objectID == b.objectID
        case (.recentlyPlayed, .recentlyPlayed): return true
        case (.favorites, .favorites): return true
        case (.allGames, .allGames): return true
        default: return false
        }
    }
}

enum LibraryViewMode {
    case grid, list
}

enum LibrarySortOrder {
    case recentlyPlayed, alphabetical, playTime

    var label: String {
        switch self {
        case .recentlyPlayed: return "Recently Played"
        case .alphabetical: return "A–Z"
        case .playTime: return "Play Time"
        }
    }

    mutating func cycle() {
        switch self {
        case .recentlyPlayed: self = .alphabetical
        case .alphabetical: self = .playTime
        case .playTime: self = .recentlyPlayed
        }
    }
}

struct LibrarySection: Identifiable {
    let system: OEDBSystem
    let games: [OEDBGame]
    var id: NSManagedObjectID { system.objectID }
}

// MARK: - OELibraryView

struct OELibraryView: View {
    let content: LibraryContent
    @ObservedObject var store: OELibraryStore
    let onBack: () -> Void
    let onPlay: (OEDBGame) -> Void
    var onSelectGame: ((OEDBGame) -> Void)? = nil

    @State private var viewMode: LibraryViewMode = .grid
    @State private var sortOrder: LibrarySortOrder = .recentlyPlayed
    @State private var filterSystem: OEDBSystem? = nil

    private var isCrossSystem: Bool {
        if case .system = content { return false }
        return true
    }

    private var contentTitle: String {
        switch content {
        case .system(let s): return s.name
        case .recentlyPlayed: return "Recently Played"
        case .favorites: return "Favorites"
        case .allGames: return "All Games"
        }
    }

    private var sections: [LibrarySection] {
        switch content {
        case .system(let s):
            let games = sort(store.games(for: s), by: sortOrder)
            return [LibrarySection(system: s, games: games)]

        case .recentlyPlayed:
            return groupedSections(from: store.recentlyPlayedGames)

        case .favorites:
            return groupedSections(from: store.favorites)

        case .allGames:
            return groupedSections(from: store.allGames)
        }
    }

    private var filteredSections: [LibrarySection] {
        guard let filter = filterSystem else { return sections }
        return sections.filter { $0.system.objectID == filter.objectID }
    }

    var body: some View {
        ZStack(alignment: .top) {
            OEColors.background

            VStack(spacing: 0) {
                libraryToolbar
                Rectangle()
                    .fill(OEColors.border)
                    .frame(height: 0.5)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ForEach(filteredSections) { section in
                            OELibrarySectionHeader(
                                system: section.system,
                                count: section.games.count,
                                sortLabel: sortOrder.label
                            )

                            if viewMode == .grid {
                                gridContent(section.games)
                            } else {
                                listContent(section.games)
                            }
                        }

                        if filteredSections.isEmpty {
                            emptyState
                        }

                        Spacer(minLength: 40)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    // MARK: - Toolbar

    private var libraryToolbar: some View {
        HStack(spacing: 0) {
            // Left: back breadcrumb — reserves space matching the sidebar toggle zone
            Spacer().frame(width: 100)

            backButton
                .padding(.trailing, 8)

            // Center: system filter chips (cross-system only)
            if isCrossSystem {
                systemFilterChips
            } else {
                Spacer()
            }

            // Right: sort + view toggle
            HStack(spacing: 6) {
                sortButton
                viewToggle
            }
            .padding(.trailing, 16)
        }
        .frame(height: 52)
        .background(OEColors.background)
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text("Home")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.65))
        }
        .buttonStyle(.plain)
    }

    private var systemFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let systemsInView = sections.map { $0.system }

                OEFilterChip(label: "All", isSelected: filterSystem == nil) {
                    filterSystem = nil
                }
                ForEach(systemsInView, id: \.objectID) { system in
                    OEFilterChip(label: system.name, isSelected: filterSystem?.objectID == system.objectID) {
                        filterSystem = filterSystem?.objectID == system.objectID ? nil : system
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private var sortButton: some View {
        Button {
            sortOrder.cycle()
        } label: {
            HStack(spacing: 4) {
                Text(sortOrder.label)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.65))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.white.opacity(0.05))
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var viewToggle: some View {
        HStack(spacing: 2) {
            toggleButton(icon: "square.grid.2x2", mode: .grid)
            toggleButton(icon: "list.bullet", mode: .list)
        }
        .padding(3)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toggleButton(icon: String, mode: LibraryViewMode) -> some View {
        Button { viewMode = mode } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(viewMode == mode ? .white : .white.opacity(0.4))
                .frame(width: 28, height: 22)
                .background(viewMode == mode ? Color.white.opacity(0.12) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid content

    private func gridContent(_ games: [OEDBGame]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160, maximum: 220))],
            spacing: 16
        ) {
            ForEach(games, id: \.objectID) { game in
                OEGameCardView(
                    game: game,
                    cardHeight: 260,
                    onSelect: { onSelectGame?(game) },
                    onPlay: { onPlay(game) }
                )
            }
        }
        .padding(.horizontal, OESpacing.rowPadding)
        .padding(.vertical, 16)
    }

    // MARK: - List content

    private func listContent(_ games: [OEDBGame]) -> some View {
        VStack(spacing: 0) {
            OEColumnHeaders()

            Rectangle()
                .fill(OEColors.border)
                .frame(height: 0.5)
                .padding(.horizontal, OESpacing.rowPadding)

            ForEach(games, id: \.objectID) { game in
                OEGameListRow(
                    game: game,
                    onSelect: { onSelectGame?(game) },
                    onPlay: { onPlay(game) }
                )
                .padding(.horizontal, OESpacing.rowPadding)

                Rectangle()
                    .fill(OEColors.border)
                    .frame(height: 0.5)
                    .padding(.horizontal, OESpacing.rowPadding)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 40))
                .foregroundColor(OEColors.textTertiary)
            Text("No games here yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(OEColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Helpers

    private func sort(_ games: [OEDBGame], by order: LibrarySortOrder) -> [OEDBGame] {
        switch order {
        case .recentlyPlayed:
            return games.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .alphabetical:
            return games.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .playTime:
            return games.sorted { $0.playTime > $1.playTime }
        }
    }

    private func groupedSections(from games: [OEDBGame]) -> [LibrarySection] {
        var bySystem: [NSManagedObjectID: (OEDBSystem, [OEDBGame])] = [:]
        for game in games {
            guard let system = game.system else { continue }
            let key = system.objectID
            if bySystem[key] == nil {
                bySystem[key] = (system, [])
            }
            bySystem[key]?.1.append(game)
        }

        return bySystem.values
            .map { (system, sectionGames) in
                LibrarySection(system: system, games: sort(sectionGames, by: sortOrder))
            }
            .sorted { $0.system.name.localizedCaseInsensitiveCompare($1.system.name) == .orderedAscending }
    }
}

// MARK: - Section header

struct OELibrarySectionHeader: View {
    let system: OEDBSystem
    let count: Int
    let sortLabel: String

    var body: some View {
        HStack(spacing: 12) {
            OESystemBadge(system: system, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(system.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(OEColors.textPrimary)
                Text("\(count) games · sorted by \(sortLabel)")
                    .font(.system(size: 11.5))
                    .foregroundColor(OEColors.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, OESpacing.rowPadding)
        .padding(.vertical, 14)
    }
}
