// Copyright (c) 2026, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted under the BSD 2-Clause license.

import Foundation
import OpenEmuBase
import os.log

private let log = Logger(subsystem: "org.openemu.OpenEmu", category: "LibretroCheatProvider")

/// Cached cheat file stored on disk per game.
private struct LibretroCachedCheatFile: Codable {
    let chtFileName: String
    let etag: String?
    let cheats: [LibretroCachedCheat]
}

private struct LibretroCachedCheat: Codable {
    let name: String
    let code: String
}

final class LibretroCheatProvider: CheatDatabaseProvider {

    let name = "Libretro"

    private static let datBaseURL = "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/no-intro/"
    private static let chtBaseURL = "https://raw.githubusercontent.com/libretro/libretro-database/master/cht/"

    // OpenEmu system ID → Libretro directory/DAT name
    private let systemMap: [String: String] = [
        OESystemIdentifierAtari2600: "Atari - 2600",
        OESystemIdentifierSMS:       "Sega - Master System - Mark III",
        OESystemIdentifierNES:       "Nintendo - Nintendo Entertainment System",
        OESystemIdentifierFDS:       "Nintendo - Family Computer Disk System",
        OESystemIdentifierN64:       "Nintendo - Nintendo 64",
        OESystemIdentifierGenesis:   "Sega - Mega Drive - Genesis",
    ]

    // In-memory cache: systemIdentifier → [uppercased MD5 → game name]
    private var datCache: [String: [String: String]] = [:]

    func supportsSystem(_ systemIdentifier: String) -> Bool {
        systemMap[systemIdentifier] != nil
    }

    func cheats(forMD5 md5: String, systemIdentifier: String) async throws -> [DatabaseCheat] {
        guard let libretroSystem = systemMap[systemIdentifier] else { return [] }

        // 1. Check local cache
        if let cached = loadCachedCheats(md5: md5, systemIdentifier: systemIdentifier) {
            log.info("Local cache hit for \(md5) (\(cached.chtFileName))")
            // Try to update in case there's a newer version
            let updated = try await fetchAndCacheCHT(
                chtFileName: cached.chtFileName,
                libretroSystem: libretroSystem,
                md5: md5,
                systemIdentifier: systemIdentifier,
                existingETag: cached.etag
            )
            // If 304 not modified, return cached; otherwise return updated
            let cheats = updated ?? cached.cheats
            return cheats.map { DatabaseCheat(name: $0.name, code: $0.code, providerName: name) }
        }

        // 2. No local cache — resolve game name via DAT
        let gameName = try await lookupGameName(md5: md5, systemIdentifier: systemIdentifier)
        guard let gameName else {
            log.info("No game found for MD5 \(md5) in system \(systemIdentifier)")
            return []
        }
        let chtFileName = "\(gameName).cht"
        log.info("MD5 \(md5) → \(chtFileName)")

        // 3. Download and cache the CHT file
        let cheats = try await fetchAndCacheCHT(
            chtFileName: chtFileName,
            libretroSystem: libretroSystem,
            md5: md5,
            systemIdentifier: systemIdentifier,
            existingETag: nil
        )
        guard let cheats else {
            log.info("No CHT file found for \(chtFileName)")
            return []
        }
        return cheats.map { DatabaseCheat(name: $0.name, code: $0.code, providerName: name) }
    }

    // MARK: - Local Cache

