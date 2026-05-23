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

/// Root view for the new OpenEmu home screen (Direction A — Faithful).
/// Hosted inside OENewMainWindowController via NSHostingController.
struct OEHomeView: View {

    @StateObject private var store = OELibraryStore.shared
    @State private var selectedTab: OENavTab = .home
    @State private var selectedSystem: OEDBSystem? = nil
    @State private var heroIndex: Int = 0
    @Binding var gameToLaunch: OEDBGame?

    private var heroGames: [OEDBGame] {
        Array(store.recentlyPlayedGames.prefix(3))
    }

    private var filteredSystems: [OEDBSystem] {
        guard let filter = selectedSystem else { return store.systems }
        return [filter]
    }

    var body: some View {
        ZStack(alignment: .top) {
            OEColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                titleBar
                scrollContent
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Title bar

    private var titleBar: some View {
        ZStack {
            // Title bar background
            Rectangle()
                .fill(Color(hex: 0x141416).opacity(0.9))
                .overlay(
                    Rectangle()
                        .fill(OEColors.border)
                        .frame(height: 0.5),
                    alignment: .bottom
                )

            HStack {
                // Traffic lights are rendered by AppKit — just reserve space
                Spacer().frame(width: 72)

                Spacer()
                OENavBar(selectedTab: $selectedTab)
                Spacer()

                // Right actions
                HStack(spacing: 8) {
                    Button {
                        // TODO: trigger search
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.65))
                    }
                    .buttonStyle(.plain)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [OEColors.accent, OEColors.accent.opacity(0.67)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text("JK")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .padding(.trailing, 16)
            }
        }
        .frame(height: 52)
    }

    // MARK: - Scrollable content

    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Hero
                if !heroGames.isEmpty {
                    let hero = heroGames[heroIndex]
                    OEHeroView(
                        game: hero,
                        currentIndex: heroIndex,
                        totalCount: heroGames.count
                    ) {
                        gameToLaunch = hero
                    } onDotTap: { idx in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            heroIndex = idx
                        }
                    }
                    .padding(.bottom, -20)
                    .id(heroIndex) // forces full redraw + art reload on switch
                }

                // System filter chips
                systemFilterRow
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                // Per-system game rows
                ForEach(filteredSystems, id: \.objectID) { system in
                    let games = store.games(for: system)
                    if !games.isEmpty {
                        OEGameRowView(
                            system: system,
                            games: games
                        ) { game in
                            gameToLaunch = game
                        } onSeeAll: { _ in
                            // TODO: push library view
                        }
                        .padding(.bottom, OESpacing.sectionGap)
                    }
                }

                Spacer(minLength: 32)
            }
        }
    }

    // MARK: - System filter chips

    private var systemFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All Systems chip
                OEFilterChip(
                    label: "All Systems",
                    isSelected: selectedSystem == nil
                ) {
                    selectedSystem = nil
                }

                ForEach(store.systems, id: \.objectID) { system in
                    OEFilterChip(
                        label: system.name ?? "",
                        isSelected: selectedSystem == system
                    ) {
                        selectedSystem = system
                    }
                }
            }
            .padding(.horizontal, OESpacing.rowPadding)
            .padding(.vertical, 4)
        }
    }
}

/// Pill-shaped filter chip matching the design.
struct OEFilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(isSelected ? Color(hex: 0x0a0a0c) : OEColors.textSecondary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    isSelected
                        ? Color(hex: 0xf5f5f7)
                        : Color.white.opacity(0.05)
                )
                .overlay(
                    Capsule().stroke(
                        isSelected ? Color.clear : Color.white.opacity(0.12),
                        lineWidth: 0.5
                    )
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
