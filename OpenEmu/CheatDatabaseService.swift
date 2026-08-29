// Copyright (c) 2026, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted under the BSD 2-Clause license.

import Foundation

/// A cheat entry returned by a provider, before import into the user's cheat list.
struct DatabaseCheat: Sendable {
    let name: String
    let code: String
    let providerName: String
}

/// A source of cheat codes for a given system and ROM.
protocol CheatDatabaseProvider {
    var name: String { get }
    func supportsSystem(_ systemIdentifier: String) -> Bool
    func cheats(forMD5 md5: String, systemID: String) async throws -> [DatabaseCheat]
}

/// Facade that aggregates cheat database providers and presents a unified interface to the UI.
final class CheatDatabaseService {

    static let shared = CheatDatabaseService()

    private let providers: [CheatDatabaseProvider]

    init(providers: [CheatDatabaseProvider] = []) {
        self.providers = providers
    }

    /// Returns true if any registered provider supports the given system.
    func supportsSystem(_ systemIdentifier: String) -> Bool {
        providers.contains { $0.supportsSystem(systemIdentifier) }
    }

    /// Fetches cheats from all providers that support the system, merges and returns them.
    func cheats(forMD5 md5: String, systemID: String) async throws -> [DatabaseCheat] {
        // TODO: query each supporting provider concurrently, merge results
        var results: [DatabaseCheat] = []
        for provider in providers where provider.supportsSystem(systemID) {
            let providerCheats = try await provider.cheats(forMD5: md5, systemID: systemID)
            results.append(contentsOf: providerCheats)
        }
        return results
    }
}
