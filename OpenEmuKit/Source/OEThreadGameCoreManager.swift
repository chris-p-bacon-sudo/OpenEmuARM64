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

@objc public class OEThreadGameCoreManager: GameCoreManager {
    var helperThread: Thread?
    var dummyTimer: Timer?
    
    var helper: OpenEmuHelperApp?
    
    typealias StopHandler = () -> Void
    var stopHandler: StopHandler?
    
    public override func loadROM(completionHandler: @escaping () -> Void, errorHandler: @escaping (Error) -> Void) {
        loadROM { error in
            if let error = error {
                errorHandler(error)
            } else {
                completionHandler()
            }
        }
    }
    
    public override func loadROM(completionHandler: @escaping StartupCompletionHandler) {
        let thread = Thread {
            self.execute(completionHandler: completionHandler)
        }
        helperThread = thread
        thread.name = "org.openemu.core-manager-thread"
        thread.qualityOfService = .userInitiated
        
        let helperInstance = OpenEmuHelperApp()
        self.helper = helperInstance
        
        if let gameCoreOwner = gameCoreOwner,
           let proxy = OEThreadProxy(target: gameCoreOwner, thread: .main) as? OEGameCoreOwner {
            helperInstance.gameCoreOwner = proxy
        } else {
            completionHandler(NSError(domain: "org.openemu.OpenEmuKit.ThreadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to initialize core owner proxy"]))
            return
        }

        thread.start()
    }
    
    public override func stopEmulation(completionHandler handler: @escaping () -> Void) {
        stopHandler = handler
        gameCoreHelper?.stopEmulation {
            self.stop()
        }
    }
    
    override func stop() {
        guard let helperThread = helperThread else { return }
        if Thread.current == helperThread {
            stopHelperThread(nil)
        } else {
            perform(#selector(stopHelperThread(_:)), on: helperThread, with: nil, waitUntilDone: false)
        }
    }
    
    private func execute(completionHandler handler: @escaping StartupCompletionHandler) {
        autoreleasepool {
            do {
                guard let helper = helper else {
                    throw NSError(domain: "org.openemu.OpenEmuKit.ThreadError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Helper app not initialized"])
                }
                
                if let proxy = OEThreadProxy(target: helper, thread: .current) as? OEGameCoreHelper {
                    gameCoreHelper = proxy
                } else {
                    throw NSError(domain: "org.openemu.OpenEmuKit.ThreadError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unable to initialize core helper proxy"])
                }

                try helper.load(withStartupInfo: startupInfo)
                DispatchQueue.main.async {
                    handler(nil)
                }
                
                let timer = Timer.scheduledTimer(withTimeInterval: 1e9, repeats: true, block: { _ in })
                dummyTimer = timer
                
                CFRunLoopRun()
                
                if let stopHandler = stopHandler {
                    DispatchQueue.main.async(execute: stopHandler)
                }
                notifyGameCoreDidTerminate()
            } catch {
                DispatchQueue.main.async {
                    handler(error)
                }
            }
        }
    }

    @objc private func stopHelperThread(_ id: Any?) {
        dummyTimer?.invalidate()
        dummyTimer = nil
        
        CFRunLoopStop(CFRunLoopGetCurrent())
        
        gameCoreHelper  = nil
        helperThread    = nil
        helper          = nil
    }
}
