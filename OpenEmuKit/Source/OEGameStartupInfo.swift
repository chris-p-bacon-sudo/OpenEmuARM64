// Copyright (c) 2022, OpenEmu Team
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

@objc(OEGameStartupInfo) public class OEGameStartupInfo: NSObject, NSSecureCoding {
    
    public let romURL: URL
    public let romMD5: String
    public let romHeader: String
    public let romSerial: String
    public let systemRegion: String
    public let displayModeInfo: [String: Any]?
    public let shaderURL: URL
    public let shaderParameters: [String: Double]
    public let corePluginURL: URL
    public let systemPluginURL: URL
    public let lockOnRomURL: URL?
    public let lockOnUpmemURL: URL?
    
    public init(romURL: URL, romMD5: String, romHeader: String, romSerial: String,
                systemRegion: String,
                displayModeInfo: [String: Any]?,
                shaderURL: URL, shaderParameters: [String: Double],
                corePluginURL: URL, systemPluginURL: URL,
                lockOnRomURL: URL? = nil, lockOnUpmemURL: URL? = nil) {
        self.romURL = romURL
        self.romMD5 = romMD5
        self.romHeader = romHeader
        self.romSerial = romSerial
        self.systemRegion = systemRegion
        self.displayModeInfo = displayModeInfo
        self.shaderURL = shaderURL
        self.shaderParameters = shaderParameters
        self.corePluginURL = corePluginURL
        self.systemPluginURL = systemPluginURL
        self.lockOnRomURL = lockOnRomURL
        self.lockOnUpmemURL = lockOnUpmemURL
    }
    
    // MARK: - NSSecureCoding
    
    public static var supportsSecureCoding: Bool { return true }
    
    public required init?(coder: NSCoder) {
        guard
            let romURL = coder.decodeObject(of: NSURL.self, forKey: CodingKeys.romURL.rawValue) as? URL,
            let romMD5 = coder.decodeObject(of: NSString.self, forKey: CodingKeys.romMD5.rawValue) as? String,
            let romHeader = coder.decodeObject(of: NSString.self, forKey: CodingKeys.romHeader.rawValue) as? String,
            let romSerial = coder.decodeObject(of: NSString.self, forKey: CodingKeys.romSerial.rawValue) as? String,
            let systemRegion = coder.decodeObject(of: NSString.self, forKey: CodingKeys.systemRegion.rawValue) as? String,
            let displayModeInfo = coder.decodePropertyList(forKey: CodingKeys.displayModeInfo.rawValue) as? [String: Any]?,
            let shaderURL = coder.decodeObject(of: NSURL.self, forKey: CodingKeys.shaderURL.rawValue) as? URL,
            let shaderParameters = coder.decodeObject(of: [NSString.self, NSDictionary.self, NSNumber.self],
                                                      forKey: CodingKeys.shaderParameters.rawValue) as? [String: Double],
            let corePluginURL = coder.decodeObject(of: NSURL.self, forKey: CodingKeys.corePluginURL.rawValue) as? URL,
            let systemPluginURL = coder.decodeObject(of: NSURL.self, forKey: CodingKeys.systemPluginURL.rawValue) as? URL
        else { return nil }
        
        self.romURL = romURL
        self.romMD5 = romMD5
        self.romHeader = romHeader
        self.romSerial = romSerial
        self.systemRegion = systemRegion
        self.displayModeInfo = displayModeInfo
        self.shaderURL = shaderURL
        self.shaderParameters = shaderParameters
        self.corePluginURL = corePluginURL
        self.systemPluginURL = systemPluginURL
        self.lockOnRomURL = coder.decodeObject(of: NSURL.self, forKey: CodingKeys.lockOnRomURL.rawValue) as? URL
        self.lockOnUpmemURL = coder.decodeObject(of: NSURL.self, forKey: CodingKeys.lockOnUpmemURL.rawValue) as? URL
    }
    
    public func encode(with coder: NSCoder) {
        coder.encode(romURL, forKey: CodingKeys.romURL.rawValue)
        coder.encode(romMD5, forKey: CodingKeys.romMD5.rawValue)
        coder.encode(romHeader, forKey: CodingKeys.romHeader.rawValue)
        coder.encode(romSerial, forKey: CodingKeys.romSerial.rawValue)
        coder.encode(systemRegion, forKey: CodingKeys.systemRegion.rawValue)
        coder.encode(displayModeInfo, forKey: CodingKeys.displayModeInfo.rawValue)
        coder.encode(shaderURL, forKey: CodingKeys.shaderURL.rawValue)
        coder.encode(shaderParameters, forKey: CodingKeys.shaderParameters.rawValue)
        coder.encode(corePluginURL, forKey: CodingKeys.corePluginURL.rawValue)
        coder.encode(systemPluginURL, forKey: CodingKeys.systemPluginURL.rawValue)
        coder.encode(lockOnRomURL, forKey: CodingKeys.lockOnRomURL.rawValue)
        coder.encode(lockOnUpmemURL, forKey: CodingKeys.lockOnUpmemURL.rawValue)
    }
    
    private enum CodingKeys: String {
        case romURL, romMD5, romHeader, romSerial
        case systemRegion, displayModeInfo
        case shaderURL, shaderParameters
        case corePluginURL, systemPluginURL
        case lockOnRomURL, lockOnUpmemURL
    }
}
