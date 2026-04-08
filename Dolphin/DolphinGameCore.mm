/*
 Copyright (c) 2013, OpenEmu Team

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/*
    What doesn't work:
          I got everything in GC working

 */

//  Changed <al*> includes to <OpenAL/al*>
//  Added iRenderFBO to Videoconfig, OGL postprocessing and renderer
//  Added SetState to device.h for input and FullAnalogControl
//  Added Render on alternate thread in Core.cpp in EmuThread() Video Thread
//  Added Render on alternate thread in Cope.cpp in CPUThread() to support single thread mode CPU/GPU

#import "DolphinGameCore.h"
#include "DolHost.h"
#include "AudioCommon/SoundStream.h"
#include "Core/System.h"
#include "OpenEmuAudioStream.h"
#include <stdatomic.h>

#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#define SAMPLERATE 48000
#define SIZESOUNDBUFFER 48000 / 60 * 4
#define OpenEmu 1

@interface DolphinGameCore () <OEGCSystemResponderClient>
@property (copy) NSString *filePath;
@end

DolphinGameCore *_current = 0;

// g_sound_stream was removed in Dolphin 26.03; access via Core::System::GetInstance().GetSoundStream()

@implementation DolphinGameCore
{
    DolHost *dol_host;

    uint16_t *_soundBuffer;
    bool _isWii;
    atomic_bool _isInitialized;
    float _frameInterval;

    NSString *autoLoadStatefileName;
    NSString *_dolphinCoreModule;
    OEIntSize _dolphinCoreAspect;
    OEIntSize _dolphinCoreScreen;

    id<MTLTexture> _dolMetalTexture;
    CAMetalLayer  *_dolMetalLayer;
}

- (instancetype)init
{
    if(self = [super init]){
        dol_host = DolHost::GetInstance();
    }

    _current = self;

    return self;
}

- (void)dealloc
{
    delete dol_host;
    free(_soundBuffer);
}

# pragma mark - Execution
- (BOOL)loadFileAtPath:(NSString *)path
{
    self.filePath = path;

    if([[self systemIdentifier] isEqualToString:@"openemu.system.gc"])
    {
        _dolphinCoreModule = @"gc";
        _isWii = false;
        _dolphinCoreAspect = OEIntSizeMake(4, 3);
        _dolphinCoreScreen = OEIntSizeMake(640, 480);
    }
    else
    {
        _dolphinCoreModule = @"Wii";
        _isWii = true;
        _dolphinCoreAspect = OEIntSizeMake(16,9);
        _dolphinCoreScreen = OEIntSizeMake(854, 480);
    }

    dol_host->Init([[self supportDirectoryPath] fileSystemRepresentation], [path fileSystemRepresentation] );

    usleep(5000);
    return YES;
}

- (void)setPauseEmulation:(BOOL)flag
{
    dol_host->Pause(flag);
    
    [super setPauseEmulation:flag];
}

- (void)stopEmulation
{
    _isInitialized = false;
    
    dol_host->RequestStop();

    [super stopEmulation];
}

- (void)startEmulation
{
    if (!_isInitialized)
    {
        dol_host->SetMetalLayer(_dolMetalLayer);
        dol_host->SetMetalTexture(_dolMetalTexture);

        if(dol_host->LoadFileAtPath())
            _isInitialized = true;
        
        _frameInterval = dol_host->GetFrameInterval();
        
    }
    [super startEmulation];

    //Disable the OE framelimiting
    [self.renderDelegate suspendFPSLimiting];
}

- (void)resetEmulation
{
     dol_host->Reset();
}

- (void)executeFrame
{
   if (![self isEmulationPaused])
    {
        if(!dol_host->CoreRunning()) {
        dol_host->Pause(false);
        }
    
      dol_host->UpdateFrame();
    }
}

# pragma mark - Nand directory Callback
- (const char *)getBundlePath
{
    NSBundle *coreBundle = [NSBundle bundleForClass:[self class]];
    const char *dataPath;
    dataPath = [[coreBundle resourcePath] fileSystemRepresentation];

    return dataPath;
}

