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

internal import os.log

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
        NSLog("[OpenEmuHelperApp] run() started")
        
        guard let serviceName = Self.serviceNameArgument else {
            NSLog("[OpenEmuHelperApp] FATAL: Unable to find XPCBrokerServiceName argument")
            fatalError("Unable to find XPCBrokerServiceName argument")
        }
        
        NSLog("[OpenEmuHelperApp] Initializing and launching application for service: %@", serviceName)
        
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
            os_log(.error, log: .helper, "Unable to retrieve helper listener. error = %{public}@", error.localizedDescription)
            _Exit(EXIT_FAILURE)
        }
    }
    
    private func setup() {
        let dm = OEDeviceManager.shared
        if #available(macOS 10.15, *) {
            if dm.accessType != .granted {
                dm.requestAccess()
                os_log(.info, log: .helper, "Input monitoring failed: Access Denied")
            }
        }
    }
    
    func terminate() {
        os_log(.debug, log: .helper, "Terminating helper")
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
            os_log(.debug, log: .helper, "Connection was invalidated; exiting.")
            _Exit(EXIT_SUCCESS)
        }
        newConnection.interruptionHandler = {
            os_log(.debug, log: .helper, "Connection was interrupted; exiting.")
            _Exit(EXIT_SUCCESS)
        }
        
        newConnection.resume()
        
        gameCoreOwner = newConnection.remoteObjectProxyWithErrorHandler({ error in
            os_log(.debug, log: .helper, "Error communicating with OEGameCoreOwner proxy: %{public}@", error.localizedDescription)
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
