// Copyright (c) 2026, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted under the BSD 2-Clause license.

import Foundation
import OpenEmuBase

/// Validates cheat codes against the formats a given core can handle.
/// TODO: move to a protocol on each core once cores declare supported formats via Info.plist
enum CheatCodeValidator {

    /// Returns true if the code (possibly multi-part with '+') is valid for the given core and system.
    static func isValid(code: String, systemIdentifier: String, coreIdentifier: String) -> Bool {
        code.components(separatedBy: "+")
            .allSatisfy { isValidSingle($0.trimmingCharacters(in: .whitespaces), systemIdentifier: systemIdentifier, coreIdentifier: coreIdentifier) }
    }

    private static func isValidSingle(_ code: String, systemIdentifier: String, coreIdentifier: String) -> Bool {
        switch systemIdentifier {
        case OESystemIdentifierAtari2600:
            // Stella: scanHexInt is flexible on length, cast to uInt16/uInt8
            return isRawAddressValue(code, maxAddressHexChars: 4, maxValueHexChars: 2)

        case OESystemIdentifierNES, OESystemIdentifierFDS:
            // FCEU: raw XXXX:XX, XXXX?XX:XX, NES Game Genie — no Pro Action Rocky
            if coreIdentifier == "org.openemu.FCEU" {
                return isRawAddressValue(code, addressHexChars: 4, valueHexChars: 2)
                    || isRawAddressValueWithCompare(code)
                    || isNESGameGenieCode(code)
            }
            // Nestopia (default): also supports Pro Action Rocky
            return isRawAddressValue(code, addressHexChars: 4, valueHexChars: 2)
                || isRawAddressValueWithCompare(code)
                || isNESGameGenieCode(code)
                || isNESProActionRockyCode(code)

        case OESystemIdentifierSMS, OESystemIdentifierGameGear, OESystemIdentifierSG1000:
            if coreIdentifier == "org.openemu.CrabEmu" {
                return isSMSActionReplayCode(code) || isRawAddressValue(code)
            }
            return isSMSGameGenieCode(code) || isSMSActionReplayCode(code) || isRawAddressValue(code)

        default:
            return true
        }
    }

    // MARK: - Format Checks

    /// Raw address:value hex format. Accepts optional exact or max size constraints.
    static func isRawAddressValue(
        _ code: String,
        addressHexChars: Int? = nil,
        valueHexChars: Int? = nil,
        maxAddressHexChars: Int? = nil,
        maxValueHexChars: Int? = nil
    ) -> Bool {
        guard code.contains(":"), !code.contains("?") else { return false }
        let parts = code.split(separator: ":")
        guard parts.count == 2, parts.allSatisfy({ $0.allSatisfy(\.isHexDigit) }) else { return false }
        if let exact = addressHexChars, parts[0].count != exact { return false }
        if let exact = valueHexChars, parts[1].count != exact { return false }
        if let max = maxAddressHexChars, parts[0].count > max { return false }
        if let max = maxValueHexChars, parts[1].count > max { return false }
        return true
    }

    /// Raw address with compare: XXXX?XX:XX (exactly 10 chars)
    static func isRawAddressValueWithCompare(_ code: String) -> Bool {
        guard code.count == 10,
              code[code.index(code.startIndex, offsetBy: 4)] == "?",
              code[code.index(code.startIndex, offsetBy: 7)] == ":"
        else { return false }
        let addr = code.prefix(4)
        let comp = code[code.index(code.startIndex, offsetBy: 5)..<code.index(code.startIndex, offsetBy: 7)]
        let val = code.suffix(2)
        return addr.allSatisfy(\.isHexDigit) && comp.allSatisfy(\.isHexDigit) && val.allSatisfy(\.isHexDigit)
    }

    /// NES Pro Action Rocky: exactly 8 hex characters, scrambled encoding (Nestopia only)
    static func isNESProActionRockyCode(_ code: String) -> Bool {
        return code.count == 8 && code.allSatisfy(\.isHexDigit)
    }

    /// SMS/GG Game Genie: XX-XXX (short) or XXX-XXX-XXX (long), hex chars with dashes
    static func isSMSGameGenieCode(_ code: String) -> Bool {
        guard code.contains("-") else { return false }
        let parts = code.split(separator: "-")
        let allHex = parts.allSatisfy { $0.allSatisfy(\.isHexDigit) }
        return allHex && (parts.count == 2 || parts.count == 3)
    }

    private static let nesGameGenieChars = Set("AEPOZXLUGKISTVYN")

    /// NES Game Genie: 6 or 8 letters from AEPOZXLUGKISTVYN
    static func isNESGameGenieCode(_ code: String) -> Bool {
        let upper = code.uppercased()
        return (upper.count == 6 || upper.count == 8)
            && upper.allSatisfy { nesGameGenieChars.contains($0) }
    }

    /// SMS/GG Action Replay: XXXX-XXXX (2 groups of 4 hex chars)
    static func isSMSActionReplayCode(_ code: String) -> Bool {
        guard code.contains("-") else { return false }
        let parts = code.split(separator: "-")
        return parts.count == 2 && parts.allSatisfy { $0.count == 4 && $0.allSatisfy(\.isHexDigit) }
    }
}
