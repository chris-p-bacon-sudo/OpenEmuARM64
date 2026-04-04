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
import Metal
import MetalKit
@_implementationOnly import os.log

// swiftlint:disable type_body_length
public final class FilterChain {
    enum InitError: Error {
        case invalidSamplerState
    }
    
    private let device: MTLDevice
    private let library: MTLLibrary
    private let loader: MTKTextureLoader
    
    private var vertex = [
        Vertex(position: simd_float4(x: 0, y: 1, z: 0, w: 1), texCoord: simd_float2(x: 0, y: 1)),
        Vertex(position: simd_float4(x: 1, y: 1, z: 0, w: 1), texCoord: simd_float2(x: 1, y: 1)),
        Vertex(position: simd_float4(x: 0, y: 0, z: 0, w: 1), texCoord: simd_float2(x: 0, y: 0)),
        Vertex(position: simd_float4(x: 1, y: 0, z: 0, w: 1), texCoord: simd_float2(x: 1, y: 0)),
    ]
    private var vertexFlipped = [
        Vertex(position: simd_float4(x: 0, y: 1, z: 0, w: 1), texCoord: simd_float2(x: 0, y: 0)),
        Vertex(position: simd_float4(x: 0, y: 0, z: 0, w: 1), texCoord: simd_float2(x: 0, y: 1)),
        Vertex(position: simd_float4(x: 1, y: 1, z: 0, w: 1), texCoord: simd_float2(x: 1, y: 0)),
        Vertex(position: simd_float4(x: 1, y: 0, z: 0, w: 1), texCoord: simd_float2(x: 1, y: 1)),
    ]
    let vertexSizeBytes: Int
    
    private var samplers: SamplerFilterArray<MTLSamplerState>
    
    public var hasShader: Bool = false
    
    // These are updated from the UI/XPC thread and read from the render thread.
    // Safe for single-word Floats on Apple Silicon (atomic reads/writes),
    // but worth noting if porting to non-TSO architectures.
    public var globalGamma: Float = 1.0
    public var globalSaturation: Float = 1.0
    
    
    private var frameCount: UInt = 0
    private var passCount: Int = 0
    private var lastPassIndex: Int = 0
    private var historyCount: Int = 0
    
    // The OriginalHistory(N) semantic
    private var historyTextures = [Texture](repeating: .init(), count: Constants.maxFrameHistory + 1)
    
    private struct OutputFrame {
        var viewport: MTLViewport
        var outputSize: TextureSize
        
        init() {
            viewport = .init()
            outputSize = .init()
        }
    }

    private var outputFrame: OutputFrame = .init()
    
    private struct Pass {
        var format = MTLPixelFormat.bgra8Unorm
        var buffers = [MTLBuffer?](repeating: nil, count: Constants.maxConstantBuffers)
        var vBuffers = [MTLBuffer?](repeating: nil, count: Constants.maxConstantBuffers) // array used for vertex binding
        var fBuffers = [MTLBuffer?](repeating: nil, count: Constants.maxConstantBuffers) // array used for fragment binding
        var renderTarget = Texture()
        var feedbackTarget = Texture()
        var frameCount = UInt32(0)
        var frameCountMod = UInt32(0)
        var frameDirection = Int32(0)
        var bindings: ShaderPassBindings?
        var viewport = MTLViewport()
        var state: MTLRenderPipelineState?
        var hasFeedback = false
        var scaleX: ShaderPassScale?
        var scaleY: ShaderPassScale?
        var isScaled: Bool { scaleX != nil && scaleY != nil }
        
        func getOutputSize(viewport: CGSize, source: CGSize) -> CGSize {
            let width: CGFloat
            switch scaleX {
            case .source(let scale):
                width = source.width * scale
            case .absolute(let size):
                width = Double(size)
            case .viewport(let scale):
                width = viewport.width * scale
            default:
                width = source.width
            }
            
            let height: CGFloat
            switch scaleY {
            case .source(let scale):
                height = source.height * scale
            case .absolute(let size):
                height = Double(size)
            case .viewport(let scale):
                height = viewport.height * scale
            default:
                height = source.height
            }
            
            return CGSize(width: width.rounded(), height: height.rounded())
        }
    }
    
    private var pass = [Pass](repeating: .init(), count: Constants.maxShaderPasses)
    private var luts = [Texture](repeating: .init(), count: Constants.maxTextures)
    
    private var renderTargetsNeedResize = true
    private var historyNeedsInit = false
    
    public private(set) var sourceRect = CGRect.zero
    
    private var aspectSize = CGSize.zero
    
    public private(set) var outputBounds = CGRect.zero
    
    public var frameDirection: Int = 1
    
    // render target layer state
    private let pipelineState: MTLRenderPipelineState
    
    private var _rotation: Float = 0
    
    private var uniforms = Uniforms.empty
    private var uniformsNoRotate = Uniforms.empty
    
    /// Used as a fallback image when a look-up texture cannot be loaded.
    private lazy var checkers: MTLTexture = {
        // swiftlint:disable identifier_name force_try
        let T0 = UInt32(0xff000000)
        let T1 = UInt32(0xffffffff)
        var checkerboard = [
            T0, T1, T0, T1, T0, T1, T0, T1,
            T1, T0, T1, T0, T1, T0, T1, T0,
            T0, T1, T0, T1, T0, T1, T0, T1,
            T1, T0, T1, T0, T1, T0, T1, T0,
            T0, T1, T0, T1, T0, T1, T0, T1,
            T1, T0, T1, T0, T1, T0, T1, T0,
            T0, T1, T0, T1, T0, T1, T0, T1,
            T1, T0, T1, T0, T1, T0, T1, T0,
        ]
        
        let ctx = CGContext(data: &checkerboard,
                            width: 8,
                            height: 8,
                            bitsPerComponent: 8,
                            bytesPerRow: 32,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
        let img = ctx.makeImage()!
        return try! loader.newTexture(cgImage: img)
    }()
    
#if os(macOS)
    // device behaviour
    private let deviceHasUnifiedMemory: Bool
#endif
    
    // parameters state
    private var parameters = [Float](repeating: 0, count: Constants.maxParameters)
    private var parametersCount = 0
    private var parametersMap = [String: Int]()
    
    public init(device: MTLDevice) throws {
        self.device = device
#if os(macOS)
        if #available(macOS 10.15, iOS 11, *) {
            deviceHasUnifiedMemory = device.hasUnifiedMemory
        } else {
            deviceHasUnifiedMemory = false
        }
#endif
        
        library = try device.makeDefaultLibrary(bundle: Bundle(for: Self.self))
        loader = .init(device: device)
        pipelineState = try Self.makePipelineState(device, library)
        samplers = try Self.makeSamplers(device)
        vertexSizeBytes = MemoryLayout<Vertex>.stride * vertex.count
        
        rotation = 0
        setDefaultFilteringLinear(false)
    }
    
