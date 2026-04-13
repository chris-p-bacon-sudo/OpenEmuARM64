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

/// Describes a required system file (BIOS) for a libretro core.
struct BIOSFileRequirement: Hashable, Sendable, Codable {
    /// The exact filename expected by the core (e.g. "scph5501.bin").
    let name: String
    /// A human-readable description of what this file is.
    let description: String
    /// The expected MD5 hash of the file for verification.
    let expectedMD5: String
    /// The expected size of the file in bytes.
    let expectedSize: Int
}

/// Describes a single libretro core available from the buildbot.
struct LibretroCore: Hashable, Sendable {
    /// OpenEmu system identifiers this core handles (e.g. "openemu.system.snes").
    let systemIdentifiers: [String]
    /// OpenEmu-style bundle identifier for the synthesised plugin (e.g. "org.openemu.libretro.snes9x").
    let bundleIdentifier: String
    /// Human-readable name shown in the UI.
    let displayName: String
    /// Base filename on the buildbot, without the trailing "_libretro" suffix (e.g. "snes9x").
    let buildbotStem: String
    /// Metadata for required system files (BIOS).
    let requiredFiles: [BIOSFileRequirement]?

    /// Full dylib filename as it appears after extraction (e.g. "snes9x_libretro.dylib").
    var dylibFilename: String { "\(buildbotStem)_libretro.dylib" }

    init(systemIdentifiers: [String], bundleIdentifier: String, displayName: String, buildbotStem: String, requiredFiles: [BIOSFileRequirement]? = nil) {
        self.systemIdentifiers = systemIdentifiers
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.buildbotStem = buildbotStem
        self.requiredFiles = requiredFiles
    }
}

/// Registry of the best ARM64 libretro cores.
///
/// This serves as a static data reference for cores that can be transparently
/// translated via the OELibretro bridge.
enum OELibretroBuildbot {

    // MARK: - Core registry

