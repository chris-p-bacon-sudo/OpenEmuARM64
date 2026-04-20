// Copyright (c) 2026, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this
//    list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import <Foundation/Foundation.h>
#import <os/log.h>
#import "OELibretroCoreTranslator.h"
#import "OEGameCore.h"
#import "OERingBuffer.h"
#import "OEGeometry.h"
#import "OEGameCoreController.h"
#import "OELogging.h"
#import <dlfcn.h>
#import "libretro.h"
#import <Accelerate/Accelerate.h>
#if __arm64__
#import <arm_neon.h>
#endif
#import <stdatomic.h>

@interface OELibretroCoreTranslator () <OELibretroInputReceiver>
@property (nonatomic, strong) NSBundle *coreBundle;
@property (nonatomic, assign) enum retro_pixel_format retroPixelFormat;
@property (nonatomic, assign) BOOL didExplicitlySetPixelFormat;
@property (nonatomic, assign) BOOL didClearSaturnBuffer;
@property (nonatomic, assign) BOOL isBufferSizeLocked;
@property (nonatomic, assign) BOOL isHW;
@property (nonatomic, assign) BOOL needsContextReset;
@property (nonatomic, assign) int clearFramesRemaining;
@property (nonatomic, assign) uint64_t serializationQuirks;
@property (atomic, assign) int touchX;
@property (atomic, assign) int touchY;
@property (atomic, assign) BOOL isTouching;

// Per-core isolation flags — set once in loadFileAtPath, used everywhere else.
// This prevents system-specific hacks from polluting other cores.
@property (nonatomic, assign) BOOL isPSP;
@property (nonatomic, assign) BOOL isNDS;
@property (nonatomic, assign) BOOL isDC;
@property (nonatomic, assign) BOOL isSaturn;
@property (nonatomic, assign) BOOL isN64;

// Persistent path storage — NSString ivars keep the ObjC objects alive,
// and the corresponding char* ivars (strdup'd) are what we hand to cores.
// The libretro spec requires these pointers remain valid for the core's
// lifetime, and [NSString UTF8String] is only autorelease-pool-scoped.
@property (nonatomic, copy) NSString *biosPath;
@property (nonatomic, copy) NSString *savesPath;
@property (nonatomic, copy) NSString *supportPath;
@end

// C-string copies of the directory paths — allocated via strdup() in init,
// freed in dealloc. These are the pointers actually returned to the core.
static char *_biosPathCStr       = NULL;
static char *_savesPathCStr      = NULL;
static char *_supportPathCStr    = NULL;
static char *_contentDirCStr     = NULL;

// Single-instance bridge — guarded by the assertion in -init. Plain `static`
// (not __thread) so libretro callbacks invoked from core-spawned worker
// threads still resolve _current correctly. All env/video/audio/input
// callbacks are written assuming this is shared across threads.
static __unsafe_unretained OELibretroCoreTranslator *_current = nil;

// HW Callbacks
typedef void (*glGetIntegerv_t)(uint32_t pname, int *params);

static void *_gl_handle = NULL;
static glGetIntegerv_t _glGetIntegerv = NULL;

static void* get_gl_handle(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _gl_handle = dlopen("/System/Library/Frameworks/OpenGL.framework/Versions/Current/OpenGL", RTLD_LAZY | RTLD_LOCAL);
        if (_gl_handle) {
            _glGetIntegerv = (glGetIntegerv_t)dlsym(_gl_handle, "glGetIntegerv");
        }
    });
    return _gl_handle;
}

static uintptr_t libretro_get_current_framebuffer(void) {
    // 1. Ask OpenEmu's renderer for the authoritative FBO
    @autoreleasepool {
        if (_current && _current.renderDelegate) {
            id fb = _current.renderDelegate.presentationFramebuffer;
            if (fb && [fb isKindOfClass:[NSNumber class]]) {
                return (uintptr_t)[(NSNumber *)fb unsignedLongValue];
            }
        }
    }

    // 2. Fall back to querying the active CGL context
    if (get_gl_handle() && _glGetIntegerv) {
        int fbo = 0;
        _glGetIntegerv(0x8CA6, &fbo); // GL_FRAMEBUFFER_BINDING
        return (uintptr_t)fbo;
    }
    return 0;
}

static void (*libretro_get_proc_address(const char *sym))(void) {
    if (!_current || !_current.isHW) return NULL;

    // First query actual OpenGL library, only fallback to global process symbols if missing
    void *gl = get_gl_handle();
    void *addr = NULL;
    if (gl) addr = dlsym(gl, sym);
    if (!addr) addr = dlsym(RTLD_DEFAULT, sym);
    return (void(*)(void))addr;
}

// BIOS Audit Check
//
// TODO: unify with `LibretroCore.requiredFiles` in OELibretroBuildbot.swift.
// Today the registry stores BIOS metadata for download/install UX while
// this table covers load-time verification. A future change should let the
// translator query the registry by system identifier instead of duplicating.
typedef struct {
    const char *systemIDFragment;       // matched via -[NSString containsString:]
    const char *files[6];               // NULL-terminated
    const char *userMessage;
} OELibretroBIOSRequirement;

static const OELibretroBIOSRequirement kBIOSRequirements[] = {
    { "dc",     { "dc_boot.bin", "dc_flash.bin", NULL },
      "Dreamcast requires dc_boot.bin and dc_flash.bin in your BIOS folder." },
    { "nds",    { "bios7.bin", "bios9.bin", "firmware.bin", NULL },
      "Nintendo DS requires bios7.bin, bios9.bin, and firmware.bin in your BIOS folder." },
    { "saturn", { "sat_bios.bin", NULL },
      "Sega Saturn requires sat_bios.bin (or a regional variant) in your BIOS folder." },
    { "psx",    { "scph5500.bin", "scph5501.bin", "scph5502.bin", NULL },
      "PlayStation requires at least one of scph5500.bin (JP), scph5501.bin (US), or scph5502.bin (EU) in your BIOS folder." },
    { "msx",    { "MSX.ROM", "MSX2.ROM", NULL },
      "MSX requires MSX.ROM and MSX2.ROM in your BIOS folder." },
};

static const OELibretroBIOSRequirement *bios_requirement_for_system(NSString *systemID) {
    for (size_t i = 0; i < sizeof(kBIOSRequirements) / sizeof(kBIOSRequirements[0]); i++) {
        NSString *fragment = [NSString stringWithUTF8String:kBIOSRequirements[i].systemIDFragment];
        if ([systemID containsString:fragment]) {
            return &kBIOSRequirements[i];
        }
    }
    return NULL;
}

// PSX is satisfied by ANY ONE of the regional BIOS files; everything else
// requires ALL listed files. Returns YES if the requirement is satisfied.
static BOOL bios_requirement_satisfied(NSString *biosPath, const OELibretroBIOSRequirement *req) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL anyOf = (strcmp(req->systemIDFragment, "psx") == 0);
    BOOL foundAny = NO;
    for (size_t i = 0; req->files[i] != NULL; i++) {
        NSString *file = [NSString stringWithUTF8String:req->files[i]];
        BOOL exists = [fm fileExistsAtPath:[biosPath stringByAppendingPathComponent:file]];
        if (anyOf) {
            if (exists) { foundAny = YES; break; }
        } else if (!exists) {
            return NO;
        }
    }
    return anyOf ? foundAny : YES;
}

static void libretro_log_cb(enum retro_log_level level, const char *fmt, ...) {
    // Hardened: Absolute Silence
}

@implementation OELibretroCoreTranslator
{
    void *_coreHandle;
    void (*_retro_init)(void);
    void (*_retro_deinit)(void);
    void (*_retro_get_system_info)(struct retro_system_info *info);
    void (*_retro_get_system_av_info)(struct retro_system_av_info *info);
    void (*_retro_set_environment)(retro_environment_t);
    void (*_retro_set_video_refresh)(retro_video_refresh_t);
    void (*_retro_set_audio_sample)(retro_audio_sample_t);
    void (*_retro_set_audio_sample_batch)(retro_audio_sample_batch_t);
    void (*_retro_set_input_poll)(retro_input_poll_t);
    void (*_retro_set_input_state)(retro_input_state_t);
    void (*_retro_run)(void);
    bool (*_retro_load_game)(const struct retro_game_info *game);
    void (*_retro_unload_game)(void);
    
    // Serialization
    size_t (*_retro_serialize_size)(void);
    bool (*_retro_serialize)(void *data, size_t size);
    bool (*_retro_unserialize)(const void *data, size_t size);
    
    struct retro_system_av_info _avInfo;
    struct retro_hw_render_callback _hw_callback;
@public
    uint32_t _oePixelFormat;
    uint32_t _oePixelType;
    uint32_t _bpp;
    const void *_videoBuffer;
    void *_oeBufferHint;
    NSData *_romData;
    size_t _cachedMaxWidth;
    size_t _cachedMaxHeight;
    
    // Input state: 4 ports × 16 buttons (RETRO_DEVICE_JOYPAD).
    // Atomic relaxed because writers (input thread) and readers (emu thread)
    // are unsynchronised; aligned int16_t is naturally atomic on arm64 but
    // without _Atomic the compiler may elide reloads or reorder writes.
    _Atomic(int16_t) _buttonStates[4][16];
    // Analog state: 4 ports × 2 sticks (index) × 2 axes
    _Atomic(int16_t) _analogStates[4][2][2];
    
    // Logging: Resolution tracking
    unsigned _lastWidth;
    unsigned _lastHeight;
}

