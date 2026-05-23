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
    @State private var selectedSystem: OEDBSystem? = nil
    @State private var heroIndex: Int = 0
    @State private var sidebarOpen: Bool = false
    @Binding var gameToLaunch: OEDBGame?

    private var heroGames: [OEDBGame] { Array(store.recentlyPlayedGames.prefix(3)) }
    private var filteredSystems: [OEDBSystem] {
        guard let filter = selectedSystem else { return store.systems }
        return [filter]
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar slides in from the left — pushes content right
            if sidebarOpen {
                OESidebarView(
                    isOpen: $sidebarOpen,
                    selectedSection: $selectedSection,
                    store: store
                )
                .transition(.move(edge: .leading))
                .zIndex(10)
            }

            // Main content fills remaining space
            ZStack(alignment: .top) {
                OEColors.background
                scrollContent
                floatingNavBar
            }
        }
        .ignoresSafeArea()  // hero fills behind the transparent title bar area
        .animation(.easeInOut(duration: 0.25), value: sidebarOpen)
        .preferredColorScheme(.dark)
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
                // Left: align buttons to the AppKit traffic lights vertical center.
                // Traffic lights live in the standard ~28pt title bar area (top of the nav),
                // so we pin the button group to the top 28pt of our 52pt nav bar.
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Spacer().frame(width: 72) // AppKit traffic lights

                        glassButton(icon: "sidebar.left") {
                            withAnimation(.easeInOut(duration: 0.25)) { sidebarOpen.toggle() }
                        }
                        glassButton(icon: "chevron.left") { /* TODO: nav stack */ }
                    }
                    .frame(height: 28) // match AppKit title bar height → same vertical center
                    Spacer()
                }
                .frame(height: 52)

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
                    .padding(.bottom, -20)
                    .id(heroIndex)
                }

                // System filter chips
                systemFilterRow
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                // Per-system game rows
                ForEach(filteredSystems, id: \.objectID) { system in
                    let games = store.games(for: system)
                    if !games.isEmpty {
                        OEGameRowView(system: system, games: games) { game in
                            gameToLaunch = game
                        } onSeeAll: { _ in }
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
                OEFilterChip(label: "All Systems", isSelected: selectedSystem == nil) {
                    selectedSystem = nil
                }
                ForEach(store.systems, id: \.objectID) { system in
                    OEFilterChip(label: system.name, isSelected: selectedSystem == system) {
                        selectedSystem = system
                    }
                }
            }
            .padding(.horizontal, OESpacing.rowPadding)
            .padding(.vertical, 4)
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
