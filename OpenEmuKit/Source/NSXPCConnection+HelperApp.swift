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

extension NSXPCConnection {
    struct BrokerError: Error, LocalizedError {
        var errorDescription: String? { 
            NSLocalizedString("Failed to launch helper app", comment: "")
        }
        let failureReason: String?
    }
    
    static let helperIdentifierArgumentPrefix = "--org.openemu.broker.id="
    static let helperServiceNameArgumentPrefix = "--org.openemu.broker.name="
    private static var xpcTaskKey = 0
    
    static func makeConnection(serviceName name: String, executableURL url: URL) throws -> NSXPCConnection {
        let identifier = UUID().uuidString
        
        /// 1. Launch Helper App
        /// This results in the helper app establishing a connection to the broker and registering its
        /// `identifier`
        let task = Process()
        task.executableURL = url
        task.arguments = ["\(Self.helperIdentifierArgumentPrefix)\(identifier)", "\(Self.helperServiceNameArgumentPrefix)\(name)"]
        task.terminationHandler = { task in
            // Log removed for Release
        }
        task.standardError  = FileHandle.standardError
        task.standardOutput = FileHandle.standardOutput
        do {
            try task.run()
        } catch {
            throw BrokerError(failureReason: error.localizedDescription)
        }
        
        var success = false
        defer {
            // Terminate helper when broker connection fails
            if !success {
                // Log removed for Release
                task.terminationHandler = nil
                task.terminate()
            }
        }
        
        /// 2. Launch a connection to the broker
        let cn = NSXPCConnection(serviceName: name)
        cn.invalidationHandler = {
            // Log removed for Release
        }
        
        cn.remoteObjectInterface = .init(with: OEXPCMatchMaking.self)
        cn.resume()
        
        let mm = cn.remoteObjectProxyWithErrorHandler { error in
            // Log removed for Release
        } as? OEXPCMatchMaking
        
        guard let mm = mm else {
            // Log removed for Release
            throw BrokerError(failureReason: NSLocalizedString("OEXPCMatchMaking proxy was nil", comment: ""))
        }
        
        let sem = DispatchSemaphore(value: 0)
        var endpoint: NSXPCListenerEndpoint?
        mm.retrieveListenerEndpoint(forIdentifier: identifier) { ep in
            endpoint = ep
            sem.signal()
        }
        
#if XPC_WAIT_FOREVER
        sem.wait()
#else
        if sem.wait(timeout: .now() + .seconds(10)) == .timedOut {
            // mediation of connection between host and helper via broker timed out
            // Log removed for Release
            
            throw BrokerError(failureReason: NSLocalizedString("Timeout waiting for connection from helper app", comment: ""))
        }
        
#endif
        
        cn.invalidationHandler = nil
        cn.invalidate()
        
        guard let endpoint = endpoint else {
            throw BrokerError(failureReason: NSLocalizedString("Broker endpoint is nil", comment: ""))
        }
        
        guard task.isRunning else {
            throw BrokerError(failureReason: NSLocalizedString("Helper unexpectedly terminated", comment: ""))
        }
        
        let newCn = NSXPCConnection(listenerEndpoint: endpoint)
        
        task.terminationHandler = { [weak newCn] task in
            // Log removed for Release
            newCn?.invalidate()
        }
        
        objc_setAssociatedObject(newCn, &Self.xpcTaskKey, task, .OBJC_ASSOCIATION_RETAIN)
        
        success = true
        return newCn
    }
}