    // MARK: - Static helpers
    
    private static func makePipelineState(_ device: MTLDevice, _ library: MTLLibrary) throws -> MTLRenderPipelineState {
        let vd = MTLVertexDescriptor()
        if let attr = vd.attributes[VertexAttribute.position.rawValue] {
            attr.offset = MemoryLayout<Vertex>.offset(of: \.position)!
            attr.format = .float4
            attr.bufferIndex = BufferIndex.positions.rawValue
        }
        if let attr = vd.attributes[VertexAttribute.texCoord.rawValue] {
            attr.offset = MemoryLayout<Vertex>.offset(of: \.texCoord)!
            attr.format = .float2
            attr.bufferIndex = BufferIndex.positions.rawValue
        }
        if let l = vd.layouts[BufferIndex.positions.rawValue] {
            l.stride = MemoryLayout<Vertex>.stride
        }
        
        let psd = MTLRenderPipelineDescriptor()
        psd.label = "Pipeline+No Alpha"
        
        if let ca = psd.colorAttachments[0] {
            ca.pixelFormat = .bgra8Unorm // NOTE(sgc): Required layer format (could be taken from layer.pixelFormat)
            ca.isBlendingEnabled = false
            ca.sourceAlphaBlendFactor = .sourceAlpha
            ca.sourceRGBBlendFactor = .sourceAlpha
            ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
        }
        
        psd.vertexDescriptor = vd
        psd.vertexFunction = library.makeFunction(name: "basic_vertex_proj_tex")
        psd.fragmentFunction = library.makeFunction(name: "basic_fragment_proj_tex")
        
        return try device.makeRenderPipelineState(descriptor: psd)
    }
    
    private static func makeSamplers(_ device: MTLDevice) throws -> SamplerFilterArray<MTLSamplerState> {
        var samplers = [[MTLSamplerState?]](repeating: [MTLSamplerState?](repeating: nil,
                                                                          count: ShaderPassWrap.allCases.count),
                                            count: ShaderPassFilter.allCases.count)
        let sd = MTLSamplerDescriptor()
        for i in ShaderPassWrap.allCases {
            var label = ""
            switch i {
            case .border:
                if #available(macOS 10.15, iOS 11, *) {
                    if device.supportsFamily(.apple1) {
                        label = "clamp_to_zero"
                        sd.sAddressMode = .clampToZero
                        break
                    }
                }
                if #available(macOS 10.12, iOS 14, *) {
                    label = "clamp_to_border"
                    sd.sAddressMode = .clampToBorderColor
                } else {
                    label = "clamp_to_zero"
                    sd.sAddressMode = .clampToZero
                }
                
            case .edge:
                label = "clamp_to_edge"
                sd.sAddressMode = .clampToEdge
                
            case .repeat:
                label = "repeat"
                sd.sAddressMode = .repeat
                
            case .mirroredRepeat:
                label = "mirrored_repeat"
                sd.sAddressMode = .mirrorRepeat
            }
            
            sd.tAddressMode = sd.sAddressMode
            sd.rAddressMode = sd.sAddressMode
            sd.minFilter = .linear
            sd.magFilter = .linear
            sd.label = "\(label) (linear)"
            if let ss = device.makeSamplerState(descriptor: sd) {
                samplers[.linear][i] = ss
            } else {
                throw InitError.invalidSamplerState
            }
            