+ (NSString *)libraryVersionForCoreAtURL:(NSURL *)url {
    void *handle = dlopen(url.path.UTF8String, RTLD_LAZY | RTLD_LOCAL);
    if (!handle) return nil;

    // Use the canonical struct from libretro.h. Defining a private copy here
    // would risk drifting out of sync with the bridge's actual ABI — the
    // exact failure mode the libretro.h header comment warns about.
    void (*get_info)(struct retro_system_info *) = dlsym(handle, "retro_get_system_info");
    NSString *version = nil;
    if (get_info) {
        struct retro_system_info info = {0};
        get_info(&info);
        if (info.library_version) {
            version = [NSString stringWithUTF8String:info.library_version];
        }
    }

    dlclose(handle);
    return version;
}

#pragma mark - Libretro Callbacks (C API)

static bool libretro_environment_cb(unsigned cmd, void *data) {
    switch (cmd) {
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
            // This is used for BIOS/Firmware.
            // We return the strdup'd C-string that lives until dealloc —
            // the libretro spec requires this pointer to remain valid for
            // the lifetime of the core.
            if (data && _current && _biosPathCStr) {
                *(const char **)data = _biosPathCStr;
#if DEBUG
                NSLog(@"[OELibretro] Core requested System/BIOS directory: %s", _biosPathCStr);
#endif
                return true;
            }
            break;
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
            if (data && _current && _savesPathCStr) {
                *(const char **)data = _savesPathCStr;
#if DEBUG
                NSLog(@"[OELibretro] Core requested Save/Battery directory: %s", _savesPathCStr);
#endif
                return true;
            }
            break;
        case RETRO_ENVIRONMENT_GET_CAN_DUPE:
            if (data) *(bool *)data = true;
            return true;
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
            if (data) {
                struct retro_log_callback *log = (struct retro_log_callback *)data;
                log->log = libretro_log_cb;
                return true;
            }
            break;
        case RETRO_ENVIRONMENT_GET_CONTENT_DIRECTORY:
            // Return the directory containing the loaded ROM, not the generic
            // support dir. _contentDirCStr is set in loadFileAtPath: from the
            // ROM file path's parent directory.
            *(const char **)data = _contentDirCStr;
            return _contentDirCStr != NULL;
        case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
            if (data) {
                *(unsigned *)data = 2; // Support V2
                return true;
            }
            break;
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS:
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:
            // Acknowledge core options
            return true;
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
            if (data && _current) {
                enum retro_pixel_format format = *(enum retro_pixel_format *)data;
                
                // Isolation Guard: Force XRGB8888 for PSP to ensure hardware bridge compatibility.
                // Many PPSSPP builds default to 0RGB1555 which can cause black screens if not 
                // explicitly handled by the Metal shaders.
                if (_current.isPSP && format != RETRO_PIXEL_FORMAT_XRGB8888) {
#if DEBUG
                    NSLog(@"[OELibretro] PSP requested format %d, but bridge is forcing XRGB8888 for stability.", format);
#endif
                    format = RETRO_PIXEL_FORMAT_XRGB8888;
                }

                _current.retroPixelFormat = format;
                _current.didExplicitlySetPixelFormat = YES;
#if DEBUG
                NSLog(@"[OELibretro] Core requested Pixel Format: %d", _current.retroPixelFormat);
#endif
                return true;
            }
            return false;
        case RETRO_ENVIRONMENT_SET_GEOMETRY:
            if (data && _current) {
                const struct retro_game_geometry *geom = (const struct retro_game_geometry *)data;
                @synchronized(_current) {
                    _current->_avInfo.geometry = *geom;
                }
                _current.didClearSaturnBuffer = NO; 
#if DEBUG
                NSLog(@"[OELibretro] Geometry updated: %dx%d (Aspect: %.2f)", geom->base_width, geom->base_height, geom->aspect_ratio);
#endif
                return true;
            }
            break;
        case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
            if (data && _current) {
                const struct retro_system_av_info *info = (const struct retro_system_av_info *)data;
                @synchronized(_current) {
                    _current->_avInfo = *info;
                }
#if DEBUG
                NSLog(@"[OELibretro] AV Info updated: %dx%d @ %.2f fps", info->geometry.base_width, info->geometry.base_height, info->timing.fps);
#endif
                return true;
            }
            break;
        case RETRO_ENVIRONMENT_SET_HW_RENDER:
            if (data && _current) {
                struct retro_hw_render_callback *hw = (struct retro_hw_render_callback *)data;
                
                // CRITICAL: Block hardware rendering for PSP. 
                // The current PPSSPP libretro nightly has a threading model that is incompatible with 
                // macOS OpenGL on Apple Silicon, leading to crashes in 'EmuThread'.
                // Returning false here forces the core to use its software renderer.
                if (_current.isPSP) {
#if DEBUG
                    NSLog(@"[OELibretro] PSP requested HW rendering, but the bridge is REJECTING it to force stable software mode.");
#endif
                    return false;
                }
                
                // Only accept OpenGL-family contexts. Reject Vulkan/D3D — we have no backend for them.
                // Cores like Flycast will retry with OpenGL when we reject Vulkan.
                switch (hw->context_type) {
                    case RETRO_HW_CONTEXT_OPENGL:
                    case RETRO_HW_CONTEXT_OPENGLES2:
                    case RETRO_HW_CONTEXT_OPENGL_CORE:
                    case RETRO_HW_CONTEXT_OPENGLES3:
                    case RETRO_HW_CONTEXT_OPENGLES_ANY:
                        break; // Accepted — fall through to setup
                    default:
#if DEBUG
                        NSLog(@"[OELibretro] REJECTED HW context type %d (Vulkan/D3D not supported). Core should fall back to GL.", hw->context_type);
#endif
                        return false;
                }
                
                hw->get_current_framebuffer = libretro_get_current_framebuffer;
                hw->get_proc_address = libretro_get_proc_address;
                _current->_hw_callback = *hw;
                _current.isHW = YES;
#if DEBUG
                NSLog(@"[OELibretro] Accepted HW Rendering (Type: %d, Version: %u.%u)", hw->context_type, hw->version_major, hw->version_minor);
#endif
                return true;
            }
            break;
        case RETRO_ENVIRONMENT_GET_HW_RENDER_INTERFACE:
            // This command expects a retro_hw_render_interface (not retro_hw_render_callback).
            // We don't implement a render interface — return false so the core uses fallbacks.
            return false;
        case RETRO_ENVIRONMENT_SET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE:
            // This bridge does not implement the context negotiation interface.
            // Returning true would be a lie that tells the core the frontend will
            // honour the interface; returning false lets the core use its own fallback.
#if DEBUG
            NSLog(@"[OELibretro] Core requested context negotiation interface — returning false (not implemented).");
#endif
            return false;
        case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
        case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
            // Acknowledge but ignore — OpenEmu has its own input system.
            return true;
        case RETRO_ENVIRONMENT_GET_VARIABLE:
            if (data && _current) {
                struct retro_variable *var = (struct retro_variable *)data;
                NSString *systemID = [_current systemIdentifier];
                
                // Mupen64Plus-Next Defaults
                if ([systemID containsString:@"n64"]) {
                    if (strcmp(var->key, "mupen64plus-rdp-plugin") == 0) {
                        var->value = "gliden64";
                        return true;
                    }
                    // GLideN64's threaded renderer spawns a GL command thread
                    // that requires a shared GL context. Our bridge does not
                    // provide one, so GL calls on that thread corrupt state
                    // and crash in TextureCache::_addTexture. Force single-threaded.
                    if (strcmp(var->key, "mupen64plus-ThreadedRenderer") == 0) {
                        var->value = "False";
                        return true;
                    }
                    if (strcmp(var->key, "mupen64plus-MaxTxCacheSize") == 0) {
                        var->value = "1500";
                        return true;
                    }
                    if (strcmp(var->key, "mupen64plus-txHiresEnable") == 0) {
                        var->value = "False";
                        return true;
                    }
                    if (strcmp(var->key, "mupen64plus-EnableEnhancedTextureStorage") == 0) {
                        var->value = "False";
                        return true;
                    }
                    if (strcmp(var->key, "mupen64plus-EnableEnhancedHighResStorage") == 0) {
                        var->value = "False";
                        return true;
                    }
                    if (strcmp(var->key, "mupen64plus-EnableTextureCache") == 0) {
                        var->value = "False";
                        return true;
                    }
                    if (strcmp(var->key, "mupen64plus-txCacheCompression") == 0) {
                        var->value = "False";
                        return true;
                    }
                    if (strcmp(var->key, "mupen64plus-cpucore") == 0) {
                        var->value = "dynamic_recompiler";
                        return true;
                    }
                }
                
                // NDS (MelonDS/DeSmuME) Defaults
                if ([systemID containsString:@"nds"]) {
                    if (strcmp(var->key, "melonds_boot_directly") == 0) {
                        var->value = "true";
                        return true;
                    }
                    if (strcmp(var->key, "melonds_threaded_renderer") == 0) {
                        var->value = "false";
                        return true;
                    }
                    if (strcmp(var->key, "desmume_jit_trust_unit") == 0) {
                        var->value = "enabled";
                        return true;
                    }
                }
                
                // Flycast/Reicast Defaults (core uses 'reicast_' prefix for legacy vars)
                if ([systemID containsString:@"dc"]) {
                    if (strcmp(var->key, "reicast_hle_bios") == 0) {
                        var->value = "disabled";
                        return true;
                    }
                    if (strcmp(var->key, "reicast_fast_gd_rom_load") == 0 ||
                        strcmp(var->key, "flycast_fast_gd_rom_load") == 0) {
                        var->value = "enabled";
                        return true;
                    }
                    // 2x native resolution (640x480 -> 1280x960) — good default for M-series Macs
                    if (strcmp(var->key, "reicast_internal_resolution") == 0 ||
                        strcmp(var->key, "flycast_internal_resolution") == 0) {
                        var->value = "1280x960";
                        return true;
                    }
                    // Disable threaded rendering — our bridge provides a single GL context;
                    // Flycast's threaded renderer spawns a second thread that needs a shared
                    // context we don't provide, which causes black screens on Apple Silicon.
                    if (strcmp(var->key, "reicast_threaded_rendering") == 0 ||
                        strcmp(var->key, "flycast_threaded_rendering") == 0) {
                        var->value = "disabled";
                        return true;
                    }
                    // Disable frame-swap delay — this variable makes retro_run block waiting
                    // for audio to be consumed, causing a deadlock with CoreAudio's IO thread.
                    if (strcmp(var->key, "reicast_delay_frame_swapping") == 0) {
                        var->value = "disabled";
                        return true;
                    }
                    // Disable DSP — reduces audio thread pressure and avoids secondary
                    // audio sync points that can contribute to the CoreAudio deadlock.
                    if (strcmp(var->key, "reicast_enable_dsp") == 0) {
                        var->value = "disabled";
                        return true;
                    }
                }

                // PPSSPP Defaults
                if ([systemID containsString:@"psp"]) {
                    if (strcmp(var->key, "ppsspp_backend") == 0) {
                        var->value = "SOFTWARE";
                        return true;
                    }
                    if (strcmp(var->key, "ppsspp_cpu_core") == 0) {
                        var->value = "jit";
                        return true;
                    }
                    if (strcmp(var->key, "ppsspp_rendering_mode") == 0) {
                        var->value = "software";
                        return true;
                    }
                    if (strcmp(var->key, "ppsspp_threaded_rendering") == 0) {
                        var->value = "disabled";
                        return true;
                    }
                    if (strcmp(var->key, "ppsspp_inflight_frames") == 0) {
                        var->value = "1";
                        return true;
                    }
                    if (strcmp(var->key, "ppsspp_software_rendering") == 0) {
                        var->value = "enabled";
                        return true;
                    }
                    if (strcmp(var->key, "ppsspp_gpu_disallow_shared_context") == 0) {
                        var->value = "enabled";
                        return true;
                    }
                    if (strcmp(var->key, "ppsspp_force_max_fps") == 0) {
                        var->value = "enabled";
                        return true;
                    }
                }
                
                // No override matched — set value to NULL and return true.
                // Spec: returning true means the frontend supports variables;
                // NULL value tells the core to use its own built-in default.
                var->value = NULL;
#if DEBUG
                NSLog(@"[OELibretro] Core queried variable: %s (System: %s) — no override", var->key, [systemID UTF8String]);
#endif
            }
            return true;
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
            if (data) *(bool *)data = false;
            return true;
        case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
            // Cores write a uint64_t bitmask declaring how their save-state
            // serialization deviates from the spec. We acknowledge it and
            // record it so -saveStateToFileAtPath: can adapt.
            if (data && _current) {
                uint64_t quirks = *(uint64_t *)data;
                _current.serializationQuirks = quirks;
#if DEBUG
                NSLog(@"[OELibretro] Core declared serialization quirks: 0x%llx%@%@%@",
                      quirks,
                      (quirks & RETRO_SERIALIZATION_QUIRK_MUST_INITIALIZE)    ? @" MUST_INITIALIZE"    : @"",
                      (quirks & RETRO_SERIALIZATION_QUIRK_CORE_VARIABLE_SIZE) ? @" CORE_VARIABLE_SIZE" : @"",
                      (quirks & RETRO_SERIALIZATION_QUIRK_SINGLE_SESSION)     ? @" SINGLE_SESSION"     : @"");
#endif
                return true;
            }
            return false;
        default:
            break;
    }
    return false;
}

