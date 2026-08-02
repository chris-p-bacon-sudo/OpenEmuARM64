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

import Cocoa

/// Matches image files in a folder to games by exact, normalized filename.
///
/// Normalization mirrors the extensionless-filename matching already used by
/// `GameInfoHelper` and `ImportOperation`: lowercased, extension stripped.
@objc(OEArtworkFolderMatcher)
final class ArtworkFolderMatcher: NSObject {

    @objc(OEArtworkFolderMatcherMatch) final class Match: NSObject {
        @objc let game: OEDBGame
        @objc let fileURL: URL

        init(game: OEDBGame, fileURL: URL) {
            self.game = game
            self.fileURL = fileURL
        }
    }

    @objc(OEArtworkFolderMatcherResult) final class Result: NSObject {
        @objc let matches: [Match]
        @objc let unmatchedFileURLs: [URL]

        init(matches: [Match], unmatchedFileURLs: [URL]) {
            self.matches = matches
            self.unmatchedFileURLs = unmatchedFileURLs
        }
    }

    private static func normalize(_ name: String) -> String {
        (name as NSString).deletingPathExtension
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }

    /// Scans `folderURL` (non-recursively) for image files and matches each one
    /// to a game in `games` whose display name normalizes to the same string.
    ///
    /// If more than one file normalizes to the same game (e.g. `Sonic.png` and
    /// `sonic.jpg`), only the first one encountered is matched; the rest are
    /// reported as unmatched rather than silently overwriting one another.
    @objc(matchWithFolderURL:games:) static func match(folderURL: URL, games: [OEDBGame]) -> Result {
        let imageTypes = Set(NSImage.imageTypes)

        let fileURLs = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .typeIdentifierKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []

        let imageFileURLs = fileURLs.filter { url in
            let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .typeIdentifierKey])
            guard resourceValues?.isRegularFile == true,
                  let uti = resourceValues?.typeIdentifier
            else { return false }
            return imageTypes.contains(uti)
        }

        var gamesByNormalizedName: [String: OEDBGame] = [:]
        for game in games {
            gamesByNormalizedName[normalize(game.displayName)] = game
        }

        var matches: [Match] = []
        var unmatchedFileURLs: [URL] = []
        var matchedNormalizedNames: Set<String> = []

        for fileURL in imageFileURLs {
            let key = normalize(fileURL.lastPathComponent)
            if let game = gamesByNormalizedName[key], !matchedNormalizedNames.contains(key) {
                matches.append(Match(game: game, fileURL: fileURL))
                matchedNormalizedNames.insert(key)
            } else {
                unmatchedFileURLs.append(fileURL)
            }
        }

        return Result(matches: matches, unmatchedFileURLs: unmatchedFileURLs)
    }
}