            sd.minFilter = .nearest
            sd.magFilter = .nearest
            sd.label = label
            if let ss = device.makeSamplerState(descriptor: sd) {
                samplers[.nearest][i] = ss
            } else {
                throw InitError.invalidSamplerState
            }
        }
        
        // swiftlint:disable:next force_cast
        return samplers.map { $0.compactMap { $0 } } as! SamplerFilterArray<MTLSamplerState>
    }
    
    public var rotation: Float {
        get { _rotation }
        set {
            _rotation = newValue * 270
            
            uniformsNoRotate.projectionMatrix = .makeOrtho(left: 0, right: 1, top: 0, bottom: 1)
            
            let rot = simd_float4x4.makeRotated(z: (Float.pi * newValue) / 180.0)
            uniforms.projectionMatrix = rot * uniformsNoRotate.projectionMatrix
        }
    }
    
    /// Sets the default filtering mode when a shader pass leaves the value unspecified.
    ///
    /// - parameters:
    ///     - linear: `true` to use linear filtering
    public func setDefaultFilteringLinear(_ linear: Bool) {
        if linear {
            samplers[.unspecified] = samplers[.linear]
        } else {
            samplers[.unspecified] = samplers[.nearest]
        }
    }
    
    private func updateHistory() {
        guard historyCount > 0 else { return }
        
        if historyNeedsInit {
            initHistory()
        } else {
            // shift history and move last texture into first position
            let tmp = historyTextures[historyCount]
            for k in (1...historyCount).reversed() {
                historyTextures[k] = historyTextures[k - 1]
            }
            historyTextures[0] = tmp
        }
    }
    
    /*
     * Take the raw visible game rect and turn it into a smaller rect
     * which is centered inside 'bounds' and has aspect ratio 'aspectSize'.
     * Currently we try to fill the window, but maybe someday we'll support fixed zooms.
     */
    private static func fitAspectRectIntoRect(aspectSize: CGSize, size: CGSize) -> CGRect {
        let wantAspect = aspectSize.width / aspectSize.height
        let viewAspect = size.width / size.height
        
        var minFactor: CGFloat
        var outRectSize: CGSize
        
        if viewAspect >= wantAspect {
            // Raw image is too wide (normal case), squish inwards
            minFactor = wantAspect / viewAspect
            outRectSize = .init(width: size.width * minFactor, height: size.height)
        } else {
            // Raw image is too tall, squish upwards
            minFactor = viewAspect / wantAspect
            outRectSize = .init(width: size.width, height: size.height * minFactor)
        }
        
        let outRect = CGRect(origin: .init(x: (size.width - outRectSize.width) / 2,
                                           y: (size.height - outRectSize.height) / 2),
                             size: outRectSize)
        
        // This is going into a Nearest Neighbor, so the edges should be on pixels!
        return outRect.integral
    }
    
    private func resize() {
        let bounds = Self.fitAspectRectIntoRect(aspectSize: aspectSize, size: drawableSize)
        if outputBounds == bounds {
            return
        }
        
        outputBounds = bounds
        let size = outputBounds.size
        
        outputFrame.viewport = MTLViewport(originX: outputBounds.origin.x,
                                           originY: outputBounds.origin.y,
                                           width: size.width,
                                           height: size.height,
                                           znear: 0,
                                           zfar: 1)
        outputFrame.outputSize = .init(width: size.width, height: size.height)
        
        if hasShader {
            renderTargetsNeedResize = true
        }
    }
    
    public func setSourceRect(_ rect: CGRect, aspect: CGSize) {
        if sourceRect == rect, aspectSize == aspect {
            return
        }
        
        sourceRect = rect
        aspectSize = aspect
        resize()
    }
    
    public var drawableSize: CGSize = .zero {
        didSet {
            resize()
        }
    }
    
    /// A list of textures to be cleared before rendering begins.
    var _clearTextures = [MTLTexture]()
    
    private func clearTexturesWithCommandBuffer(_ commandBuffer: MTLCommandBuffer) {
        guard !_clearTextures.isEmpty else { return }
        
        defer { _clearTextures.removeAll(keepingCapacity: true) }
        
        guard #available(macOS 10.15, *) else { return }
        
        // Find the size of the largest texture, in order to allocate a buffer with at least enough space for all textures.
        var sizeMax = 0
        for t in _clearTextures {
            let bytesPerPixel = t.pixelFormat.bytesPerPixel
            precondition(bytesPerPixel > 0, "Unable to determine bytes per pixel for pixel format \(t.pixelFormat)")
            
            let bytesPerRow = t.width * bytesPerPixel
            let bytesPerImage = t.height * bytesPerRow
            if bytesPerImage > sizeMax {
                sizeMax = bytesPerImage
            }
        }
        
        // Allocate a buffer over the entire heap and fill it with zeros
        if let bce = commandBuffer.makeBlitCommandEncoder(),
           let buf = device.makeBuffer(length: sizeMax, options: [.storageModePrivate])
        {
            bce.fill(buffer: buf, range: 0..<sizeMax, value: 0)
            
            // Use the cleared buffer to clear the destination texture.
            for t in _clearTextures {
                let bytesPerPixel = t.pixelFormat.bytesPerPixel
                let bytesPerRow = t.width * bytesPerPixel
                let bytesPerImage = t.height * bytesPerRow
                let sourceSize = MTLSize(width: t.width, height: t.height, depth: 1)
                bce.copy(from: buf, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: bytesPerImage, sourceSize: sourceSize,
                         to: t, destinationSlice: 0, destinationLevel: 0, destinationOrigin: .init())
            }
            bce.endEncoding()
        }
    }
    
    private func fetchNextHistoryTexture() -> MTLTexture {
        // either no history, or we moved a texture of a different size in the front slot.
        if historyTextures[0].view == nil || 
           historyTextures[0].size.x != Float(sourceRect.width) || 
           historyTextures[0].size.y != Float(sourceRect.height)
        {
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                               width: Int(sourceRect.width),
                                                               height: Int(sourceRect.height),
                                                               mipmapped: false)
            td.storageMode = .private
            td.usage = [.shaderRead, .shaderWrite, .renderTarget]
            initTexture(&historyTextures[0], withDescriptor: td)
        }
        
        return historyTextures[0].view!
    }
    
    private func prepareNextFrame(sourceTexture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        frameCount += 1
        
        resizeRenderTargets()
        updateHistory()
        clearTexturesWithCommandBuffer(commandBuffer)
        
        let needsAdjustments = globalGamma != 1.0 || globalSaturation != 1.0
        
        if historyCount == 0 && !needsAdjustments {
            // No need to copy or adjust, set the sourceTexture to Original / OriginalHistory0 semantic
            initTexture(&historyTextures[0], withTexture: sourceTexture)
        } else {
            let texture = fetchNextHistoryTexture()
            
            let orig = MTLOrigin(x: Int(sourceRect.origin.x), y: Int(sourceRect.origin.y), z: 0)
            let size = MTLSize(width: Int(sourceRect.width), height: Int(sourceRect.height), depth: 1)
            let zero = MTLOrigin()
            
            if needsAdjustments {
                // Apply Gamma/Saturation during the initial copy into historyTextures[0]
                // This ensures all subsequent shader passes see the adjusted colors.
                let rpd = MTLRenderPassDescriptor()
                rpd.colorAttachments[0].texture = texture
                rpd.colorAttachments[0].loadAction = .dontCare
                rpd.colorAttachments[0].storeAction = .store
                
                if let rce = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {
                    // ── Calculate UVs to match sourceRect ─────────────────
                    let tw = Float(sourceTexture.width)
                    let th = Float(sourceTexture.height)
                    let u0 = Float(sourceRect.origin.x) / tw
                    let v0 = Float(sourceRect.origin.y) / th
                    let u1 = Float(sourceRect.origin.x + sourceRect.size.width) / tw
                    let v1 = Float(sourceRect.origin.y + sourceRect.size.height) / th
                    
                    let prepVertex = [
                        Vertex(position: .init(0, 1, 0, 1), texCoord: .init(u0, v1)),
                        Vertex(position: .init(1, 1, 0, 1), texCoord: .init(u1, v1)),
                        Vertex(position: .init(0, 0, 0, 1), texCoord: .init(u0, v0)),
                        Vertex(position: .init(1, 0, 0, 1), texCoord: .init(u1, v0)),
                    ]
                    
                    var prepUniforms = Uniforms.empty
                    prepUniforms.projectionMatrix = .makeOrtho(left: 0, right: 1, top: 0, bottom: 1)
                    prepUniforms.gamma = globalGamma
                    prepUniforms.saturation = globalSaturation
                    prepUniforms.outputSize = .init(Float(texture.width), Float(texture.height))
                    
                    rce.setVertexBytes(&prepUniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
                    rce.setFragmentBytes(&prepUniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
                    rce.setVertexBytes(prepVertex, length: MemoryLayout<Vertex>.stride * 4, index: BufferIndex.positions.rawValue)
                    rce.setRenderPipelineState(pipelineState)
                    rce.setFragmentSamplerState(samplers[.nearest][.edge], index: SamplerIndex.draw.rawValue)
                    rce.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(texture.width), height: Double(texture.height), znear: 0, zfar: 1))
                    rce.setFragmentTexture(sourceTexture, index: TextureIndex.color.rawValue)
                    rce.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    rce.endEncoding()
                }
            } else {
                if let bce = commandBuffer.makeBlitCommandEncoder() {
                    bce.copy(from: sourceTexture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: orig, sourceSize: size,
                             to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: zero)
                    bce.endEncoding()
                }
            }
        }
    }
    
    private func initTexture(_ t: inout Texture, withDescriptor td: MTLTextureDescriptor) {
        t.view = device.makeTexture(descriptor: td)
        t.size = .init(width: td.width, height: td.height)
    }
    
    private func initTexture(_ t: inout Texture, withTexture tex: MTLTexture) {
        t.view = tex
        t.size = .init(width: tex.width, height: tex.height)
    }
    
    private func initHistory() {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                          width: Int(sourceRect.width),
                                                          height: Int(sourceRect.height),
                                                          mipmapped: false)
        td.storageMode = .private
        td.usage = [.shaderRead, .shaderWrite, .renderTarget]
        
        for i in 0...historyCount {
            initTexture(&historyTextures[i], withDescriptor: td)
            _clearTextures.append(historyTextures[i].view!)
        }
        historyNeedsInit = false
    }
    
    private func renderTexture(_ texture: MTLTexture, renderCommandEncoder rce: MTLRenderCommandEncoder) {
        // Set gamma/saturation to 1.0 because they are already applied during the initial copy 
        // in prepareNextFrame (pre-pass). Applying them here again would cause double-rendering.
        uniforms.gamma = 1.0
        uniforms.saturation = 1.0
        rce.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        rce.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        rce.setRenderPipelineState(pipelineState)
        rce.setFragmentSamplerState(samplers[.nearest][.edge], index: SamplerIndex.draw.rawValue)
        rce.setViewport(outputFrame.viewport)
        rce.setFragmentTexture(texture, index: TextureIndex.color.rawValue)
        rce.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    
    public func render(sourceTexture: MTLTexture,
                       commandBuffer: MTLCommandBuffer,
                       renderPassDescriptor rpd: MTLRenderPassDescriptor,
                       flipVertically: Bool = false)
    {
        renderOffscreenPasses(sourceTexture: sourceTexture, commandBuffer: commandBuffer)
        if let rce = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {
            renderFinalPass(withCommandEncoder: rce, flipVertically: flipVertically)
            rce.endEncoding()
        }
    }
    
    public func renderOffscreenPasses(sourceTexture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        prepareNextFrame(sourceTexture: sourceTexture, commandBuffer: commandBuffer)
        updateBuffersForPasses()
        
        guard hasShader, passCount > 0 else { return }
        
        // swap feedback render targets
        for i in 0..<passCount where pass[i].hasFeedback {
            (pass[i].renderTarget, pass[i].feedbackTarget) = (pass[i].feedbackTarget, pass[i].renderTarget)
        }
        
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].loadAction = .dontCare
        rpd.colorAttachments[0].storeAction = .store
        let lassPassIsDirect = pass[lastPassIndex].renderTarget.view == nil
        let count = lassPassIsDirect ? passCount - 1 : passCount
        
        for i in 0..<count {
            rpd.colorAttachments[0].texture = pass[i].renderTarget.view
            guard let rce = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { continue }
            rce.setVertexBytes(&vertex, length: vertexSizeBytes, index: BufferIndex.positions.rawValue)
            rce.setViewport(pass[i].viewport)
            renderPassIndex(i, renderCommandEncoder: rce)
            rce.endEncoding()
        }
    }
    
    private func updateBuffersForPasses() {
        for i in 0..<passCount {
            pass[i].frameDirection = Int32(frameDirection)
            pass[i].frameCount = UInt32(frameCount)
            if pass[i].frameCountMod != 0 {
                pass[i].frameCount %= pass[i].frameCountMod
            }
            
            for j in 0..<Constants.maxConstantBuffers {
                let sem = pass[i].bindings!.buffers[j]
                
                guard
                    sem.bindingVert != nil || sem.bindingFrag != nil,
                    !sem.uniforms.isEmpty
                else { continue }
                
                if let buffer = pass[i].buffers[j] {
                    let data = buffer.contents()
                    for uniform in sem.uniforms {
                        data.advanced(by: uniform.offset).copyMemory(from: uniform.data, byteCount: uniform.size)
                    }
#if os(macOS)
                    if !deviceHasUnifiedMemory {
                        buffer.didModifyRange(0..<buffer.length)
                    }
#endif
                }
            }
        }
    }
    
    // these fields are used as temporary storage when rendering each pass
    private var _renderTextures: [MTLTexture?] = .init(repeating: nil, count: Constants.maxShaderBindings)
    private var _renderSamplers: [MTLSamplerState?] = .init(repeating: nil, count: Constants.maxShaderBindings)
    private var _renderbOffsets: [Int] = .init(repeating: 0, count: Constants.maxConstantBuffers)
    
    private func renderPassIndex(_ i: Int, renderCommandEncoder rce: MTLRenderCommandEncoder) {
        defer {
            // clear references from temporary buffers
            for i in 0..<Constants.maxShaderBindings {
                _renderTextures[i] = nil
                _renderSamplers[i] = nil
            }
        }
        
        for bind in pass[i].bindings!.textures {
            let binding = Int(bind.binding)
            _renderTextures[binding] = bind.texture.load(as: MTLTexture?.self)
            _renderSamplers[binding] = samplers[bind.filter][bind.wrap]
        }
        
        // enqueue commands
        rce.setRenderPipelineState(pass[i].state!)
        rce.label = pass[i].state!.label
        
        rce.setVertexBuffers(pass[i].vBuffers, offsets: _renderbOffsets, range: 0..<Constants.maxConstantBuffers)
        rce.setFragmentBuffers(pass[i].fBuffers, offsets: _renderbOffsets, range: 0..<Constants.maxConstantBuffers)
        rce.setFragmentTextures(_renderTextures, range: 0..<Constants.maxShaderBindings)
        rce.setFragmentSamplerStates(_renderSamplers, range: 0..<Constants.maxShaderBindings)
        rce.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    
    public func renderFinalPass(withCommandEncoder rce: MTLRenderCommandEncoder, flipVertically: Bool) {
        rce.setViewport(outputFrame.viewport)
        if flipVertically {
            rce.setVertexBytes(&vertexFlipped, length: vertexSizeBytes, index: BufferIndex.positions.rawValue)
        } else {
            rce.setVertexBytes(&vertex, length: vertexSizeBytes, index: BufferIndex.positions.rawValue)
        }
        
        if !hasShader || passCount == 0 {
            guard let texture = historyTextures[0].view else { return }
            return renderTexture(texture, renderCommandEncoder: rce)
        }
        
        if let view = pass[lastPassIndex].renderTarget.view {
            return renderTexture(view, renderCommandEncoder: rce)
        } else {
            // last pass renders directly to the final render target
            return renderPassIndex(lastPassIndex, renderCommandEncoder: rce)
        }
    }
    
    private func resizeRenderTargets() {
        guard renderTargetsNeedResize else { return }
        
        // current source size
        var sourceSize = sourceRect.size
        
        let viewportSize = CGSize(width: outputFrame.viewport.width, height: outputFrame.viewport.height)
        
        for i in 0..<passCount {
            let pass = pass[i]
            
            let passSize: CGSize
            if !pass.isScaled {
                passSize = i == lastPassIndex ? viewportSize : sourceSize
            } else {
                passSize = pass.getOutputSize(viewport: viewportSize, source: sourceSize)
            }
            
            sourceSize = passSize // capture source size for next pass
            
            
            
            let fmt = self.pass[i].format
            let needsAdjustments = globalGamma != 1.0 || globalSaturation != 1.0
            if !needsAdjustments && i == lastPassIndex && passSize == viewportSize && fmt == .bgra8Unorm {
                // last pass can render directly to the output render target
                self.pass[i].renderTarget.size = .init(width: passSize.width, height: passSize.height)
            } else {
                let (width, height) = (Int(passSize.width), Int(passSize.height))
                
                self.pass[i].viewport = .init(originX: 0, originY: 0,
                                              width: Double(width), height: Double(height),
                                              znear: 0, zfar: 1)
                
                if let tex = self.pass[i].renderTarget.view,
                    tex.width == width,
                   tex.height == height,
                   tex.width != 0, tex.height != 0
                {
                    let size = TextureSize(width: width, height: height)
                    self.pass[i].renderTarget.size = size
                    if self.pass[i].hasFeedback {
                        self.pass[i].feedbackTarget.size = size
                    }
                    continue
                }
                let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
                td.storageMode = .private
                td.usage = [.shaderRead, .renderTarget]
                initTexture(&self.pass[i].renderTarget, withDescriptor: td)
                // textures should be cleared before first use
                _clearTextures.append(self.pass[i].renderTarget.view!)
                
                let label = String(format: "Pass %02d Output", i)
                self.pass[i].renderTarget.view?.label = label
                if self.pass[i].hasFeedback {
                    initTexture(&self.pass[i].feedbackTarget, withDescriptor: td)
                    self.pass[i].feedbackTarget.view?.label = label
                    _clearTextures.append(self.pass[i].feedbackTarget.view!)
                }
            }
        }
        
        renderTargetsNeedResize = false
    }
    
    private func freeShaderResources() {
        pass = .init(repeating: .init(), count: Constants.maxShaderPasses)
        luts = .init(repeating: .init(), count: Constants.maxTextures)
        historyTextures = .init(repeating: .init(), count: Constants.maxFrameHistory + 1)
        
        parameters = .init(repeating: 0, count: Constants.maxParameters)
        parametersMap = [:]
        parametersCount = 0
        
        historyCount = 0
        passCount = 0
        lastPassIndex = 0
        hasShader = false
    }
    
    public func setCompiledShader(_ container: CompiledShaderContainer) throws {
        freeShaderResources()
        
        let start = CACurrentMediaTime()
        
        let ss = container.shader
        
        passCount = ss.passes.count
        lastPassIndex = passCount - 1
        
        parametersCount = ss.parameters.count
        parametersMap = .init(uniqueKeysWithValues: ss.parameters.enumerated().map { index, param in (param.name, index) })
        parameters = .init(ss.parameters.map { ($0.initial as NSDecimalNumber).floatValue })
        
        let texStride = MemoryLayout<Texture>.stride
        let texViewOffset = MemoryLayout<Texture>.offset(of: \.view)!
        let texSizeOffset = MemoryLayout<Texture>.offset(of: \.size)!
        
        for passNumber in 0..<passCount {
            let sem = ShaderPassSemantics()
            
            withUnsafePointer(to: &historyTextures[0]) {
                let p = UnsafeRawPointer($0)
                sem.addTexture(p.advanced(by: texViewOffset),
                               size: p.advanced(by: texSizeOffset),
                               semantic: .original)
                
                sem.addTexture(p.advanced(by: texViewOffset), stride: texStride,
                               size: p.advanced(by: texSizeOffset), stride: texStride,
                               semantic: .originalHistory)
                
                if passNumber == 0 {
                    // The source texture for first pass is the original input texture
                    sem.addTexture(p.advanced(by: texViewOffset),
                                   size: p.advanced(by: texSizeOffset),
                                   semantic: .source)
                }
            }
            
            if passNumber > 0 {
                // The source texture for passes 1..<n is the output of the previous pass
                withUnsafePointer(to: &pass[passNumber - 1].renderTarget) {
                    let p = UnsafeRawPointer($0)
                    sem.addTexture(p.advanced(by: texViewOffset),
                                   size: p.advanced(by: texSizeOffset),
                                   semantic: .source)
                }
            }
            
            withUnsafePointer(to: &pass[0]) {
                let p = UnsafeRawPointer($0)
                
                let rt = p.advanced(by: MemoryLayout<Pass>.offset(of: \.renderTarget)!)
                sem.addTexture(rt.advanced(by: texViewOffset), stride: MemoryLayout<Pass>.stride,
                               size: rt.advanced(by: texSizeOffset), stride: MemoryLayout<Pass>.stride,
                               semantic: .passOutput)
                
                let ft = p.advanced(by: MemoryLayout<Pass>.offset(of: \.feedbackTarget)!)
                sem.addTexture(ft.advanced(by: texViewOffset), stride: MemoryLayout<Pass>.stride,
                               size: ft.advanced(by: texSizeOffset), stride: MemoryLayout<Pass>.stride,
                               semantic: .passFeedback)
            }
            
            withUnsafePointer(to: &luts[0]) {
                let p = UnsafeRawPointer($0)
                sem.addTexture(p.advanced(by: texViewOffset), stride: texStride,
                               size: p.advanced(by: texSizeOffset), stride: texStride,
                               semantic: .user)
            }
            
            if passNumber == lastPassIndex {
                withUnsafePointer(to: &uniforms.projectionMatrix) {
                    sem.addUniformData(UnsafeRawPointer($0), semantic: .mvp)
                }
            } else {
                withUnsafePointer(to: &uniformsNoRotate.projectionMatrix) {
                    sem.addUniformData(UnsafeRawPointer($0), semantic: .mvp)
                }
            }
            
            withUnsafePointer(to: &pass[passNumber]) {
                let p = UnsafeRawPointer($0)
                sem.addUniformData(p.advanced(by: MemoryLayout<Pass>.offset(of: \.renderTarget.size)!), semantic: .outputSize)
                sem.addUniformData(p.advanced(by: MemoryLayout<Pass>.offset(of: \.frameCount)!), semantic: .frameCount)
                sem.addUniformData(p.advanced(by: MemoryLayout<Pass>.offset(of: \.frameDirection)!), semantic: .frameDirection)
            }
            
            withUnsafePointer(to: &outputFrame.outputSize) {
                sem.addUniformData(UnsafeRawPointer($0), semantic: .finalViewportSize)
            }
            
            for i in 0..<parametersCount {
                withUnsafePointer(to: &parameters[i]) {
                    sem.addUniformData(UnsafeRawPointer($0), forParameterAt: i)
                }
            }
            
            let bindings = ShaderPassBindings()
            let pass = ss.passes[passNumber]
            updateBindings(passBindings: bindings,
                           forPassNumber: passNumber,
                           passSemantics: sem,
                           pass: pass)
            self.pass[passNumber].bindings = bindings
            self.pass[passNumber].format = .init(pass.format)
            self.pass[passNumber].frameCountMod = UInt32(pass.frameCountMod)
            
            // update scaling
            self.pass[passNumber].scaleX = .init(pass.scaleX)
            self.pass[passNumber].scaleY = .init(pass.scaleY)
            
            let vd = MTLVertexDescriptor()
            if let attr = vd.attributes[VertexAttribute.position.rawValue] {
                attr.offset = MemoryLayout<Vertex>.offset(of: \.position)!
                attr.format = .float4
                attr.bufferIndex = BufferIndex.positions.rawValue
            }
            if let attr = vd.attributes[VertexAttribute.texCoord.rawValue] {
                attr.offset = MemoryLayout<Vertex>.offset(of: \.texCoord)!
                attr.format = .float2
                attr.bufferIndex = BufferIndex.positions.rawValue
            }
            if let l = vd.layouts[BufferIndex.positions.rawValue] {
                l.stride = MemoryLayout<Vertex>.stride
            }
            
            let psd = MTLRenderPipelineDescriptor()
            if let alias = pass.alias {
                psd.label = "pass \(passNumber) (\(alias))"
            } else {
                psd.label = "pass \(passNumber)"
            }
            
            if let ca = psd.colorAttachments[0] {
                ca.pixelFormat = self.pass[passNumber].format
                ca.isBlendingEnabled = false
                ca.sourceAlphaBlendFactor = .sourceAlpha
                ca.sourceRGBBlendFactor = .sourceAlpha
                ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
            }
            
            psd.sampleCount = 1
            psd.vertexDescriptor = vd
            
            let options = MTLCompileOptions()
            options.languageVersion = try MTLLanguageVersion(ss.languageVersion)
            options.fastMathEnabled = true
            do {
                let lib = try device.makeLibrary(source: pass.vertexSource, options: options)
                psd.vertexFunction = lib.makeFunction(name: "main0")
            }
            
            do {
                let lib = try device.makeLibrary(source: pass.fragmentSource, options: options)
                psd.fragmentFunction = lib.makeFunction(name: "main0")
            }
            
            self.pass[passNumber].state = try device.makeRenderPipelineState(descriptor: psd)
            
            for j in 0..<Constants.maxConstantBuffers {
                let sem = self.pass[passNumber].bindings!.buffers[j]
                
                let size = sem.size
                guard size > 0 else { continue }
#if os(macOS)
                let opts: MTLResourceOptions = deviceHasUnifiedMemory ? .storageModeShared : .storageModeManaged
#else
                let opts: MTLResourceOptions = .storageModeShared
#endif
                let buf = device.makeBuffer(length: size, options: opts)
                self.pass[passNumber].buffers[j] = buf
                
                if let binding = sem.bindingVert {
                    self.pass[passNumber].vBuffers[binding] = buf
                }
                if let binding = sem.bindingFrag {
                    self.pass[passNumber].fBuffers[binding] = buf
                }
            }
        }
        
        // finalise remaining state
        historyCount = ss.historyCount
        for pass in ss.passes {
            self.pass[pass.index].hasFeedback = pass.isFeedback
        }
        
        let end = CACurrentMediaTime() - start
        
        loadLuts(container)
        hasShader = true
        renderTargetsNeedResize = true
        historyNeedsInit = true
    }
    
    private func loadLuts(_ cc: CompiledShaderContainer) {
        let opts: [MTKTextureLoader.Option: Any] = [
            .generateMipmaps: true,
            .allocateMipmaps: true,
            .SRGB: false,
            .textureStorageMode: MTLStorageMode.private.rawValue,
        ]
        
        let images = cc.shader.luts
        
        var i = 0
        for lut in images {
            let t: MTLTexture
            do {
                let data = try cc.getLUTByName(lut.name)
                if let cgImg = CGContext.makeForTexture(data: data)?.makeImage() {
                    t = try loader.newTexture(cgImage: cgImg, options: opts)
                } else {
                    t = checkers
                }
            } catch {
                t = checkers
            }
            initTexture(&luts[i], withTexture: t)
            i += 1
        }
    }
    
    func updateBindings(passBindings: ShaderPassBindings, forPassNumber passNumber: Int, passSemantics: ShaderPassSemantics, pass: Compiled.ShaderPass) {
        func addUniforms(bufferIndex: Int) {
            let desc = pass.buffers[bufferIndex]
            guard desc.size > 0 else { return }

            let bind = passBindings.buffers[bufferIndex]
            bind.bindingVert = desc.bindingVert
            bind.bindingFrag = desc.bindingFrag
            bind.size = (desc.size + 0xf) & ~0xf // round up to nearest 16 bytes
            
            for u in desc.uniforms {
                switch u.semantic {
                case .floatParameter:
                    guard let param = passSemantics.parameter(at: u.index!)
                    else { fatalError("Unable to find parameter at index \(u.index!)") }
                    bind.addUniformData(param.data,
                                        size: u.size,
                                        offset: u.offset,
                                        name: u.name)
                    
                case .mvp, .outputSize, .finalViewportSize, .frameCount, .frameDirection:
                    bind.addUniformData(passSemantics.uniforms[u.semantic]!.data,
                                        size: u.size,
                                        offset: u.offset,
                                        name: u.name)

                case .originalSize, .sourceSize, .originalHistorySize, .passOutputSize, .passFeedbackSize, .userSize:
                    let tex = passSemantics.textureUniforms[u.semantic]!
                    
                    bind.addUniformData(tex.size.advanced(by: u.index! * tex.stride),
                                        size: u.size,
                                        offset: u.offset,
                                        name: u.name)
                }
            }
        }
        
        // UBO
        addUniforms(bufferIndex: 0)
        // Push
        addUniforms(bufferIndex: 1)
        
        for t in pass.textures {
            let tex = passSemantics.textures[t.semantic]!
            let bind = passBindings.addTexture(tex.texture.advanced(by: t.index * tex.stride),
                                               binding: t.binding,
                                               name: t.name)
            bind.wrap = .init(t.wrap)
            bind.filter = .init(t.filter)
        }
    }
    
    public func setValue(_ value: CGFloat, forParameterName name: String) {
        if let index = parametersMap[name] {
            parameters[index] = Float(value)
        }
    }
    
    public func setValue(_ value: CGFloat, forParameterIndex index: Int) {
        if case 0..<parametersCount = index {
            parameters[index] = Float(value)
        }
    }
    
    typealias SamplerWrapArray<Element> = [Element]
    typealias SamplerFilterArray<Element> = [SamplerWrapArray<Element>]
}

