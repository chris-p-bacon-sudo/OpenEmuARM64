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
import OpenEmuSystem

public class OESystemPlugin: OEPlugin {
    
    public static let didRegisterNotification = Notification.Name("OESystemPluginDidRegisterNotification")
    
    private static var pluginsBySystemIdentifiers: [String: OESystemPlugin] = [:]
    
    override public class var pluginExtension: String {
        "oesystemplugin"
    }
    
    override public class var pluginFolder: String {
        "Systems"
    }
    
    @objc public class var allPlugins: [OESystemPlugin] {
        // swiftlint:disable:next force_cast
        return plugins() as! [OESystemPlugin]
    }
    
    required init(bundleAtURL bundleURL: URL, name: String?) throws {
        try super.init(bundleAtURL: bundleURL, name: name)
        
        assert(infoDictionary[OESystemIdentifier] != nil, "Info.plist missing value for required key: \(OESystemIdentifier)")
        
        Self.register(self, forIdentifier: systemIdentifier)
    }
    
    private static func register(_ plugin: OESystemPlugin, forIdentifier identifier: String) {
        pluginsBySystemIdentifiers[identifier] = plugin
        
        // invalidate global caches
        cachedSupportedTypeExtensions = nil
        cachedSupportedSystemTypes = nil
        cachedSupportedSystemMedia = nil
        
        NotificationCenter.default.post(name: didRegisterNotification, object: plugin)
    }
    
    public static func systemPlugin(bundleAtURL bundleURL: URL) -> OESystemPlugin? {
        return try? plugin(bundleAtURL: bundleURL)
    }
    
    public static func systemPlugin(forIdentifier identifier: String) -> OESystemPlugin? {
        return pluginsBySystemIdentifiers[identifier]
    }
    
    // MARK: -
    
    typealias Controller = OESystemController
    
    private var _controller: Controller?
    public var controller: OESystemController! {
        if _controller == nil,
           let principalClass = bundle.principalClass {
            _controller = newPluginController(with: principalClass)
        }
        return _controller
    }
    
    private func newPluginController(with bundleClass: AnyClass) -> Controller? {
        guard let bundleClass = bundleClass as? Controller.Type else { return nil }
        return bundleClass.init(bundle: bundle)
    }
    
    // MARK: -
    
    private static var cachedSupportedTypeExtensions: Set<String>?
    public static var supportedTypeExtensions: Set<String> {
        if cachedSupportedTypeExtensions == nil {
            var extensions: Set<String> = []
            for plugin in allPlugins {
                extensions.formUnion(plugin.supportedTypeExtensions)
            }
            
            cachedSupportedTypeExtensions = extensions
        }
        
        return cachedSupportedTypeExtensions!
    }
    
    private static var cachedSupportedSystemTypes: Set<String>?
    public static var supportedSystemTypes: Set<String> {
        if cachedSupportedSystemTypes == nil {
            var types: Set<String> = []
            for plugin in allPlugins {
                types.insert(plugin.systemType)
            }
            
            cachedSupportedSystemTypes = types
        }
        
        return cachedSupportedSystemTypes!
    }
    
    private static var cachedSupportedSystemMedia: Set<String>?
    public static var supportedSystemMedia: Set<String> {
        if cachedSupportedSystemMedia == nil {
            var media: Set<String> = []
            for plugin in allPlugins {
                media.formUnion(plugin.systemMedia)
            }
            
            cachedSupportedSystemMedia = media
        }
        
        return cachedSupportedSystemMedia!
    }
    
    public var systemIdentifier: String {
        return infoDictionary[OESystemIdentifier] as? String ?? ""
    }
    
    public var systemName: String {
        return controller.systemName
    }
    
    public var systemType: String {
        return controller.systemType
    }
    
    public var systemMedia: [String] {
        return controller.systemMedia
    }
    
    public var systemIcon: NSImage {
        return controller?.systemIcon ?? NSImage()
    }
    
    public var responderClass: AnyClass {
        return controller.responderClass
    }
    
    public var coverAspectRatio: CGFloat {
        return controller.coverAspectRatio
    }
    
    public var supportsDiscsWithDescriptorFile: Bool {
        return controller.supportsDiscsWithDescriptorFile
    }
    
    public var supportedTypeExtensions: [String] {
        return controller.fileTypes
    }
    
    // MARK: -
    
    override public var isOutOfSupport: Bool {
        // system plugins are shipped inside the application bundle;
        // all plugins located in the application support directory must be removed
        let bundleURL = bundle.bundleURL
        let fm = FileManager.default
        let systemsDirectory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenEmu", isDirectory: true)
            .appendingPathComponent(Self.pluginFolder, isDirectory: true)
        if bundleURL.isSubpath(of: systemsDirectory) {
            return true
        }
        
        return false
    }
}

private extension URL {
    
    func isSubpath(of url: URL) -> Bool {
        let parentPathComponents = url.standardized.pathComponents
        let ownPathComponents = standardized.pathComponents
        
        let ownPathCount = ownPathComponents.count
        
        for i in 0 ..< parentPathComponents.count {
            if i >= ownPathCount || parentPathComponents[i] != ownPathComponents[i] {
                return false
            }
        }
        
        return true
    }
}
