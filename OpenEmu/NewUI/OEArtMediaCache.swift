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
import OpenEmuKit

actor OEArtMediaCache {

    static let shared = OEArtMediaCache()

    private let cacheDir: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("OpenEmu/ArtMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func items(forMD5 md5: String) -> [SteamGridDBItem]? {
        let path = cacheDir.appendingPathComponent("\(md5.lowercased()).json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? decoder.decode([SteamGridDBItem].self, from: data)
    }

    func setItems(_ items: [SteamGridDBItem], forMD5 md5: String) {
        let path = cacheDir.appendingPathComponent("\(md5.lowercased()).json")
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: path)
    }

    func fetchOrCache(for game: OEDBGame) async -> [SteamGridDBItem] {
        let (md5, displayName) = await MainActor.run {
            (game.defaultROM?.md5Hash?.lowercased() ?? "", game.displayName)
        }
        guard !md5.isEmpty else { return [] }
        if let cached = items(forMD5: md5) { return cached }
        guard !displayName.isEmpty else { return [] }
        guard let gameID = await SteamGridDBClient.shared.gameID(for: displayName) else { return [] }
        let result = await SteamGridDBClient.shared.fetchArtMedia(gameID: gameID)
        if !result.isEmpty { setItems(result, forMD5: md5) }
        return result
    }
}