extension FilterChain.SamplerWrapArray {
    subscript(x: ShaderPassWrap) -> Element {
        get { self[x.rawValue] }
        set { self[x.rawValue] = newValue }
    }
}

extension FilterChain.SamplerFilterArray {
    subscript(x: ShaderPassFilter) -> Element {
        get { self[x.rawValue] }
        set { self[x.rawValue] = newValue }
    }
}

// MARK: - Types shared between Metal shaders and Swift

extension FilterChain {
    enum BufferIndex: Int {
        case uniforms = 1
        case positions = 4
    }
    
    enum VertexAttribute: Int {
        case position = 0
        case texCoord = 1
    }
    
    enum TextureIndex: Int {
        case color = 0
    }
    
    enum SamplerIndex: Int {
        case draw = 0
    }
    
    @frozen @usableFromInline struct Vertex {
        let position: simd_float4
        let texCoord: simd_float2
    }
    
    @frozen @usableFromInline struct Uniforms {
        static let empty: Uniforms = .init(projectionMatrix: simd_float4x4(), outputSize: simd_float2(), time: 0.0, gamma: 1.0, saturation: 1.0, padding1: 0.0, padding2: simd_float2(0,0))
        
        var projectionMatrix: simd_float4x4 // 64 bytes
        var outputSize: simd_float2         // 8 bytes
        var time: Float                     // 4 bytes
        var gamma: Float                    // 4 bytes
        var saturation: Float               // 4 bytes
        var padding1: Float                 // 4 bytes, to align to 16 bytes. Total = 88 bytes. Need 8 for layout alignment
        var padding2: simd_float2           // 8 bytes. Total = 96 bytes. (Matches stride)
    }
}

