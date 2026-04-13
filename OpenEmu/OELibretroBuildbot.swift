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

/// Describes a single libretro core available from the buildbot.
struct LibretroCore {
    /// OpenEmu system identifiers this core handles (e.g. "openemu.system.snes").
    let systemIdentifiers: [String]
    /// OpenEmu-style bundle identifier for the synthesised plugin (e.g. "org.openemu.libretro.snes9x").
    let bundleIdentifier: String
    /// Human-readable name shown in the "Missing Core" alert.
    let displayName: String
    /// Base filename on the buildbot, without the trailing "_libretro" suffix (e.g. "snes9x").
    let buildbotStem: String
    /// Metadata for required system files (BIOS).
    let requiredFiles: [[String: Any]]?

    /// Full dylib filename as it appears after extraction (e.g. "snes9x_libretro.dylib").
    var dylibFilename: String { "\(buildbotStem)_libretro.dylib" }

    /// Download URL on the Libretro development buildbot for macOS.
    var downloadURL: URL {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        return URL(string: "https://buildbot.libretro.com/nightly/apple/osx/\(arch)/latest/\(dylibFilename).zip")!
    }

    init(systemIdentifiers: [String], bundleIdentifier: String, displayName: String, buildbotStem: String, requiredFiles: [[String: Any]]? = nil) {
        self.systemIdentifiers = systemIdentifiers
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.buildbotStem = buildbotStem
        self.requiredFiles = requiredFiles
    }
}

/// Registry of the best ARM64 libretro cores and helpers for injecting them into CoreUpdater.
///
/// Cores are chosen for:
///  - Native ARM64 dylib availability on the buildbot
///  - XRGB8888 or RGB565 pixel format (Metal-compatible without conversion)
///  - Active upstream maintenance
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
        // Genesis Plus GX handles all of these in a single ARM64 dylib.
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

        // Sega 32X — Picodrive: the only libretro core that emulates 32X
        LibretroCore(
            systemIdentifiers: ["openemu.system.32x"],
            bundleIdentifier:  "org.openemu.libretro.picodrive",
            displayName:       "PicoDrive",
            buildbotStem:      "picodrive"
        ),

        // Sega Saturn — Beetle Saturn (Mednafen): very accurate, native ARM64
        LibretroCore(
            systemIdentifiers: ["openemu.system.saturn"],
            bundleIdentifier:  "org.openemu.libretro.mednafen",
            displayName:       "Beetle Saturn",
            buildbotStem:      "mednafen_saturn",
            requiredFiles: [
                ["Name": "sat_bios_jp.bin", "Description": "Saturn BIOS (JP)", "MD5": "2aba4251329305f8b29bc62d3a3d537f", "Size": 524288],
                ["Name": "sat_bios_us.bin", "Description": "Saturn BIOS (US)", "MD5": "af58e0fdc11efec58df169ca13c36c64", "Size": 524288],
                ["Name": "sat_bios_eu.bin", "Description": "Saturn BIOS (EU)", "MD5": "9469502759e07503fa658d57053e19fb", "Size": 524288]
            ]
        ),

        // Dreamcast — Flycast libretro: modern, active, high-performance ARM64.
        // Replaces the custom Flycast native wrapper (same upstream, libretro API).
        LibretroCore(
            systemIdentifiers: ["openemu.system.dc"],
            bundleIdentifier:  "org.openemu.libretro.flycast",
            displayName:       "Flycast",
            buildbotStem:      "flycast"
        ),

        // ── Sony ─────────────────────────────────────────────────────────────

        // PlayStation — PCSX-ReARMed: hand-optimised ARM NEON assembly,
        // active nightly ARM64 builds, best PSX performance on Apple Silicon.
        LibretroCore(
            systemIdentifiers: ["openemu.system.psx"],
            bundleIdentifier:  "org.openemu.libretro.pcsx-rearmed",
            displayName:       "PCSX-ReARMed",
            buildbotStem:      "pcsx_rearmed",
            requiredFiles: [
                ["Name": "scph5501.bin", "Description": "PlayStation BIOS (US)", "MD5": "490f666e1a21530d03ad55ad333aa372", "Size": 524288]
            ]
        ),

        // PlayStation Portable — PPSSPP: best PSP performance, active nightly
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

        // Atari 2600 — Stella (current): actively maintained
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

        // Atari Jaguar already listed above

        // ── Computers / other ─────────────────────────────────────────────────

        // MSX / MSX2 — blueMSX
        LibretroCore(
            systemIdentifiers: ["openemu.system.msx"],
            bundleIdentifier:  "org.openemu.blueMSX",
            displayName:       "blueMSX",
            buildbotStem:      "bluemsx",
            requiredFiles: [
                ["Name": "MSX.ROM", "Description": "MSX BIOS", "MD5": "70d06191c95e1e1948842183f38128ec", "Size": 32768],
                ["Name": "MSX2.ROM", "Description": "MSX2 BIOS", "MD5": "1356f627727a3c330f606a5992fe464d", "Size": 32768]
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
    /// Comparison is case-insensitive because `CoreUpdater.coresDict` stores keys lowercased
    /// while the registry uses mixed-case identifiers (e.g. "org.openemu.Snes9x").
    static func core(forBundleIdentifier bundleID: String) -> LibretroCore? {
        allCores.first { $0.bundleIdentifier.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    /// Returns the registry entry whose `dylibFilename` matches the given filename, if any.
    static func core(forDylibFilename filename: String) -> LibretroCore? {
        allCores.first { $0.dylibFilename == filename }
    }

    /// Returns all system identifiers known for the given dylib filename.
    /// Comparison is case-insensitive to handle buildbot vs registry naming differences.
    static func systemIdentifiers(forDylibFilename filename: String) -> [String] {
        let core = allCores.first { $0.dylibFilename.caseInsensitiveCompare(filename) == .orderedSame }
        return core?.systemIdentifiers ?? []
    }

    // MARK: - CoreUpdater injection

    /// Injects a `CoreDownload` entry for every libretro core that is not already present
    /// in `dict` (i.e. not yet installed or already known).  Call this from
    /// `CoreUpdater.checkForNewCores()` after the standard OpenEmu core list is fetched.
    ///
    /// - Parameters:
    ///   - dict:     The `CoreUpdater.coresDict` to mutate (keyed by lowercased bundle ID).
    ///   - delegate: The `CoreDownloadDelegate` (= the `CoreUpdater` singleton).
    static func injectCoreDownloads(
        into dict: inout [String: CoreDownload],
        delegate: CoreDownloadDelegate
    ) {
        for core in allCores {
            let key = core.bundleIdentifier.lowercased()
            // Skip if already installed (plugin-backed CoreDownload exists).
            guard dict[key] == nil else { continue }

            let download          = CoreDownload()
            download.name             = core.displayName
            download.bundleIdentifier = core.bundleIdentifier
            download.systemIdentifiers = core.systemIdentifiers
            download.canBeInstalled   = true
            download.appcastItem      = CoreAppcastItem(
                url:          core.downloadURL,
                version:      "Nightly",
                minOSVersion: "11.0"
            )
            download.delegate = delegate

            dict[key] = download
        }
    }
}
