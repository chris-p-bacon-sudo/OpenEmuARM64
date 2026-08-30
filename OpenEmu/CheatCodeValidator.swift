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
            // Stella: uInt16 address, uInt8 value
            return isRawAddressValue(code, maxAddressHexChars: 4, maxValueHexChars: 2)

        case OESystemIdentifierSMS, OESystemIdentifierGameGear, OESystemIdentifierSG1000:
            if coreIdentifier == "org.openemu.CrabEmu" {
                return isActionReplayCode(code) || isRawAddressValue(code)
            }
            return isGameGenieCode(code) || isActionReplayCode(code) || isRawAddressValue(code)

        default:
            return true
        }
    }

    // MARK: - Format Checks

    /// Raw address:value hex format with optional size constraints.
    static func isRawAddressValue(_ code: String, maxAddressHexChars: Int? = nil, maxValueHexChars: Int? = nil) -> Bool {
        guard code.contains(":") else { return false }
        let parts = code.split(separator: ":")
        guard parts.count == 2, parts.allSatisfy({ $0.allSatisfy(\.isHexDigit) }) else { return false }
        if let maxAddr = maxAddressHexChars, parts[0].count > maxAddr { return false }
        if let maxVal = maxValueHexChars, parts[1].count > maxVal { return false }
        return true
    }

    /// Game Genie: XX-XXX (short) or XXX-XXX-XXX (long)
    static func isGameGenieCode(_ code: String) -> Bool {
        guard code.contains("-") else { return false }
        let parts = code.split(separator: "-")
        let allHex = parts.allSatisfy { $0.allSatisfy(\.isHexDigit) }
        return allHex && (parts.count == 2 || parts.count == 3)
    }

    /// Action Replay: XXXX-XXXX (2 groups of 4 hex chars)
    static func isActionReplayCode(_ code: String) -> Bool {
        guard code.contains("-") else { return false }
        let parts = code.split(separator: "-")
        return parts.count == 2 && parts.allSatisfy { $0.count == 4 && $0.allSatisfy(\.isHexDigit) }
    }
}
