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
import OpenEmuShaders
import OpenEmuBase
@_implementationOnly import Atomics
import os.log

final class MTL3DGameRenderer: GameRenderer {
    var surfaceSize: OEIntSize { gameCore.bufferSize }
    let gameCore: OEGameCore
    
    private let device: MTLDevice
    private let converter: MTLPixelConverter
    private var buffer: PixelBuffer!
    private var texture: MTLTexture!
    
    var renderingThreadCanProceed = DispatchSemaphore(value: 0)
    var executeThreadCanProceed = DispatchSemaphore(value: 0)
    
    var isFPSLimiting = ManagedAtomic(0)
    
    init(withDevice device: MTLDevice, gameCore: OEGameCore) throws {
        self.device      = device
        self.converter   = try .init(device: device)
        self.gameCore    = gameCore
        
        gameCore.createMetalTexture(device: device)
    }
    
    func update() {
        precondition(gameCore.gameCoreRendering == .metal2, "Metal now supports 3D rendering")

        let pixelFormat = gameCore.pixelFormat
        let pixelType   = gameCore.pixelType
        guard let pf = OEMTLPixelFormat(pixelFormat: pixelFormat, pixelType: pixelType) else {
            fatalError("Invalid pixel format")
        }

        if buffer == nil {
            let bufferSize  = gameCore.bufferSize
            let bytesPerRow = gameCore.bytesPerRow
            
            buffer = PixelBuffer.makeBuffer(withDevice: device,
                                            converter: converter,
                                            format: pf,
                                            height: Int(bufferSize.height),
                                            bytesPerRow: bytesPerRow)
        }
    }

    var canChangeBufferSize: Bool { true }
    
    func willExecuteFrame() {
        if isFPSLimiting.load(ordering: .sequentiallyConsistent) != 0 {
            renderingThreadCanProceed.signal()
        }
    }
    
    func didExecuteFrame() {
        // Wait for the rendering thread to complete this frame.
        // Most cores with rendering threads don't seem to handle timing themselves - they're probably relying on Vsync.
        if isFPSLimiting.load(ordering: .sequentiallyConsistent) != 0 {
            executeThreadCanProceed.wait()
        }
    }
    
    func resumeFPSLimiting() {
        guard isFPSLimiting.load(ordering: .sequentiallyConsistent) != 1
        else { return }
        
        isFPSLimiting.wrappingIncrement(ordering: .sequentiallyConsistent)
    }
    
    func suspendFPSLimiting() {
        guard isFPSLimiting.load(ordering: .sequentiallyConsistent) != 0
        else { return }
        
        isFPSLimiting.wrappingDecrement(ordering: .sequentiallyConsistent)
    }
    
    func prepareFrameForRender(commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        return gameCore.metalTexture
    }
    
    func willRenderFrameOnAlternateThread() {
       
    }
    
    func didRenderFrameOnAlternateThread() {
        // Update the IOSurface.
        //glFlushRenderAPPLE()
        
        // Do FPS limiting, but only once setup is over.
        if isFPSLimiting.load(ordering: .sequentiallyConsistent) != 0 {
            // Technically the above should be a glFinish(), but I'm hoping the GPU work
            // is fast enough that it's not needed.
            executeThreadCanProceed.signal()
            
            // Wait to be allowed to start next frame.
            renderingThreadCanProceed.wait()
        }
    }
}
