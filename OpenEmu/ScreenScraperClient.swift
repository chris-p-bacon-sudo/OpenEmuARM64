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
import OpenEmuSystem

// Backward-compatible alias — callers migrating to OEGameMetadata can use either name.
typealias ScreenScraperResult = OEGameMetadata

final class ScreenScraperClient {

    static let shared = ScreenScraperClient()

    // ScreenScraper numeric system IDs keyed by OpenEmu system identifier.
    // Retained for resolveSystemID, which GameInfoHelper uses for system-aware lookups.
    static let systemIDs: [String: Int] = [
        // Nintendo
        "openemu.system.nes":           3,
        "openemu.system.fds":         106,
        "openemu.system.snes":          4,
        "openemu.system.n64":          14,
        "openemu.system.gc":           13,
        "openemu.system.wii":          16,
        "openemu.system.gb":            9,
        "openemu.system.gba":          12,
        "openemu.system.nds":          15,
        "openemu.system.vb":           11,
        "openemu.system.pokemonmini": 211,

        // Sony
        "openemu.system.psx":          57,
        "openemu.system.ps2":          58,
        "openemu.system.psp":          61,

        // Sega
        "openemu.system.sg":            1,
        "openemu.system.sg1000":      109,
        "openemu.system.sms":           2,
        "openemu.system.gg":           21,
        "openemu.system.scd":          20,
        "openemu.system.32x":          19,
        "openemu.system.saturn":       22,
        "openemu.system.dc":           23,

        // Atari
        "openemu.system.2600":         26,
        "openemu.system.5200":         40,
        "openemu.system.7800":         41,
        "openemu.system.jaguar":       27,
        "openemu.system.lynx":         28,
        "openemu.system.atari8bit":    43,

        // NEC
        "openemu.system.pce":          31,
        "openemu.system.pcecd":       114,
        "openemu.system.pcfx":         72,

        // SNK
        "openemu.system.ngp":          25,

        // Bandai
        "openemu.system.ws":           45,

        // Other home consoles
        "openemu.system.3do":          29,
        "openemu.system.colecovision": 48,
        "openemu.system.intellivision": 115,
        "openemu.system.odyssey2":    104,
        "openemu.system.vectrex":     102,
        "openemu.system.sv":          207,

        // Computer / MSX
        "openemu.system.msx":         113,
        "openemu.system.c64":          66,

        // Arcade
        "openemu.system.arcade":       75,
    ]

    /// Returns the ScreenScraper system ID for a given OpenEmu identifier, upgrading
    /// to a color-variant ID when the ROM extension indicates a sub-platform.
    static func resolveSystemID(for systemIdentifier: String, romName: String?) -> Int? {
        guard let baseID = systemIDs[systemIdentifier] else { return nil }
        guard let name = romName?.lowercased() else { return baseID }
        let ext = (name as NSString).pathExtension
        switch (systemIdentifier, ext) {
        case ("openemu.system.gb",  "gbc"): return 10
        case ("openemu.system.ws",  "wsc"): return 46
        case ("openemu.system.ngp", "ngc"): return 82
        default: return baseID
        }
    }

    /// Strips parenthesised and bracketed annotations from a ROM filename while preserving
    /// the extension. Used to retry lookups when the raw filename misses.
    static func cleanedROMFileName(_ filename: String) -> String {
        let ns = filename as NSString
        let ext  = ns.pathExtension
        let base = ns.deletingPathExtension
        var stripped = base
        stripped = stripped.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        stripped = stripped.trimmingCharacters(in: .whitespaces)
        if stripped.isEmpty { return filename }
        return ext.isEmpty ? stripped : "\(stripped).\(ext)"
    }
}