#pragma mark - Optimised Video Copy Handlers (Hot Path)

// Each handler converts one libretro pixel format into BGRA8888 (the layout
// OpenEmu's Metal renderer expects). The libretro spec only defines RGB
// orderings — there is no BGR variant — so no byte-swap branch is needed.
typedef void (*OEVideoCopyHandler)(const uint8_t *src, uint32_t *dst, unsigned width, unsigned height, size_t srcPitch, size_t dstPitchWords);

static void OEVideoCopy0RGB1555(const uint8_t *src, uint32_t *dst, unsigned width, unsigned height, size_t srcPitch, size_t dstPitchWords) {
    const uint16_t *s_row = (const uint16_t *)src;
    uint32_t *d_row = dst;

    for (unsigned y = 0; y < height; y++) {
        const uint16_t *s = s_row;
        uint32_t *d = d_row;
        unsigned x = 0;

        // NEON path: process 8 pixels at a time.
        // Source layout 0RGB1555:  0RRRRRGGGGGBBBBB
        // Destination BGRA in little-endian memory: B, G, R, A
#if __arm64__
        for (; x + 7 < width; x += 8) {
            uint16x8_t pixels = vld1q_u16(s + x);

            uint16x8_t r_16 = vandq_u16(vshrq_n_u16(pixels, 10), vdupq_n_u16(0x1F));
            uint16x8_t g_16 = vandq_u16(vshrq_n_u16(pixels, 5),  vdupq_n_u16(0x1F));
            uint16x8_t b_16 = vandq_u16(pixels,                  vdupq_n_u16(0x1F));

            uint8x8_t r = vmovn_u16(vorrq_u16(vshlq_n_u16(r_16, 3), vshrq_n_u16(r_16, 2)));
            uint8x8_t g = vmovn_u16(vorrq_u16(vshlq_n_u16(g_16, 3), vshrq_n_u16(g_16, 2)));
            uint8x8_t b = vmovn_u16(vorrq_u16(vshlq_n_u16(b_16, 3), vshrq_n_u16(b_16, 2)));
            uint8x8_t a = vdup_n_u8(0xFF);

            uint8x8x2_t bg = vzip_u8(b, g);
            uint8x8x2_t ra = vzip_u8(r, a);

            uint16x4x2_t bgra0 = vzip_u16(vreinterpret_u16_u8(bg.val[0]), vreinterpret_u16_u8(ra.val[0]));
            uint16x4x2_t bgra1 = vzip_u16(vreinterpret_u16_u8(bg.val[1]), vreinterpret_u16_u8(ra.val[1]));

            vst1q_u32(d + x + 0, vreinterpretq_u32_u16(vcombine_u16(bgra0.val[0], bgra0.val[1])));
            vst1q_u32(d + x + 4, vreinterpretq_u32_u16(vcombine_u16(bgra1.val[0], bgra1.val[1])));
        }
#endif

        // Scalar tail (also handles all pixels on non-arm64)
        for (; x < width; x++) {
            uint16_t pix = s[x];
            uint32_t r_val = (pix >> 10) & 0x1F;
            uint32_t g_val = (pix >> 5)  & 0x1F;
            uint32_t b_val =  pix        & 0x1F;
            r_val = (r_val << 3) | (r_val >> 2);
            g_val = (g_val << 3) | (g_val >> 2);
            b_val = (b_val << 3) | (b_val >> 2);
            d[x] = 0xFF000000 | (r_val << 16) | (g_val << 8) | b_val;
        }

        s_row = (const uint16_t *)((const uint8_t *)s_row + srcPitch);
        d_row += dstPitchWords;
    }
}

static void OEVideoCopyRGB565(const uint8_t *src, uint32_t *dst, unsigned width, unsigned height, size_t srcPitch, size_t dstPitchWords) {
    const uint16_t *s_line = (const uint16_t *)src;
    uint32_t *d_line = dst;

    for (unsigned y = 0; y < height; y++) {
        const uint16_t *s = s_line;
        uint32_t *d = d_line;
        unsigned x = 0;

        // Source layout RGB565: RRRRRGGGGGGBBBBB
#if __arm64__
        for (; x + 7 < width; x += 8) {
            uint16x8_t pixels = vld1q_u16(s + x);

            uint16x8_t r_16 = vandq_u16(vshrq_n_u16(pixels, 11), vdupq_n_u16(0x1F));
            uint16x8_t g_16 = vandq_u16(vshrq_n_u16(pixels, 5),  vdupq_n_u16(0x3F));
            uint16x8_t b_16 = vandq_u16(pixels,                  vdupq_n_u16(0x1F));

            uint8x8_t r = vmovn_u16(vorrq_u16(vshlq_n_u16(r_16, 3), vshrq_n_u16(r_16, 2)));
            uint8x8_t g = vmovn_u16(vorrq_u16(vshlq_n_u16(g_16, 2), vshrq_n_u16(g_16, 4)));
            uint8x8_t b = vmovn_u16(vorrq_u16(vshlq_n_u16(b_16, 3), vshrq_n_u16(b_16, 2)));
            uint8x8_t a = vdup_n_u8(0xFF);

            uint8x8x2_t bg = vzip_u8(b, g);
            uint8x8x2_t ra = vzip_u8(r, a);

            uint16x4x2_t bgra0 = vzip_u16(vreinterpret_u16_u8(bg.val[0]), vreinterpret_u16_u8(ra.val[0]));
            uint16x4x2_t bgra1 = vzip_u16(vreinterpret_u16_u8(bg.val[1]), vreinterpret_u16_u8(ra.val[1]));

            vst1q_u32(d + x + 0, vreinterpretq_u32_u16(vcombine_u16(bgra0.val[0], bgra0.val[1])));
            vst1q_u32(d + x + 4, vreinterpretq_u32_u16(vcombine_u16(bgra1.val[0], bgra1.val[1])));
        }
#endif

        // Scalar tail (also handles all pixels on non-arm64)
        for (; x < width; x++) {
            uint16_t pix = s[x];
            uint32_t r_val = (pix >> 11) & 0x1F;
            uint32_t g_val = (pix >> 5)  & 0x3F;
            uint32_t b_val =  pix        & 0x1F;
            r_val = (r_val << 3) | (r_val >> 2);
            g_val = (g_val << 2) | (g_val >> 4);
            b_val = (b_val << 3) | (b_val >> 2);
            d[x] = 0xFF000000 | (r_val << 16) | (g_val << 8) | b_val;
        }

        s_line = (const uint16_t *)((const uint8_t *)s_line + srcPitch);
        d_line += dstPitchWords;
    }
}

