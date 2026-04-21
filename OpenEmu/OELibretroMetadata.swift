// Copyright (c) 2026, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// ...
//

import Foundation

/// Metadata for a required system file (BIOS).
@objc protocol OELibretroBIOSRequirement {
    var name: String { get }
    var fileDescription: String { get }
    var expectedMD5: String { get }
    var expectedSize: Int { get }
}

final class BIOSRequirement: NSObject, OELibretroBIOSRequirement {
    let name: String
    let fileDescription: String
    let expectedMD5: String
    let expectedSize: Int

    init(name: String, description: String, md5: String, size: Int) {
        self.name = name
        self.fileDescription = description
        self.expectedMD5 = md5
        self.expectedSize = size
    }
}

/// Unified registry for Libretro core runtime metadata (BIOS, System IDs).
/// This replaces the dynamic buildbot registry for runtime checks.
@objc(OELibretroMetadata)
final class OELibretroMetadata: NSObject {

    @objc static let shared = OELibretroMetadata()
    
    /// The current version of the Libretro bridge.
    /// Cores can specify OERequiredBridgeVersion in their Info.plist to ensure compatibility.
    @objc let currentBridgeVersion: Double = 1.0
    
    @objc let versionDescription: String = "1.0-silicon-hardened"

    /// Returns the BIOS requirements for a given system identifier.
    /// - Parameter systemID: The OpenEmu system identifier (e.g. "openemu.system.psx").
    /// - Returns: An array of BIOS requirements, or nil if none are defined.
    @objc func biosRequirements(forSystem systemID: String) -> [OELibretroBIOSRequirement]? {
        let id = systemID.lowercased()

        if id.contains("psx") {
            return [
                BIOSRequirement(name: "scph5500.bin", description: "PlayStation BIOS (JP)", md5: "8dd7d5296a650fac7319bce665a6a53c", size: 524288),
                BIOSRequirement(name: "scph5501.bin", description: "PlayStation BIOS (US)", md5: "490f666e1a21530d03ad55ad333aa372", size: 524288),
                BIOSRequirement(name: "scph5502.bin", description: "PlayStation BIOS (EU)", md5: "32736f17079d0b2b7024407c39bd3050", size: 524288)
            ]
        }

        if id.contains("dc") {
            return [
                BIOSRequirement(name: "dc_boot.bin", description: "Dreamcast BIOS", md5: "", size: 0),
                BIOSRequirement(name: "dc_flash.bin", description: "Dreamcast Flash", md5: "", size: 0)
            ]
        }

        if id.contains("saturn") {
            return [
                BIOSRequirement(name: "sat_bios_jp.bin", description: "Saturn BIOS (JP)", md5: "2aba4251329305f8b29bc62d3a3d537f", size: 524288),
                BIOSRequirement(name: "sat_bios_us.bin", description: "Saturn BIOS (US)", md5: "af58e0fdc11efec58df169ca13c36c64", size: 524288),
                BIOSRequirement(name: "sat_bios_eu.bin", description: "Saturn BIOS (EU)", md5: "9469502759e07503fa658d57053e19fb", size: 524288)
            ]
        }

        if id.contains("nds") {
            return [
                BIOSRequirement(name: "bios7.bin", description: "DS BIOS 7", md5: "", size: 0),
                BIOSRequirement(name: "bios9.bin", description: "DS BIOS 9", md5: "", size: 0),
                BIOSRequirement(name: "firmware.bin", description: "DS Firmware", md5: "", size: 0)
            ]
        }
        
        if id.contains("msx") {
            return [
                BIOSRequirement(name: "MSX.ROM", description: "MSX BIOS", md5: "70d06191c95e1e1948842183f38128ec", size: 32768),
                BIOSRequirement(name: "MSX2.ROM", description: "MSX2 BIOS", md5: "1356f627727a3c330f606a5992fe464d", size: 32768)
            ]
        }

        return nil
    }
}
