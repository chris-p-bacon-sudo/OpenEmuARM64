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
import OpenGL
@_implementationOnly import Atomics

final class OpenGL2GameRenderer: BaseOpenGLGameRenderer {
    
    override class var attributes: [CGLPixelFormatAttribute] { [
        kCGLPFAAccelerated,
        kCGLPFAAllowOfflineRenderers,
        kCGLPFANoRecovery,
        kCGLPFAColorSize, CGLPixelFormatAttribute(24),
        kCGLPFADepthSize, CGLPixelFormatAttribute(24),
        CGLPixelFormatAttribute(0),
    ] }
    
    override func setupFramebuffer() {
        glGenFramebuffersEXT(1, &coreVideoFBO)
        glBindFramebufferEXT(GLenum(GL_FRAMEBUFFER), coreVideoFBO)
        glFramebufferTexture2DEXT(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_RECTANGLE_ARB), texture.openGLTexture, 0)
        var status = glGetError()
        if status != 0 {
            // Log removed for Release
        }
        
        // Complete the FBO
        glGenRenderbuffersEXT(1, &depthStencilRB)
        glBindRenderbufferEXT(GLenum(GL_RENDERBUFFER_EXT), depthStencilRB)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER_EXT), GLenum(GL_DEPTH24_STENCIL8), GLsizei(texture.size.width), GLsizei(texture.size.height))
        glFramebufferRenderbufferEXT(GLenum(GL_FRAMEBUFFER_EXT), GLenum(GL_DEPTH_STENCIL_ATTACHMENT), GLenum(GL_RENDERBUFFER_EXT), depthStencilRB)
        status = glGetError()
        if status != 0 {
            // Log removed for Release
        }
        
        status = glCheckFramebufferStatusEXT(GLenum(GL_FRAMEBUFFER_EXT))
        if status != GL_FRAMEBUFFER_COMPLETE_EXT {
            // Log removed for Release
        }
    }
    
    override func setupDoubleBufferedFBO() {
        // Clear the other one while we're on this one.
        clearFramebuffer()
        
        glGenFramebuffersEXT(1, &alternateFBO)
        glBindFramebufferEXT(GLenum(GL_FRAMEBUFFER_EXT), alternateFBO)
        
        glGenRenderbuffersEXT(2, &tempRB)
        glBindRenderbufferEXT(GLenum(GL_RENDERBUFFER_EXT), tempRB[0])
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER_EXT), GLenum(GL_RGB8), GLsizei(texture.size.width), GLsizei(texture.size.height))
        glFramebufferRenderbufferEXT(GLenum(GL_FRAMEBUFFER_EXT), GLenum(GL_COLOR_ATTACHMENT0_EXT), GLenum(GL_RENDERBUFFER_EXT), tempRB[0])
        
        glBindRenderbufferEXT(GLenum(GL_RENDERBUFFER_EXT), tempRB[1])
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER_EXT), GLenum(GL_DEPTH32F_STENCIL8), GLsizei(texture.size.width), GLsizei(texture.size.height))
        glFramebufferRenderbufferEXT(GLenum(GL_FRAMEBUFFER_EXT), GLenum(GL_DEPTH_STENCIL_ATTACHMENT), GLenum(GL_RENDERBUFFER_EXT), tempRB[1])
        
        let status = glCheckFramebufferStatusEXT(GLenum(GL_FRAMEBUFFER_EXT))
        if status != GL_FRAMEBUFFER_COMPLETE_EXT {
            glDeleteFramebuffersEXT(1, &alternateFBO)
        }
        
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        
        isDoubleBufferFBOMode = true
        // Log removed for Release
    }
    
    override func bindFBO(_ fbo: GLuint) {
        // Bind our FBO / and thus our IOSurface
        glBindFramebufferEXT(GLenum(GL_FRAMEBUFFER_EXT), fbo)
        // Assume FBOs JUST WORK, because we checked on startExecution
        var status = glGetError()
        if status != 0 {
            // Log removed for Release
        }
        
        status = glCheckFramebufferStatusEXT(GLenum(GL_FRAMEBUFFER_EXT))
        if status != GL_FRAMEBUFFER_COMPLETE_EXT {
            // Log removed for Release
        }
    }
    
    override func presentDoubleBufferedFBO() {
        glBindFramebufferEXT(GLenum(GL_READ_FRAMEBUFFER_EXT), alternateFBO)
        glBindFramebufferEXT(GLenum(GL_DRAW_FRAMEBUFFER_EXT), coreVideoFBO)
        
        glBlitFramebufferEXT(0, 0, GLint(texture.size.width), GLint(texture.size.height),
                             0, 0, GLint(texture.size.width), GLint(texture.size.height), GLbitfield(GL_COLOR_BUFFER_BIT), GLenum(GL_NEAREST))
        let status = glGetError()
        if status != 0 {
            // Log removed for Release
        }
        
        glBindFramebufferEXT(GLenum(GL_FRAMEBUFFER_EXT), alternateFBO)
    }
    
    override func willExecuteFrame() {
        super.willExecuteFrame()
        
        // Save state in case the game messes it up.
        glPushAttrib(GLenum(GL_ALL_ATTRIB_BITS))
        glPushClientAttrib(GLenum(GL_CLIENT_ALL_ATTRIB_BITS))
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
        
        // Reset anything the core did.
        glPopAttrib()
        glPopClientAttrib()
        
        // Update the IOSurface.
        glFlushRenderAPPLE()
    }
}