private typealias TextureSize = SIMD4<Float>

extension TextureSize {
    static let zero: Self = .init(x: 0, y: 0, z: 0, w: 0)
    
    init(width w: Int, height h: Int) {
        self.init(width: CGFloat(w), height: CGFloat(h))
    }
    
    init(width w: CGFloat, height h: CGFloat) {
        let width = Float(w)
        let height = Float(h)
        self = .init(x: width, y: height, z: 1.0 / width, w: 1.0 / height)
    }
}

private struct Texture {
    var view: MTLTexture?
    var size: TextureSize = .zero
}

public enum MTLLangageVersionError: LocalizedError {
    case versionUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .versionUnavailable:
            return "The specified Metal version is unavailable for this OS or version of OpenEmuShaders"
        }
    }
}

extension MTLLanguageVersion {
    init(_ languageVersion: Compiled.LanguageVersion) throws {
        switch languageVersion {
        case .version2_4:
            if #available(macOS 12.0, iOS 15.0, *) {
                self = .version2_4
            } else {
                throw MTLLangageVersionError.versionUnavailable
            }
        case .version2_3:
            if #available(macOS 11.0, iOS 14.0, *) {
                self = .version2_3
            } else {
                throw MTLLangageVersionError.versionUnavailable
            }
        case .version2_2:
            if #available(macOS 10.15, iOS 13.0, *) {
                self = .version2_2
            } else {
                throw MTLLangageVersionError.versionUnavailable
            }
        case .version2_1:
            self = .version2_1
        }
    }
}

