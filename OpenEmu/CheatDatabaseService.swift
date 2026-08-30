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
    func cheats(forMD5 md5: String, systemIdentifier: String) async throws -> [DatabaseCheat]
}

/// Facade that aggregates cheat database providers and presents a unified interface to the UI.
final class CheatDatabaseService {

    static let shared = CheatDatabaseService(providers: [OpenEmuCheatProvider(), LibretroCheatProvider()])

    private let providers: [CheatDatabaseProvider]

    init(providers: [CheatDatabaseProvider]) {
        self.providers = providers
    }

    /// Returns true if any registered provider supports the given system.
    func supportsSystem(_ systemIdentifier: String) -> Bool {
        providers.contains { $0.supportsSystem(systemIdentifier) }
    }

    /// Fetches cheats from all providers that support the system, merges and deduplicates.
    /// Provider ordering determines precedence — earlier providers win on duplicate codes.
    func cheats(forMD5 md5: String, systemIdentifier: String) async throws -> [DatabaseCheat] {
        var results: [DatabaseCheat] = []
        var seenCodes: Set<String> = []
        for provider in providers where provider.supportsSystem(systemIdentifier) {
            let providerCheats = try await provider.cheats(forMD5: md5, systemIdentifier: systemIdentifier)
            for cheat in providerCheats {
                let normalized = cheat.code.replacingOccurrences(of: " ", with: "").lowercased()
                guard !seenCodes.contains(normalized) else { continue }
                seenCodes.insert(normalized)
                results.append(cheat)
            }
        }
        return results
    }
}
