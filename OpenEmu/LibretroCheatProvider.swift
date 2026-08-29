// Copyright (c) 2026, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted under the BSD 2-Clause license.

import Foundation
import OpenEmuBase
import os.log

private let log = Logger(subsystem: "org.openemu.OpenEmu", category: "LibretroCheatProvider")

final class LibretroCheatProvider: CheatDatabaseProvider {

    let name = "Libretro"

    private static let datBaseURL = "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/no-intro/"

    // OpenEmu system ID → Libretro directory/DAT name
    private let systemMap: [String: String] = [
        OESystemIdentifierAtari2600: "Atari - 2600",
    ]

    // In-memory cache: systemIdentifier → [uppercased MD5 → game name]
    private var datCache: [String: [String: String]] = [:]

    func supportsSystem(_ systemIdentifier: String) -> Bool {
        systemMap[systemIdentifier] != nil
    }

    func cheats(forMD5 md5: String, systemIdentifier: String) async throws -> [DatabaseCheat] {
        let gameName = try await lookupGameName(md5: md5, systemIdentifier: systemIdentifier)
        guard let gameName else {
            log.info("No game found for MD5 \(md5) in system \(systemIdentifier)")
            return []
        }
        log.info("MD5 \(md5) → CHT file: \(gameName).cht")

        // TODO: 2. Check local cache (ETag-based freshness)
        // TODO: 3. Fetch CHT file from raw.githubusercontent.com if needed
        // TODO: 4. Parse CHT file (handle both code-based and address-based formats)
        // TODO: 5. Filter empty codes, clean up, cache result
        return []
    }

    // MARK: - DAT Lookup

    private func lookupGameName(md5: String, systemIdentifier: String) async throws -> String? {
        if let cached = datCache[systemIdentifier] {
            log.debug("DAT cache hit for \(systemIdentifier)")
            return cached[md5.uppercased()]
        }

        guard let libretroSystem = systemMap[systemIdentifier] else { return nil }
        log.info("Downloading DAT for \(libretroSystem)…")

        let encoded = libretroSystem.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? libretroSystem
        let urlString = "\(Self.datBaseURL)\(encoded).dat"
        guard let url = URL(string: urlString) else { return nil }

        let (data, _) = try await URLSession.shared.data(from: url)
        let parsed = parseDATFile(data)
        datCache[systemIdentifier] = parsed
        log.info("DAT loaded for \(libretroSystem): \(parsed.count) games indexed")

        return parsed[md5.uppercased()]
    }

    // MARK: - DAT Parser (clrmamepro format)

    /// Parses a No-Intro DAT file and returns [uppercased MD5 → game name].
    private func parseDATFile(_ data: Data) -> [String: String] {
        guard let content = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        var currentName: String?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("name \"") {
                let start = trimmed.index(trimmed.startIndex, offsetBy: 6)
                if let end = trimmed.lastIndex(of: "\""), end > start {
                    currentName = String(trimmed[start..<end])
                }
            } else if trimmed.contains("md5 "), let name = currentName {
                if let md5Range = trimmed.range(of: "md5 ") {
                    let afterMD5 = trimmed[md5Range.upperBound...]
                    let md5Value = afterMD5.prefix(while: { !$0.isWhitespace })
                    if md5Value.count == 32 {
                        result[md5Value.uppercased()] = name
                    }
                }
            }
        }
        return result
    }
}