extension MTLPixelFormat {
    // swiftlint:disable cyclomatic_complexity
    init(_ pixelFormat: Compiled.PixelFormat) {
        switch pixelFormat {
        case .r8Unorm:
            self = .r8Unorm
        case .r8Uint:
            self = .r8Uint
        case .r8Sint:
            self = .r8Sint
        case .rg8Unorm:
            self = .rg8Unorm
        case .rg8Uint:
            self = .rg8Uint
        case .rg8Sint:
            self = .rg8Sint
        case .rgba8Unorm:
            self = .rgba8Unorm
        case .rgba8Uint:
            self = .rgba8Uint
        case .rgba8Sint:
            self = .rgba8Sint
        case .rgba8Unorm_srgb:
            self = .rgba8Unorm_srgb
        case .rgb10a2Unorm:
            self = .rgb10a2Unorm
        case .rgb10a2Uint:
            self = .rgb10a2Uint
        case .r16Uint:
            self = .r16Uint
        case .r16Sint:
            self = .r16Sint
        case .r16Float:
            self = .r16Float
        case .rg16Uint:
            self = .rg16Uint
        case .rg16Sint:
            self = .rg16Sint
        case .rg16Float:
            self = .rg16Float
        case .rgba16Uint:
            self = .rgba16Uint
        case .rgba16Sint:
            self = .rgba16Sint
        case .rgba16Float:
            self = .rgba16Float
        case .r32Uint:
            self = .r32Uint
        case .r32Sint:
            self = .r32Sint
        case .r32Float:
            self = .r32Float
        case .rg32Uint:
            self = .rg32Uint
        case .rg32Sint:
            self = .rg32Sint
        case .rg32Float:
            self = .rg32Float
        case .rgba32Uint:
            self = .rgba32Uint
        case .rgba32Sint:
            self = .rgba32Sint
        case .rgba32Float:
            self = .rgba32Float
        case .bgra8Unorm_srgb:
            self = .bgra8Unorm_srgb
        case .bgra8Unorm:
            self = .bgra8Unorm
        }
    }
    