    private func cacheFileURL(md5: String, systemIdentifier: String) -> URL? {
        guard let base = OELibraryDatabase.default?.databaseFolderURL else { return nil }
        let dir = base
            .appendingPathComponent("CheatDatabase", isDirectory: true)
            .appendingPathComponent("libretro", isDirectory: true)
            .appendingPathComponent(systemIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(md5.uppercased()).json")
    }

    private func loadCachedCheats(md5: String, systemIdentifier: String) -> LibretroCachedCheatFile? {
        guard let url = cacheFileURL(md5: md5, systemIdentifier: systemIdentifier),
              let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(LibretroCachedCheatFile.self, from: data)
        else { return nil }
        return cached
    }

    private func saveCachedCheats(_ file: LibretroCachedCheatFile, md5: String, systemIdentifier: String) {
        guard let url = cacheFileURL(md5: md5, systemIdentifier: systemIdentifier),
              let data = try? JSONEncoder().encode(file)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - CHT Fetch

    /// Downloads (or conditionally updates) a CHT file. Returns parsed cheats, or nil if 304/not found.
    private func fetchAndCacheCHT(
        chtFileName: String,
        libretroSystem: String,
        md5: String,
        systemIdentifier: String,
        existingETag: String?
    ) async throws -> [LibretroCachedCheat]? {
        let encoded = "\(libretroSystem)/\(chtFileName)"
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? chtFileName
        guard let url = URL(string: "\(Self.chtBaseURL)\(encoded)") else { return nil }

        var request = URLRequest(url: url)
        if let etag = existingETag {
            request.setValue("\"\(etag)\"", forHTTPHeaderField: "If-None-Match")
            log.debug("Checking for CHT update: \(chtFileName)")
        } else {
            log.info("Downloading CHT: \(chtFileName)")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return nil }

        switch httpResponse.statusCode {
        case 304:
            log.debug("CHT not modified: \(chtFileName)")
            return nil
        case 404:
            log.info("CHT not found: \(chtFileName)")
            return nil
        case 200:
            break
        default:
            log.warning("Unexpected HTTP \(httpResponse.statusCode) for \(chtFileName)")
            return nil
        }

        let newETag = httpResponse.value(forHTTPHeaderField: "ETag")?.replacingOccurrences(of: "\"", with: "")
        let cheats = parseCHTFile(data, systemIdentifier: systemIdentifier)
        log.info("CHT parsed: \(chtFileName) → \(cheats.count) cheats")

        let cached = LibretroCachedCheatFile(chtFileName: chtFileName, etag: newETag, cheats: cheats)
        saveCachedCheats(cached, md5: md5, systemIdentifier: systemIdentifier)

        return cheats
    }

    // MARK: - CHT Parser

    private func parseCHTFile(_ data: Data, systemIdentifier: String) -> [LibretroCachedCheat] {
        guard let content = String(data: data, encoding: .utf8) else { return [] }

        // Group fields by cheat index: "cheat0" → ["desc": "...", "code": "...", "address": "...", ...]
        var groups: [String: [String: String]] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let eqRange = trimmed.range(of: " = ") else { continue }

            let key = String(trimmed[..<eqRange.lowerBound])
            let raw = String(trimmed[eqRange.upperBound...])
            let value = raw.hasPrefix("\"") && raw.hasSuffix("\"") && raw.count >= 2
                ? String(raw.dropFirst().dropLast())
                : raw

            // Split "cheat0_desc" → prefix "cheat0", field "desc"
            guard let underIdx = key.firstIndex(of: "_") else { continue }
            let prefix = String(key[..<underIdx])
            let field = String(key[key.index(after: underIdx)...])
            groups[prefix, default: [:]][field] = value
        }

        var cheats: [LibretroCachedCheat] = []
        var seenCodes: Set<String> = []

        for index in 0..<groups.count {
            let prefix = "cheat\(index)"
            guard let fields = groups[prefix] else { continue }
            guard let desc = fields["desc"], !desc.isEmpty else { continue }

            var code = fields["code"] ?? ""

            // If code is empty, try to synthesize from address + value (Format B)
            // TODO: handle big_endian and memory_search_size for multi-byte systems
            // TODO: filter by cheat_type — only type 1 (set to value) is usable; types 2-7 need RetroArch's RAM engine
            if code.isEmpty, let addrStr = fields["address"], let valStr = fields["value"],
               let addr = UInt(addrStr), let val = UInt(valStr) {
                code = String(format: "%02X:%02X", addr, val)
            }

            guard !code.isEmpty else { continue }
            // Normalize separators: some CHT files use ';' instead of '+'
            var cleaned = code.replacingOccurrences(of: " ", with: "")
                              .replacingOccurrences(of: ";", with: "+")
            cleaned = normalizeCode(cleaned, systemIdentifier: systemIdentifier)
            guard !seenCodes.contains(cleaned) else { continue }
            seenCodes.insert(cleaned)
            cheats.append(LibretroCachedCheat(name: desc, code: cleaned))
        }

        return cheats
    }

    /// Normalizes non-standard code formats into forms the core can parse.
    private func normalizeCode(_ code: String, systemIdentifier: String) -> String {
        switch systemIdentifier {
        case OESystemIdentifierGenesis:
            return normalizeGenesisCode(code)
        default:
            return code
        }
    }

    private func normalizeGenesisCode(_ code: String) -> String {
        // 10 hex chars without separator → insert colon at position 6 (e.g., FF00220010 → FF0022:0010)
        if code.count == 10 && !code.contains(":") && !code.contains("-") && code.allSatisfy(\.isHexDigit) {
            let idx = code.index(code.startIndex, offsetBy: 6)
            return "\(code[..<idx]):\(code[idx...])"
        }
        // Handle '+' used as address/value separator instead of multi-code joiner.
        // Pattern: alternating 6-hex and 4-hex parts (e.g., FF002C+1800 or FF002C+1800+FF003C+2800)
        let parts = code.split(separator: "+")
        if parts.count >= 2 && parts.count.isMultiple(of: 2) {
            var pairs: [String] = []
            var i = 0
            while i < parts.count - 1 {
                let addr = parts[i], val = parts[i + 1]
                if addr.count == 6 && val.count == 4
                    && addr.allSatisfy(\.isHexDigit) && val.allSatisfy(\.isHexDigit) {
                    pairs.append("\(addr):\(val)")
                    i += 2
                } else {
                    return code
                }
            }
            if !pairs.isEmpty { return pairs.joined(separator: "+") }
        }
        return code
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
