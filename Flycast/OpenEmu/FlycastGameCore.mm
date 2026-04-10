// Copyright (c) 2025, OpenEmu Team
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

// Rename macOS Carbon's RGBColor to avoid clash with Flycast's RGBColor
#define RGBColor __macOS_RGBColor
#import <Cocoa/Cocoa.h>
#undef RGBColor

#import "FlycastGameCore.h"
#import <OpenEmuBase/OERingBuffer.h>
#import <OpenEmuBase/OEGameCore.h>

#include "emulator.h"
#include "types.h"
#include "cfg/option.h"
#include "stdclass.h"
#include "hw/maple/maple_cfg.h"
#include "hw/maple/maple_devs.h"
#include "hw/pvr/Renderer_if.h"
#include "input/gamepad.h"
#include "input/gamepad_device.h"
#include "audio/audiostream.h"
#include "ui/gui.h"
#include "rend/gles/gles.h"
#include "hw/mem/addrspace.h"
#include "oslib/oslib.h"
#include "wsi/osx.h"
#include "hw/gdrom/gdromv3.h"

#include <OpenGL/gl3.h>
#include <sys/stat.h>
#include <atomic>

// Diagnostic probes defined in their respective translation units
extern std::atomic<uint32_t> g_sh4_diag_pc;

#define SAMPLERATE 44100
#define SIZESOUNDBUFFER (44100 / 60 * 4)

#pragma mark - OpenEmu Audio Backend

// Custom AudioBackend that writes samples to OpenEmu's ring buffer
class OpenEmuAudioBackend : public AudioBackend
{
public:
    OpenEmuAudioBackend() : AudioBackend("openemu", "OpenEmu") {}

    bool init() override { return true; }

    u32 push(const void *data, u32 frames, bool wait) override
    {
        if (_current) {
            OERingBuffer *buf = (OERingBuffer *)[_current audioBufferAtIndex:0];
            NSUInteger needed = (NSUInteger)frames * 4; // stereo s16 = 4 bytes per frame
            if (wait) {
                // Block until the ring buffer has room. This is Flycast's primary
                // frame-rate governor: the SH4 thread calls push() with wait=true
                // (config::LimitFPS=true) once per audio batch (~735 samples at 60fps).
                // Without blocking here the SH4 runs unconstrained, causing sped-up
                // and choppy gameplay.
                while ([buf freeBytes] < needed)
                    [NSThread sleepForTimeInterval:0.001];
            }
            [buf write:(const uint8_t *)data maxLength:needed];
        }
        return frames;
    }

    void term() override {}
};

static OpenEmuAudioBackend openEmuAudioBackend;

#pragma mark -

@interface FlycastGameCore () <OEDCSystemResponderClient>
{
    NSString *_romPath;
    int _videoWidth;
    int _videoHeight;
    BOOL _isInitialized;
    BOOL _emuInitialized;
    double _frameInterval;
    // Diagnostic: track cold-boot timing and frame activity
    NSTimeInterval _bootStartTime;
    NSTimeInterval _lastFrameTime;
    uint32_t _frameCount;
    BOOL _firstFrameLogged;
    FILE *_diagFile;  // direct file log to bypass NSLog rate-limiting
}
@end

__weak FlycastGameCore *_current;

@implementation FlycastGameCore

#pragma mark - Lifecycle

- (id)init
{
    if (self = [super init]) {
        _videoWidth = 640;
        _videoHeight = 480;
        _isInitialized = NO;
        _frameInterval = 59.94;
        NSString *diagPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"flycast_diag.txt"];
        _diagFile = fopen(diagPath.fileSystemRepresentation, "w");
        NSLog(@"[Flycast] Diag file: %@", diagPath);
    }
    _current = self;
    return self;
}

- (void)dealloc
{
    if (_diagFile) { fclose(_diagFile); _diagFile = nil; }
    _current = nil;
}

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
    _romPath = [path copy];
    return YES;
}

- (void)setupEmulation
{
    NSString *supportPath = [self supportDirectoryPath];
    NSString *savesPath   = [self batterySavesDirectoryPath];
    NSString *biosPath    = [self biosDirectoryPath];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:[supportPath stringByAppendingPathComponent:@"data"]
  withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:savesPath
  withIntermediateDirectories:YES attributes:nil error:nil];

    set_user_config_dir(supportPath.fileSystemRepresentation);
    set_user_data_dir(savesPath.fileSystemRepresentation);
    add_system_data_dir(supportPath.fileSystemRepresentation);
    add_system_data_dir(biosPath.fileSystemRepresentation);

    config::RendererType = RenderType::OpenGL;
    config::AudioBackend.set("openemu");
    config::DynarecEnabled.override(false); // interpreter — JIT has stability issues on ARM64 macOS

    if (!addrspace::reserve()) {
        NSLog(@"[Flycast] Failed to reserve Dreamcast address space");
    }
    os_InstallFaultHandler();

    emu.init();
    _emuInitialized = YES;
}

- (void)startEmulation
{
    [super startEmulation];
}

