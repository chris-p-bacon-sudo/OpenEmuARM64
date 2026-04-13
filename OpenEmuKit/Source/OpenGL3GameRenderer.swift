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
            // Log removed for Release
        }
        
        // Complete the FBO
        glGenRenderbuffers(1, &depthStencilRB)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), depthStencilRB)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_DEPTH24_STENCIL8), GLsizei(texture.size.width), GLsizei(texture.size.height))
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_DEPTH_STENCIL_ATTACHMENT), GLenum(GL_RENDERBUFFER), depthStencilRB)
        status = glGetError()
        if status != 0 {
            // Log removed for Release
        }
        
        status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GL_FRAMEBUFFER_COMPLETE {
            // Log removed for Release
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
            glDeleteFramebuffersEXT(1, &alternateFBO)
        }
        
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        
        isDoubleBufferFBOMode = true
        // Log removed for Release
    }
    
    override func bindFBO(_ fbo: GLuint) {
        // Bind our FBO / and thus our IOSurface
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
        // Assume FBOs JUST WORK, because we checked on startExecution
        var status = glGetError()
        if status != 0 {
            // Log removed for Release
        }
        
        status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GL_FRAMEBUFFER_COMPLETE {
            // Log removed for Release
        }
    }
    
    override func presentDoubleBufferedFBO() {
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), alternateFBO)
        glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), coreVideoFBO)
        
        glBlitFramebuffer(0, 0, GLint(texture.size.width), GLint(texture.size.height),
                          0, 0, GLint(texture.size.width), GLint(texture.size.height), GLbitfield(GL_COLOR_BUFFER_BIT), GLenum(GL_NEAREST))
        
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), alternateFBO)
    }
    
    override func suspendFPSLimiting() {
        super.suspendFPSLimiting()
        
        // Wake up the rendering thread one last time.
        // After this, it'll skip checking the semaphore until resumed.
        renderingThreadCanProceed.signal()
    }
    
    override func didExecuteFrame() {
        if alternateContext != nil {
            // Wait for the rendering thread to complete this frame.
            // Most cores with rendering threads don't seem to handle timing themselves - they're probably relying on Vsync.
            if isFPSLimiting.load(ordering: .sequentiallyConsistent) != 0 {
                executeThreadCanProceed.wait()
            }
            
            // Don't do any other work.
            return
        }
        
        // Update the IOSurface.
        glFlushRenderAPPLE()
    }
}
