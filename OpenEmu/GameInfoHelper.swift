// Copyright (c) 2021, OpenEmu Team
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

import Foundation
import OpenEmuSystem

final class GameInfoHelper {

    static let shared = GameInfoHelper()

    var database: OpenVGDB? {
        return OpenVGDB.shared.isAvailable ? OpenVGDB.shared : nil
    }

    func gameInfo(withDictionary gameInfo: [String : Any]) -> [String : Any] {

        DispatchQueue(label: "org.openemu.OpenEmu.GameInfoHelper").sync {

            lazy var resultDict: [String : Any] = [:]

            let systemIdentifier = gameInfo["systemIdentifier"] as! String
            var header = gameInfo["header"] as? String
            var serial = gameInfo["serial"] as? String
            let md5 = gameInfo["md5"] as? String
            let url = gameInfo["URL"] as? URL

            // ScreenScraper credentials — resolved lazily so we don't hit the Keychain
            // on every ROM lookup (e.g. during a full library scan).
            lazy var hasSScredentials: Bool = {
                let user = UserDefaults.standard.string(forKey: "ScreenScraperUsername") ?? ""
                guard !user.isEmpty else { return false }
                return !(ScreenScraperCredentials.storedPassword() ?? "").isEmpty
            }()

            guard let database = database else {
                // OpenVGDB unavailable.
                // Priority 1: ScreenScraper when the user has credentials configured.
                // If they have NOT logged in to ScreenScraper we return empty here;
                // fuzzy logic requires OpenVGDB, so there is nothing else we can do.
                guard hasSScredentials else { return [:] }

                // FIX: preserve the file extension so ScreenScraper can disambiguate
                // ROMs that share the same name across platforms (e.g. .n64 vs .sfc).
                let romName = url?.lastPathComponent
                var fallback: [String: Any] = [:]
                if let ss = ScreenScraperClient.shared.fetchGameInfo(md5: md5, romName: romName, systemIdentifier: systemIdentifier) {
                    if let boxURL = ss.boxImageURL { fallback["boxImageURL"] = boxURL.absoluteString }
                    if let title = ss.gameTitle   { fallback["gameTitle"] = title }
                    if let desc  = ss.gameDescription { fallback["gameDescription"] = desc }
                }

                // Tier 3: libretro-thumbnails — no credentials, best-effort name match
                if fallback["boxImageURL"] == nil, let title = fallback["gameTitle"] as? String {
                    if let ltURL = LibretroThumbnailsClient.shared.fetchBoxArtURL(gameName: title, systemIdentifier: systemIdentifier) {
                        fallback["boxImageURL"] = ltURL
                    }
                }
                return fallback
            }

            // --- OpenVGDB is available below this point ---

            let archiveFileIndex = gameInfo["archiveFileIndex"] as? NSNumber

            var isSystemWithHashlessROM = hashlessROMCheck(forSystem: systemIdentifier)
            var isSystemWithROMHeader   = headerROMCheck(forSystem: systemIdentifier)
            var isSystemWithROMSerial   = serialROMCheck(forSystem: systemIdentifier)
            var headerSize              = sizeOfROMHeader(forSystem: systemIdentifier)

            let DBMD5Key                       = "romHashMD5"
            let DBROMExtensionlessFileNameKey   = "romExtensionlessFileName"
            let DBROMHeaderKey                 = "romHeader"
            let DBROMSerialKey                 = "romSerial"

            var key: String?
            var value: String?

            let determineQueryParams: (() -> Void) = {

                if value != nil { return }

                if isSystemWithHashlessROM, let url = url {
                    key   = DBROMExtensionlessFileNameKey
                    value = (url.lastPathComponent as NSString).deletingPathExtension.lowercased()
                }
                else if isSystemWithROMHeader {
                    key   = DBROMHeaderKey
                    value = header?.uppercased()
                }
                else if isSystemWithROMSerial {
                    key   = DBROMSerialKey
                    value = serial?.uppercased()
                }
                else if headerSize == 0, let md5 = md5 {
                    key   = DBMD5Key
                    value = md5.uppercased()
                }
            }

            determineQueryParams()

            if value == nil, let url = url {

                var removeFile = false
                var romURL: URL
                if let archiveFileIndex = archiveFileIndex as? Int,
                   let archiveURL = ArchiveHelper.decompressFileInArchive(at: url, atIndex: archiveFileIndex) {
                    romURL     = archiveURL
                    removeFile = true
                } else {
                    romURL = url
                }

                var file: OEFile
                do {
                    file = try OEFile(url: romURL)
                } catch {
                    return [:]
                }

                let headerFound = OEDBSystem.header(for: file, forSystem: systemIdentifier)
                let serialFound = OEDBSystem.serial(for: file, forSystem: systemIdentifier)

                if headerFound == nil && serialFound == nil {
                    if let md5 = try? FileManager.default.hashFile(at: romURL, fileOffset: Int(headerSize)) {
                        key             = DBMD5Key
                        value           = md5.uppercased()
                        resultDict["md5"] = value
                    }
                } else {
                    if let headerFound = headerFound {
                        header              = headerFound
                        resultDict["header"] = headerFound
                    }
                    if let serialFound = serialFound {
                        serial              = serialFound
                        resultDict["serial"] = serialFound
                    }
                    determineQueryParams()
                }

                if removeFile {
                    try? FileManager.default.removeItem(at: romURL)
                }
            }

            if value == nil {
                isSystemWithHashlessROM = false
                isSystemWithROMHeader   = false
                isSystemWithROMSerial   = false
                headerSize              = 0
                determineQueryParams()
            }

            guard let key = key, let value = value else { return [:] }

            // --- Primary exact-match lookup ---
            let sql = """
            SELECT DISTINCT releaseTitleName as 'gameTitle', releaseCoverFront as 'boxImageURL', releaseDescription as 'gameDescription', regionName as 'region'
            FROM ROMs rom LEFT JOIN RELEASES release USING (romID) LEFT JOIN REGIONS region on (regionLocalizedID=region.regionID)
            WHERE \(key) = '\(value)'
            """

            var results = (try? database.executeQuery(sql)) ?? []

            // --- Region preference ---
            var result: [String : Any]? = pickPreferredRegion(from: results)

            if var picked = result {
                picked.removeValue(forKey: "region")
                resultDict.merge(picked) { (_, new) in new }
            }

            // --- ScreenScraper (Priority 1 when user is logged in) ---
            // Only runs when the user HAS configured SS credentials.
            // Users who have NOT logged in to ScreenScraper go through the
            // advanced fuzzy path below instead.
            if hasSScredentials {
                // FIX: pass full filename (including extension) so ScreenScraper
                // can differentiate ROMs sharing names across systems.
                let romName = url?.lastPathComponent
                if let ss = ScreenScraperClient.shared.fetchGameInfo(
                    md5: md5,
                    romName: romName,
                    systemIdentifier: systemIdentifier
                ) {
                    if let boxURL = ss.boxImageURL {
                        resultDict["boxImageURL"] = boxURL.absoluteString
                    }
                    if resultDict["gameTitle"] == nil, let title = ss.gameTitle {
                        resultDict["gameTitle"] = title
                    }
                    if resultDict["gameDescription"] == nil, let desc = ss.gameDescription {
                        resultDict["gameDescription"] = desc
                    }
                }

                // Tier 3: libretro-thumbnails — runs when ScreenScraper found no box art
                if resultDict["boxImageURL"] == nil,
                   let title = resultDict["gameTitle"] as? String {
                    if let ltURL = LibretroThumbnailsClient.shared.fetchBoxArtURL(gameName: title, systemIdentifier: systemIdentifier) {
                        resultDict["boxImageURL"] = ltURL
                    }
                }

                // ScreenScraper (+ libretro fallback) handled it; no need for fuzzy fallback.
                return resultDict
            }

            // --- Advanced fuzzy fallback (only for users NOT logged in to ScreenScraper) ---
            // Runs when: hasSScredentials == false
            // i.e., the user has not provided ScreenScraper credentials, so we do our
            // best with OpenVGDB fuzzy matching instead of leaving them with nothing.
            let missingBoxArt = resultDict["boxImageURL"] == nil
                             || (resultDict["boxImageURL"] as? String)?.isEmpty == true

            if missingBoxArt, let url = url {
                let rawName     = (url.lastPathComponent as NSString).deletingPathExtension
                let cleanedName = cleanROMName(rawName)

                // Three cascading passes — each only runs if the previous found nothing.
                // All fuzzy queries filter for releaseCoverFront IS NOT NULL so any
                // non-empty result means we found art; fuzzyFound tracks this.
                var fuzzyFound = false

                // Pass 1 – full title word AND match
                let words = cleanedName
                    .components(separatedBy: .whitespaces)
                    .filter { $0.count > 1 }
                if !words.isEmpty {
                    let conditions = words.map { "releaseTitleName LIKE '%\($0)%'" }.joined(separator: " AND ")
                    let fuzzySql = """
                    SELECT DISTINCT releaseTitleName as 'gameTitle', releaseCoverFront as 'boxImageURL', releaseDescription as 'gameDescription', regionName as 'region'
                    FROM ROMs rom LEFT JOIN RELEASES release USING (romID) LEFT JOIN REGIONS region on (regionLocalizedID=region.regionID)
                    WHERE \(conditions)
                      AND romSystemID IN (SELECT systemID FROM SYSTEMS WHERE systemOEID = '\(systemIdentifier)')
                      AND releaseCoverFront IS NOT NULL AND releaseCoverFront != ''
                    LIMIT 5
                    """
                    let fuzzyResults = (try? database.executeQuery(fuzzySql)) ?? []
                    if !fuzzyResults.isEmpty {
                        results = fuzzyResults
                        fuzzyFound = true
                    }
                }

                // Pass 2 – compilation splitter (+ and & only; - excluded to avoid
                // splitting "Game Name - Subtitle" style titles incorrectly)
                if !fuzzyFound {
                    let compilationSeparators = CharacterSet(charactersIn: "+&")
                    let parts = cleanedName
                        .components(separatedBy: compilationSeparators)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    if parts.count > 1 {
                        for part in parts {
                            let partWords = part
                                .components(separatedBy: .whitespaces)
                                .filter { $0.count > 1 }
                            guard !partWords.isEmpty else { continue }
                            let cond = partWords.map { "releaseTitleName LIKE '%\($0)%'" }.joined(separator: " AND ")
                            let splitSql = """
                            SELECT DISTINCT releaseTitleName as 'gameTitle', releaseCoverFront as 'boxImageURL', releaseDescription as 'gameDescription', regionName as 'region'
                            FROM ROMs rom LEFT JOIN RELEASES release USING (romID) LEFT JOIN REGIONS region on (regionLocalizedID=region.regionID)
                            WHERE \(cond)
                              AND romSystemID IN (SELECT systemID FROM SYSTEMS WHERE systemOEID = '\(systemIdentifier)')
                              AND releaseCoverFront IS NOT NULL AND releaseCoverFront != ''
                            LIMIT 1
                            """
                            let splitResults = (try? database.executeQuery(splitSql)) ?? []
                            if !splitResults.isEmpty {
                                results = splitResults
                                fuzzyFound = true
                                break
                            }
                        }
                    }
                }

                // Pass 3 – last resort: first two significant words only
                if !fuzzyFound {
                    let firstTwo = cleanedName
                        .components(separatedBy: .whitespaces)
                        .filter { $0.count > 1 }
                        .prefix(2)
                    if firstTwo.count >= 2 {
                        let cond = firstTwo.map { "releaseTitleName LIKE '%\($0)%'" }.joined(separator: " AND ")
                        let lastSql = """
                        SELECT DISTINCT releaseTitleName as 'gameTitle', releaseCoverFront as 'boxImageURL', releaseDescription as 'gameDescription', regionName as 'region'
                        FROM ROMs rom LEFT JOIN RELEASES release USING (romID) LEFT JOIN REGIONS region on (regionLocalizedID=region.regionID)
                        WHERE \(cond)
                          AND romSystemID IN (SELECT systemID FROM SYSTEMS WHERE systemOEID = '\(systemIdentifier)')
                          AND releaseCoverFront IS NOT NULL AND releaseCoverFront != ''
                        LIMIT 5
                        """
                        let lastResults = (try? database.executeQuery(lastSql)) ?? []
                        if !lastResults.isEmpty { results = lastResults }
                    }
                }

                // Merge best fuzzy result (if any) into resultDict
                if let best = pickPreferredRegion(from: results) {
                    var picked = best
                    picked.removeValue(forKey: "region")
                    resultDict.merge(picked) { (existing, _) in existing }
                }

                // Tier 3: libretro-thumbnails — runs when OpenVGDB fuzzy matching found no box art
                let stillMissingArt = resultDict["boxImageURL"] == nil
                                   || (resultDict["boxImageURL"] as? String)?.isEmpty == true
                if stillMissingArt, let title = resultDict["gameTitle"] as? String {
                    if let ltURL = LibretroThumbnailsClient.shared.fetchBoxArtURL(gameName: title, systemIdentifier: systemIdentifier) {
                        resultDict["boxImageURL"] = ltURL
                    }
                }
            }

            return resultDict
        }
    }