static void OEVideoCopyXRGB8888(const uint8_t *src, uint32_t *dst, unsigned width, unsigned height, size_t srcPitch, size_t dstPitchWords) {
    // Libretro XRGB8888 stored as a uint32_t 0x00RRGGBB is, in little-endian
    // memory, the byte sequence (B, G, R, 0x00) — already identical to BGRA.
    for (unsigned y = 0; y < height; y++) {
        memcpy(dst + (y * dstPitchWords), src + (y * srcPitch), width * 4);
    }
}

static void libretro_video_refresh_cb(const void *data, unsigned width, unsigned height, size_t pitch) {
    if (data && _current) {
        if (width != _current->_lastWidth || height != _current->_lastHeight) {
#if DEBUG
            NSLog(@"[OELibretro] Resolution change detected: %ux%u (Pitch: %zu)", width, height, pitch);
#endif
            _current->_lastWidth = width;
            _current->_lastHeight = height;
        }

        // Handle Hardware Render Presentation
        if (data == RETRO_HW_FRAME_BUFFER_VALID) {
            // Cores using OpenGL render directly to the FBO provided by OpenEmu.
            // Do NOT store this sentinel as _videoBuffer — it's not a real pointer.
            return;
        }

        _current->_videoBuffer = data;

        if (_current->_oeBufferHint) {
            uint32_t *dst = (uint32_t *)_current->_oeBufferHint;
            size_t destRowWords = _current.bufferSize.width;
            size_t bufferHeight = _current.bufferSize.height;

            if (_current.clearFramesRemaining > 0) {
                memset(dst, 0, destRowWords * bufferHeight * 4);
                _current.clearFramesRemaining--;
            }
            
            // Safety Check: Avoid out-of-bounds writes if core resolution exceeds buffer
            if (width > destRowWords || height > bufferHeight) {
                width = (unsigned)MIN(width, destRowWords);
                height = (unsigned)MIN(height, bufferHeight);
            }

            OEVideoCopyHandler handler = NULL;
            switch (_current.retroPixelFormat) {
                case RETRO_PIXEL_FORMAT_0RGB1555: handler = OEVideoCopy0RGB1555; break;
                case RETRO_PIXEL_FORMAT_RGB565:   handler = OEVideoCopyRGB565;   break;
                case RETRO_PIXEL_FORMAT_XRGB8888: handler = OEVideoCopyXRGB8888; break;
                default:
                    NSLog(@"[OELibretro] WARNING: Unknown pixel format %d — frame will not be drawn.",
                          _current.retroPixelFormat);
                    break;
            }

            if (handler) {
                // Copy to (0,0) and let OpenEmu Metal handle centring the viewport.
                handler((const uint8_t *)data, dst, width, height, pitch, destRowWords);
            }
        }
    }
}

static void libretro_audio_sample_cb(int16_t left, int16_t right) {
    if (_current) {
        int16_t samples[2] = {left, right};
        [[_current audioBufferAtIndex:0] write:samples maxLength:sizeof(samples)];
    }
}

static size_t libretro_audio_sample_batch_cb(const int16_t *data, size_t frames) {
    if (_current && data) {
        [[_current audioBufferAtIndex:0] write:data maxLength:frames * 2 * sizeof(int16_t)];
        return frames;
    }
    return 0;
}
static void libretro_input_poll_cb(void) {
    // OpenEmu's model is push-based, but we give the core a chance to poll if it needs to.
}
static int16_t libretro_input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (!_current) return 0;

    switch (device) {
        case RETRO_DEVICE_JOYPAD:
            // Standard digital buttons — up to 16 buttons per port.
            if (port < 4 && id < 16) {
                return atomic_load_explicit(&_current->_buttonStates[port][id], memory_order_relaxed);
            }
            return 0;
        case RETRO_DEVICE_ANALOG:
            // Analog sticks: index 0 = left stick, 1 = right stick; id 0 = X, 1 = Y.
            if (port < 4 && index < 2 && id < 2) {
                return atomic_load_explicit(&_current->_analogStates[port][index][id], memory_order_relaxed);
            }
            return 0;
        case RETRO_DEVICE_POINTER:
            if (id == RETRO_DEVICE_ID_POINTER_X) {
                // Generic pointer X: full surface (0..screen width) → Libretro range
                return (int16_t)(([_current touchX] / 256.0) * 65535 - 32768);
            }
            if (id == RETRO_DEVICE_ID_POINTER_Y) {
                if (_current.isNDS) {
                    // NDS-specific: touch screen is the bottom half (Y 192..384)
                    float yNorm = ([_current touchY] - 192.0) / 192.0;
                    if (yNorm < 0) yNorm = 0;
                    if (yNorm > 1) yNorm = 1;
                    return (int16_t)(yNorm * 65535 - 32768);
                } else {
                    // Generic pointer Y: full surface
                    return (int16_t)(([_current touchY] / 256.0) * 65535 - 32768);
                }
            }
            if (id == RETRO_DEVICE_ID_POINTER_PRESSED) {
                return [_current isTouching] ? 1 : 0;
            }
            break;
    }
    return 0;
}

#pragma mark - Symbol Resolution Helper

// dlsym already strips the Mach-O leading underscore, so passing
// "retro_init" finds the "_retro_init" symbol. No additional mangling
// fallback is needed (or correct) on macOS.
static void* bridge_dlsym(void *handle, const char *symbol) {
    return dlsym(handle, symbol);
}

- (instancetype)init {
    NSAssert(_current == nil, @"OELibretroCoreTranslator is designed as a single-instance bridge due to thread-local callback residency.");
    if (_current != nil) {
        // Release-build guard — NSAssert compiles out in Release.
        NSLog(@"[OELibretro] FATAL: Attempted to create a second OELibretroCoreTranslator while one is active.");
        return nil;
    }
    self = [super init];
    if (self) {
        _current = self;
        _oePixelFormat = OEPixelFormat_BGRA;
        _oePixelType   = OEPixelType_UNSIGNED_INT_8_8_8_8_REV;
        _bpp           = 4;
        _cachedMaxWidth = 0;
        _cachedMaxHeight = 0;
        _isBufferSizeLocked = NO;
        _clearFramesRemaining = 20;
        _retroPixelFormat = RETRO_PIXEL_FORMAT_0RGB1555; // Libretro spec default

        // Retain NSString path objects and create strdup'd C-string copies.
        // The C-strings are what we hand to libretro cores via the environment
        // callback; they remain valid until dealloc.
        self.biosPath = [self biosDirectoryPath];
        self.savesPath = [self batterySavesDirectoryPath];
        self.supportPath = [self supportDirectoryPath];

        free(_biosPathCStr);    _biosPathCStr    = self.biosPath    ? strdup([self.biosPath UTF8String])    : NULL;
        free(_savesPathCStr);   _savesPathCStr   = self.savesPath   ? strdup([self.savesPath UTF8String])   : NULL;
        free(_supportPathCStr); _supportPathCStr = self.supportPath ? strdup([self.supportPath UTF8String]) : NULL;
    }
    return self;
}

- (void)dealloc {
    if (_current == self) _current = nil;
    free(_biosPathCStr);    _biosPathCStr    = NULL;
    free(_savesPathCStr);   _savesPathCStr   = NULL;
    free(_supportPathCStr); _supportPathCStr = NULL;
    free(_contentDirCStr);  _contentDirCStr  = NULL;
    if (_coreHandle) {
        if (_retro_unload_game) _retro_unload_game();
        if (_retro_deinit) _retro_deinit();
        dlclose(_coreHandle);
        _coreHandle = NULL;
    }
}

