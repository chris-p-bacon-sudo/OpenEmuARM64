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

import AppKit
import OpenEmuKit

/// Fetches and disk-caches wide background/fanart images from ScreenScraper.
/// Falls back to the game's box art when no fanart is found.
///
/// Cache location: ~/Library/Application Support/OpenEmu/HeroArt/{MD5}.png
actor OEHeroArtFetcher {

    static let shared = OEHeroArtFetcher()

    private let cacheDir: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("OpenEmu/HeroArt", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // In-flight request deduplication
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    func heroArt(for game: OEDBGame) async -> NSImage? {
        let md5 = await MainActor.run { game.defaultROM?.md5Hash?.lowercased() ?? "" }
        guard !md5.isEmpty else { return await boxArt(for: game) }

        // Check disk cache
        let cachedPath = cacheDir.appendingPathComponent("\(md5).png")
        if FileManager.default.fileExists(atPath: cachedPath.path),
           let img = NSImage(contentsOf: cachedPath) {
            return img
        }

        // Deduplicate concurrent fetches for the same MD5
        if let existing = inFlight[md5] {
            return await existing.value
        }

        let systemID = await MainActor.run { game.system?.systemIdentifier ?? "" }

        let task = Task<NSImage?, Never> {
            defer { inFlight.removeValue(forKey: md5) }

            // Try ScreenScraper fanart first
            if let artURL = await fetchFanartURL(md5: md5, systemIdentifier: systemID),
               let data = try? Data(contentsOf: artURL),
               let img = NSImage(data: data) {
                cacheToDisk(img, path: cachedPath)
                return img
            }

            // Fallback: box art (already on disk via OE's cache)
            return await boxArt(for: game)
        }

        inFlight[md5] = task
        return await task.value
    }

    // MARK: - Private

    private func fetchFanartURL(md5: String, systemIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let url = ScreenScraperClient().fetchFanartURL(md5: md5, systemIdentifier: systemIdentifier)
                continuation.resume(returning: url)
            }
        }
    }

    private func boxArt(for game: OEDBGame) async -> NSImage? {
        await MainActor.run { game.boxImage?.image }
    }

    private func cacheToDisk(_ image: NSImage, path: URL) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: path)
    }
}

// MARK: - ScreenScraperClient fanart extension

extension ScreenScraperClient {
    /// Lightweight call to get fanart/screenshot URL for a game.
    /// Does NOT fetch full game metadata — only parses the medias array.
    func fetchFanartURL(md5: String, systemIdentifier: String) -> URL? {
        guard let systemID = Self.resolveSystemID(for: systemIdentifier, romName: nil) else {
            return nil
        }

        var components = URLComponents(string: "https://www.screenscraper.fr/api2/jeuInfos.php")!
        components.queryItems = [
            URLQueryItem(name: "devid",       value: Self.devID),
            URLQueryItem(name: "devpassword", value: Self.devPassword),
            URLQueryItem(name: "softname",    value: "OpenEmuSilicon"),
            URLQueryItem(name: "output",      value: "json"),
            URLQueryItem(name: "rommd5",      value: md5),
            URLQueryItem(name: "systemeid",   value: String(systemID)),
        ]

        guard let url = components.url,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let jeu = response["jeu"] as? [String: Any],
              let medias = jeu["medias"] as? [[String: Any]] else {
            return nil
        }

        // Preferred media types for hero backgrounds, in priority order
        let preferredTypes = ["fanart", "ss", "steamgrid"]
        for type_ in preferredTypes {
            if let match = medias.first(where: { ($0["type"] as? String) == type_ }),
               let urlStr = match["url"] as? String,
               let mediaURL = URL(string: urlStr) {
                return mediaURL
            }
        }
        return nil
    }
}