    /// All supported libretro cores, ordered by preference when multiple cores
    /// serve the same system.
    static let allCores: [LibretroCore] = [

        // ── Nintendo ──────────────────────────────────────────────────────────

        // NES / Famicom Disk System — Nestopia UE
        LibretroCore(
            systemIdentifiers: ["openemu.system.nes", "openemu.system.fds"],
            bundleIdentifier:  "org.openemu.libretro.nestopia",
            displayName:       "Nestopia",
            buildbotStem:      "nestopia"
        ),
        
        // Super Nintendo
        LibretroCore(
            systemIdentifiers: ["openemu.system.snes"],
            bundleIdentifier:  "org.openemu.libretro.snes9x",
            displayName:       "Snes9x",
            buildbotStem:      "snes9x"
        ),
        
        // Game Boy / Game Boy Color — Gambatte
        LibretroCore(
            systemIdentifiers: ["openemu.system.gb"],
            bundleIdentifier:  "org.openemu.libretro.gambatte",
            displayName:       "Gambatte",
            buildbotStem:      "gambatte"
        ),
        
        // Game Boy Advance — mGBA
        LibretroCore(
            systemIdentifiers: ["openemu.system.gba"],
            bundleIdentifier:  "org.openemu.libretro.mgba",
            displayName:       "mGBA",
            buildbotStem:      "mgba"
        ),
        
        // Nintendo DS — DeSmuME
        LibretroCore(
            systemIdentifiers: ["openemu.system.nds"],
            bundleIdentifier:  "org.openemu.libretro.desmume",
            displayName:       "DeSmuME",
            buildbotStem:      "desmume"
        ),
        
        // Nintendo 64 — Mupen64Plus-Next
        LibretroCore(
            systemIdentifiers: ["openemu.system.n64"],
            bundleIdentifier:  "org.openemu.libretro.mupen64plus",
            displayName:       "Mupen64Plus-Next",
            buildbotStem:      "mupen64plus_next"
        ),
        
        // Virtual Boy — Beetle VB
        LibretroCore(
            systemIdentifiers: ["openemu.system.vb"],
            bundleIdentifier:  "org.openemu.libretro.beetlevb",
            displayName:       "Beetle Virtual Boy",
            buildbotStem:      "mednafen_vb"
        ),
        
        // Pokemon Mini
        LibretroCore(
            systemIdentifiers: ["openemu.system.pokemonmini"],
            bundleIdentifier:  "org.openemu.libretro.pokemini",
            displayName:       "PokeMini",
            buildbotStem:      "pokemini"
        ),

        // ── Sega ─────────────────────────────────────────────────────────────

        // Genesis / Mega Drive / Sega CD / Master System / Game Gear / SG-1000
        LibretroCore(
            systemIdentifiers: ["openemu.system.sg",
                                 "openemu.system.scd",
                                 "openemu.system.sms",
                                 "openemu.system.gg",
                                 "openemu.system.sg1000"],
            bundleIdentifier:  "org.openemu.libretro.genesisplus",
            displayName:       "Genesis Plus GX",
            buildbotStem:      "genesis_plus_gx"
        ),

        // Sega 32X — Picodrive
        LibretroCore(
            systemIdentifiers: ["openemu.system.32x"],
            bundleIdentifier:  "org.openemu.libretro.picodrive",
            displayName:       "PicoDrive",
            buildbotStem:      "picodrive"
        ),

        // Sega Saturn — Beetle Saturn (Mednafen)
        LibretroCore(
            systemIdentifiers: ["openemu.system.saturn"],
            bundleIdentifier:  "org.openemu.libretro.mednafen",
            displayName:       "Beetle Saturn",
            buildbotStem:      "mednafen_saturn",
            requiredFiles: [
                BIOSFileRequirement(name: "sat_bios_jp.bin", description: "Saturn BIOS (JP)", expectedMD5: "2aba4251329305f8b29bc62d3a3d537f", expectedSize: 524288),
                BIOSFileRequirement(name: "sat_bios_us.bin", description: "Saturn BIOS (US)", expectedMD5: "af58e0fdc11efec58df169ca13c36c64", expectedSize: 524288),
                BIOSFileRequirement(name: "sat_bios_eu.bin", description: "Saturn BIOS (EU)", expectedMD5: "9469502759e07503fa658d57053e19fb", expectedSize: 524288)
            ]
        ),

        // Dreamcast — Flycast
        LibretroCore(
            systemIdentifiers: ["openemu.system.dc"],
            bundleIdentifier:  "org.openemu.libretro.flycast",
            displayName:       "Flycast",
            buildbotStem:      "flycast"
        ),

        // ── Sony ─────────────────────────────────────────────────────────────

        // PlayStation — PCSX-ReARMed
        LibretroCore(
            systemIdentifiers: ["openemu.system.psx"],
            bundleIdentifier:  "org.openemu.libretro.pcsx-rearmed",
            displayName:       "PCSX-ReARMed",
            buildbotStem:      "pcsx_rearmed",
            requiredFiles: [
                BIOSFileRequirement(name: "scph5501.bin", description: "PlayStation BIOS (US)", expectedMD5: "490f666e1a21530d03ad55ad333aa372", expectedSize: 524288)
            ]
        ),

        // PlayStation Portable — PPSSPP
        LibretroCore(
            systemIdentifiers: ["openemu.system.psp"],
            bundleIdentifier:  "org.openemu.libretro.ppsspp",
            displayName:       "PPSSPP",
            buildbotStem:      "ppsspp"
        ),

        // ── NEC ──────────────────────────────────────────────────────────────

        // PC Engine / TurboGrafx-16 / PC Engine CD — Beetle PCE
        LibretroCore(
            systemIdentifiers: ["openemu.system.pce", "openemu.system.pcecd"],
            bundleIdentifier:  "org.openemu.libretro.beetlepce",
            displayName:       "Beetle PC Engine",
            buildbotStem:      "mednafen_pce_fast"
        ),

        // PC-FX — Beetle PC-FX
        LibretroCore(
            systemIdentifiers: ["openemu.system.pcfx"],
            bundleIdentifier:  "org.openemu.BeetlePCFX",
            displayName:       "Beetle PC-FX",
            buildbotStem:      "mednafen_pcfx"
        ),

        // ── Atari ────────────────────────────────────────────────────────────

        // Atari 2600 — Stella
        LibretroCore(
            systemIdentifiers: ["openemu.system.2600"],
            bundleIdentifier:  "org.openemu.Stella",
            displayName:       "Stella",
            buildbotStem:      "stella"
        ),

        // Atari 7800 — ProSystem
        LibretroCore(
            systemIdentifiers: ["openemu.system.7800"],
            bundleIdentifier:  "org.openemu.ProSystem",
            displayName:       "ProSystem",
            buildbotStem:      "prosystem"
        ),

        // Atari 5200 / Atari 8-bit computers — Atari800
        LibretroCore(
            systemIdentifiers: ["openemu.system.5200", "openemu.system.atari8bit"],
            bundleIdentifier:  "org.openemu.Atari800",
            displayName:       "Atari800",
            buildbotStem:      "atari800"
        ),

        // Atari Jaguar — Virtual Jaguar
        LibretroCore(
            systemIdentifiers: ["openemu.system.jaguar"],
            bundleIdentifier:  "org.openemu.VirtualJaguar",
            displayName:       "Virtual Jaguar",
            buildbotStem:      "virtualjaguar"
        ),

        // Atari Lynx — Beetle Lynx
        LibretroCore(
            systemIdentifiers: ["openemu.system.lynx"],
            bundleIdentifier:  "org.openemu.BeetleLynx",
            displayName:       "Beetle Lynx",
            buildbotStem:      "mednafen_lynx"
        ),

        // ── Handheld / portable ──────────────────────────────────────────────

        // Neo Geo Pocket / Color — Beetle NGP
        LibretroCore(
            systemIdentifiers: ["openemu.system.ngp"],
            bundleIdentifier:  "org.openemu.BeetleNGP",
            displayName:       "Beetle Neo Geo Pocket",
            buildbotStem:      "mednafen_ngp"
        ),

        // WonderSwan / WonderSwan Color — Beetle WonderSwan
        LibretroCore(
            systemIdentifiers: ["openemu.system.ws"],
            bundleIdentifier:  "org.openemu.BeetleWS",
            displayName:       "Beetle WonderSwan",
            buildbotStem:      "mednafen_wswan"
        ),

        // Supervision — Potator
        LibretroCore(
            systemIdentifiers: ["openemu.system.sv"],
            bundleIdentifier:  "org.openemu.Potator",
            displayName:       "Potator",
            buildbotStem:      "potator"
        ),

        // ── Home consoles (other) ─────────────────────────────────────────────

        // 3DO Interactive Multiplayer — Opera
        LibretroCore(
            systemIdentifiers: ["openemu.system.3do"],
            bundleIdentifier:  "org.openemu.Opera",
            displayName:       "Opera",
            buildbotStem:      "opera"
        ),

        // Vectrex — vecx
        LibretroCore(
            systemIdentifiers: ["openemu.system.vectrex"],
            bundleIdentifier:  "org.openemu.Vecx",
            displayName:       "vecx",
            buildbotStem:      "vecx"
        ),

        // ── Computers / other ─────────────────────────────────────────────────

        // MSX / MSX2 — blueMSX
        LibretroCore(
            systemIdentifiers: ["openemu.system.msx"],
            bundleIdentifier:  "org.openemu.blueMSX",
            displayName:       "blueMSX",
            buildbotStem:      "bluemsx",
            requiredFiles: [
                BIOSFileRequirement(name: "MSX.ROM", description: "MSX BIOS", expectedMD5: "70d06191c95e1e1948842183f38128ec", expectedSize: 32768),
                BIOSFileRequirement(name: "MSX2.ROM", description: "MSX2 BIOS", expectedMD5: "1356f627727a3c330f606a5992fe464d", expectedSize: 32768)
            ]
        ),

        // ColecoVision — GearColeco
        LibretroCore(
            systemIdentifiers: ["openemu.system.colecovision"],
            bundleIdentifier:  "org.openemu.GearColeco",
            displayName:       "GearColeco",
            buildbotStem:      "gearcoleco"
        ),

        // Mattel Intellivision — FreeIntv
        LibretroCore(
            systemIdentifiers: ["openemu.system.intellivision"],
            bundleIdentifier:  "org.openemu.FreeIntv",
            displayName:       "FreeIntv",
            buildbotStem:      "freeintv"
        ),

        // Magnavox Odyssey² — O2EM
        LibretroCore(
            systemIdentifiers: ["openemu.system.odyssey2"],
            bundleIdentifier:  "org.openemu.O2EM",
            displayName:       "O2EM",
            buildbotStem:      "o2em"
        ),
    ]

    // MARK: - Lookup helpers

    /// Returns the registry entry whose `bundleIdentifier` matches the given one, if any.
    static func core(forBundleIdentifier bundleID: String) -> LibretroCore? {
        allCores.first { $0.bundleIdentifier.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    /// Returns the registry entry whose `dylibFilename` matches the given filename, if any.
    static func core(forDylibFilename filename: String) -> LibretroCore? {
        allCores.first { $0.dylibFilename == filename }
    }

    /// Returns all system identifiers known for the given dylib filename.
    static func systemIdentifiers(forDylibFilename filename: String) -> [String] {
        let core = allCores.first { $0.dylibFilename.caseInsensitiveCompare(filename) == .orderedSame }
        return core?.systemIdentifiers ?? []
    }
}