# pragma mark - Video
- (OEGameCoreRendering)gameCoreRendering
{
    return OEGameCoreRenderingMetal2;
}

- (BOOL)hasAlternateRenderingThread
{
    return YES;
}

- (void)createMetalTextureWithDevice:(id<MTLDevice>)device
{
    // Texture OE composites from — needs RenderTarget so Dolphin can write into it.
    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                     width:_dolphinCoreScreen.width
                                    height:_dolphinCoreScreen.height
                                 mipmapped:NO];
    desc.usage       = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    desc.storageMode = MTLStorageModePrivate;
    _dolMetalTexture = [device newTextureWithDescriptor:desc];

    // Clear to black so frame 0 composites black instead of uninitialized magenta.
    id<MTLCommandQueue> q = [device newCommandQueue];
    id<MTLCommandBuffer> cb = [q commandBuffer];
    MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    rpd.colorAttachments[0].texture    = _dolMetalTexture;
    rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
    rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    rpd.colorAttachments[0].storeAction = MTLStoreActionStore;
    [[cb renderCommandEncoderWithDescriptor:rpd] endEncoding];
    [cb commit];
    [cb waitUntilCompleted];

    // Sizing layer: gives Dolphin's Metal backend real surface dimensions for SetupSurface().
    // BindBackbuffer bypasses this layer's drawables and uses _dolMetalTexture directly.
    _dolMetalLayer              = [CAMetalLayer layer];
    _dolMetalLayer.device       = device;
    _dolMetalLayer.pixelFormat  = MTLPixelFormatBGRA8Unorm;
    _dolMetalLayer.framebufferOnly = NO;
    _dolMetalLayer.bounds       = CGRectMake(0, 0, _dolphinCoreScreen.width, _dolphinCoreScreen.height);
    _dolMetalLayer.contentsScale = 1.0;
}

- (id<MTLTexture>)metalTexture
{
    return _dolMetalTexture;
}

// MTL3DGameRenderer.update() reads these to resolve OEMTLPixelFormat even in Metal2 mode.
// GL_BGRA (0x80E1) + GL_UNSIGNED_INT_8_8_8_8_REV (0x8367) → OEMTLPixelFormat.BGRA8Unorm,
// matching the MTLPixelFormatBGRA8Unorm texture we create above.
- (GLenum)pixelFormat  { return 0x80E1; } // GL_BGRA
- (GLenum)pixelType    { return 0x8367; } // GL_UNSIGNED_INT_8_8_8_8_REV

- (const void *)videoBuffer
{
    return NULL;
}

- (NSTimeInterval)frameInterval
{
    return _frameInterval ?: 60;
}

- (OEIntSize)bufferSize
{
    return _dolphinCoreScreen;
}

- (OEIntSize)aspectSize
{
    return _dolphinCoreAspect;
}

- (void) SetScreenSize:(int)width :(int)height
{
}

# pragma mark - Audio
- (NSUInteger)channelCount
{
    return 2;
}

- (double)audioSampleRate
{
    return OE_SAMPLERATE;
}

- (id<OEAudioBuffer>)audioBufferAtIndex:(NSUInteger)index
{
    return self;
}

- (NSUInteger)length
{
    return OE_SIZESOUNDBUFFER;
}

- (NSUInteger)read:(void *)buffer maxLength:(NSUInteger)len
{
    SoundStream* sound_stream = Core::System::GetInstance().GetSoundStream();
    if (_isInitialized && sound_stream)
        return static_cast<OpenEmuAudioStream*>(sound_stream)->readAudio(buffer, (int)len);
    return 0;
}

- (NSUInteger)write:(const void *)buffer maxLength:(NSUInteger)length
{
    return 0;
}