    /// Returns the number of bytes per pixel for the given format; otherwise, 0 if the format is not supported
    var bytesPerPixel: Int {
        switch self {
        case .a8Unorm, .r8Unorm, .r8Unorm_srgb, .r8Snorm, .r8Uint, .r8Sint:
            return 1
            
        case .r16Unorm, .r16Snorm, .r16Uint, .r16Sint, .r16Float:
            return 2
            
        case .rg8Unorm, .rg8Unorm_srgb, .rg8Snorm, .rg8Uint, .rg8Sint, .b5g6r5Unorm, .a1bgr5Unorm, .abgr4Unorm,
             .bgr5A1Unorm:
            return 2
            
        case .r32Uint, .r32Sint, .r32Float, .rg16Unorm, .rg16Snorm, .rg16Uint, .rg16Sint, .rg16Float, .rgba8Unorm,
             .rgba8Unorm_srgb, .rgba8Snorm, .rgba8Uint, .rgba8Sint, .bgra8Unorm, .bgra8Unorm_srgb, .rgb10a2Unorm,
             .rgb10a2Uint, .rg11b10Float, .rgb9e5Float, .bgr10a2Unorm, .bgr10_xr, .bgr10_xr_srgb:
            return 4
            
        case .rg32Uint, .rg32Sint, .rg32Float, .rgba16Unorm, .rgba16Snorm, .rgba16Uint, .rgba16Sint, .rgba16Float,
             .bgra10_xr, .bgra10_xr_srgb:
            return 8
            
        case .rgba32Uint, .rgba32Sint, .rgba32Float:
            return 16
            
        case .invalid:
            return 0
        default:
            return 0
        }
    }
}

extension CGContext {
    /// Returns a context using the dimensions and contents from the image identified by the data.
    /// The context data format is compatible with BGRA8
    /// - Parameter data: The data of the source image.
    /// - Returns: a new ``CGContext`` with dimensions and contents matching the source image.
    static func makeForTexture(data: Data) -> CGContext? {
        guard
            let src = CGImageSourceCreateWithData(data as CFData, nil),
            let img = CGImageSourceCreateImageAtIndex(src, CGImageSourceGetPrimaryImageIndex(src), nil)
        else { return nil }
        
        guard let context = CGContext(data: nil,
                                      width: img.width, height: img.height,
                                      bitsPerComponent: 8, bytesPerRow: img.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }
        
        context.interpolationQuality = .none
        context.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        
        return context
    }
}
