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

/// Observable bridge between OELibraryDatabase (Core Data / ObjC) and the SwiftUI view layer.
/// Wraps the existing data layer — no migration, no schema changes.
@MainActor
final class OELibraryStore: ObservableObject {

    static let shared = OELibraryStore()

    @Published private(set) var systems: [OEDBSystem] = []
    @Published private(set) var recentlyPlayedGames: [OEDBGame] = []
    @Published private(set) var allGames: [OEDBGame] = []
    @Published private(set) var favorites: [OEDBGame] = []
    @Published private(set) var saveStates: [OEDBSaveState] = []

    private var notificationObserver: NSObjectProtocol?

    init() {
        // Don't call reload() here — Core Data context isn't ready at init time.
        // Load is triggered by the .libraryDidLoad notification or explicit reload() call.
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .libraryDidLoad,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let obs = notificationObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func reload() {
        guard let db = OELibraryDatabase.default else { return }
        let ctx = db.mainThreadContext

        // Use OE's own high-level APIs — raw fetch requests on nested contexts
        // are unsafe due to NSException propagation through OE's writer/view context stack.
        // Sort systems by most recently played game across the system
        let loadedSystems = OEDBSystem.allSystems(in: ctx)
            .filter { $0.games.count > 0 }
            .sorted { sysA, sysB in
                let latestA = sysA.games.compactMap { $0.lastPlayed }.max() ?? .distantPast
                let latestB = sysB.games.compactMap { $0.lastPlayed }.max() ?? .distantPast
                return latestA > latestB
            }
        systems = loadedSystems

        // Build the full game list from system sets (avoids direct fetch)
        let all = loadedSystems.flatMap { Array($0.games) }
        allGames = all.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }

        recentlyPlayedGames = allGames
            .filter { $0.lastPlayed != nil }
            .prefix(20)
            .map { $0 }

        favorites = []

        // Save states via OEDBGame's roms (avoids unsafe fetch on writer context)
        let states = allGames.flatMap { game in
            game.roms.flatMap { Array($0.saveStates) }
        }
        saveStates = states
            .sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            .prefix(20)
            .map { $0 }
    }

    func games(for system: OEDBSystem) -> [OEDBGame] {
        system.games.sorted {
            ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast)
        }
    }

    var heroGame: OEDBGame? {
        recentlyPlayedGames.first
    }
}
