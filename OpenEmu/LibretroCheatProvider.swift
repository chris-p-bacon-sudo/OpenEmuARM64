// Copyright (c) 2026, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted under the BSD 2-Clause license.

import Foundation
import OpenEmuBase

final class LibretroCheatProvider: CheatDatabaseProvider {

    let name = "Libretro"

    // OpenEmu system ID → Libretro CHT directory name
    private let systemMap: [String: String] = [
        OESystemIdentifierAtari2600: "Atari - 2600",
    ]

    func supportsSystem(_ systemIdentifier: String) -> Bool {
        systemMap[systemIdentifier] != nil
    }

    func cheats(forMD5 md5: String, systemIdentifier: String) async throws -> [DatabaseCheat] {
        // TODO: 1. Look up game name from DAT file (MD5 → name)
        // TODO: 2. Check local cache (ETag-based freshness)
        // TODO: 3. Fetch CHT file from raw.githubusercontent.com if needed
        // TODO: 4. Parse CHT file (handle both code-based and address-based formats)
        // TODO: 5. Filter empty codes, clean up, cache result
        return []
    }
}
