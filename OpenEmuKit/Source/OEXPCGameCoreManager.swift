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
import OpenEmuKitPrivate

@objc public class OEXPCGameCoreManager: GameCoreManager {
    let serviceName: String
    let helperExecutableName: String
    
    @objc public init(startupInfo: OEGameStartupInfo, gameCoreOwner: OEGameCoreOwner, serviceName: String, helperExecutableName: String) {
        self.serviceName = serviceName
        self.helperExecutableName = helperExecutableName
        super.init(startupInfo: startupInfo, gameCoreOwner: gameCoreOwner)
    }
    
    var executableURL: URL? {
        Bundle.main.url(forAuxiliaryExecutable: helperExecutableName)
    }
    
    var helperConnection: NSXPCConnection?
    var gameCoreOwnerProxy: OEThreadProxy?
    
    public override func loadROM(completionHandler: @escaping StartupCompletionHandler) {
        guard let executableURL = executableURL
        else { fatalError("Missing XPC helper executable") }
        
        let cn: NSXPCConnection
        do {
            // Log removed for Release
            cn = try .makeConnection(serviceName: serviceName, executableURL: executableURL)
            helperConnection = cn
        } catch {
            DispatchQueue.main.async {
                completionHandler(error)
            }
            
            // There's no listener endpoint, so don't bother trying to create an NSXPCConnection.
            // Returning now since calling initWithListenerEndpoint: and passing it nil results in a memory leak.
            // Also, there's no point in trying to get the gameCoreHelper if there's no _helperConnection.
            return
        }
        
        cn.invalidationHandler = { [weak self] in
            self?.notifyGameCoreDidTerminate()
        }
        
        let proxy = OEThreadProxy(target: gameCoreOwner, thread: .main)
        
        cn.exportedInterface = .init(with: OEGameCoreOwner.self)
        cn.exportedObject = proxy
        
        let intf = NSXPCInterface(with: OEXPCGameCoreHelper.self)
        
        // startup
        let classes: NSSet = [OEGameStartupInfo.self]
        // swiftlint:disable:next force_cast
        intf.setClasses(classes as! Set<AnyHashable>,
                        for: #selector(OEXPCGameCoreHelper.load(with:completionHandler:)),
                        argumentIndex: 0,
                        ofReply: false)
        
        cn.remoteObjectInterface = intf
        cn.resume()
        
        let gameCoreHelper = cn.remoteObjectProxyWithErrorHandler { error in
            // Log removed for Release
            DispatchQueue.main.async {
                completionHandler(error)
                self.stop()
            }
        } as? OEXPCGameCoreHelper
        
        guard let gameCoreHelper = gameCoreHelper
        else { return }
        
        gameCoreHelper.load(with: startupInfo) { error in
            if let error = error {
                DispatchQueue.main.async {
                    completionHandler(error)
                    self.stop()
                }
                
                // There's no listener endpoint, so don't bother trying to create an NSXPCConnection.
                // Returning now since calling initWithListenerEndpoint: and passing it nil results in a memory leak.
                return
            }
            
            self.gameCoreHelper = gameCoreHelper
            DispatchQueue.main.async {
                completionHandler(nil)
            }
        }
    }
    
    public override func loadROM(completionHandler: @escaping () -> Void, errorHandler: @escaping (Error) -> Void) {
        loadROM { error in
            if let error = error {
                errorHandler(error)
            } else {
                completionHandler()
            }
        }
    }
    
    override func stop() {
        gameCoreHelper = nil
        gameCoreOwnerProxy = nil
        helperConnection?.invalidate()
    }
}
 