#pragma mark - OEGameCore Overrides

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error {
    _current = self;
    self.coreBundle = [[self owner] bundle];

    // Fallback: if owner didn't provide a bundle, scan all loaded bundles
    // for one that declares OELibretroCoreTranslator as its game core class.
    if (!self.coreBundle) {
        for (NSBundle *b in [NSBundle allBundles]) {
            if ([[b objectForInfoDictionaryKey:@"OEGameCoreClass"] isEqualToString:@"OELibretroCoreTranslator"]) {
                self.coreBundle = b;
                break;
            }
        }
    }

    NSString *corePath = [[self coreBundle] objectForInfoDictionaryKey:@"OELibretroCorePath"];

    if (!corePath) {
        corePath = [self.coreBundle executablePath];
    }

    // If the plist value is a relative path, resolve it against the bundle's
    // MacOS/ directory (where the dylib sits alongside the stub executable).
    if (corePath && ![corePath isAbsolutePath]) {
        NSString *bundleMacOSDir = [[self.coreBundle executablePath] stringByDeletingLastPathComponent];
        corePath = [bundleMacOSDir stringByAppendingPathComponent:corePath];
    }
    
    // Per-system isolation flags — identify system once, use flags everywhere.
    // This prevents core-specific logic from leaking across systems.
    NSString *systemID = [self systemIdentifier];
    
    _isPSP    = [systemID containsString:@"psp"];
    _isNDS    = [systemID containsString:@"nds"];
    _isDC     = [systemID containsString:@"dc"];
    _isSaturn = [systemID containsString:@"saturn"];
    _isN64    = [systemID containsString:@"n64"];
    _isHW     = NO;  // Reset — core will re-request via SET_HW_RENDER if needed

    // Populate content directory (ROM's parent folder) for RETRO_ENVIRONMENT_GET_CONTENT_DIRECTORY.
    // The libretro spec says this should be the directory that contains the loaded content.
    {
        NSString *romDir = [path stringByDeletingLastPathComponent];
        free(_contentDirCStr);
        _contentDirCStr = romDir ? strdup([romDir fileSystemRepresentation]) : NULL;
    }
    
    // Trust the core to set its own pixel format via RETRO_ENVIRONMENT_SET_PIXEL_FORMAT.
    // The Libretro spec default (0RGB1555) is set in -init; the core overrides it
    // during retro_set_environment or retro_init via the environment callback.
    
    _cachedMaxWidth = 0; 
    _cachedMaxHeight = 0;

    if (![[NSFileManager defaultManager] fileExistsAtPath:corePath]) {
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Libretro core not found at %@", corePath]}];
        }
        return NO;
    }
    
    _coreHandle = dlopen([corePath UTF8String], RTLD_LAZY | RTLD_LOCAL);
    if (!_coreHandle) {
        const char *err = dlerror();
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to load libretro core: %s", err ?: "unknown error"]}];
        }
        return NO;
    }
    
    // Resolve all mandatory symbols with fallback
    #define RESOLVE(name) _##name = bridge_dlsym(_coreHandle, #name);
    
    RESOLVE(retro_init);
    RESOLVE(retro_deinit);
    RESOLVE(retro_get_system_info);
    RESOLVE(retro_get_system_av_info);
    RESOLVE(retro_set_environment);
    RESOLVE(retro_set_video_refresh);
    RESOLVE(retro_set_audio_sample);
    RESOLVE(retro_set_audio_sample_batch);
    RESOLVE(retro_set_input_poll);
    RESOLVE(retro_set_input_state);
    RESOLVE(retro_run);
    RESOLVE(retro_load_game);
    RESOLVE(retro_unload_game);
    
    // Optional (but highly recommended) Serialization
    RESOLVE(retro_serialize_size);
    RESOLVE(retro_serialize);
    RESOLVE(retro_unserialize);
    
    // Safety check for absolute minimum required to function
    if (!_retro_init || !_retro_run || !_retro_load_game) {
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{NSLocalizedDescriptionKey: @"Core is missing essential Libretro functions."}];
        }
        dlclose(_coreHandle);
        _coreHandle = NULL;
        return NO;
    }
    
    // Register callbacks — guard each with a nil-check in case the core
    // is missing a non-mandatory setter (e.g. stripped or minimal builds).
    if (_retro_set_environment)        _retro_set_environment(libretro_environment_cb);
    if (_retro_set_video_refresh)      _retro_set_video_refresh(libretro_video_refresh_cb);
    if (_retro_set_audio_sample)       _retro_set_audio_sample(libretro_audio_sample_cb);
    if (_retro_set_audio_sample_batch) _retro_set_audio_sample_batch(libretro_audio_sample_batch_cb);
    if (_retro_set_input_poll)         _retro_set_input_poll(libretro_input_poll_cb);
    if (_retro_set_input_state)        _retro_set_input_state(libretro_input_state_cb);
    
    _retro_init();
    
    // BIOS Verification Stage — non-fatal: log only. The core's own
    // retro_load_game will surface the canonical error if the BIOS is
    // truly required and missing.
    NSString *biosPath = [self biosDirectoryPath];
#if DEBUG
    NSLog(@"[OELibretro] BIOS Directory: %@", biosPath);
#endif

    NSString *errorMsg = nil;
    const OELibretroBIOSRequirement *req = bios_requirement_for_system(systemID);
    if (req && !bios_requirement_satisfied(biosPath, req)) {
        errorMsg = [NSString stringWithUTF8String:req->userMessage];
#if DEBUG
        NSLog(@"[OELibretro] BIOS DIAGNOSTIC: %@", errorMsg);
#endif
    }
    
    struct retro_system_info sysInfo = {0};
    _retro_get_system_info(&sysInfo);
    
    struct retro_game_info gameInfo = {0};
    gameInfo.path = [path UTF8String];
    
    if (sysInfo.need_fullpath) {
        gameInfo.data = NULL;
        gameInfo.size = 0;
    } else {
        _romData = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        gameInfo.data = [_romData bytes];
        gameInfo.size = [_romData length];
    }
    
    _clearFramesRemaining = 20; // Warm-up: Clear buffer for 20 frames to avoid memory artifacts

    if (!_retro_load_game(&gameInfo)) {
        errorMsg = @"The core rejected the ROM load. This is usually due to missing BIOS or corrupted files.";

        // If we know this system requires specific BIOS files, surface that
        // hint to the user instead of the generic message.
        if (req) {
            errorMsg = [NSString stringWithUTF8String:req->userMessage];
        }

        NSLog(@"[OELibretro] !!! CRITICAL LOAD FAILURE: %@", errorMsg);
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain 
                                         code:OEGameCoreCouldNotLoadROMError 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    
    // Core is loaded — resolve serialization state size now.
    // Spec: cores may only know their true state size after loading content.
    if (_retro_serialize_size) {
        size_t s = _retro_serialize_size();
        #if DEBUG
        os_log_info(OE_LOG_DEFAULT, "Libretro: Core reported serialization size: %zu bytes", s);
        #endif
    }
    
    // Update geometry and log handshake
    if (_retro_get_system_av_info) {
        _retro_get_system_av_info(&_avInfo);
        
        // Finalize the cached geometry to ensure buffer stability
        if (_cachedMaxWidth == 0) {
            _cachedMaxWidth  = _avInfo.geometry.max_width ?: 640;
            _cachedMaxHeight = _avInfo.geometry.max_height ?: 480;
        }
    }
    
    return YES;
}

- (void)stopEmulation {
    [super stopEmulation];
    // Nil _current BEFORE dlclose so any callbacks that fire during shutdown
    // see nil and return early (prevents use-after-free in C callbacks).
    _current = nil;
    if (_coreHandle) {
        if (_retro_unload_game) _retro_unload_game();
        if (_retro_deinit) _retro_deinit();
        dlclose(_coreHandle);
        _coreHandle = NULL;
    }
}

- (void)executeFrame {
    _current = self;
    
    // The OpenGL context is only guaranteed to be bound to this thread AFTER startEmulation,
    // right at the beginning of the first frame execution. This is the latest and safest 
    // place to initialize the core's hardware context.
    if (self.needsContextReset) {
        self.needsContextReset = NO;
        
        if (self.isHW && _hw_callback.context_reset) {
            _hw_callback.context_reset();
        }
    }
    
    if (_retro_run) _retro_run();
}

- (void)startEmulation {
    [super startEmulation];
    
    _current = self;
    self.needsContextReset = YES;
}

- (OEIntSize)bufferSize {
    @synchronized(self) {
        // High-Stability Strategy: Always return the core's reported maximum resolution.
        // This provides a stable canvas that prevents zooming/cropping artifacts (like in PSP).
        size_t width  = _avInfo.geometry.max_width ?: 1024;
        size_t height = _avInfo.geometry.max_height ?: 1024;
        
        // Final protection: OpenEmu needs non-zero dimensions
        if (width == 0) width = 1024;
        if (height == 0) height = 1024;
        
        return OEIntSizeMake((int)width, (int)height);
    }
}

- (OEIntRect)screenRect {
    @synchronized(self) {
        int width  = _avInfo.geometry.base_width;
        int height = _avInfo.geometry.base_height;
        
        // Fallback to max dimensions if base is invalid
        if (width <= 0) width = 320;
        if (height <= 0) height = 240;
        
        // Always return from (0,0). OpenEmu's Metal renderer extracts the game from our Max-Canvas.
        return OEIntRectMake(0, 0, width, height);
    }
}

- (OEIntSize)aspectSize {
    @synchronized(self) {
        // OEGameCore.aspectSize is the *aspect ratio expressed as a size*
        // (e.g. (8,7) for NES, (4,3) for SNES) — not the pixel resolution.
        // Returning base_width × base_height directly produces incorrect
        // aspect on any system with non-square pixels.
        //
        // Prefer the core-reported aspect_ratio and snap to a small integer
        // pair via continued-fraction approximation. Fall back to base
        // dimensions only when aspect_ratio is unset (0 or NaN).
        float aspect = _avInfo.geometry.aspect_ratio;
        int baseW = (int)_avInfo.geometry.base_width;
        int baseH = (int)_avInfo.geometry.base_height;

        if (!isfinite(aspect) || aspect <= 0.0f) {
            if (baseW > 0 && baseH > 0) {
                aspect = (float)baseW / (float)baseH;
            } else {
                return OEIntSizeMake(4, 3);
            }
        }

        // Snap aspect to a small (num, den) pair with denominator ≤ 16.
        int bestNum = 4, bestDen = 3;
        float bestErr = INFINITY;
        for (int den = 1; den <= 16; den++) {
            int num = (int)lroundf(aspect * den);
            if (num <= 0) continue;
            float err = fabsf((float)num / (float)den - aspect);
            if (err < bestErr) {
                bestErr = err;
                bestNum = num;
                bestDen = den;
            }
        }
        return OEIntSizeMake(bestNum, bestDen);
    }
}