- (void)stopEmulationWithCompletionHandler:(void(^)(void))completionHandler
{
    // In threaded rendering mode, the OE game loop thread is blocked inside
    // rend_single_frame() waiting for the next frame from the SH4 thread.
    // emu.stop() calls rend_cancel_emu_wait() which unblocks it, freeing the
    // thread to execute the completion handler. Safe to call twice — emu.stop()
    // checks state != Running and returns immediately on the second call.
    if (_isInitialized)
        emu.stop();
    [super stopEmulationWithCompletionHandler:completionHandler];
}

- (void)stopEmulation
{
    if (_isInitialized) {
        emu.stop();
        emu.unloadGame();
        rend_term_renderer();
        theGLContext.term();
        _isInitialized = NO;
    }
    os_UninstallFaultHandler();
    if (_emuInitialized) {
        emu.term();
        _emuInitialized = NO;
    }
    [super stopEmulation];
}

- (void)resetEmulation
{
    if (_isInitialized) {
        emu.requestReset();
    }
}

#pragma mark - Frame Execution

- (void)executeFrame
{
    if (!_isInitialized) {
        try {
            gui_init();
            theGLContext.init();
            emu.loadGame(_romPath.fileSystemRepresentation);
            // loadGame calls reset()+load() which clears all settings — re-apply after it returns.
            config::DynarecEnabled.override(false); // keep interpreter; JIT unstable on ARM64 macOS
            config::AudioBackend.set("openemu");    // reset() clears this to "auto"; restore before InitAudio()
            // FastGDRomLoad makes disc reads instantaneous, dramatically cutting cold-boot
            // time under the interpreter (which runs at ~10-20% real speed). Without this,
            // simulated disc I/O adds minutes to the cold-boot black screen.
            config::FastGDRomLoad.override(true);
            NSLog(@"[Flycast] Starting emulation — UseReios=%d FastGDRomLoad=1 DynarecEnabled=0",
                  (bool)config::UseReios);
            rend_init_renderer();
            emu.start();
            gui_setState(GuiState::Closed);
            _bootStartTime = [NSDate timeIntervalSinceReferenceDate];
            _firstFrameLogged = NO;
            _isInitialized = YES;
        } catch (const std::exception &e) {
            NSLog(@"[Flycast] Error loading game: %s", e.what());
            return;
        } catch (...) {
            NSLog(@"[Flycast] Unknown error loading game");
            return;
        }
    }

    bool frameReady = emu.render();

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

// Convenience macro: write to file (bypasses NSLog rate-limiting from log flood)
#define DIAG_LOG(fmt, ...) \
    do { if (_diagFile) { fprintf(_diagFile, fmt "\n", ##__VA_ARGS__); fflush(_diagFile); } } while(0)

    if (frameReady) {
        if (!_firstFrameLogged) {
            _firstFrameLogged = YES;
            NSLog(@"[Flycast] First frame rendered %.1f s after emu.start()", now - _bootStartTime);
            DIAG_LOG("[Flycast] First frame rendered %.1f s after emu.start()", now - _bootStartTime);
        }
        _lastFrameTime = now;
        _frameCount++;
        // Log frame rate every 300 rendered frames (~5 s at 60 fps)
        if (_frameCount % 300 == 0) {
            NSLog(@"[Flycast] Heartbeat: %u frames rendered, running %.0f s", _frameCount, now - _bootStartTime);
            DIAG_LOG("[Flycast] Heartbeat: %u frames rendered, running %.0f s", _frameCount, (double)(now - _bootStartTime));
        }
    } else {
        // emu.render() timed out — no PVR frame in 50 ms. Log PC and GD-ROM state
        // every 2 s to diagnose cold-boot loading freeze. Write to file to bypass
        // macOS NSLog rate-limiting caused by Flycast's internal debug log flood.
        if (_firstFrameLogged && (now - _lastFrameTime) > 5.0) {
            int elapsed = (int)(now - _lastFrameTime);
            if (elapsed % 2 == 0) {
                uint32_t pc = g_sh4_diag_pc.load(std::memory_order_relaxed);
                int gdState = gdrom_diag_get_state();
                const char *gdName =
                      gdState == 0 ? "waitcmd" :
                      gdState == 1 ? "procata" :
                      gdState == 2 ? "waitpacket" :
                      gdState == 3 ? "procpacket" :
                      gdState == 4 ? "pio_send" :
                      gdState == 5 ? "pio_get" :
                      gdState == 6 ? "pio_end" :
                      gdState == 7 ? "procpacketdone" :
                      gdState == 8 ? "readsector_pio" :
                      gdState == 9 ? "readsector_dma" :
                      gdState == 10 ? "process_set_mode" : "unknown";
                DIAG_LOG("[Flycast] Stuck %d s — SH4 PC=0x%08x GD-ROM state=%d (%s)",
                         elapsed, pc, gdState, gdName);
            }
        }
    }
#undef DIAG_LOG
}

#pragma mark - Video

- (OEGameCoreRendering)gameCoreRendering
{
    return OEGameCoreRenderingOpenGL3Video;
}

- (BOOL)needsDoubleBufferedFBO
{
    return NO;
}

- (OEIntSize)bufferSize
{
    return OEIntSizeMake(_videoWidth, _videoHeight);
}

- (OEIntSize)aspectSize
{
    return OEIntSizeMake(4, 3);
}

- (NSTimeInterval)frameInterval
{
    return _frameInterval;
}

#pragma mark - Audio

- (NSUInteger)channelCount
{
    return 2;
}

- (double)audioSampleRate
{
    return SAMPLERATE;
}

#pragma mark - Save States

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    if (!_isInitialized) { block(NO, nil); return; }

    @try {
        dc_savestate(0);
        std::string srcPath = hostfs::getSavestatePath(0, false);
        NSString *src = [NSString stringWithUTF8String:srcPath.c_str()];
        NSError *err = nil;
        [[NSFileManager defaultManager] removeItemAtPath:fileName error:nil];
        [[NSFileManager defaultManager] copyItemAtPath:src toPath:fileName error:&err];
        block(err == nil, err);
    } @catch (NSException *e) {
        NSError *error = [NSError errorWithDomain:OEGameCoreErrorDomain
                                             code:OEGameCoreCouldNotSaveStateError
                                         userInfo:@{NSLocalizedDescriptionKey: e.reason ?: @"Failed to save state"}];
        block(NO, error);
    }
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    if (!_isInitialized) { block(NO, nil); return; }

    @try {
        std::string dstPath = hostfs::getSavestatePath(0, true);
        NSString *dst = [NSString stringWithUTF8String:dstPath.c_str()];
        NSError *err = nil;
        [[NSFileManager defaultManager] removeItemAtPath:dst error:nil];
        [[NSFileManager defaultManager] copyItemAtPath:fileName toPath:dst error:&err];
        if (!err) dc_loadstate(0);
        block(err == nil, err);
    } @catch (NSException *e) {
        NSError *error = [NSError errorWithDomain:OEGameCoreErrorDomain
                                             code:OEGameCoreCouldNotLoadStateError
                                         userInfo:@{NSLocalizedDescriptionKey: e.reason ?: @"Failed to load state"}];
        block(NO, error);
    }
}

#pragma mark - Input

- (oneway void)didMoveDCJoystickDirection:(OEDCButton)button withValue:(CGFloat)value forPlayer:(NSUInteger)player
{
    NSUInteger p = player - 1;
    if (p > 3) return;

    switch (button) {
        case OEDCAnalogUp:    joyy[p] = (s16)(value * -32768); break;
        case OEDCAnalogDown:  joyy[p] = (s16)(value *  32767); break;
        case OEDCAnalogLeft:  joyx[p] = (s16)(value * -32768); break;
        case OEDCAnalogRight: joyx[p] = (s16)(value *  32767); break;
        case OEDCAnalogL:     lt[p]   = (u16)(value * 65535);  break;
        case OEDCAnalogR:     rt[p]   = (u16)(value * 65535);  break;
        default: break;
    }
}

- (oneway void)didPushDCButton:(OEDCButton)button forPlayer:(NSUInteger)player
{
    NSUInteger p = player - 1;
    if (p > 3) return;

    switch (button) {
        case OEDCButtonUp:    kcode[p] &= ~DC_DPAD_UP;    break;
        case OEDCButtonDown:  kcode[p] &= ~DC_DPAD_DOWN;  break;
        case OEDCButtonLeft:  kcode[p] &= ~DC_DPAD_LEFT;  break;
        case OEDCButtonRight: kcode[p] &= ~DC_DPAD_RIGHT; break;
        case OEDCButtonA:     kcode[p] &= ~DC_BTN_A;      break;
        case OEDCButtonB:     kcode[p] &= ~DC_BTN_B;      break;
        case OEDCButtonX:     kcode[p] &= ~DC_BTN_X;      break;
        case OEDCButtonY:     kcode[p] &= ~DC_BTN_Y;      break;
        case OEDCButtonStart: kcode[p] &= ~DC_BTN_START;  break;
        default: break;
    }
}

- (oneway void)didReleaseDCButton:(OEDCButton)button forPlayer:(NSUInteger)player
{
    NSUInteger p = player - 1;
    if (p > 3) return;

    switch (button) {
        case OEDCButtonUp:    kcode[p] |= DC_DPAD_UP;    break;
        case OEDCButtonDown:  kcode[p] |= DC_DPAD_DOWN;  break;
        case OEDCButtonLeft:  kcode[p] |= DC_DPAD_LEFT;  break;
        case OEDCButtonRight: kcode[p] |= DC_DPAD_RIGHT; break;
        case OEDCButtonA:     kcode[p] |= DC_BTN_A;      break;
        case OEDCButtonB:     kcode[p] |= DC_BTN_B;      break;
        case OEDCButtonX:     kcode[p] |= DC_BTN_X;      break;
        case OEDCButtonY:     kcode[p] |= DC_BTN_Y;      break;
        case OEDCButtonStart: kcode[p] |= DC_BTN_START;  break;
        default: break;
    }
}

@end
