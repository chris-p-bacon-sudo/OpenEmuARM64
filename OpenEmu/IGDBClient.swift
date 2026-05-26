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

struct IGDBGame {
    var name: String?
    var coverURL: URL?
    var screenshotURLs: [URL] = []
    var genres: [String] = []
    var developer: String?
    var publisher: String?
    var criticRating: Double?
    var criticRatingCount: Int?
    var ageRating: String?
    var franchise: String?
    var gameModes: [String] = []
    var summary: String?
    var releaseDate: String?
}

actor IGDBClient {

    static let shared = IGDBClient()

    private var accessToken: String?
    private var tokenExpiry: Date = .distantPast

    private struct TwitchTokenResponse: Decodable {
        let access_token: String
        let expires_in: Int
    }

    private static let platformIDs: [String: Int] = [
        "openemu.system.nes":           18,
        "openemu.system.fds":           51,
        "openemu.system.snes":          19,
        "openemu.system.n64":            4,
        "openemu.system.gc":            21,
        "openemu.system.wii":            5,
        "openemu.system.gb":            33,
        "openemu.system.gba":           24,
        "openemu.system.nds":           20,
        "openemu.system.vb":            39,
        "openemu.system.psx":            7,
        "openemu.system.ps2":            8,
        "openemu.system.psp":           38,
        "openemu.system.sg":            29,
        "openemu.system.sms":           64,
        "openemu.system.gg":            35,
        "openemu.system.scd":           78,
        "openemu.system.32x":           30,
        "openemu.system.saturn":        32,
        "openemu.system.dc":            23,
        "openemu.system.2600":          59,
        "openemu.system.5200":          66,
        "openemu.system.7800":          60,
        "openemu.system.jaguar":        62,
        "openemu.system.lynx":          61,
        "openemu.system.pce":           86,
        "openemu.system.pcecd":        150,
        "openemu.system.ngp":          119,
        "openemu.system.ws":            57,
        "openemu.system.arcade":        52,
        "openemu.system.msx":           27,
        "openemu.system.c64":           15,
        "openemu.system.3do":           50,
        "openemu.system.colecovision":  68,
        "openemu.system.intellivision": 67,
        "openemu.system.vectrex":       71,
    ]

    static func igdbPlatformID(forSystemIdentifier systemID: String,
                                romFileExtension ext: String? = nil) -> Int? {
        switch systemID {
        case "openemu.system.gb":  return ext?.lowercased() == "gbc" ? 22  : 33
        case "openemu.system.ngp": return ext?.lowercased() == "ngc" ? 120 : 119
        case "openemu.system.ws":  return ext?.lowercased() == "wsc" ? 123 : 57
        default:                   return platformIDs[systemID]
        }
    }

    // Returns a valid access token, refreshing from Twitch if expired.
    // Token is stored in memory only — it's a developer credential, not user data.
    private func validToken() async -> String? {
        if let token = accessToken, Date() < tokenExpiry {
            return token
        }

        var components = URLComponents(string: "https://id.twitch.tv/oauth2/token")!
        components.queryItems = [
            URLQueryItem(name: "client_id",     value: IGDBClient.clientID),
            URLQueryItem(name: "client_secret", value: IGDBClient.clientSecret),
            URLQueryItem(name: "grant_type",    value: "client_credentials"),
        ]
        var request = URLRequest(url: URL(string: "https://id.twitch.tv/oauth2/token")!)
        request.httpMethod = "POST"
        request.url = components.url

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(TwitchTokenResponse.self, from: data) else {
            os_log(.error, log: .default, "IGDBClient: failed to fetch Twitch access token")
            return nil
        }

        accessToken = response.access_token
        // Subtract 60s to renew slightly before actual expiry.
        tokenExpiry = Date().addingTimeInterval(TimeInterval(response.expires_in - 60))
        return accessToken
    }

    func fetchGame(name: String, platformID: Int? = nil) async -> IGDBGame? {
        guard let token = await validToken() else { return nil }
        let safeName = name.replacingOccurrences(of: "\"", with: "\\\"")

        let fields = "fields name,cover.url,screenshots.url,genres.name,involved_companies.company.name,involved_companies.developer,involved_companies.publisher,aggregated_rating,aggregated_rating_count,age_ratings.category,age_ratings.rating,franchise.name,game_modes.name,summary,first_release_date;"
        let cat    = "(category = null | category = (0,8,9))"

        if let pid = platformID {
            // Pass 1: platform + screenshots + category — best signal for retro games.
            if let game = await queryGames(token: token, body: """
                \(fields)
                where name = "\(safeName)" & platforms = [\(pid)] & screenshots != null & \(cat);
                sort first_release_date asc; limit 1;
                """) { return game }

            // Pass 2: platform + category, no screenshot requirement.
            if let game = await queryGames(token: token, body: """
                \(fields)
                where name = "\(safeName)" & platforms = [\(pid)] & \(cat);
                sort first_release_date asc; limit 1;
                """) { return game }

            // Pass 3: platform-scoped fuzzy search — handles "Title, The" ROM naming and
            // subtitle punctuation mismatches. Sort oldest-first to prefer original releases
            // over later mods, remasters, or compilations that share the same keywords.
            if let game = await queryGames(token: token, body: """
                \(fields)
                search "\(safeName)"; where platforms = [\(pid)] & \(cat); sort first_release_date asc; limit 1;
                """) { return game }
        }

        // Pass 4: exact name + category, no platform filter (catches unmapped systems).
        if let game = await queryGames(token: token, body: """
            \(fields)
            where name = "\(safeName)" & \(cat);
            sort first_release_date asc; limit 1;
            """) { return game }

        // Pass 5: unscoped fuzzy search (last resort for title mismatches on unmapped systems).
        return await queryGames(token: token, body: """
            \(fields)
            search "\(safeName)"; limit 1;
            """)
    }

    // MARK: - Private

    private func queryGames(token: String, body: String) async -> IGDBGame? {
        guard let url = URL(string: "https://api.igdb.com/v4/games") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(IGDBClient.clientID, forHTTPHeaderField: "Client-ID")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body.data(using: .utf8)

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let games = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let game = games.first else { return nil }

        return parseGame(game)
    }

    private func parseGame(_ game: [String: Any]) -> IGDBGame {
        var result = IGDBGame()

        result.name = game["name"] as? String

        if let cover = game["cover"] as? [String: Any],
           let urlStr = cover["url"] as? String {
            let bigURL = urlStr.replacingOccurrences(of: "t_thumb", with: "t_cover_big")
            result.coverURL = URL(string: "https:\(bigURL)")
        }

        if let screenshots = game["screenshots"] as? [[String: Any]] {
            result.screenshotURLs = screenshots.compactMap { ss -> URL? in
                guard let urlStr = ss["url"] as? String else { return nil }
                let bigURL = urlStr.replacingOccurrences(of: "t_thumb", with: "t_screenshot_big")
                return URL(string: "https:\(bigURL)")
            }
        }

        if let genres = game["genres"] as? [[String: Any]] {
            result.genres = genres.compactMap { $0["name"] as? String }
        }

        if let companies = game["involved_companies"] as? [[String: Any]] {
            for entry in companies {
                guard let co = entry["company"] as? [String: Any],
                      let name = co["name"] as? String else { continue }
                if (entry["developer"] as? Bool == true) && result.developer == nil { result.developer = name }
                if (entry["publisher"] as? Bool == true) && result.publisher == nil { result.publisher = name }
            }
        }

        result.criticRating      = game["aggregated_rating"] as? Double
        result.criticRatingCount = game["aggregated_rating_count"] as? Int

        if let ageRatings = game["age_ratings"] as? [[String: Any]] {
            let esrb = ageRatings.first { $0["category"] as? Int == 1 }
            let pegi = ageRatings.first { $0["category"] as? Int == 2 }
            if let r = esrb?["rating"] as? Int { result.ageRating = esrbLabel(r) }
            else if let r = pegi?["rating"] as? Int { result.ageRating = pegiLabel(r) }
        }

        if let franchise = game["franchise"] as? [String: Any] {
            result.franchise = franchise["name"] as? String
        }
        if let modes = game["game_modes"] as? [[String: Any]] {
            result.gameModes = modes.compactMap { $0["name"] as? String }
        }

        result.summary = game["summary"] as? String

        if let timestamp = game["first_release_date"] as? Int {
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            result.releaseDate = formatter.string(from: date)
        }

        return result
    }

    private func esrbLabel(_ v: Int) -> String {
        switch v {
        case 6:  return "RP"
        case 7:  return "EC"
        case 8:  return "E"
        case 9:  return "E10+"
        case 10: return "T"
        case 11: return "M"
        case 12: return "AO"
        default: return "—"
        }
    }

    private func pegiLabel(_ v: Int) -> String {
        switch v {
        case 1: return "PEGI 3"
        case 2: return "PEGI 7"
        case 3: return "PEGI 12"
        case 4: return "PEGI 16"
        case 5: return "PEGI 18"
        default: return "—"
        }
    }
}
