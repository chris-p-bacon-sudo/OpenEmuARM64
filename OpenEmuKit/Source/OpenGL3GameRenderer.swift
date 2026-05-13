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
import OpenEmuBase
import OpenGL.GL3
@_implementationOnly import Atomics
internal import os.log

final class OpenGL3GameRenderer: BaseOpenGLGameRenderer {
    
    override var canChangeBufferSize: Bool {
        // TODO: Test alternate threads - might need to call glViewport() again on that thread.
        // TODO: Implement for double buffered FBO - need to reallocate alternateFBO.
        alternateContext == nil && !isDoubleBufferFBOMode
    }
    
    override class var attributes: [CGLPixelFormatAttribute] { [
        kCGLPFAAccelerated,
        kCGLPFAAllowOfflineRenderers,
        kCGLPFAOpenGLProfile,
        CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
        kCGLPFADepthSize, CGLPixelFormatAttribute(24),
        CGLPixelFormatAttribute(0),
    ] }
    
    override func setupFramebuffer() {
        glGenFramebuffers(1, &coreVideoFBO)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), coreVideoFBO)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_RECTANGLE), texture.openGLTexture, 0)
        var status = glGetError()
        if status != 0 {
            os_log(.error, log: .renderer,
                   "Setup failed: create interop texture FBO 1, OpenGL error %04X",
                   status)
        }
        
        // Complete the FBO
        glGenRenderbuffers(1, &depthStencilRB)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), depthStencilRB)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_DEPTH24_STENCIL8), GLsizei(texture.size.width), GLsizei(texture.size.height))
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_DEPTH_STENCIL_ATTACHMENT), GLenum(GL_RENDERBUFFER), depthStencilRB)
        status = glGetError()
        if status != 0 {
            os_log(.error, log: .renderer,
                   "Setup failed: create ioSurface FBO 2, OpenGL error %04X",
                   status)
        }
        
        status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GL_FRAMEBUFFER_COMPLETE {
            os_log(.error, log: .renderer,
                   "Cannot create FBO, OpenGL error %04X",
                   status)
        }
    }
    
    override func setupDoubleBufferedFBO() {
        // Clear the other one while we're on this one.
        clearFramebuffer()
        
        glGenFramebuffers(1, &alternateFBO)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), alternateFBO)
        
        glGenRenderbuffers(2, &tempRB)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), tempRB[0])
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_RGB8), GLsizei(texture.size.width), GLsizei(texture.size.height))
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_RENDERBUFFER), tempRB[0])
        
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), tempRB[1])
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_DEPTH32F_STENCIL8), GLsizei(texture.size.width), GLsizei(texture.size.height))
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_DEPTH_STENCIL_ATTACHMENT), GLenum(GL_RENDERBUFFER), tempRB[1])
        
        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GL_FRAMEBUFFER_COMPLETE {
            os_log(.error, log: .renderer, "Cannot create temp FBO. OpenGL error %04X", status)
            
            glDeleteFramebuffersEXT(1, &alternateFBO)
        }
        
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        
        isDoubleBufferFBOMode = true
        
        os_log(.debug, log: .renderer, "Setup GL3 3D 'double-buffered FBO' rendering")
    }
    
    override func bindFBO(_ fbo: GLuint) {
        // Bind our FBO / and thus our IOSurface
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
        // Assume FBOs JUST WORK, because we checked on startExecution
        var status = glGetError()
        if status != 0 {
            os_log(.error, log: .renderer, "bindFBO: OpenGL error %04X", status)
        }
        
        status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GL_FRAMEBUFFER_COMPLETE {
            os_log(.error, log: .renderer, "OpenGL error %04X in draw, check FBO", status)
        }
    }
    
    override func presentDoubleBufferedFBO() {
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), alternateFBO)
        glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), coreVideoFBO)
        
        glBlitFramebuffer(0, 0, GLint(texture.size.width), GLint(texture.size.height),
                          0, 0, GLint(texture.size.width), GLint(texture.size.height), GLbitfield(GL_COLOR_BUFFER_BIT), GLenum(GL_NEAREST))
        
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), alternateFBO)
    }
    
    // MARK: - HW render shared context

    override func prepareHWRenderSharedContext() {
        guard hwSharedContext == nil else {
            os_log(.debug, log: .renderer, "prepareHWRenderSharedContext: already set up, skipping")
            return
        }

        // Create a CGL context that shares the texture namespace of glContext.
        // Textures (including the IOSurface-backed texture and the staging
        // texture we create below) are shared across both contexts. FBOs and
        // renderbuffers are NOT shared, so they live entirely on sharedCtx.
        var sharedCtx: CGLContextObj?
        let err = CGLCreateContext(glPixelFormat, glContext, &sharedCtx)
        guard err == kCGLNoError, let sharedCtx else {
            os_log(.error, log: .renderer,
                   "prepareHWRenderSharedContext: CGLCreateContext failed: %{public}s",
                   CGLErrorString(err))
            return
        }

        CGLSetCurrentContext(sharedCtx)

        let w = GLsizei(texture.size.width)
        let h = GLsizei(texture.size.height)

        // --- Staging texture --------------------------------------------------
        // Plain GL_TEXTURE_2D in ordinary GPU memory. This is what the libretro
        // core actually renders into. Issue #464 confirmed that attaching the
        // IOSurface-backed GL_TEXTURE_RECTANGLE directly as the FBO color
        // attachment produces no observable pixels even though the framebuffer
        // is COMPLETE — GLideN64's draws (and likely other GL cores' draws)
        // don't make it through that attachment path. The staging texture
        // sidesteps that entirely; we blit its contents into the IOSurface
        // texture at end-of-frame (see didExecuteFrame).
        var stagingTex: GLuint = 0
        glGenTextures(1, &stagingTex)
        glBindTexture(GLenum(GL_TEXTURE_2D), stagingTex)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S),     GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T),     GL_CLAMP_TO_EDGE)
        glTexImage2D(
            GLenum(GL_TEXTURE_2D), 0,
            GL_RGBA8,
            w, h, 0,
            GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil
        )
        if glGetError() != 0 {
            os_log(.error, log: .renderer, "prepareHWRenderSharedContext: staging texture alloc failed")
        }
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)

        // --- hwSharedFBO (returned to the libretro core) ---------------------
        // Color attachment = staging texture (2D). Depth/stencil renderbuffer.
        var fbo: GLuint = 0
        glGenFramebuffers(1, &fbo)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
        glFramebufferTexture2D(
            GLenum(GL_FRAMEBUFFER),
            GLenum(GL_COLOR_ATTACHMENT0),
            GLenum(GL_TEXTURE_2D),
            stagingTex,
            0
        )
        var status = glGetError()
        if status != 0 {
            os_log(.error, log: .renderer,
                   "prepareHWRenderSharedContext: attach staging texture, GL error %04X", status)
        }

        var depthRB: GLuint = 0
        glGenRenderbuffers(1, &depthRB)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), depthRB)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_DEPTH24_STENCIL8), w, h)
        glFramebufferRenderbuffer(
            GLenum(GL_FRAMEBUFFER),
            GLenum(GL_DEPTH_STENCIL_ATTACHMENT),
            GLenum(GL_RENDERBUFFER),
            depthRB
        )
        status = glGetError()
        if status != 0 {
            os_log(.error, log: .renderer,
                   "prepareHWRenderSharedContext: attach depth/stencil RB, GL error %04X", status)
        }

        let fbStatus = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if fbStatus != GL_FRAMEBUFFER_COMPLETE {
            os_log(.error, log: .renderer,
                   "prepareHWRenderSharedContext: hwSharedFBO incomplete, status %04X", fbStatus)
            glDeleteFramebuffers(1, &fbo)
            glDeleteRenderbuffers(1, &depthRB)
            glDeleteTextures(1, &stagingTex)
            CGLSetCurrentContext(nil)
            CGLReleaseContext(sharedCtx)
            return
        }

        // --- hwOutputFBO (blit destination, end-of-frame) --------------------
        // Color attachment = the IOSurface-backed GL_TEXTURE_RECTANGLE.
        // We blit from hwSharedFBO into here, then flush to commit IOSurface.
        var outFBO: GLuint = 0
        glGenFramebuffers(1, &outFBO)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), outFBO)
        glFramebufferTexture2D(
            GLenum(GL_FRAMEBUFFER),
            GLenum(GL_COLOR_ATTACHMENT0),
            GLenum(GL_TEXTURE_RECTANGLE),
            texture.openGLTexture,
            0
        )
        let outStatus = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if outStatus != GL_FRAMEBUFFER_COMPLETE {
            os_log(.error, log: .renderer,
                   "prepareHWRenderSharedContext: hwOutputFBO incomplete, status %04X", outStatus)
            glDeleteFramebuffers(1, &outFBO)
            glDeleteFramebuffers(1, &fbo)
            glDeleteRenderbuffers(1, &depthRB)
            glDeleteTextures(1, &stagingTex)
            CGLSetCurrentContext(nil)
            CGLReleaseContext(sharedCtx)
            return
        }

        // Leave hwSharedFBO bound — it's the FBO the translator will return
        // from libretro_get_current_framebuffer() and the core will use for
        // its first context_reset.
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)

        hwSharedContext        = sharedCtx
        hwSharedFBO            = fbo
        hwSharedStagingTexture = stagingTex
        hwSharedDepthStencilRB = depthRB
        hwOutputFBO            = outFBO

        os_log(.debug, log: .renderer,
               "prepareHWRenderSharedContext: shared ctx %p, hwSharedFBO=%u (staging tex %u, %dx%d), hwOutputFBO=%u (IOSurface tex %u)",
               sharedCtx, fbo, stagingTex, Int(w), Int(h), outFBO, texture.openGLTexture)
    }

    override func suspendFPSLimiting() {
        super.suspendFPSLimiting()
        
        // Wake up the rendering thread one last time.
        // After this, it'll skip checking the semaphore until resumed.
        renderingThreadCanProceed.signal()
    }
    
    override func didExecuteFrame() {
        if alternateContext != nil {
            // Wait for the rendering thread to complete this frame, but use a
            // short timed wait instead of DISPATCH_TIME_FOREVER.  A forever-wait
            // permanently blocks the core-loop thread whenever the emulation
            // thread is not in its VI handler — e.g. during JIT initialisation,
            // a slow interpreter loop, or any other non-VI execution path.
            // The 100 ms timeout lets us re-check isFPSLimiting on each lap so
            // that stopEmulation's suspendFPSLimiting() call drains cleanly
            // regardless of where the emulation thread is at that moment.
            while isFPSLimiting.load(ordering: .sequentiallyConsistent) != 0 {
                if executeThreadCanProceed.wait(timeout: .now() + .milliseconds(100)) == .success {
                    break
                }
                // Timed out — loop and re-check isFPSLimiting.
            }
            
            // Don't do any other work.
            return
        }
        
        if hwSharedContext != nil {
            // HW render mode: the core rendered into hwSharedFBO (which is
            // backed by hwSharedStagingTexture, a plain GL_TEXTURE_2D in GPU
            // memory). We now blit that into hwOutputFBO (which is backed by
            // the IOSurface-backed GL_TEXTURE_RECTANGLE) so the compositor
            // sees the new frame.
            //
            // Issue #464: this two-FBO + blit approach is necessary because
            // attaching an IOSurface-backed RECTANGLE texture directly as the
            // core's render target produced complete-but-blank framebuffers
            // for GLideN64. The blit costs one full-frame GPU copy per frame.
            CGLSetCurrentContext(hwSharedContext)

            if hwSharedFBO != 0 && hwOutputFBO != 0 {
                let w = GLint(texture.size.width)
                let h = GLint(texture.size.height)
                // Save current bindings so the core's next frame state is unaffected.
                var prevDraw: GLint = 0
                var prevRead: GLint = 0
                glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &prevDraw)
                glGetIntegerv(GLenum(GL_READ_FRAMEBUFFER_BINDING), &prevRead)

                glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), hwSharedFBO)
                glReadBuffer(GLenum(GL_COLOR_ATTACHMENT0))
                glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), hwOutputFBO)
                // Some drivers need an explicit color-write enable + scissor-off
                // for a clean blit.
                glColorMask(GLboolean(GL_TRUE), GLboolean(GL_TRUE), GLboolean(GL_TRUE), GLboolean(GL_TRUE))
                glDisable(GLenum(GL_SCISSOR_TEST))
                glBlitFramebuffer(
                    0, 0, w, h,
                    0, 0, w, h,
                    GLbitfield(GL_COLOR_BUFFER_BIT),
                    GLenum(GL_NEAREST)
                )

                // Restore previous bindings so context_reset / glsm_state_bind
                // state on the next frame matches what the core expects.
                glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), GLuint(prevDraw))
                glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), GLuint(prevRead))
            }
            glFinish()
            // Switch to glContext (which owns the CVOpenGLTextureCacheRef) for
            // glFlushRenderAPPLE() to commit the IOSurface texture contents.
            CGLSetCurrentContext(glContext)
            glFlushRenderAPPLE()
            return
        }

        // Update the IOSurface.
        glFlushRenderAPPLE()
    }
}
