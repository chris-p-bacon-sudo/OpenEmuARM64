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

actor SteamGridDBClient {

    static let shared = SteamGridDBClient()

    private let base = "https://www.steamgriddb.com/api/v2"

    // Avoid redundant search calls when hero and icon are fetched for the same game.
    private var nameToID: [String: Int] = [:]

    func gameID(for name: String) async -> Int? {
        if let cached = nameToID[name] { return cached }

        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(base)/search/autocomplete/\(encoded)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(SteamGridDBClient.apiKey)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let id = dataArray.first?["id"] as? Int else { return nil }

        nameToID[name] = id
        return id
    }

    func heroURL(for gameID: Int) async -> URL? {
        guard let url = URL(string: "\(base)/heroes/game/\(gameID)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(SteamGridDBClient.apiKey)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else { return nil }

        // Prefer images at least 1920px wide; fall back to first result.
        let entry = dataArray.first(where: { ($0["width"] as? Int ?? 0) >= 1920 }) ?? dataArray.first
        guard let urlStr = entry?["url"] as? String else { return nil }
        return URL(string: urlStr)
    }

    func iconURL(for gameID: Int) async -> URL? {
        guard let url = URL(string: "\(base)/icons/game/\(gameID)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(SteamGridDBClient.apiKey)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let urlStr = dataArray.first?["url"] as? String else { return nil }
        return URL(string: urlStr)
    }
}
