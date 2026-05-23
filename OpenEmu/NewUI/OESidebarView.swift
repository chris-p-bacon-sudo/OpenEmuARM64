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

enum OENavSection: String, CaseIterable, Identifiable {
    case home           = "Home"
    case recentlyPlayed = "Recently Played"
    case recentlyAdded  = "Recently Added"
    case favorites      = "Favorites"
    case saveStates     = "Save States"
    case search         = "Search"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home:           return "house.fill"
        case .recentlyPlayed: return "clock"
        case .recentlyAdded:  return "plus.square"
        case .favorites:      return "heart"
        case .saveStates:     return "square.and.arrow.down"
        case .search:         return "magnifyingglass"
        }
    }

    var badge: Int? { nil }
}

struct OESidebarView: View {
    @Binding var isOpen: Bool
    @Binding var selectedSection: OENavSection
    @ObservedObject var store: OELibraryStore

    var body: some View {
        HStack(spacing: 0) {
            panel
                .frame(width: 240)
                .background(Color(red: 0.067, green: 0.067, blue: 0.071)) // #111113
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 0.5),
                    alignment: .trailing
                )

            // Dismiss overlay — tapping outside closes sidebar
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { isOpen = false } }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Traffic lights + collapse
            HStack {
                // Traffic lights are rendered by AppKit — reserve space
                Spacer().frame(width: 72)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { isOpen = false }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }
            .frame(height: 52)

            // App identity
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x1c1c1e), Color(hex: 0x2a2a2e)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.85))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text("OpenEmu")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(OEColors.textPrimary)
                    Text("\(store.allGames.count) games · \(store.systems.count) systems")
                        .font(.system(size: 10.5))
                        .foregroundColor(OEColors.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            // Navigation items
            VStack(spacing: 1) {
                ForEach(OENavSection.allCases) { section in
                    navRow(section)
                }
            }
            .padding(.horizontal, 8)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            // Systems
            Text("SYSTEMS")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.7)
                .foregroundColor(OEColors.textTertiary)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(store.systems, id: \.objectID) { system in
                        systemRow(system)
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            // User row
            HStack(spacing: 10) {
                OEUserAvatar(size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(NSFullUserName().isEmpty ? NSUserName() : NSFullUserName())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OEColors.textSecondary)
                        .lineLimit(1)
                    Text("iCloud sync active")
                        .font(.system(size: 10.5))
                        .foregroundColor(OEColors.textTertiary)
                }
                Spacer()
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func navRow(_ section: OENavSection) -> some View {
        Button {
            selectedSection = section
            withAnimation(.easeInOut(duration: 0.25)) { isOpen = false }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14))
                    .foregroundColor(selectedSection == section ? .white.opacity(0.95) : .white.opacity(0.5))
                    .frame(width: 20)

                Text(section.rawValue)
                    .font(.system(size: 13, weight: selectedSection == section ? .medium : .regular))
                    .foregroundColor(selectedSection == section ? OEColors.textPrimary : OEColors.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                selectedSection == section
                    ? RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1))
                    : nil
            )
        }
        .buttonStyle(.plain)
    }

    private func systemRow(_ system: OEDBSystem) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { isOpen = false }
        } label: {
            HStack(spacing: 10) {
                OESystemBadge(system: system, size: 28)

                Text(system.name)
                    .font(.system(size: 13))
                    .foregroundColor(OEColors.textSecondary)
                    .lineLimit(1)

                Spacer()

                Text("\(system.games.count)")
                    .font(.system(size: 11.5))
                    .foregroundColor(OEColors.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

/// Current macOS user avatar — tries Collaboration framework, falls back to initials.
struct OEUserAvatar: View {
    let size: CGFloat
    @State private var avatar: NSImage? = nil

    var body: some View {
        Group {
            if let img = avatar {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    OEColors.accent
                    Text(String(NSFullUserName().prefix(2)).uppercased())
                        .font(.system(size: size * 0.38, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .onAppear { loadAvatar() }
    }

    private func loadAvatar() {
        Task.detached(priority: .userInitiated) {
            let img = OEUserAvatarLoader.load()
            await MainActor.run { avatar = img }
        }
    }
}

/// Loads the current macOS user's profile picture from known system paths.
enum OEUserAvatarLoader {
    static func load() -> NSImage? {
        // Path 1: ~/.face (classic macOS user icon location)
        let facePath = NSHomeDirectory() + "/.face"
        if let img = NSImage(contentsOfFile: facePath) { return img }

        // Path 2: Contacts-synced picture
        let contactsPath = NSHomeDirectory() +
            "/Library/Application Support/Contacts/Images/\(NSUserName()).jpg"
        if let img = NSImage(contentsOfFile: contactsPath) { return img }

        // Path 3: macOS account picture (cached JPEG by login item)
        let accountPaths = [
            "/Library/Caches/com.apple.UserNotificationCenter/\(NSUserName())/profileimage.png",
            NSHomeDirectory() + "/Library/Caches/ProfilePictures.db",
        ]
        for path in accountPaths {
            if let img = NSImage(contentsOfFile: path) { return img }
        }

        return nil
    }
}