- (double)audioSampleRate {
    @synchronized(self) {
        return _avInfo.timing.sample_rate ?: 44100.0;
    }
}

- (double)frameDuration {
    @synchronized(self) {
        return _avInfo.timing.fps > 0 ? 1.0 / _avInfo.timing.fps : 1.0 / 60.0;
    }
}

#pragma mark - Save States

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void(^)(BOOL success, NSError *error))block {
    NSError *err = nil;
    NSData *data = [self serializeStateWithError:&err];
    if (!data) {
        if (block) block(NO, err);
        return;
    }
    NSError *writeErr = nil;
    BOOL ok = [data writeToFile:fileName options:NSDataWritingAtomic error:&writeErr];
    if (!ok) {
        NSLog(@"[OELibretro] Failed to save state to %@: %@", fileName, writeErr);
    }
    if (block) block(ok, writeErr);
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void(^)(BOOL success, NSError *error))block {
    NSError *readErr = nil;
    NSData *data = [NSData dataWithContentsOfFile:fileName options:0 error:&readErr];
    if (!data) {
        if (block) block(NO, readErr);
        return;
    }
    NSError *err = nil;
    BOOL ok = [self deserializeState:data withError:&err];
    if (block) block(ok, err);
}

- (NSData *)serializeStateWithError:(NSError **)error {
    if (!_retro_serialize_size || !_retro_serialize) {
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain
                                         code:OEGameCoreCouldNotSaveStateError
                                     userInfo:@{NSLocalizedDescriptionKey: @"This core does not support save states."}];
        }
        return nil;
    }

    if (self.serializationQuirks & RETRO_SERIALIZATION_QUIRK_INCOMPLETE) {
#if DEBUG
        NSLog(@"[OELibretro] Refusing to save state: core declared INCOMPLETE serialization.");
#endif
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain
                                         code:OEGameCoreCouldNotSaveStateError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Core declared incomplete serialization."}];
        }
        return nil;
    }

    // Cores that set CORE_VARIABLE_SIZE may report a different size between
    // calls; query immediately before each serialize to get the current value.
    size_t size = _retro_serialize_size();
    if (size == 0) {
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain
                                         code:OEGameCoreCouldNotSaveStateError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Core reported zero-size save state."}];
        }
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (!_retro_serialize(data.mutableBytes, size)) {
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain
                                         code:OEGameCoreCouldNotSaveStateError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Core failed to serialize save state."}];
        }
        return nil;
    }

#if DEBUG
    NSLog(@"[OELibretro] Save state serialized: %zu bytes", size);
#endif
    return data;
}

- (BOOL)deserializeState:(NSData *)state withError:(NSError **)error {
    if (!_retro_unserialize) {
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain
                                         code:OEGameCoreCouldNotLoadStateError
                                     userInfo:@{NSLocalizedDescriptionKey: @"This core does not support save states."}];
        }
        return NO;
    }

    if (!_retro_unserialize(state.bytes, state.length)) {
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain
                                         code:OEGameCoreCouldNotLoadStateError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Core failed to deserialize save state."}];
        }
        return NO;
    }

#if DEBUG
    NSLog(@"[OELibretro] Save state loaded: %lu bytes", (unsigned long)state.length);
#endif
    return YES;
}

- (uint32_t)pixelFormat {
    return _oePixelFormat;
}

- (uint32_t)pixelType {
    return _oePixelType;
}

- (NSInteger)bytesPerRow {
    return self.bufferSize.width * _bpp;
}

- (NSUInteger)channelCount {
    return 2;
}

- (const void *)getVideoBufferWithHint:(void *)hint {
    _oeBufferHint = hint;
    if (!hint && _videoBuffer) {
        // Hand back the core's most recent frame, then forget the pointer:
        // it's only valid for the duration of the libretro callback that
        // produced it, and OpenEmu mustn't read it twice.
        const void *frame = _videoBuffer;
        _videoBuffer = NULL;
        return frame;
    }
    // For the Metal renderer, we MUST return the hint to satisfy the direct rendering assertion.
    // We handle cores with internal buffers by copying the data in libretro_video_refresh_cb.
    return hint;
}

#pragma mark - Input: OELibretroInputReceiver
// These methods are the canonical input entry point for the bridge.
// System responders (OEGBASystemResponder, etc.) call these directly via
// the OEBridgeInputTranslation protocol. The per-system didPushXXXButton:
// methods below are fallback stubs that also route here — they fire only
// when a native (non-bridge) core somehow ends up loading through the
// translator, which should not happen in practice. If you update the
// button mapping in a system responder's kXXXLibretroMap[], verify the
// corresponding translator-side table (if any) stays consistent.

- (void)receiveLibretroButton:(uint8_t)buttonID forPort:(NSUInteger)port pressed:(BOOL)pressed {
    if (port < 4 && buttonID < 16) {
        atomic_store_explicit(&_buttonStates[port][buttonID], pressed ? 1 : 0, memory_order_relaxed);
    }
}

- (void)receiveLibretroAnalogIndex:(uint8_t)index axis:(uint8_t)axis value:(int16_t)value forPort:(NSUInteger)port {
    if (port < 4 && index < 2 && axis < 2) {
        atomic_store_explicit(&_analogStates[port][index][axis], value, memory_order_relaxed);
    }
}

#pragma mark - Input Stubs

- (void)didPushOEButton:(NSInteger)button forPlayer:(NSUInteger)player {
    uint8_t retroID = [self _retroButtonForOEButton:button];
    if (retroID != 0xFF) {
        [self receiveLibretroButton:retroID forPort:(player > 0 ? player - 1 : 0) pressed:YES];
    }
}

- (void)didReleaseOEButton:(NSInteger)button forPlayer:(NSUInteger)player {
    uint8_t retroID = [self _retroButtonForOEButton:button];
    if (retroID != 0xFF) {
        [self receiveLibretroButton:retroID forPort:(player > 0 ? player - 1 : 0) pressed:NO];
    }
}

- (uint8_t)_retroButtonForOEButton:(NSInteger)button {
    // Standard OpenEmu button order tends to match SNES-ish layout for simple digital pads.
    // However, the cleanest way to support multiple cores is to map based on the current system.
    
    if (self.isPSP) {
        // OEPSPButton mapping
        switch (button) {
            case 0:  return RETRO_DEVICE_ID_JOYPAD_UP;     // OEPSPButtonUp
            case 1:  return RETRO_DEVICE_ID_JOYPAD_DOWN;   // OEPSPButtonDown
            case 2:  return RETRO_DEVICE_ID_JOYPAD_LEFT;   // OEPSPButtonLeft
            case 3:  return RETRO_DEVICE_ID_JOYPAD_RIGHT;  // OEPSPButtonRight
            case 4:  return RETRO_DEVICE_ID_JOYPAD_X;      // OEPSPButtonTriangle
            case 5:  return RETRO_DEVICE_ID_JOYPAD_A;      // OEPSPButtonCircle
            case 6:  return RETRO_DEVICE_ID_JOYPAD_B;      // OEPSPButtonCross
            case 7:  return RETRO_DEVICE_ID_JOYPAD_Y;      // OEPSPButtonSquare
            case 8:  return RETRO_DEVICE_ID_JOYPAD_L;      // OEPSPButtonL1
            case 11: return RETRO_DEVICE_ID_JOYPAD_R;      // OEPSPButtonR1
            case 14: return RETRO_DEVICE_ID_JOYPAD_START;  // OEPSPButtonStart
            case 15: return RETRO_DEVICE_ID_JOYPAD_SELECT; // OEPSPButtonSelect
            default: return 0xFF;
        }
    }
    
    if (self.isSaturn) {
        // OESaturnButton mapping
        switch (button) {
            case 0: return RETRO_DEVICE_ID_JOYPAD_UP;     // OESaturnButtonUp
            case 1: return RETRO_DEVICE_ID_JOYPAD_DOWN;   // OESaturnButtonDown
            case 2: return RETRO_DEVICE_ID_JOYPAD_LEFT;   // OESaturnButtonLeft
            case 3: return RETRO_DEVICE_ID_JOYPAD_RIGHT;  // OESaturnButtonRight
            case 4: return RETRO_DEVICE_ID_JOYPAD_Y;      // OESaturnButtonA -> Y (Libretro Saturn layout)
            case 5: return RETRO_DEVICE_ID_JOYPAD_B;      // OESaturnButtonB -> B
            case 6: return RETRO_DEVICE_ID_JOYPAD_A;      // OESaturnButtonC -> A
            case 7: return RETRO_DEVICE_ID_JOYPAD_L;      // OESaturnButtonX -> L
            case 8: return RETRO_DEVICE_ID_JOYPAD_X;      // OESaturnButtonY -> X
            case 9: return RETRO_DEVICE_ID_JOYPAD_R;      // OESaturnButtonZ -> R
            case 10: return RETRO_DEVICE_ID_JOYPAD_L2;    // OESaturnButtonL -> L2
            case 11: return RETRO_DEVICE_ID_JOYPAD_R2;    // OESaturnButtonR -> R2
            case 12: return RETRO_DEVICE_ID_JOYPAD_START; // OESaturnButtonStart
            default: return 0xFF;
        }
    }

    // Default Fallback (SNES/Generic)
    switch (button) {
        case 0: return RETRO_DEVICE_ID_JOYPAD_UP;
        case 1: return RETRO_DEVICE_ID_JOYPAD_DOWN;
        case 2: return RETRO_DEVICE_ID_JOYPAD_LEFT;
        case 3: return RETRO_DEVICE_ID_JOYPAD_RIGHT;
        case 4: return RETRO_DEVICE_ID_JOYPAD_A;
        case 5: return RETRO_DEVICE_ID_JOYPAD_B;
        case 6: return RETRO_DEVICE_ID_JOYPAD_X;
        case 7: return RETRO_DEVICE_ID_JOYPAD_Y;
        case 8: return RETRO_DEVICE_ID_JOYPAD_L;
        case 9: return RETRO_DEVICE_ID_JOYPAD_R;
        case 10: return RETRO_DEVICE_ID_JOYPAD_START;
        case 11: return RETRO_DEVICE_ID_JOYPAD_SELECT;
        default: return 0xFF;
    }
}

