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

public enum OEGameCorePluginError: Int, CustomNSError {
    case alreadyLoaded = -1000
    case invalid = -1001
    case outOfSupport = -1002
    
    public static var errorDomain: String { "org.openemu.OpenEmuKit.OEPlugin" }
}

public class OEPlugin: NSObject {
    
    private static var pluginClasses: Set<String> = []
    private static var allPluginsByType: [String: NSMutableDictionary] = [:]
    private static var pluginsForPathsByType: [String: NSMutableDictionary] = [:]
    private static var pluginsForNamesByType: [String: NSMutableDictionary] = [:]
    
    public private(set) var url: URL
    public private(set) var name: String
    
    public private(set) var bundle: Bundle
    public private(set) var infoDictionary: [String: Any]
    public private(set) var version: String
    public private(set) var displayName: String
    
    private class func pluginsForNames(createIfNeeded create: Bool) -> NSMutableDictionary? {
        var plugins = pluginsForNamesByType[Self.pluginType]
        if plugins == nil && create {
            plugins = [:]
            pluginsForNamesByType[Self.pluginType] = plugins
        }
        return plugins
    }
    
    private class func pluginsForPaths(createIfNeeded create: Bool) -> NSMutableDictionary? {
        var plugins = pluginsForPathsByType[Self.pluginType]
        if plugins == nil && create {
            plugins = [:]
            pluginsForPathsByType[Self.pluginType] = plugins
        }
        return plugins
    }
    
    private class var pluginType: String {
        return NSStringFromClass(self)
    }
    
    class var pluginExtension: String {
        assertionFailure("+pluginExtension must be overriden")
        return ""
    }
    
    class var pluginFolder: String {
        assertionFailure("+pluginFolder must be overriden")
        return ""
    }
    
    override public var description: String {
        "Type: \(Self.pluginType), Bundle: \(displayName), Version: \(version), Path: \(url.path)"
    }
    
    required init(bundleAtURL bundleURL: URL, name: String?) throws {
        guard let bundle = Bundle(url: bundleURL),
              let infoDictionary = bundle.infoDictionary
        else {
            throw OEGameCorePluginError.invalid
        }
        
        let name = name ?? (bundleURL.lastPathComponent as NSString).deletingPathExtension
        
        let existing = Self.pluginsForNames(createIfNeeded: false)?[name]
                    ?? Self.pluginsForPaths(createIfNeeded: false)?[bundleURL.path]
        if existing != nil {
            throw OEGameCorePluginError.alreadyLoaded
        }
        
        if bundleURL.pathExtension != Self.pluginExtension {
            throw OEGameCorePluginError.invalid
        }
        
        self.url = bundle.bundleURL
        self.name = name
        
        self.bundle = bundle
        self.infoDictionary = infoDictionary
        self.version = infoDictionary["CFBundleVersion"] as? String ?? ""
        self.displayName = infoDictionary["CFBundleName"] as? String ?? infoDictionary["CFBundleExecutable"] as? String ?? ""
        
        super.init()
        
        if isOutOfSupport {
            // plugin must be removed
            // Log removed for Release
            
            let fm = FileManager.default
            do {
                try fm.removeItem(at: bundleURL)
            } catch {
                // Log removed for Release
            }
            
            throw OEGameCorePluginError.outOfSupport
        }
        
        Self.pluginsForPaths(createIfNeeded: true)![bundleURL.path] = self
        Self.pluginsForNames(createIfNeeded: true)![name] = self
    }
    
    deinit {
        bundle.unload()
    }
    
    public class func plugin(bundleAtURL bundleURL: URL, forceReload reload: Bool = false) throws -> Self? {
        var plugins = allPluginsByType[Self.pluginType]
        if plugins == nil {
            plugins = NSMutableDictionary()
            allPluginsByType[Self.pluginType] = plugins
        }
        
        let pluginName = (bundleURL.lastPathComponent as NSString).deletingPathExtension
        var ret = plugins?[pluginName] as? NSObject
        
        if reload {
            // Will override a previous failed attempt at loading a plugin
            if ret == NSNull() {
                ret = nil
            }
            // A plugin was already successfully loaded
            else if ret != nil {
                throw OEGameCorePluginError.alreadyLoaded
            }
        }
        
        // No plugin with such name, attempt to actually load the file at the given url
        if ret == nil {
            var err: Error?
            
            do {
                ret = try Self.init(bundleAtURL: bundleURL, name: pluginName)
            } catch {
                err = error
            }
            
            // If ret is still nil at this point, it means the plugin can't be loaded
            if ret == nil {
                ret = NSNull()
            }
            
            Self.willChangeValue(forKey: "allPlugins")
            plugins?[pluginName] = ret
            Self.didChangeValue(forKey: "allPlugins")
            
            if let error = err {
                throw error
            }
        }
        
        if ret == NSNull() {
            ret = nil
        }
        
        return ret as? Self
    }
    
    public class func registerClass() {
        pluginClasses.insert(Self.pluginType)
        
        _ = plugins()
    }
    
    class func plugins() -> [OEPlugin] {
        guard pluginClasses.contains(Self.pluginType) else {
            assertionFailure("\(pluginType) must be registered with +registerClass")
            return []
        }
        var plugins = allPluginsByType[Self.pluginType]
        if plugins == nil {
            let fm = FileManager.default
            
            // load plugins in Application Support
            let appSupportDir: URL
            #if swift(>=5.7)
            if #available(macOS 13.0, *) {
                appSupportDir = .applicationSupportDirectory
            } else {
                appSupportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            }
            #else
            appSupportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            #endif
            let pluginsDir = appSupportDir.appendingPathComponent("OpenEmu", isDirectory: true)
                                          .appendingPathComponent(Self.pluginFolder, isDirectory: true)
            let pluginURLs = try? fm.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: [])
            for bundleURL in pluginURLs ?? [] where bundleURL.pathExtension == Self.pluginExtension {
                _ = try? plugin(bundleAtURL: bundleURL, forceReload: true)
            }
            
            // load plugins in application bundle
            let builtInPluginsURL = Bundle.main.builtInPlugInsURL!
            let bundledPluginsDir = builtInPluginsURL.appendingPathComponent(Self.pluginFolder, isDirectory: true)
            let bundledPluginURLs = try? fm.contentsOfDirectory(at: bundledPluginsDir, includingPropertiesForKeys: [])
            for bundleURL in bundledPluginURLs ?? [] where bundleURL.pathExtension == Self.pluginExtension {
                _ = try? plugin(bundleAtURL: bundleURL)
            }
            
            plugins = allPluginsByType[Self.pluginType]
        }
        
        let val = plugins?.allValues.compactMap { $0 as? OEPlugin } ?? []
        let set = Set(val)
        let ret = Array(set).sorted { $0.displayName.caseInsensitiveCompare($1.displayName) == .orderedAscending }
        
        return ret
    }
    
    var isDeprecated: Bool {
        return isOutOfSupport
    }
    
    var isOutOfSupport: Bool {
        return false
    }
    
    public func flushBundleCache() {
        bundle.flushBundleCache()
        
        infoDictionary = bundle.infoDictionary ?? infoDictionary
        version = infoDictionary["CFBundleVersion"] as? String ?? ""
        displayName = infoDictionary["CFBundleName"] as? String ?? infoDictionary["CFBundleExecutable"] as? String ?? ""
    }
}

extension OEPlugin: NSCopying {
    // When an instance is assigned as objectValue to an NSCell, the NSCell creates a copy.
    // Therefore we have to implement the NSCopying protocol
    // No need to make an actual copy, we can consider each OEPlugin instance like a singleton for their bundle
    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }
}