# pragma mark - Save States
- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    // we need to make sure we are initialized before attempting to save a state
    while (! _isInitialized)
        usleep (1000);

    block(dol_host->SaveState([fileName UTF8String]),nil);

}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    if (!_isInitialized)
    {
        //Start a separate thread to load
        autoLoadStatefileName = fileName;
        
        [NSThread detachNewThreadSelector:@selector(autoloadWaitThread) toTarget:self withObject:nil];
        block(true, nil);
    } else {
        block(dol_host->LoadState([fileName UTF8String]),nil);
    }
}

- (void)autoloadWaitThread
{
    @autoreleasepool
    {
        //Wait here until we get the signal for full initialization
        while (!_isInitialized)
            usleep (100);
        
        dol_host->LoadState([autoLoadStatefileName UTF8String]);
    }
}

# pragma mark - Input GC
- (oneway void)didMoveGCJoystickDirection:(OEGCButton)button withValue:(CGFloat)value forPlayer:(NSUInteger)player
{
    if(_isInitialized)
    {
        dol_host->SetAxis(button, value, (int)player);
    }
}

- (oneway void)didPushGCButton:(OEGCButton)button forPlayer:(NSUInteger)player
{
    if(_isInitialized)
    {
        dol_host->setButtonState(button, 1, (int)player);
    }
}

- (oneway void)didReleaseGCButton:(OEGCButton)button forPlayer:(NSUInteger)player
{
    if(_isInitialized)
    {
        dol_host->setButtonState(button, 0, (int)player);
    }
}

# pragma mark - Input Wii
- (oneway void)didMoveWiiJoystickDirection:(OEWiiButton)button withValue:(CGFloat)value forPlayer:(NSUInteger)player
{
    if(_isInitialized)
    {
        dol_host->SetAxis(button, value, (int)player);
    }
}

- (oneway void)didPushWiiButton:(OEWiiButton)button forPlayer:(NSUInteger)player
{
    if(_isInitialized)
    {
        if (button > OEWiiButtonCount) {
            dol_host->processSpecialKeys(button , (int)player);
        } else {
            dol_host->setButtonState(button, 1, (int)player);
        }
    }
}

- (oneway void)didReleaseWiiButton:(OEWiiButton)button forPlayer:(NSUInteger)player
{
    if(_isInitialized && button != OEWiimoteSideways && button != OEWiimoteUpright)
    {
        dol_host->setButtonState(button, 0, (int)player);
    }
}

//- (oneway void) didMoveWiiAccelerometer:(OEWiiAccelerometer)accelerometer withValue:(CGFloat)X withValue:(CGFloat)Y withValue:(CGFloat)Z forPlayer:(NSUInteger)player
//{
//    if(_isInitialized)
//    {
//        if (accelerometer == OEWiiNunchuk)
//        {
//            dol_host->setNunchukAccel(X,Y,Z,(int)player);
//        }
//        else
//        {
//            dol_host->setWiimoteAccel(X,Y,Z,(int)player);
//        }
//    }
//}

//- (oneway void)didMoveWiiIR:(OEWiiButton)button IRinfo:(OEwiimoteIRinfo)IRinfo forPlayer:(NSUInteger)player
//{
//    if(_isInitialized)
//    {
//        dol_host->setIRdata(IRinfo ,(int)player);
//    }
//}

- (oneway void)didChangeWiiExtension:(OEWiimoteExtension)extension forPlayer:(NSUInteger)player
{
    if(_isInitialized)
    {
        dol_host->changeWiimoteExtension(extension, (int)player);
    }
}

- (oneway void)IRMovedAtPoint:(int)X withValue:(int)Y
{
//    if (_isInitialized)
//    {
//        int dX = (1023.0 / 854.0) * X;
//        int dY =  (767.0 / 480.0) * Y;
//
////        dol_host->DisplayMessage([[NSString stringWithFormat:@"X: %d, Y: %d",dX,dY ] UTF8String]);
//
//       dol_host->SetIR(0, dX,dY);
//    }
}

# pragma mark - Cheats
- (void)setCheat:(NSString *)code setType:(NSString *)type setEnabled:(BOOL)enabled
{
    dol_host->SetCheat([code UTF8String], [type UTF8String], enabled);
}
@end
