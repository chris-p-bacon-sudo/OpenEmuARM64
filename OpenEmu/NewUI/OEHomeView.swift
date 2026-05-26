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

/// Root view for the OpenEmu home screen — Cinematic direction.
/// The title bar floats transparently over the hero; sidebar slides in from the left.
struct OEHomeView: View {

    @StateObject private var store = OELibraryStore.shared
    @State private var selectedTab: OENavTab = .home
    @State private var selectedSection: OENavSection = .home
    @State private var heroIndex: Int = 0
    @State private var sidebarOpen: Bool = false
    @State private var detailGame: OEDBGame? = nil
    @State private var libraryContent: LibraryContent? = nil
    @Binding var gameToLaunch: OEDBGame?

    private var heroGames: [OEDBGame] { Array(store.recentlyPlayedGames.prefix(3)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                // Sidebar slides in from the left — pushes content right
                if sidebarOpen {
                    OESidebarView(
                        selectedSection: $selectedSection,
                        store: store
                    )
                    .transition(.move(edge: .leading))
                    .zIndex(10)
                }

                // Main content fills remaining space
                ZStack(alignment: .top) {
                    OEColors.background

                    if let game = detailGame {
                        OEGameDetailView(
                            game: game,
                            onBack: { withAnimation(.easeInOut(duration: 0.2)) { detailGame = nil } },
                            onPlay: { gameToLaunch = game },
                            onSelectGame: { g in
                                withAnimation(.easeInOut(duration: 0.2)) { detailGame = g }
                            }
                        )
                        .transition(.opacity)
                    } else if let content = libraryContent {
                        OELibraryView(
                            content: content,
                            store: store,
                            onBack: { withAnimation(.easeInOut(duration: 0.2)) { libraryContent = nil } },
                            onPlay: { gameToLaunch = $0 },
                            onSelectGame: { game in
                                withAnimation(.easeInOut(duration: 0.2)) { detailGame = game }
                            }
                        )
                        .transition(.opacity)
                    } else {
                        scrollContent
                        floatingNavBar
                    }
                }
                .clipped()
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.25), value: sidebarOpen)
            .preferredColorScheme(.dark)

            // Sidebar toggle pinned at the same window-level position in both states:
            // closed → x≈78 in full window; open → x≈(sidebarWidth-28-12) in sidebar area.
            // Keeping it here in the outer ZStack means sidebarOpen is always mutated
            // directly — no binding indirection, no hit-test conflicts.
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer().frame(width: sidebarOpen ? 200 : 100)
                    glassButton(icon: "sidebar.left") {
                        sidebarOpen.toggle()
                    }
                    Spacer()
                }
                .frame(height: 52)
                Spacer()
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedSection) { section in
            withAnimation(.easeInOut(duration: 0.2)) {
                switch section {
                case .recentlyPlayed: libraryContent = .recentlyPlayed
                case .favorites:      libraryContent = .favorites
                case .home:           libraryContent = nil; detailGame = nil
                default:              break
                }
            }
        }
        .onChange(of: heroGames.count) { count in
            if heroIndex >= count { heroIndex = max(0, count - 1) }
        }
    }

    // MARK: - Floating nav bar

    /// Transparent title bar that floats over the hero art.
    private var floatingNavBar: some View {
        ZStack {
            // Subtle top gradient so traffic lights and nav are readable over art
            LinearGradient(
                colors: [Color.black.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)
            .ignoresSafeArea()

            HStack(spacing: 0) {
                // Left: when sidebar is closed, show only the toggle after the traffic lights.
                // When sidebar is open, the toggle lives in the sidebar header instead — nothing here.
                // Spacer reserves the toggle button's width so the nav pill stays centered
                Spacer().frame(width: 106)

                Spacer()

                // Center: pill nav
                OENavBar(selectedTab: $selectedTab)

                Spacer()

                // Right: search + avatar
                HStack(spacing: 8) {
                    glassButton(icon: "magnifyingglass") { /* TODO: search */ }

                    OEUserAvatar(size: 28)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                }
                .padding(.trailing, 16)
            }
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func glassButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(Color(hex: 0x141416).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scrollable content

    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Hero — starts at the very top, nav floats over it
                if !heroGames.isEmpty {
                    let hero = heroGames[heroIndex]
                    OEHeroView(
                        game: hero,
                        currentIndex: heroIndex,
                        totalCount: heroGames.count
                    ) {
                        gameToLaunch = hero
                    } onDotTap: { idx in
                        withAnimation(.easeInOut(duration: 0.3)) { heroIndex = idx }
                    }
                    .id(heroIndex)
                }

                // Continue Playing — icon strip
                if !store.recentlyPlayedGames.isEmpty {
                    OEContinuePlayingRow(games: store.recentlyPlayedGames) { game in
                        withAnimation(.easeInOut(duration: 0.2)) { detailGame = game }
                    }
                    .padding(.top, 28)
                    .padding(.bottom, OESpacing.sectionGap)
                }

                // Recent Saves
                if !store.saveStates.isEmpty {
                    OERecentSavesSection(
                        saves: store.saveStates,
                        onResume: { state in
                            if let game = state.rom?.game { gameToLaunch = game }
                        },
                        onSeeAll: {
                            withAnimation(.easeInOut(duration: 0.2)) { libraryContent = .allGames }
                        }
                    )
                    .padding(.bottom, OESpacing.sectionGap)
                }

                // Browse by Genre
                OEBrowseByGenreSection(games: store.allGames)
                    .padding(.bottom, OESpacing.sectionGap)

                // Recently Added
                if !store.recentlyAddedGames.isEmpty {
                    OERecentlyAddedSection(
                        games: store.recentlyAddedGames,
                        onPlay: { gameToLaunch = $0 },
                        onSelectGame: { game in
                            withAnimation(.easeInOut(duration: 0.2)) { detailGame = game }
                        },
                        onSeeAll: {
                            withAnimation(.easeInOut(duration: 0.2)) { libraryContent = .allGames }
                        }
                    )
                    .padding(.bottom, OESpacing.sectionGap)
                }

                // Most Played
                if !store.mostPlayedGames.isEmpty {
                    OEMostPlayedSection(
                        games: store.mostPlayedGames,
                        onPlay: { gameToLaunch = $0 },
                        onSelectGame: { game in
                            withAnimation(.easeInOut(duration: 0.2)) { detailGame = game }
                        },
                        onSeeAll: {
                            withAnimation(.easeInOut(duration: 0.2)) { libraryContent = .favorites }
                        }
                    )
                    .padding(.bottom, OESpacing.sectionGap)
                }

                // Rediscover banner
                if let game = store.rediscoverGame {
                    OERediscoverBanner(game: game) { gameToLaunch = game }
                        .padding(.bottom, OESpacing.sectionGap)
                }

                Spacer(minLength: 32)
            }
        }
    }
}

/// Pill-shaped filter chip.
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
                .background(isSelected ? Color(hex: 0xf5f5f7) : Color.white.opacity(0.05))
                .overlay(Capsule().stroke(isSelected ? .clear : Color.white.opacity(0.12), lineWidth: 0.5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