    // MARK: - Helpers

    /// Picks the best region match from a result set.
    /// Priority: user's preferred region → USA → Europe → first available.
    private func pickPreferredRegion(from results: [[String: Any]]) -> [String: Any]? {
        guard !results.isEmpty else { return nil }
        guard results.count > 1 else { return results.last }

        var preferredRegion = OELocalizationHelper.shared.regionName
        if preferredRegion == "North America" { preferredRegion = "USA" }

        if let match = results.first(where: { $0["region"] as? String == preferredRegion }) {
            return match
        }
        if let usa = results.first(where: { $0["region"] as? String == "USA" }) {
            return usa
        }
        if let eur = results.first(where: { $0["region"] as? String == "Europe" }) {
            return eur
        }
        return results.last
    }

    /// Strips region tags, revision markers, and extra punctuation from a ROM filename
    /// so fuzzy SQL queries are not polluted by brackets/parens content.
    private func cleanROMName(_ name: String) -> String {
        var cleaned = name
        // Remove parenthesised and bracketed annotations: (USA), [!], (Rev A), etc.
        cleaned = cleaned.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        // Collapse leftover punctuation to spaces
        cleaned = cleaned.replacingOccurrences(of: "[^a-zA-Z0-9 ]", with: " ", options: .regularExpression)
        // Collapse multiple spaces
        cleaned = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        return cleaned
    }

