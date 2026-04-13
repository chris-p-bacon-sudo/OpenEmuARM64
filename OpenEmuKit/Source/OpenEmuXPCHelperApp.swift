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


@objc public class OpenEmuXPCHelperApp: OpenEmuHelperApp {
    var mainListener: NSXPCListener!
    var gameCoreConnection: NSXPCConnection!
    
    var serviceName: String
    
    init(serviceName: String) {
        self.serviceName = serviceName
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    static var serviceNameArgument: String? {
        ProcessInfo
            .processInfo
            .arguments
            // find the first argument with the service name option
            .first { $0.hasPrefix(NSXPCConnection.helperServiceNameArgumentPrefix) }
            // trim the prefix to return just the service name
            .map { String($0.suffix(from: NSXPCConnection.helperServiceNameArgumentPrefix.endIndex)) }
    }
    
    public static func run() {
        // Log removed for Release
        
        guard let serviceName = Self.serviceNameArgument else {
            // Log removed for Release
            fatalError("Unable to find XPCBrokerServiceName argument")
        }
        
        // Log removed for Release
        
        autoreleasepool {
            let app = OpenEmuXPCHelperApp(serviceName: serviceName)
            app.launchApplication()
        }
    }
    
    public override func launchApplication() {
        do {
            let mainListener: NSXPCListener = try .makeHelperListener(serviceName: serviceName)
            mainListener.delegate = self
            mainListener.resume()
            self.mainListener = mainListener
            
            setup()
            
            CFRunLoopRun()
            _Exit(EXIT_SUCCESS)
        } catch {
            // Log removed for Release
            _Exit(EXIT_FAILURE)
        }
    }
    
    private func setup() {
        let dm = OEDeviceManager.shared
        if #available(macOS 10.15, *) {
            if dm.accessType != .granted {
                dm.requestAccess()
                // Log removed for Release
            }
        }
    }
    
    func terminate() {
        // Log removed for Release
        CFRunLoopStop(CFRunLoopGetMain())
    }
}

@objc extension OpenEmuXPCHelperApp: NSXPCListenerDelegate {
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard listener == mainListener
        else { return false }
        
        let intf = NSXPCInterface(with: OEXPCGameCoreHelper.self)
        
        // load ROM
        let classes: NSSet = [OEGameStartupInfo.self]
        // swiftlint:disable:next force_cast
        intf.setClasses(classes as! Set<AnyHashable>,
                        for: #selector(load(with:completionHandler:)),
                        argumentIndex: 0,
                        ofReply: false)
        
        gameCoreConnection = newConnection
        
        newConnection.exportedInterface = intf
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = NSXPCInterface(with: OEGameCoreOwner.self)
        newConnection.invalidationHandler = {
            // Log removed for Release
            _Exit(EXIT_SUCCESS)
        }
        newConnection.interruptionHandler = {
            // Log removed for Release
            _Exit(EXIT_SUCCESS)
        }
        
        newConnection.resume()
        
        gameCoreOwner = newConnection.remoteObjectProxyWithErrorHandler({ error in
            // Log removed for Release
            self.stopEmulation {
            }
        }) as? OEGameCoreOwner
        
        return true
    }
    
}

@objc extension OpenEmuXPCHelperApp: OEXPCGameCoreHelper {
    public func load(with info: OEGameStartupInfo, completionHandler: @escaping (Error?) -> Void) {
        do {
            try load(withStartupInfo: info)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
