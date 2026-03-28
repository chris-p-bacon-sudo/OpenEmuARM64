// Copyright (c) 2026, OpenEmu Team
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
import os.log
import OpenEmuSystem

struct ScreenScraperResult {
    var gameTitle: String?
    var boxImageURL: URL?
    var gameDescription: String?
}

final class ScreenScraperClient {

    static let shared = ScreenScraperClient()

    // ScreenScraper numeric system IDs keyed by OpenEmu system identifier
    static let systemIDs: [String: Int] = [
        "openemu.system.nes":           3,
        "openemu.system.snes":          4,
        "openemu.system.n64":          14,
        "openemu.system.gb":            9,   // Game Boy (also covers GBC — no separate GBC plugin)
        "openemu.system.gba":          12,
        "openemu.system.nds":          15,
        "openemu.system.gg":           21,
        "openemu.system.sms":           2,
        "openemu.system.sg":            1,
        "openemu.system.scd":          20,
        "openemu.system.32x":          19,
        "openemu.system.psx":          57,
        "openemu.system.saturn":       22,
        "openemu.system.dc":           23,
        "openemu.system.2600":         26,
        "openemu.system.5200":         40,
        "openemu.system.7800":         41,
        "openemu.system.jaguar":       27,
        "openemu.system.msx":         113,
        "openemu.system.colecovision": 48,
        "openemu.system.intellivision": 115,
        "openemu.system.odyssey2":    104,
        "openemu.system.vectrex":     102,
        "openemu.system.pokemonmini": 211,
        "openemu.system.arcade":       75,
        "openemu.system.c64":          64,
    ]

    // Preferred region tags in priority order, per OELocalizationHelper region
    private func preferredRegions() -> [String] {
        let region = OELocalizationHelper.shared.regionName
        switch region {
        case "North America":
            return ["us", "wor", "eu", "jp"]
        case "Europe":
            return ["eu", "wor", "us", "jp"]
        case "Japan":
            return ["jp", "wor", "us", "eu"]
        default:
            return ["wor", "us", "eu", "jp"]
        }
    }

    /// Synchronous fetch suitable for calling from a background DispatchQueue.sync block.
    /// Returns nil silently on error (network unavailable, rate-limited, not found, etc.)
    ///
    /// Pass `debugMode: true` to attach the developer debug password (100 uses/day limit).
    func fetchGameInfo(md5: String?, romName: String?, systemIdentifier: String, debugMode: Bool = false) -> ScreenScraperResult? {

        guard let systemID = ScreenScraperClient.systemIDs[systemIdentifier] else {
            return nil
        }

        var components = URLComponents(string: "https://www.screenscraper.fr/api2/jeuInfos.php")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "softname",  value: "OpenEmu-Silicon"),
            URLQueryItem(name: "output",    value: "json"),
            URLQueryItem(name: "systemeid", value: String(systemID)),
            // Developer app credentials — always present, identify the software to the API
            URLQueryItem(name: "devid",       value: ScreenScraperClient.devID),
            URLQueryItem(name: "devpassword", value: ScreenScraperClient.devPassword),
        ]

        // ScreenScraper requires romnom; rommd5 is additive for accuracy.
        // Sending both when available gives the best match rate.
        guard (md5 != nil && !(md5!.isEmpty)) || (romName != nil && !(romName!.isEmpty)) else {
            return nil
        }
        if let md5 = md5, !md5.isEmpty {
            queryItems.append(URLQueryItem(name: "rommd5", value: md5.uppercased()))
        }
        if let romName = romName, !romName.isEmpty {
            queryItems.append(URLQueryItem(name: "romnom", value: romName))
        }

        // User credentials — optional, attached when the user has saved their own account.
        // Increases the user's personal rate limit beyond the anonymous shared quota.
        let ssUsername = UserDefaults.standard.string(forKey: "ScreenScraperUsername") ?? ""
        let ssPassword = ScreenScraperCredentials.storedPassword() ?? ""
        if !ssUsername.isEmpty && !ssPassword.isEmpty {
            queryItems.append(URLQueryItem(name: "ssid",       value: ssUsername))
            queryItems.append(URLQueryItem(name: "sspassword", value: ssPassword))
        }

        // Developer debug mode — forces cache refresh and bypasses quota counters for testing.
        // Capped at 100 uses/day by ScreenScraper. Never enable in production flows.
        if debugMode {
            queryItems.append(URLQueryItem(name: "devdebugpassword", value: ScreenScraperClient.devDebugPassword))
            queryItems.append(URLQueryItem(name: "forceupdate",      value: "1"))
        }

        components.queryItems = queryItems

        guard let url = components.url else { return nil }

        var result: ScreenScraperResult?
        let semaphore = DispatchSemaphore(value: 0)

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            defer { semaphore.signal() }

            guard let self = self else { return }

            if let error = error {
                os_log(.debug, log: .default, "ScreenScraper network error: %{public}@", error.localizedDescription)
                return
            }

            if let http = response as? HTTPURLResponse {
                // 430 = rate limited; 404 = not found — both are silent no-ops
                guard (200..<300).contains(http.statusCode) else { return }
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let response = json["response"] as? [String: Any],
                  let jeu = response["jeu"] as? [String: Any] else {
                return
            }

            result = self.parseGameInfo(jeu: jeu)
        }

        task.resume()
        semaphore.wait()
        return result
    }

    // MARK: - JSON Parsing

    private func parseGameInfo(jeu: [String: Any]) -> ScreenScraperResult? {
        var result = ScreenScraperResult()

        // Game title — prefer regional name
        if let noms = jeu["noms"] as? [[String: Any]] {
            let preferred = preferredRegions()
            var picked: String?
            for region in preferred {
                if let match = noms.first(where: { ($0["region"] as? String) == region }),
                   let text = match["text"] as? String {
                    picked = text
                    break
                }
            }
            if picked == nil {
                picked = noms.first?["text"] as? String
            }
            result.gameTitle = picked
        }

        // Description — prefer regional
        if let synopses = jeu["synopsis"] as? [[String: Any]] {
            let preferred = preferredRegions()
            var picked: String?
            for region in preferred {
                if let match = synopses.first(where: { ($0["region"] as? String) == region }),
                   let text = match["text"] as? String {
                    picked = text
                    break
                }
            }
            if picked == nil {
                picked = synopses.first?["text"] as? String
            }
            result.gameDescription = picked
        }

        // Box art URL — medias array, type "box-2D", prefer regional
        if let medias = jeu["medias"] as? [[String: Any]] {
            let boxMedias = medias.filter { ($0["type"] as? String) == "box-2D" }
            let preferred = preferredRegions()
            var pickedURL: URL?
            for region in preferred {
                if let match = boxMedias.first(where: { ($0["region"] as? String) == region }),
                   let urlStr = match["url"] as? String,
                   let url = URL(string: urlStr) {
                    pickedURL = url
                    break
                }
            }
            if pickedURL == nil {
                if let urlStr = boxMedias.first?["url"] as? String {
                    pickedURL = URL(string: urlStr)
                }
            }
            result.boxImageURL = pickedURL
        }

        guard result.gameTitle != nil || result.boxImageURL != nil else { return nil }
        return result
    }
}