#pragma mark - Speed Control

- (float)rate {
    return _current == self ? [super rate] : 1.0f;
}

- (OEGameCoreRendering)gameCoreRendering {
    if (self.isHW) {
        return OEGameCoreRenderingOpenGL3;
    }
    return OEGameCoreRenderingBitmap;
}

- (void)fastForwardAtSpeed:(CGFloat)speed {
    self.rate = (float)speed;
}

- (void)rewindAtSpeed:(CGFloat)speed {
    // Rewind is not implemented in the bridge; pause to avoid undefined negative rate.
    self.rate = 0;
}

- (void)slowMotionAtSpeed:(CGFloat)speed {
    self.rate = (float)speed;
}

#pragma mark - System Specific Responders
// Most systems use generic didPushOEButton: routing through _retroButtonForOEButton:.
// Systems with analog input or non-standard button orderings get dedicated lookup tables.

- (oneway void)didPushNESButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didReleaseNESButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

- (oneway void)didPushSNESButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didReleaseSNESButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

- (oneway void)didPushSaturnButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didReleaseSaturnButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

- (oneway void)didPushPSPButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didReleasePSPButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

- (oneway void)didPush7800Button:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didRelease7800Button:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

- (oneway void)didPushSMSButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didReleaseSMSButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

- (oneway void)didPushGGButton:(NSInteger)button {
    [self didPushOEButton:button forPlayer:1];
}
- (oneway void)didReleaseGGButton:(NSInteger)button {
    [self didReleaseOEButton:button forPlayer:1];
}

- (oneway void)didPushPSXButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didReleasePSXButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

- (oneway void)didPushColecoVisionButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didReleaseColecoVisionButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

- (oneway void)didPush5200Button:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didRelease5200Button:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

- (oneway void)didPushA8Button:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didReleaseA8Button:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

- (oneway void)didPushSega32XButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didReleaseSega32XButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

- (oneway void)didPushSegaCDButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didReleaseSegaCDButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

#pragma mark - OEGenesisSystemResponderClient (lookup table)

// OEGenesisButton enum: Up=0, Down=1, Left=2, Right=3, A=4, B=5, C=6, X=7, Y=8, Z=9, Start=10, Mode=11
static const uint8_t OEGenesisButtonToLibretro[] = {
    RETRO_DEVICE_ID_JOYPAD_UP,     // 0 Up
    RETRO_DEVICE_ID_JOYPAD_DOWN,   // 1 Down
    RETRO_DEVICE_ID_JOYPAD_LEFT,   // 2 Left
    RETRO_DEVICE_ID_JOYPAD_RIGHT,  // 3 Right
    RETRO_DEVICE_ID_JOYPAD_Y,      // 4 A → Y (genesis_plus_gx mapping)
    RETRO_DEVICE_ID_JOYPAD_B,      // 5 B → B
    RETRO_DEVICE_ID_JOYPAD_A,      // 6 C → A
    RETRO_DEVICE_ID_JOYPAD_L,      // 7 X → L
    RETRO_DEVICE_ID_JOYPAD_X,      // 8 Y → X
    RETRO_DEVICE_ID_JOYPAD_R,      // 9 Z → R
    RETRO_DEVICE_ID_JOYPAD_START,  // 10 Start
    RETRO_DEVICE_ID_JOYPAD_SELECT, // 11 Mode → Select
};
static const NSUInteger OEGenesisButtonCount = sizeof(OEGenesisButtonToLibretro) / sizeof(OEGenesisButtonToLibretro[0]);

- (oneway void)didPushGenesisButton:(NSInteger)button forPlayer:(NSUInteger)player {
    if ((NSUInteger)button < OEGenesisButtonCount) {
        [self receiveLibretroButton:OEGenesisButtonToLibretro[button] forPort:(player > 0 ? player - 1 : 0) pressed:YES];
    }
}
- (oneway void)didReleaseGenesisButton:(NSInteger)button forPlayer:(NSUInteger)player {
    if ((NSUInteger)button < OEGenesisButtonCount) {
        [self receiveLibretroButton:OEGenesisButtonToLibretro[button] forPort:(player > 0 ? player - 1 : 0) pressed:NO];
    }
}

#pragma mark - OEN64SystemResponderClient (lookup table + analog)

// OEN64Button enum: DPadUp=0..DPadRight=3, CUp=4..CRight=7, A=8, B=9, L=10, R=11, Z=12, Start=13, AnalogUp=14..AnalogRight=17
// Analog entries use 0xFF sentinel — handled separately in didMoveN64JoystickDirection:.
static const uint8_t OEN64ButtonToLibretro[] = {
    RETRO_DEVICE_ID_JOYPAD_UP,     // 0 DPadUp
    RETRO_DEVICE_ID_JOYPAD_DOWN,   // 1 DPadDown
    RETRO_DEVICE_ID_JOYPAD_LEFT,   // 2 DPadLeft
    RETRO_DEVICE_ID_JOYPAD_RIGHT,  // 3 DPadRight
    0xFF,                          // 4 CUp    (mapped as right-stick up)
    0xFF,                          // 5 CDown  (mapped as right-stick down)
    0xFF,                          // 6 CLeft  (mapped as right-stick left)
    0xFF,                          // 7 CRight (mapped as right-stick right)
    RETRO_DEVICE_ID_JOYPAD_A,      // 8 A
    RETRO_DEVICE_ID_JOYPAD_B,      // 9 B
    RETRO_DEVICE_ID_JOYPAD_L,      // 10 L
    RETRO_DEVICE_ID_JOYPAD_R,      // 11 R
    RETRO_DEVICE_ID_JOYPAD_L2,     // 12 Z → L2 (mupen64plus-next mapping)
    RETRO_DEVICE_ID_JOYPAD_START,  // 13 Start
    0xFF,                          // 14 AnalogUp
    0xFF,                          // 15 AnalogDown
    0xFF,                          // 16 AnalogLeft
    0xFF,                          // 17 AnalogRight
};
static const NSUInteger OEN64ButtonCount = sizeof(OEN64ButtonToLibretro) / sizeof(OEN64ButtonToLibretro[0]);

- (oneway void)didPushN64Button:(NSInteger)button forPlayer:(NSUInteger)player {
    if ((NSUInteger)button < OEN64ButtonCount && OEN64ButtonToLibretro[button] != 0xFF) {
        [self receiveLibretroButton:OEN64ButtonToLibretro[button] forPort:(player > 0 ? player - 1 : 0) pressed:YES];
    }
    // C-buttons as right analog stick digital presses
    NSUInteger port = player > 0 ? player - 1 : 0;
    switch (button) {
        case 4: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_Y value:-0x7FFF forPort:port]; break; // CUp
        case 5: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_Y value: 0x7FFF forPort:port]; break; // CDown
        case 6: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_X value:-0x7FFF forPort:port]; break; // CLeft
        case 7: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_X value: 0x7FFF forPort:port]; break; // CRight
        default: break;
    }
}
- (oneway void)didReleaseN64Button:(NSInteger)button forPlayer:(NSUInteger)player {
    if ((NSUInteger)button < OEN64ButtonCount && OEN64ButtonToLibretro[button] != 0xFF) {
        [self receiveLibretroButton:OEN64ButtonToLibretro[button] forPort:(player > 0 ? player - 1 : 0) pressed:NO];
    }
    NSUInteger port = player > 0 ? player - 1 : 0;
    switch (button) {
        case 4: case 5: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_Y value:0 forPort:port]; break;
        case 6: case 7: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_X value:0 forPort:port]; break;
        default: break;
    }
}

- (oneway void)didMoveN64JoystickDirection:(NSInteger)button withValue:(CGFloat)value forPlayer:(NSUInteger)player {
    NSUInteger port = player > 0 ? player - 1 : 0;
    int16_t scaledValue = (int16_t)(value * 0x7FFF);
    switch (button) {
        case 14: // AnalogUp
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_Y value:-scaledValue forPort:port];
            break;
        case 15: // AnalogDown
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_Y value:scaledValue forPort:port];
            break;
        case 16: // AnalogLeft
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_X value:-scaledValue forPort:port];
            break;
        case 17: // AnalogRight
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_X value:scaledValue forPort:port];
            break;
        default:
            break;
    }
}

