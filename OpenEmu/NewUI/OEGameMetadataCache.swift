// Copyright (c) 2024, OpenEmu Team
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

actor OEGameMetadataCache {

    static let shared = OEGameMetadataCache()

    private let cacheDir: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("OpenEmu/GameMeta", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func metadata(forMD5 md5: String) -> OEGameMetadata? {
        let path = cacheDir.appendingPathComponent("\(md5.lowercased()).json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? decoder.decode(OEGameMetadata.self, from: data)
    }

    func setMetadata(_ result: OEGameMetadata, forMD5 md5: String) {
        let path = cacheDir.appendingPathComponent("\(md5.lowercased()).json")
        guard let data = try? encoder.encode(result) else { return }
        try? data.write(to: path)
    }

    func fetchOrCacheMetadata(for game: OEDBGame) async -> OEGameMetadata? {
        let (md5, displayName, systemID, romExt) = await MainActor.run {
            let md5         = game.defaultROM?.md5Hash?.lowercased() ?? ""
            let displayName = game.displayName
            let systemID    = game.system?.systemIdentifier
            let romExt      = game.defaultROM?.fileName.flatMap {
                                  URL(fileURLWithPath: $0).pathExtension.isEmpty ? nil
                                      : URL(fileURLWithPath: $0).pathExtension
                              }
            return (md5, displayName, systemID, romExt)
        }
        guard !md5.isEmpty else { return nil }

        if let cached = metadata(forMD5: md5) { return cached }

        guard !displayName.isEmpty else { return nil }

        let platformID = systemID.flatMap {
            IGDBClient.igdbPlatformID(forSystemIdentifier: $0, romFileExtension: romExt)
        }

        guard let igdbGame = await IGDBClient.shared.fetchGame(name: displayName, platformID: platformID) else { return nil }

        var result = OEGameMetadata()
        result.gameTitle      = igdbGame.name
        result.gameDescription = igdbGame.summary
        result.developer      = igdbGame.developer
        result.releaseDate    = igdbGame.releaseDate
        result.genres         = igdbGame.genres
        result.screenshotURLs = igdbGame.screenshotURLs
        result.boxImageURL    = igdbGame.coverURL

        setMetadata(result, forMD5: md5)
        return result
    }
}