    // MARK: - System property queries

    func hashlessROMCheck(forSystem system: String) -> Bool {
        guard let database = database else { return false }
        let sql = "select systemhashless as 'hashless' from systems where systemoeid = '\(system)'"
        let result = try? database.executeQuery(sql)
        return result?.last?["hashless"] as? Int32 == 1
    }

    func headerROMCheck(forSystem system: String) -> Bool {
        guard let database = database else { return false }
        let sql = "select systemheader as 'header' from systems where systemoeid = '\(system)'"
        let result = try? database.executeQuery(sql)
        return result?.last?["header"] as? Int32 == 1
    }

    func serialROMCheck(forSystem system: String) -> Bool {
        guard let database = database else { return false }
        let sql = "select systemserial as 'serial' from systems where systemoeid = '\(system)'"
        let result = try? database.executeQuery(sql)
        // NOTE: As of OpenVGDB 28, the "systemSerial" column is of type "TEXT".
        return (result?.last?["serial"] as? String) == "1" || (result?.last?["serial"] as? Int32) == 1
    }

    func sizeOfROMHeader(forSystem system: String) -> Int32 {
        guard let database = database else { return 0 }
        let sql = "select systemheadersizebytes as 'size' from systems where systemoeid = '\(system)'"
        let result = try? database.executeQuery(sql)
        return result?.last?["size"] as? Int32 ?? 0
    }
}