#pragma mark - OEGBASystemResponderClient (lookup table)

// OEGBAButton enum: Up=0, Down=1, Left=2, Right=3, A=4, B=5, L=6, R=7, Start=8, Select=9
static const uint8_t OEGBAButtonToLibretro[] = {
    RETRO_DEVICE_ID_JOYPAD_UP,     // 0 Up
    RETRO_DEVICE_ID_JOYPAD_DOWN,   // 1 Down
    RETRO_DEVICE_ID_JOYPAD_LEFT,   // 2 Left
    RETRO_DEVICE_ID_JOYPAD_RIGHT,  // 3 Right
    RETRO_DEVICE_ID_JOYPAD_A,      // 4 A
    RETRO_DEVICE_ID_JOYPAD_B,      // 5 B
    RETRO_DEVICE_ID_JOYPAD_L,      // 6 L
    RETRO_DEVICE_ID_JOYPAD_R,      // 7 R
    RETRO_DEVICE_ID_JOYPAD_START,  // 8 Start
    RETRO_DEVICE_ID_JOYPAD_SELECT, // 9 Select
};
static const NSUInteger OEGBAButtonCount = sizeof(OEGBAButtonToLibretro) / sizeof(OEGBAButtonToLibretro[0]);

- (oneway void)didPushGBAButton:(NSInteger)button forPlayer:(NSUInteger)player {
    if ((NSUInteger)button < OEGBAButtonCount) {
        [self receiveLibretroButton:OEGBAButtonToLibretro[button] forPort:(player > 0 ? player - 1 : 0) pressed:YES];
    }
}
- (oneway void)didReleaseGBAButton:(NSInteger)button forPlayer:(NSUInteger)player {
    if ((NSUInteger)button < OEGBAButtonCount) {
        [self receiveLibretroButton:OEGBAButtonToLibretro[button] forPort:(player > 0 ? player - 1 : 0) pressed:NO];
    }
}

#pragma mark - OEGBSystemResponderClient (lookup table)

// OEGBButton enum: Up=0, Down=1, Left=2, Right=3, A=4, B=5, Start=6, Select=7
static const uint8_t OEGBButtonToLibretro[] = {
    RETRO_DEVICE_ID_JOYPAD_UP,     // 0
    RETRO_DEVICE_ID_JOYPAD_DOWN,   // 1
    RETRO_DEVICE_ID_JOYPAD_LEFT,   // 2
    RETRO_DEVICE_ID_JOYPAD_RIGHT,  // 3
    RETRO_DEVICE_ID_JOYPAD_A,      // 4
    RETRO_DEVICE_ID_JOYPAD_B,      // 5
    RETRO_DEVICE_ID_JOYPAD_START,  // 6
    RETRO_DEVICE_ID_JOYPAD_SELECT, // 7
};
static const NSUInteger OEGBButtonCount = sizeof(OEGBButtonToLibretro) / sizeof(OEGBButtonToLibretro[0]);

- (oneway void)didPushGBButton:(NSInteger)button {
    if ((NSUInteger)button < OEGBButtonCount) {
        [self receiveLibretroButton:OEGBButtonToLibretro[button] forPort:0 pressed:YES];
    }
}
- (oneway void)didReleaseGBButton:(NSInteger)button {
    if ((NSUInteger)button < OEGBButtonCount) {
        [self receiveLibretroButton:OEGBButtonToLibretro[button] forPort:0 pressed:NO];
    }
}

#pragma mark - OEDCSystemResponderClient (lookup table + analog)

// OEDCButton enum: Up=0, Down=1, Left=2, Right=3, A=4, B=5, X=6, Y=7,
// AnalogL=8, AnalogR=9, Start=10, AnalogUp=11, AnalogDown=12, AnalogLeft=13, AnalogRight=14
// Analog entries use 0xFF sentinel — handled separately in didMoveDCJoystickDirection:.
static const uint8_t OEDCButtonToLibretro[] = {
    RETRO_DEVICE_ID_JOYPAD_UP,     // 0
    RETRO_DEVICE_ID_JOYPAD_DOWN,   // 1
    RETRO_DEVICE_ID_JOYPAD_LEFT,   // 2
    RETRO_DEVICE_ID_JOYPAD_RIGHT,  // 3
    RETRO_DEVICE_ID_JOYPAD_A,      // 4
    RETRO_DEVICE_ID_JOYPAD_B,      // 5
    RETRO_DEVICE_ID_JOYPAD_X,      // 6
    RETRO_DEVICE_ID_JOYPAD_Y,      // 7
    0xFF,                          // 8  AnalogL (analog)
    0xFF,                          // 9  AnalogR (analog)
    RETRO_DEVICE_ID_JOYPAD_START,  // 10
    0xFF,                          // 11 AnalogUp (analog)
    0xFF,                          // 12 AnalogDown (analog)
    0xFF,                          // 13 AnalogLeft (analog)
    0xFF,                          // 14 AnalogRight (analog)
};
static const NSUInteger OEDCButtonCount = sizeof(OEDCButtonToLibretro) / sizeof(OEDCButtonToLibretro[0]);

- (oneway void)didPushDCButton:(NSInteger)button forPlayer:(NSUInteger)player {
    if ((NSUInteger)button >= OEDCButtonCount) return;
    uint8_t libretroID = OEDCButtonToLibretro[button];
    if (libretroID != 0xFF) {
        NSUInteger port = player > 0 ? player - 1 : 0;
        [self receiveLibretroButton:libretroID forPort:port pressed:YES];
    }
}

- (oneway void)didReleaseDCButton:(NSInteger)button forPlayer:(NSUInteger)player {
    if ((NSUInteger)button >= OEDCButtonCount) return;
    uint8_t libretroID = OEDCButtonToLibretro[button];
    if (libretroID != 0xFF) {
        NSUInteger port = player > 0 ? player - 1 : 0;
        [self receiveLibretroButton:libretroID forPort:port pressed:NO];
    }
}

- (oneway void)didMoveDCJoystickDirection:(NSInteger)button withValue:(CGFloat)value forPlayer:(NSUInteger)player {
    NSUInteger port = player > 0 ? player - 1 : 0;
    if (port >= 4) return;

    // Scale CGFloat value to libretro int16_t range.
    // Sticks: OE sends [-1.0, 1.0] -> libretro [-32768, 32767]
    // Triggers: OE sends [0.0, 1.0] -> libretro [0, 32767]
    int16_t scaled = (int16_t)(value * 32767.0);

    switch (button) {
        case 13: // OEDCAnalogLeft  -> X axis
            atomic_store_explicit(&_analogStates[port][RETRO_DEVICE_INDEX_ANALOG_LEFT][RETRO_DEVICE_ID_ANALOG_X], scaled, memory_order_relaxed);
            break;
        case 14: // OEDCAnalogRight -> X axis (right stick)
            atomic_store_explicit(&_analogStates[port][RETRO_DEVICE_INDEX_ANALOG_RIGHT][RETRO_DEVICE_ID_ANALOG_X], scaled, memory_order_relaxed);
            break;
        case 11: // OEDCAnalogUp    -> Y axis
            atomic_store_explicit(&_analogStates[port][RETRO_DEVICE_INDEX_ANALOG_LEFT][RETRO_DEVICE_ID_ANALOG_Y], scaled, memory_order_relaxed);
            break;
        case 12: // OEDCAnalogDown  -> Y axis
            atomic_store_explicit(&_analogStates[port][RETRO_DEVICE_INDEX_ANALOG_LEFT][RETRO_DEVICE_ID_ANALOG_Y], scaled, memory_order_relaxed);
            break;
        // Analog triggers — Flycast's libretro core actually supports true analog
        // L2/R2 via RETRO_DEVICE_ANALOG index 2, but our _analogStates array is
        // [4][2][2] (left/right stick only). Expanding to index 3 just for DC
        // triggers isn't worth the memory/complexity cost. Instead we digitize
        // the trigger: >50% threshold = pressed. This loses analog granularity
        // but is safe and functional for all bridge cores.
        case 8:  // OEDCAnalogL
            [self receiveLibretroButton:RETRO_DEVICE_ID_JOYPAD_L2 forPort:port pressed:(value > 0.5)];
            break;
        case 9:  // OEDCAnalogR
            [self receiveLibretroButton:RETRO_DEVICE_ID_JOYPAD_R2 forPort:port pressed:(value > 0.5)];
            break;
        default:
            break;
    }
}

#pragma mark - NDS Touch Responder

- (oneway void)didPushNDSButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didReleaseNDSButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

- (oneway void)didTouchScreenPoint:(OEIntPoint)point {
    _touchX = point.x;
    _touchY = point.y;
    _isTouching = YES;
}

- (oneway void)didReleaseTouch {
    _isTouching = NO;
}

#pragma mark - Mouse/Keyboard Stubs

- (void)mouseMovedAtPoint:(OEIntPoint)aPoint {}
- (void)leftMouseDownAtPoint:(OEIntPoint)aPoint {}
- (void)leftMouseUpAtPoint:(OEIntPoint)aPoint {}
- (void)rightMouseDownAtPoint:(OEIntPoint)aPoint {}
- (void)rightMouseUpAtPoint:(OEIntPoint)aPoint {}
- (void)keyDown:(unsigned short)keyCode characters:(NSString *)characters charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers flags:(NSEventModifierFlags)flags {}
- (void)keyUp:(unsigned short)keyCode characters:(NSString *)characters charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers flags:(NSEventModifierFlags)flags {}

@end
