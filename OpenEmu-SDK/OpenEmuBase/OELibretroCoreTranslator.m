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

// Flip to 1 to dump libretro audio plumbing to the unified log. Off by default —
// production logs are too chatty otherwise. Filter with:
//   log show --predicate 'process == "OpenEmuHelperApp"' --last 30s | grep "OELibretro/audio"
#ifndef OE_LIBRETRO_AUDIO_DEBUG
#define OE_LIBRETRO_AUDIO_DEBUG 0
#endif

#if OE_LIBRETRO_AUDIO_DEBUG
#define OE_AUDIO_LOG(fmt, ...) NSLog(@"[OELibretro/audio] " fmt, ##__VA_ARGS__)
#else
#define OE_AUDIO_LOG(fmt, ...) ((void)0)
#endif

// Not in the trimmed SDK libretro.h — defined upstream as (47 | 0x10000).
// Some cores skip producing audio if the host doesn't acknowledge this query.
#ifndef RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE
#define RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE (47 | 0x10000)
#endif

#ifndef RETRO_ENVIRONMENT_SET_ROTATION
#define RETRO_ENVIRONMENT_SET_ROTATION 1
#endif

NSString * const OELibretroBridgeVersion = @"4";


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

// Per-system policy is stored in the _policy ivar (see @implementation block).
// To add a new system, extend OELibretroSystemPolicyForSystemID() below.
@property (nonatomic, assign) retro_keyboard_event_t retroKeyboardEvent;

// Persistent path storage — NSString ivars keep the ObjC objects alive,
// and the corresponding char* ivars (strdup'd) are what we hand to cores.
// The libretro spec requires these pointers remain valid for the core's
// lifetime, and [NSString UTF8String] is only autorelease-pool-scoped.
@property (nonatomic, copy) NSString *biosPath;
@property (nonatomic, copy) NSString *savesPath;
@property (nonatomic, copy) NSString *supportPath;

// Defaults the core declared via SET_VARIABLES / SET_CORE_OPTIONS{,_V2,_INTL}.
// Populated as the core initialises; consulted on every GET_VARIABLE miss
// before falling back to the empty-string sentinel.
//
// Values are stored as NSData with nul-terminated UTF-8 bytes (rather than
// NSString) so we can hand the core a `const char *` whose lifetime tracks
// the dictionary entry's. -[NSString UTF8String] is autorelease-pool scoped
// and would race with the core caching the pointer across calls.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *declaredOptionDefaults;
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

// ---------------------------------------------------------------------------
// Per-system policy
// ---------------------------------------------------------------------------
// One value of this struct is built once per session in -loadFileAtPath: and
// consulted everywhere the host needs system-specific behaviour. To add a new
// system, add its static tables below and fill in the factory function.

typedef struct {
    const char *key;
    const char *value;
} OELibretroVariableDefault;

typedef struct {
    // If YES, any pixel format the core requests is overridden to XRGB8888.
    BOOL forceXRGB8888;

    // If YES, RETRO_ENVIRONMENT_SET_HW_RENDER is rejected so the core falls
    // back to its software renderer.
    BOOL rejectHWRender;

    // If YES, pointer Y is mapped to the bottom half of the screen
    // (NDS: top screen 0..191, touch screen 192..383).
    BOOL hasNDSTouchScreen;

    // Per-system core variable overrides. The host returns these before
    // falling back to the core's own declared defaults.
    const OELibretroVariableDefault *variableDefaults;
    NSUInteger variableDefaultCount;

    // Button map for -_retroButtonForOEButton:. NULL = use the generic
    // SNES-ish fallback. 0xFF = analog / unmapped button.
    const uint8_t *buttonMap;
    NSUInteger buttonMapCount;

    // When non-NULL, any variable key matching this prefix returns "100".
    // Used for Snes9x sndchan_volume keys that mute channels when empty.
    const char *sndchanVolumePrefix;
} OELibretroSystemPolicy;

// --- Button maps ------------------------------------------------------------
// OEPSPButton: Up=0 Down=1 Left=2 Right=3
//   AnalogUp=4..AnalogRight=7  (handled in didMovePSPJoystickDirection:)
//   Triangle=8 Circle=9 Cross=10 Square=11  L1=12 R1=13 Start=14 Select=15
static const uint8_t kPSPButtonMap[] = {
    [0]  = RETRO_DEVICE_ID_JOYPAD_UP,
    [1]  = RETRO_DEVICE_ID_JOYPAD_DOWN,
    [2]  = RETRO_DEVICE_ID_JOYPAD_LEFT,
    [3]  = RETRO_DEVICE_ID_JOYPAD_RIGHT,
    [4]  = 0xFF, // AnalogUp    → didMovePSPJoystickDirection:
    [5]  = 0xFF, // AnalogDown
    [6]  = 0xFF, // AnalogLeft
    [7]  = 0xFF, // AnalogRight
    [8]  = RETRO_DEVICE_ID_JOYPAD_X,      // Triangle
    [9]  = RETRO_DEVICE_ID_JOYPAD_A,      // Circle
    [10] = RETRO_DEVICE_ID_JOYPAD_B,      // Cross
    [11] = RETRO_DEVICE_ID_JOYPAD_Y,      // Square
    [12] = RETRO_DEVICE_ID_JOYPAD_L,      // L1
    [13] = RETRO_DEVICE_ID_JOYPAD_R,      // R1
    [14] = RETRO_DEVICE_ID_JOYPAD_START,
    [15] = RETRO_DEVICE_ID_JOYPAD_SELECT,
};

// OESaturnButton: Up=0 Down=1 Left=2 Right=3
//   A=4 B=5 C=6  X=7 Y=8 Z=9  L=10 R=11  Start=12
static const uint8_t kSaturnButtonMap[] = {
    [0]  = RETRO_DEVICE_ID_JOYPAD_UP,
    [1]  = RETRO_DEVICE_ID_JOYPAD_DOWN,
    [2]  = RETRO_DEVICE_ID_JOYPAD_LEFT,
    [3]  = RETRO_DEVICE_ID_JOYPAD_RIGHT,
    [4]  = RETRO_DEVICE_ID_JOYPAD_Y,      // A → Y (Libretro Saturn layout)
    [5]  = RETRO_DEVICE_ID_JOYPAD_B,      // B → B
    [6]  = RETRO_DEVICE_ID_JOYPAD_A,      // C → A
    [7]  = RETRO_DEVICE_ID_JOYPAD_L,      // X → L
    [8]  = RETRO_DEVICE_ID_JOYPAD_X,      // Y → X
    [9]  = RETRO_DEVICE_ID_JOYPAD_R,      // Z → R
    [10] = RETRO_DEVICE_ID_JOYPAD_L2,     // L → L2
    [11] = RETRO_DEVICE_ID_JOYPAD_R2,     // R → R2
    [12] = RETRO_DEVICE_ID_JOYPAD_START,
};

// --- Variable default tables ------------------------------------------------
static const OELibretroVariableDefault kN64VariableDefaults[] = {
    // GLideN64 — best-compat renderer on Apple Silicon.
    { "mupen64plus-rdp-plugin",                   "gliden64" },
    // GLideN64's threaded renderer needs a shared GL context we don't provide;
    // crashes in TextureCache::_addTexture without this.
    { "mupen64plus-ThreadedRenderer",             "False" },
    { "mupen64plus-MaxTxCacheSize",               "1500" },
    { "mupen64plus-txHiresEnable",                "False" },
    { "mupen64plus-EnableEnhancedTextureStorage", "False" },
    { "mupen64plus-EnableEnhancedHighResStorage", "False" },
    { "mupen64plus-EnableTextureCache",           "False" },
    { "mupen64plus-txCacheCompression",           "False" },
    { "mupen64plus-cpucore",                      "dynamic_recompiler" },
};

static const OELibretroVariableDefault kNDSVariableDefaults[] = {
    { "melonds_boot_directly",     "true" },
    // Threaded renderer needs a shared GL context we don't provide.
    { "melonds_threaded_renderer", "false" },
    { "desmume_jit_trust_unit",    "enabled" },
};

// Flycast uses both "reicast_" (legacy) and "flycast_" key prefixes.
static const OELibretroVariableDefault kDCVariableDefaults[] = {
    { "reicast_hle_bios",              "disabled" },
    { "reicast_fast_gd_rom_load",      "enabled" },
    { "flycast_fast_gd_rom_load",      "enabled" },
    // 2× native (640×480 → 1280×960) — good default for M-series Macs.
    { "reicast_internal_resolution",   "1280x960" },
    { "flycast_internal_resolution",   "1280x960" },
    // Threaded rendering needs a shared GL context we can't provide.
    { "reicast_threaded_rendering",    "disabled" },
    { "flycast_threaded_rendering",    "disabled" },
    // Frame-swap delay causes a CoreAudio deadlock — retro_run blocks waiting
    // for audio to drain, while the IO thread waits for retro_run to return.
    { "reicast_delay_frame_swapping",  "disabled" },
    // DSP adds audio sync points that worsen the CoreAudio deadlock risk.
    { "reicast_enable_dsp",            "disabled" },
};

static const OELibretroVariableDefault kC64VariableDefaults[] = {
    { "vice_c64_model",           "C64C PAL" }, // better late-era compatibility
    { "vice_drive_true_emulation","disabled" }, // faster loading
    { "vice_joyport",             "2" },         // standard for most C64 games
    { "vice_autostart",           "enabled" },
};

// PPSSPP: force software rendering — hardware path crashes on Apple Silicon
// due to incompatible threading in EmuThread + our single-context bridge.
static const OELibretroVariableDefault kPSPVariableDefaults[] = {
    { "ppsspp_backend",                     "SOFTWARE" },
    { "ppsspp_cpu_core",                    "jit" },
    { "ppsspp_rendering_mode",              "software" },
    { "ppsspp_threaded_rendering",          "disabled" },
    { "ppsspp_inflight_frames",             "1" },
    { "ppsspp_software_rendering",          "enabled" },
    { "ppsspp_gpu_disallow_shared_context", "enabled" },
    { "ppsspp_force_max_fps",              "enabled" },
};

// --- Factory function -------------------------------------------------------
// Returns the policy for the given OE system identifier string. Called once
// per session in -loadFileAtPath:. To add a new system, add a branch here
// (and static tables above if needed).
static OELibretroSystemPolicy OELibretroSystemPolicyForSystemID(NSString *systemID) {
#define ARRAY_COUNT(a) (sizeof(a) / sizeof((a)[0]))
    if ([systemID containsString:@"psp"]) {
        return (OELibretroSystemPolicy){
            .forceXRGB8888        = YES,
            .rejectHWRender       = YES,
            .variableDefaults     = kPSPVariableDefaults,
            .variableDefaultCount = ARRAY_COUNT(kPSPVariableDefaults),
            .buttonMap            = kPSPButtonMap,
            .buttonMapCount       = ARRAY_COUNT(kPSPButtonMap),
        };
    }
    if ([systemID containsString:@"nds"]) {
        return (OELibretroSystemPolicy){
            .hasNDSTouchScreen    = YES,
            .variableDefaults     = kNDSVariableDefaults,
            .variableDefaultCount = ARRAY_COUNT(kNDSVariableDefaults),
        };
    }
    if ([systemID containsString:@"dc"]) {
        return (OELibretroSystemPolicy){
            .variableDefaults     = kDCVariableDefaults,
            .variableDefaultCount = ARRAY_COUNT(kDCVariableDefaults),
        };
    }
    if ([systemID containsString:@"saturn"]) {
        return (OELibretroSystemPolicy){
            .buttonMap      = kSaturnButtonMap,
            .buttonMapCount = ARRAY_COUNT(kSaturnButtonMap),
        };
    }
    if ([systemID containsString:@"c64"]) {
        return (OELibretroSystemPolicy){
            .variableDefaults     = kC64VariableDefaults,
            .variableDefaultCount = ARRAY_COUNT(kC64VariableDefaults),
        };
    }
    if ([systemID containsString:@"n64"]) {
        return (OELibretroSystemPolicy){
            .variableDefaults     = kN64VariableDefaults,
            .variableDefaultCount = ARRAY_COUNT(kN64VariableDefaults),
        };
    }
    if ([systemID isEqualToString:@"openemu.system.snes"]) {
        return (OELibretroSystemPolicy){
            // snes9x_sndchan_volume_* keys use atoi(); an empty string returns 0
            // and mutes every channel. Return "100" for full per-channel volume.
            .sndchanVolumePrefix = "snes9x_sndchan_volume_",
        };
    }
    // No quirks for this system.
    return (OELibretroSystemPolicy){};
#undef ARRAY_COUNT
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
    void (*_retro_reset)(void);
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
    _Atomic(unsigned) _rotation;
    
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

    os_unfair_lock _avInfoLock;

    // Per-system policy — set once in -loadFileAtPath:, consulted everywhere
    // else. Adding a new system: extend OELibretroSystemPolicyForSystemID().
    OELibretroSystemPolicy _policy;
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

#pragma mark - Core option defaults

// Mirror what RetroArch does: when a core declares its options, capture
// (key, default_value) so we can hand the default back on GET_VARIABLE
// instead of the empty string. Empty / NULL values are skipped — see the
// Beetle PSX hang that motivated this whole layer for why "" is unsafe.
static void OEStoreOptionDefault(NSMutableDictionary<NSString *, NSData *> *dict,
                                 const char *key, const char *defaultValue, size_t defaultLen) {
    if (!dict || !key || !defaultValue || defaultLen == 0) return;
    NSString *k = [NSString stringWithUTF8String:key];
    if (!k) return;
    NSMutableData *d = [NSMutableData dataWithLength:defaultLen + 1];
    memcpy(d.mutableBytes, defaultValue, defaultLen);
    ((char *)d.mutableBytes)[defaultLen] = '\0';
    dict[k] = d;
}

static void OEStoreOptionDefaultCStr(NSMutableDictionary<NSString *, NSData *> *dict,
                                     const char *key, const char *defaultValue) {
    if (!defaultValue) return;
    OEStoreOptionDefault(dict, key, defaultValue, strlen(defaultValue));
}

// SET_VARIABLES (V0): value is "Description; default|other|third".
static void OEParseSetVariables(NSMutableDictionary<NSString *, NSData *> *dict,
                                const struct retro_variable *vars) {
    if (!vars) return;
    for (const struct retro_variable *v = vars; v->key != NULL; v++) {
        if (!v->value) continue;
        const char *semi = strchr(v->value, ';');
        if (!semi) continue;
        const char *p = semi + 1;
        while (*p == ' ' || *p == '\t') p++;
        const char *end = p;
        while (*end && *end != '|') end++;
        if (end == p) continue;
        OEStoreOptionDefault(dict, v->key, p, (size_t)(end - p));
    }
}

// SET_CORE_OPTIONS (V1).
static void OEParseCoreOptionsV1(NSMutableDictionary<NSString *, NSData *> *dict,
                                 const struct retro_core_option_definition *defs) {
    if (!defs) return;
    for (const struct retro_core_option_definition *d = defs; d->key != NULL; d++) {
        OEStoreOptionDefaultCStr(dict, d->key, d->default_value);
    }
}

// SET_CORE_OPTIONS_V2.
static void OEParseCoreOptionsV2(NSMutableDictionary<NSString *, NSData *> *dict,
                                 const struct retro_core_options_v2 *opts) {
    if (!opts || !opts->definitions) return;
    for (const struct retro_core_option_v2_definition *d = opts->definitions; d->key != NULL; d++) {
        OEStoreOptionDefaultCStr(dict, d->key, d->default_value);
    }
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
        case RETRO_ENVIRONMENT_SET_VARIABLES:
            if (_current) {
                if (!_current.declaredOptionDefaults) {
                    _current.declaredOptionDefaults = [NSMutableDictionary dictionary];
                }
                OEParseSetVariables(_current.declaredOptionDefaults,
                                    (const struct retro_variable *)data);
            }
            return true;
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS:
            if (_current) {
                if (!_current.declaredOptionDefaults) {
                    _current.declaredOptionDefaults = [NSMutableDictionary dictionary];
                }
                OEParseCoreOptionsV1(_current.declaredOptionDefaults,
                                     (const struct retro_core_option_definition *)data);
            }
            return true;
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:
            if (_current) {
                if (!_current.declaredOptionDefaults) {
                    _current.declaredOptionDefaults = [NSMutableDictionary dictionary];
                }
                OEParseCoreOptionsV2(_current.declaredOptionDefaults,
                                     (const struct retro_core_options_v2 *)data);
            }
            return true;
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL:
            // INTL wrapper: parse the English (.us) array — keys/defaults are
            // language-independent and OpenEmu doesn't surface translated labels.
            if (_current && data) {
                if (!_current.declaredOptionDefaults) {
                    _current.declaredOptionDefaults = [NSMutableDictionary dictionary];
                }
                const struct retro_core_options_intl *intl =
                    (const struct retro_core_options_intl *)data;
                OEParseCoreOptionsV1(_current.declaredOptionDefaults, intl->us);
            }
            return true;
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL:
            if (_current && data) {
                if (!_current.declaredOptionDefaults) {
                    _current.declaredOptionDefaults = [NSMutableDictionary dictionary];
                }
                const struct retro_core_options_v2_intl *intl =
                    (const struct retro_core_options_v2_intl *)data;
                OEParseCoreOptionsV2(_current.declaredOptionDefaults, intl->us);
            }
            return true;
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK:
            // Acknowledge but don't wire — we have no options UI to refresh.
            return true;
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
            if (data && _current) {
                enum retro_pixel_format format = *(enum retro_pixel_format *)data;
                
                // System policy may force XRGB8888 regardless of what the core requests
                // (e.g. PPSSPP: many builds default to 0RGB1555, causing black screens).
                if (_current->_policy.forceXRGB8888 && format != RETRO_PIXEL_FORMAT_XRGB8888) {
#if DEBUG
                    NSLog(@"[OELibretro] System policy: forcing XRGB8888 (core requested %d).", format);
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
        case RETRO_ENVIRONMENT_SET_ROTATION:
            if (data && _current) {
                unsigned rotation = (*(const unsigned *)data) & 3;
                atomic_store_explicit(&_current->_rotation, rotation, memory_order_release);
                _current.didClearSaturnBuffer = NO;
                _current.clearFramesRemaining = 3;
#if DEBUG
                NSLog(@"[OELibretro] Rotation updated: %u", rotation);
#endif
                return true;
            }
            return false;
        case RETRO_ENVIRONMENT_SET_GEOMETRY:
            if (data && _current) {
                const struct retro_game_geometry *geom = (const struct retro_game_geometry *)data;
                os_unfair_lock_lock(&_current->_avInfoLock);
                _current->_avInfo.geometry = *geom;
                os_unfair_lock_unlock(&_current->_avInfoLock);
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
                os_unfair_lock_lock(&_current->_avInfoLock);
                double oldRate = _current->_avInfo.timing.sample_rate;
                _current->_avInfo = *info;
                os_unfair_lock_unlock(&_current->_avInfoLock);
                double newRate = info->timing.sample_rate;
#if DEBUG
                NSLog(@"[OELibretro] AV Info updated: %dx%d @ %.2f fps, sample_rate=%.2f", info->geometry.base_width, info->geometry.base_height, info->timing.fps, newRate);
#endif
                OE_AUDIO_LOG(@"SET_SYSTEM_AV_INFO sample_rate %.2f -> %.2f%@",
                             oldRate, newRate,
                             (oldRate > 0 && fabs(oldRate - newRate) > 0.5) ? @" (CHANGED)" : @"");
                // If the core changed the sample rate after the host already
                // built its audio graph, notify the host so the AudioUnit can
                // reconfigure. Same pattern as MupenGameCore.m. Without this,
                // the AU stays at the old rate and audio plays at wrong pitch
                // or — if the buffer was sized for the old rate and the new
                // rate is much higher — drops to silence under starvation.
                if (newRate > 0 && oldRate > 0 && fabs(newRate - oldRate) > 0.5) {
                    [[_current audioDelegate] audioSampleRateDidChange];
                }
                return true;
            }
            break;
        case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE:
            // Bit 0 = audio enabled, bit 1 = video enabled, bit 2 = fast-savestates,
            // bit 3 = hard-disable audio. We always want audio + video.
            if (data) *(int *)data = (1 << 0) | (1 << 1);
            return true;
        case RETRO_ENVIRONMENT_SET_HW_RENDER:
            if (data && _current) {
                struct retro_hw_render_callback *hw = (struct retro_hw_render_callback *)data;
                
                // CRITICAL: Block hardware rendering for PSP. 
                // The current PPSSPP libretro nightly has a threading model that is incompatible with 
                // macOS OpenGL on Apple Silicon, leading to crashes in 'EmuThread'.
                // Returning false here forces the core to use its software renderer.
                if (_current->_policy.rejectHWRender) {
#if DEBUG
                    NSLog(@"[OELibretro] System policy: rejecting HW render request (forcing software mode).");
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

                // Per-system variable overrides — looked up from the policy table
                // set once in -loadFileAtPath:. To add overrides for a new system,
                // add a static table and extend OELibretroSystemPolicyForSystemID().
                for (NSUInteger i = 0; i < _current->_policy.variableDefaultCount; i++) {
                    if (strcmp(var->key, _current->_policy.variableDefaults[i].key) == 0) {
                        var->value = _current->_policy.variableDefaults[i].value;
                        return true;
                    }
                }

                // SNES sndchan volume prefix — "snes9x_sndchan_volume_*" keys are
                // parsed via atoi(); an empty string returns 0 and mutes the channel.
                if (_current->_policy.sndchanVolumePrefix) {
                    size_t prefixLen = strlen(_current->_policy.sndchanVolumePrefix);
                    if (strncmp(var->key, _current->_policy.sndchanVolumePrefix, prefixLen) == 0) {
                        var->value = "100";
                        return true;
                    }
                }

                // No per-system override matched. Next layer: the default the
                // core itself declared via SET_VARIABLES / SET_CORE_OPTIONS{,_V2}.
                // RetroArch behaves the same way; returning the declared default
                // is what unsticks Beetle PSX (its gpu_overclock=="" loops forever
                // because atoi("")==0, but atoi("1") short-circuits the shift).
                NSString *declaredKey = var->key ? [NSString stringWithUTF8String:var->key] : nil;
                NSData *declaredDefault = declaredKey ? _current.declaredOptionDefaults[declaredKey] : nil;
                if (declaredDefault) {
                    var->value = (const char *)declaredDefault.bytes;
                    return true;
                }

                // Last resort: empty string rather than NULL, so cores that
                // skip the null-check before strcmp() don't crash. Only fires
                // for keys the core never declared (rare; usually a core bug).
                var->value = "";
#if DEBUG
                NSLog(@"[OELibretro] Core queried variable: %s — no override and no declared default", var->key);
#endif
#if OE_LIBRETRO_AUDIO_DEBUG
                {
                    static os_unfair_lock keysLock = OS_UNFAIR_LOCK_INIT;
                    static const char *seenKeys[64] = {0};
                    static int seenKeyCount = 0;
                    os_unfair_lock_lock(&keysLock);
                    BOOL already = NO;
                    for (int i = 0; i < seenKeyCount; i++) {
                        if (strcmp(seenKeys[i], var->key) == 0) { already = YES; break; }
                    }
                    if (!already && seenKeyCount < 64) {
                        seenKeys[seenKeyCount++] = strdup(var->key);
                    }
                    os_unfair_lock_unlock(&keysLock);
                    if (!already) {
                        NSString *k = [NSString stringWithUTF8String:var->key ?: ""];
                        OE_AUDIO_LOG(@"GET_VARIABLE key=\"%@\" -> \"\" (no override)", k);
                    }
                }
#endif
            }
            return true;
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
            if (data) *(bool *)data = false;
            return true;
        case RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK:
            if (data && _current) {
                struct retro_keyboard_callback *kb = (struct retro_keyboard_callback *)data;
                _current->_retroKeyboardEvent = kb->callback;
                return true;
            }
            return false;
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
#if OE_LIBRETRO_AUDIO_DEBUG
            // One log per distinct command id so we see what cores are asking
            // for that we don't handle. Audio diagnoses often turn on something
            // like SET_AUDIO_CALLBACK or SET_FRAME_TIME_CALLBACK we're missing.
            {
                static os_unfair_lock seenLock = OS_UNFAIR_LOCK_INIT;
                static unsigned seen[16] = {0};
                static int seenCount = 0;
                os_unfair_lock_lock(&seenLock);
                BOOL already = NO;
                for (int i = 0; i < seenCount; i++) if (seen[i] == cmd) { already = YES; break; }
                if (!already && seenCount < 16) seen[seenCount++] = cmd;
                os_unfair_lock_unlock(&seenLock);
                if (!already) OE_AUDIO_LOG(@"unhandled env cmd %u (0x%x)", cmd, cmd);
            }
#endif
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

        // NEON path: process 32 pixels at a time (128 bytes of output).
        // Source layout 0RGB1555: 0RRRRRGGGGGBBBBB
        // Destination BGRA in little-endian memory: B, G, R, A
#if __arm64__
        uint16x8_t r_mask = vdupq_n_u16(0x7C00);
        uint16x8_t g_mask = vdupq_n_u16(0x03E0);
        uint16x8_t b_mask = vdupq_n_u16(0x001F);
        uint8x16_t a_vec  = vdupq_n_u8(0xFF);

        for (; x + 31 < width; x += 32) {
            // Load 32 pixels (64 bytes)
            uint16x8x4_t pixels = vld1q_u16_x4(s + x);

            // Process each 8-pixel chunk
            for (int i = 0; i < 4; i++) {
                uint16x8_t pix = pixels.val[i];
                uint16x8_t r_16 = vshrq_n_u16(vandq_u16(pix, r_mask), 10);
                uint16x8_t g_16 = vshrq_n_u16(vandq_u16(pix, g_mask), 5);
                uint16x8_t b_16 = vandq_u16(pix, b_mask);

                uint8x8_t r = vmovn_u16(vorrq_u16(vshlq_n_u16(r_16, 3), vshrq_n_u16(r_16, 2)));
                uint8x8_t g = vmovn_u16(vorrq_u16(vshlq_n_u16(g_16, 3), vshrq_n_u16(g_16, 2)));
                uint8x8_t b = vmovn_u16(vorrq_u16(vshlq_n_u16(b_16, 3), vshrq_n_u16(b_16, 2)));

                // Interleave to BGRA
                uint8x8x2_t bg = vzip_u8(b, g);
                uint8x8x2_t ra = vzip_u8(r, vget_low_u8(a_vec));

                uint16x4x2_t bgra0 = vzip_u16(vreinterpret_u16_u8(bg.val[0]), vreinterpret_u16_u8(ra.val[0]));
                uint16x4x2_t bgra1 = vzip_u16(vreinterpret_u16_u8(bg.val[1]), vreinterpret_u16_u8(ra.val[1]));

                vst1q_u32(d + x + (i * 8) + 0, vreinterpretq_u32_u16(vcombine_u16(bgra0.val[0], bgra0.val[1])));
                vst1q_u32(d + x + (i * 8) + 4, vreinterpretq_u32_u16(vcombine_u16(bgra1.val[0], bgra1.val[1])));
            }
        }

        // Remaining 8-pixel chunks (if any)
        for (; x + 7 < width; x += 8) {
            uint16x8_t pix = vld1q_u16(s + x);
            uint16x8_t r_16 = vshrq_n_u16(vandq_u16(pix, r_mask), 10);
            uint16x8_t g_16 = vshrq_n_u16(vandq_u16(pix, g_mask), 5);
            uint16x8_t b_16 = vandq_u16(pix, b_mask);

            uint8x8_t r = vmovn_u16(vorrq_u16(vshlq_n_u16(r_16, 3), vshrq_n_u16(r_16, 2)));
            uint8x8_t g = vmovn_u16(vorrq_u16(vshlq_n_u16(g_16, 3), vshrq_n_u16(g_16, 2)));
            uint8x8_t b = vmovn_u16(vorrq_u16(vshlq_n_u16(b_16, 3), vshrq_n_u16(b_16, 2)));

            uint8x8x2_t bg = vzip_u8(b, g);
            uint8x8x2_t ra = vzip_u8(r, vget_low_u8(a_vec));

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

        // NEON path: process 32 pixels at a time (128 bytes of output).
        // Source layout RGB565: RRRRRGGGGGGBBBBB
        // Destination BGRA in little-endian memory: B, G, R, A
#if __arm64__
        uint16x8_t r_mask = vdupq_n_u16(0xF800);
        uint16x8_t g_mask = vdupq_n_u16(0x07E0);
        uint16x8_t b_mask = vdupq_n_u16(0x001F);
        uint8x16_t a_vec  = vdupq_n_u8(0xFF);

        for (; x + 31 < width; x += 32) {
            // Load 32 pixels (64 bytes)
            uint16x8x4_t pixels = vld1q_u16_x4(s + x);

            // Process each 8-pixel chunk
            for (int i = 0; i < 4; i++) {
                uint16x8_t pix = pixels.val[i];
                uint16x8_t r_16 = vshrq_n_u16(vandq_u16(pix, r_mask), 11);
                uint16x8_t g_16 = vshrq_n_u16(vandq_u16(pix, g_mask), 5);
                uint16x8_t b_16 = vandq_u16(pix, b_mask);

                uint8x8_t r = vmovn_u16(vorrq_u16(vshlq_n_u16(r_16, 3), vshrq_n_u16(r_16, 2)));
                uint8x8_t g = vmovn_u16(vorrq_u16(vshlq_n_u16(g_16, 2), vshrq_n_u16(g_16, 4)));
                uint8x8_t b = vmovn_u16(vorrq_u16(vshlq_n_u16(b_16, 3), vshrq_n_u16(b_16, 2)));

                // Interleave to BGRA
                uint8x8x2_t bg = vzip_u8(b, g);
                uint8x8x2_t ra = vzip_u8(r, vget_low_u8(a_vec));

                uint16x4x2_t bgra0 = vzip_u16(vreinterpret_u16_u8(bg.val[0]), vreinterpret_u16_u8(ra.val[0]));
                uint16x4x2_t bgra1 = vzip_u16(vreinterpret_u16_u8(bg.val[1]), vreinterpret_u16_u8(ra.val[1]));

                vst1q_u32(d + x + (i * 8) + 0, vreinterpretq_u32_u16(vcombine_u16(bgra0.val[0], bgra0.val[1])));
                vst1q_u32(d + x + (i * 8) + 4, vreinterpretq_u32_u16(vcombine_u16(bgra1.val[0], bgra1.val[1])));
            }
        }

        // Remaining 8-pixel chunks (if any)
        for (; x + 7 < width; x += 8) {
            uint16x8_t pix = vld1q_u16(s + x);
            uint16x8_t r_16 = vshrq_n_u16(vandq_u16(pix, r_mask), 11);
            uint16x8_t g_16 = vshrq_n_u16(vandq_u16(pix, g_mask), 5);
            uint16x8_t b_16 = vandq_u16(pix, b_mask);

            uint8x8_t r = vmovn_u16(vorrq_u16(vshlq_n_u16(r_16, 3), vshrq_n_u16(r_16, 2)));
            uint8x8_t g = vmovn_u16(vorrq_u16(vshlq_n_u16(g_16, 2), vshrq_n_u16(g_16, 4)));
            uint8x8_t b = vmovn_u16(vorrq_u16(vshlq_n_u16(b_16, 3), vshrq_n_u16(b_16, 2)));

            uint8x8x2_t bg = vzip_u8(b, g);
            uint8x8x2_t ra = vzip_u8(r, vget_low_u8(a_vec));

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

static inline uint32_t OEVideoDecodePixelBGRA(const uint8_t *src, enum retro_pixel_format format) {
    switch (format) {
        case RETRO_PIXEL_FORMAT_0RGB1555: {
            uint16_t pix = *(const uint16_t *)src;
            uint32_t r = (pix >> 10) & 0x1F;
            uint32_t g = (pix >> 5)  & 0x1F;
            uint32_t b =  pix        & 0x1F;
            r = (r << 3) | (r >> 2);
            g = (g << 3) | (g >> 2);
            b = (b << 3) | (b >> 2);
            return 0xFF000000 | (r << 16) | (g << 8) | b;
        }
        case RETRO_PIXEL_FORMAT_RGB565: {
            uint16_t pix = *(const uint16_t *)src;
            uint32_t r = (pix >> 11) & 0x1F;
            uint32_t g = (pix >> 5)  & 0x3F;
            uint32_t b =  pix        & 0x1F;
            r = (r << 3) | (r >> 2);
            g = (g << 2) | (g >> 4);
            b = (b << 3) | (b >> 2);
            return 0xFF000000 | (r << 16) | (g << 8) | b;
        }
        case RETRO_PIXEL_FORMAT_XRGB8888:
            return *(const uint32_t *)src | 0xFF000000;
        default:
            return 0;
    }
}

static void OEVideoCopyRotated(const uint8_t *src, uint32_t *dst, unsigned width, unsigned height, size_t srcPitch, size_t dstPitchWords, enum retro_pixel_format format, unsigned rotation) {
    const size_t bytesPerPixel = (format == RETRO_PIXEL_FORMAT_XRGB8888) ? 4 : 2;

    for (unsigned y = 0; y < height; y++) {
        const uint8_t *srcRow = src + (y * srcPitch);
        for (unsigned x = 0; x < width; x++) {
            uint32_t pixel = OEVideoDecodePixelBGRA(srcRow + (x * bytesPerPixel), format);
            unsigned dstX = x;
            unsigned dstY = y;

            switch (rotation & 3) {
                case 1: // 90 degrees counter-clockwise per libretro API.
                    dstX = y;
                    dstY = width - 1 - x;
                    break;
                case 2:
                    dstX = width - 1 - x;
                    dstY = height - 1 - y;
                    break;
                case 3:
                    dstX = height - 1 - y;
                    dstY = x;
                    break;
                default:
                    break;
            }

            dst[(dstY * dstPitchWords) + dstX] = pixel;
        }
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
            
            unsigned rotation = atomic_load_explicit(&_current->_rotation, memory_order_acquire) & 3;
            unsigned outputWidth = (rotation == 1 || rotation == 3) ? height : width;
            unsigned outputHeight = (rotation == 1 || rotation == 3) ? width : height;

            // Safety Check: Avoid out-of-bounds writes if core resolution exceeds buffer
            if (outputWidth > destRowWords || outputHeight > bufferHeight) {
                if (rotation == 1 || rotation == 3) {
                    height = (unsigned)MIN(height, destRowWords);
                    width = (unsigned)MIN(width, bufferHeight);
                } else {
                    width = (unsigned)MIN(width, destRowWords);
                    height = (unsigned)MIN(height, bufferHeight);
                }
            }

            if (rotation != 0) {
                OEVideoCopyRotated((const uint8_t *)data, dst, width, height, pitch, destRowWords, _current.retroPixelFormat, rotation);
                return;
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

            if (handler && width <= 4096) {
                // Copy to (0,0) and let OpenEmu Metal handle centring the viewport.
                handler((const uint8_t *)data, dst, width, height, pitch, destRowWords);
            } else if (handler) {
                // Fallback for extreme resolutions (> 4K) to avoid SIMD overflows
                OEVideoCopyXRGB8888((const uint8_t *)data, dst, width, height, pitch, destRowWords);
            }
        }
    }
}

static void libretro_audio_sample_cb(int16_t left, int16_t right) {
    if (_current) {
#if OE_LIBRETRO_AUDIO_DEBUG
        static dispatch_once_t once;
        dispatch_once(&once, ^{ OE_AUDIO_LOG(@"first single-sample callback fired"); });
#endif
        int16_t samples[2] = {left, right};
        [[_current audioBufferAtIndex:0] write:samples maxLength:sizeof(samples)];
    }
}

static size_t libretro_audio_sample_batch_cb(const int16_t *data, size_t frames) {
    if (_current && data) {
#if OE_LIBRETRO_AUDIO_DEBUG
        static dispatch_once_t once;
        dispatch_once(&once, ^{ OE_AUDIO_LOG(@"first batch callback fired, frames=%zu", frames); });
        // Periodic amplitude sample so we can tell whether the core is
        // actually producing sound vs. handing us a silent buffer.
        static atomic_uint_fast64_t batchCount = 0;
        uint64_t n = atomic_fetch_add_explicit(&batchCount, 1, memory_order_relaxed);
        if (n < 5 || (n % 600) == 0) {
            int16_t mn = INT16_MAX, mx = INT16_MIN;
            size_t total = frames * 2;
            size_t step = total > 64 ? total / 64 : 1;
            for (size_t i = 0; i < total; i += step) {
                int16_t s = data[i];
                if (s < mn) mn = s;
                if (s > mx) mx = s;
            }
            OE_AUDIO_LOG(@"batch %llu frames=%zu sample min=%d max=%d", (unsigned long long)n, frames, mn, mx);
        }
#endif
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
                if (_current->_policy.hasNDSTouchScreen) {
                    // NDS: touch screen is the bottom half (Y 192..383 of a 384-line frame).
                    float yNorm = ([_current touchY] - 192.0) / 192.0;
                    if (yNorm < 0) yNorm = 0;
                    if (yNorm > 1) yNorm = 1;
                    return (int16_t)(yNorm * 65535 - 32768);
                } else {
                    // Generic pointer Y: full surface.
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
        atomic_store_explicit(&_rotation, 0, memory_order_relaxed);
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

    // ABI Sanity Check: Ensure our compiled layout matches the Libretro spec requirements
    // for Apple Silicon (64-byte hw_render_callback, 16-byte aligned pointers).
    if (sizeof(struct retro_hw_render_callback) != 64) {
        os_log_error(OE_LOG_DEFAULT, "[OELibretro] FATAL: ABI Mismatch detected! hw_render_callback size: %zu (Expected 64)", sizeof(struct retro_hw_render_callback));
    }

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
    
    // Build the per-system policy once — consulted throughout the session.
    // To add a new system, extend OELibretroSystemPolicyForSystemID().
    NSString *systemID = [self systemIdentifier];
    _policy = OELibretroSystemPolicyForSystemID(systemID);
    _isHW   = NO;  // Reset — core will re-request via SET_HW_RENDER if needed

    // Reset declared option defaults so a re-load doesn't carry stale entries
    // from a previous game/core into the new core's environment callbacks.
    self.declaredOptionDefaults = [NSMutableDictionary dictionary];

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
    RESOLVE(retro_reset);
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

        // Persistent diagnostic — small, useful when triaging "core X is silent"
        // reports. Records what the core declared at handshake time so we can
        // see immediately whether a later SET_SYSTEM_AV_INFO is changing things.
        NSLog(@"[OELibretro] AV handshake: %ux%u @ %.3f fps, sample_rate=%.2f Hz",
              _avInfo.geometry.base_width, _avInfo.geometry.base_height,
              _avInfo.timing.fps, _avInfo.timing.sample_rate);

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

- (void)resetEmulation {
    if (_retro_reset) _retro_reset();
}

- (void)startEmulation {
    [super startEmulation];
    
    _current = self;
    self.needsContextReset = YES;
}

- (OEIntSize)bufferSize {
    // High-Stability Strategy: Always return the core's reported maximum resolution.
    // This provides a stable canvas that prevents zooming/cropping artifacts (like in PSP).
    os_unfair_lock_lock(&_avInfoLock);
    size_t width  = _avInfo.geometry.max_width  ?: 1024;
    size_t height = _avInfo.geometry.max_height ?: 1024;
    os_unfair_lock_unlock(&_avInfoLock);
    unsigned rotation = atomic_load_explicit(&_rotation, memory_order_acquire) & 3;
    // Final protection: OpenEmu needs non-zero dimensions
    if (width == 0)  width  = 1024;
    if (height == 0) height = 1024;
    if (rotation == 1 || rotation == 3) {
        size_t tmp = width;
        width = height;
        height = tmp;
    }
    return OEIntSizeMake((int)width, (int)height);
}

- (OEIntRect)screenRect {
    os_unfair_lock_lock(&_avInfoLock);
    int width  = _avInfo.geometry.base_width;
    int height = _avInfo.geometry.base_height;
    os_unfair_lock_unlock(&_avInfoLock);
    unsigned rotation = atomic_load_explicit(&_rotation, memory_order_acquire) & 3;
    // Fallback to max dimensions if base is invalid
    if (width <= 0)  width  = 320;
    if (height <= 0) height = 240;
    if (rotation == 1 || rotation == 3) {
        int tmp = width;
        width = height;
        height = tmp;
    }
    // Always return from (0,0). OpenEmu's Metal renderer extracts the game from our Max-Canvas.
    return OEIntRectMake(0, 0, width, height);
}

- (OEIntSize)aspectSize {
    // OEGameCore.aspectSize is the *aspect ratio expressed as a size*
    // (e.g. (8,7) for NES, (4,3) for SNES) — not the pixel resolution.
    // Returning base_width × base_height directly produces incorrect
    // aspect on any system with non-square pixels.
    //
    // Prefer the core-reported aspect_ratio and snap to a small integer
    // pair via continued-fraction approximation. Fall back to base
    // dimensions only when aspect_ratio is unset (0 or NaN).
    os_unfair_lock_lock(&_avInfoLock);
    float aspect = _avInfo.geometry.aspect_ratio;
    int baseW = (int)_avInfo.geometry.base_width;
    int baseH = (int)_avInfo.geometry.base_height;
    os_unfair_lock_unlock(&_avInfoLock);
    unsigned rotation = atomic_load_explicit(&_rotation, memory_order_acquire) & 3;
    if (!isfinite(aspect) || aspect <= 0.0f) {
        if (baseW > 0 && baseH > 0) {
            aspect = (float)baseW / (float)baseH;
        } else {
            return OEIntSizeMake(4, 3);
        }
    }
    if ((rotation == 1 || rotation == 3) && aspect > 0.0f) {
        aspect = 1.0f / aspect;
    }

    // Snap aspect to a small (num, den) pair with denominator ≤ 16.
    int bestNum = 4, bestDen = 3;
    float bestErr = FLT_MAX;
    for (int den = 1; den <= 16; den++) {
        int num = (int)lroundf(aspect * den);
        if (num <= 0) continue;
        float err = fabsf((float)num / (float)den - aspect);
        if (err < bestErr) { bestErr = err; bestNum = num; bestDen = den; }
    }
    return OEIntSizeMake(bestNum, bestDen);
}

- (double)audioSampleRate {
    os_unfair_lock_lock(&_avInfoLock);
    double rate = _avInfo.timing.sample_rate ?: 44100.0;
    os_unfair_lock_unlock(&_avInfoLock);
#if OE_LIBRETRO_AUDIO_DEBUG
    static dispatch_once_t once;
    dispatch_once(&once, ^{ OE_AUDIO_LOG(@"audioSampleRate first read = %.2f", rate); });
#endif
    return rate;
}

- (double)frameDuration {
    os_unfair_lock_lock(&_avInfoLock);
    double fps = _avInfo.timing.fps;
    os_unfair_lock_unlock(&_avInfoLock);
    return fps > 0 ? 1.0 / fps : 1.0 / 60.0;
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
        atomic_store_explicit(&_buttonStates[port][buttonID], pressed ? 1 : 0, memory_order_release);
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
    // Use the per-system button map from the policy if one is set.
    // Each map entry is a RETRO_DEVICE_ID_JOYPAD_* value; 0xFF = analog/unmapped.
    // The generic SNES-ish layout is the fallback when no map is provided.
    if (_policy.buttonMap) {
        if ((NSUInteger)button < _policy.buttonMapCount) {
            return _policy.buttonMap[button];
        }
        return 0xFF; // out of range for this system's map
    }

    // Default fallback (SNES/generic layout).
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

#pragma mark - OEC64SystemResponderClient

// OEC64Button enum values must match OEC64SystemResponderClient.h:
// OEC64JoystickUp=0, Down=1, Left=2, Right=3, Fire=4, Jump=5, SwapJoysticks=6
static const uint8_t OEC64ButtonToLibretro[] = {
    RETRO_DEVICE_ID_JOYPAD_UP,    // OEC64JoystickUp    = 0
    RETRO_DEVICE_ID_JOYPAD_DOWN,  // OEC64JoystickDown  = 1
    RETRO_DEVICE_ID_JOYPAD_LEFT,  // OEC64JoystickLeft  = 2
    RETRO_DEVICE_ID_JOYPAD_RIGHT, // OEC64JoystickRight = 3
    RETRO_DEVICE_ID_JOYPAD_B,     // OEC64Fire          = 4
    RETRO_DEVICE_ID_JOYPAD_A,     // OEC64Jump          = 5
};

- (void)didPushC64Button:(NSInteger)button forPlayer:(NSUInteger)player {
    NSUInteger port = player > 0 ? player - 1 : 0;
    if (port >= 4 || (NSUInteger)button >= sizeof(OEC64ButtonToLibretro)) return;
    uint8_t btn = OEC64ButtonToLibretro[button];
    if (btn == 0xFF) return;
    atomic_store_explicit(&_buttonStates[port][btn], 1, memory_order_relaxed);
}

- (void)didReleaseC64Button:(NSInteger)button forPlayer:(NSUInteger)player {
    NSUInteger port = player > 0 ? player - 1 : 0;
    if (port >= 4 || (NSUInteger)button >= sizeof(OEC64ButtonToLibretro)) return;
    uint8_t btn = OEC64ButtonToLibretro[button];
    if (btn == 0xFF) return;
    atomic_store_explicit(&_buttonStates[port][btn], 0, memory_order_relaxed);
}

#pragma mark - OEArcadeSystemResponderClient

static const unsigned OERetroKeyTab = 9;
static const unsigned OERetroKeyF2  = 283;

// Standard 6-button arcade layout for FBA/MAME libretro cores.
// Buttons 1-3 are the top row (jab/strong/fierce), 4-6 the bottom (short/forward/roundhouse).
static const uint8_t OEArcadeButtonToLibretro[] = {
    RETRO_DEVICE_ID_JOYPAD_UP,     // OEArcadeButtonUp         = 0
    RETRO_DEVICE_ID_JOYPAD_DOWN,   // OEArcadeButtonDown       = 1
    RETRO_DEVICE_ID_JOYPAD_LEFT,   // OEArcadeButtonLeft       = 2
    RETRO_DEVICE_ID_JOYPAD_RIGHT,  // OEArcadeButtonRight      = 3
    RETRO_DEVICE_ID_JOYPAD_Y,      // OEArcadeButton1 (jab)    = 4
    RETRO_DEVICE_ID_JOYPAD_X,      // OEArcadeButton2 (strong) = 5
    RETRO_DEVICE_ID_JOYPAD_L,      // OEArcadeButton3 (fierce) = 6
    RETRO_DEVICE_ID_JOYPAD_B,      // OEArcadeButton4 (short)  = 7
    RETRO_DEVICE_ID_JOYPAD_A,      // OEArcadeButton5 (fwd)    = 8
    RETRO_DEVICE_ID_JOYPAD_R,      // OEArcadeButton6 (rhouse) = 9
    RETRO_DEVICE_ID_JOYPAD_START,  // OEArcadeButtonP1Start    = 10
    RETRO_DEVICE_ID_JOYPAD_SELECT, // OEArcadeButtonInsertCoin = 11
    0xFF,                          // OEArcadeButtonService    = 12
    0xFF,                          // OEArcadeUIConfigure      = 13
};

- (oneway void)didPushArcadeButton:(NSInteger)button forPlayer:(NSUInteger)player {
    if (button == 13) { // OEArcadeUIConfigure — MAME menu (TAB)
        if (_retroKeyboardEvent) _retroKeyboardEvent(true, OERetroKeyTab, 0, 0);
        return;
    }
    if (button == 12) { // OEArcadeButtonService — MAME service mode (F2)
        if (_retroKeyboardEvent) _retroKeyboardEvent(true, OERetroKeyF2, 0, 0);
        return;
    }

    NSUInteger port = player > 0 ? player - 1 : 0;
    if (port >= 4 || (NSUInteger)button >= sizeof(OEArcadeButtonToLibretro)) return;
    uint8_t btn = OEArcadeButtonToLibretro[button];
    if (btn == 0xFF) return;
    atomic_store_explicit(&_buttonStates[port][btn], 1, memory_order_relaxed);
}

- (oneway void)didReleaseArcadeButton:(NSInteger)button forPlayer:(NSUInteger)player {
    if (button == 13) { // OEArcadeUIConfigure — MAME menu (TAB)
        if (_retroKeyboardEvent) _retroKeyboardEvent(false, OERetroKeyTab, 0, 0);
        return;
    }
    if (button == 12) { // OEArcadeButtonService — MAME service mode (F2)
        if (_retroKeyboardEvent) _retroKeyboardEvent(false, OERetroKeyF2, 0, 0);
        return;
    }

    NSUInteger port = player > 0 ? player - 1 : 0;
    if (port >= 4 || (NSUInteger)button >= sizeof(OEArcadeButtonToLibretro)) return;
    uint8_t btn = OEArcadeButtonToLibretro[button];
    if (btn == 0xFF) return;
    atomic_store_explicit(&_buttonStates[port][btn], 0, memory_order_relaxed);
}

static unsigned OERetroKeyForMacVirtualKey(NSInteger keycode) {
    // Libretro keyboard callbacks use RETROK_* values, which mirror SDL 1.2
    // key symbols for common keys. OpenEmu hands us macOS virtual keycodes.
    switch (keycode) {
        case 36:  return 13;   // Return
        case 48:  return 9;    // Tab — opens MAME's internal menu.
        case 49:  return 32;   // Space
        case 51:  return 8;    // Delete / Backspace
        case 53:  return 27;   // Escape
        case 120: return OERetroKeyF2;
        case 123: return 276;  // Left
        case 124: return 275;  // Right
        case 125: return 274;  // Down
        case 126: return 273;  // Up
        default: break;
    }

    static const struct { NSInteger mac; unsigned retro; } letterMap[] = {
        {0, 'a'}, {11, 'b'}, {8, 'c'}, {2, 'd'}, {14, 'e'}, {3, 'f'},
        {5, 'g'}, {4, 'h'}, {34, 'i'}, {38, 'j'}, {40, 'k'}, {37, 'l'},
        {46, 'm'}, {45, 'n'}, {31, 'o'}, {35, 'p'}, {12, 'q'}, {15, 'r'},
        {1, 's'}, {17, 't'}, {32, 'u'}, {9, 'v'}, {13, 'w'}, {7, 'x'},
        {16, 'y'}, {6, 'z'},
    };
    for (NSUInteger i = 0; i < sizeof(letterMap) / sizeof(letterMap[0]); i++) {
        if (letterMap[i].mac == keycode) return letterMap[i].retro;
    }

    return (unsigned)keycode;
}

- (void)didPressKey:(NSInteger)keycode forPlayer:(NSUInteger)player {
    if (_retroKeyboardEvent) {
        _retroKeyboardEvent(true, OERetroKeyForMacVirtualKey(keycode), 0, 0);
    }
}

- (void)didReleaseKey:(NSInteger)keycode forPlayer:(NSUInteger)player {
    if (_retroKeyboardEvent) {
        _retroKeyboardEvent(false, OERetroKeyForMacVirtualKey(keycode), 0, 0);
    }
}

- (oneway void)keyDown:(NSUInteger)keyCode {
    [self didPressKey:(NSInteger)keyCode forPlayer:1];
}

- (oneway void)keyUp:(NSUInteger)keyCode {
    [self didReleaseKey:(NSInteger)keyCode forPlayer:1];
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

// OEPSXButton enum analog entries:
// 17 LeftAnalogUp, 18 LeftAnalogDown, 19 LeftAnalogLeft, 20 LeftAnalogRight,
// 21 RightAnalogUp, 22 RightAnalogDown, 23 RightAnalogLeft, 24 RightAnalogRight.
- (oneway void)didMovePSXJoystickDirection:(NSInteger)button withValue:(CGFloat)value forPlayer:(NSUInteger)player {
    NSUInteger port = player > 0 ? player - 1 : 0;
    int16_t scaledValue = (int16_t)(value * 0x7FFF);
    switch (button) {
        case 17: // LeftAnalogUp
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_Y value:-scaledValue forPort:port];
            break;
        case 18: // LeftAnalogDown
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_Y value:scaledValue forPort:port];
            break;
        case 19: // LeftAnalogLeft
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_X value:-scaledValue forPort:port];
            break;
        case 20: // LeftAnalogRight
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_X value:scaledValue forPort:port];
            break;
        case 21: // RightAnalogUp
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_Y value:-scaledValue forPort:port];
            break;
        case 22: // RightAnalogDown
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_Y value:scaledValue forPort:port];
            break;
        case 23: // RightAnalogLeft
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_X value:-scaledValue forPort:port];
            break;
        case 24: // RightAnalogRight
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_X value:scaledValue forPort:port];
            break;
        default:
            break;
    }
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

// The systems below have analog handlers above; their digital push/release
// handlers also need to exist to prevent the same unrecognized-selector
// crash on any face-button press. They route through the generic OE
// fallback — no verified per-system index mapping yet.

- (oneway void)didPushGCButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didReleaseGCButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

- (oneway void)didPushPS2Button:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didReleasePS2Button:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

- (oneway void)didPushVectrexButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didReleaseVectrexButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didReleaseOEButton:button forPlayer:player];
}

- (oneway void)didPushWiiButton:(NSInteger)button forPlayer:(NSUInteger)player {
    [self didPushOEButton:button forPlayer:player];
}
- (oneway void)didReleaseWiiButton:(NSInteger)button forPlayer:(NSUInteger)player {
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
            atomic_store_explicit(&_analogStates[port][RETRO_DEVICE_INDEX_ANALOG_LEFT][RETRO_DEVICE_ID_ANALOG_X], scaled, memory_order_release);
            break;
        case 14: // OEDCAnalogRight -> X axis (right stick)
            atomic_store_explicit(&_analogStates[port][RETRO_DEVICE_INDEX_ANALOG_RIGHT][RETRO_DEVICE_ID_ANALOG_X], scaled, memory_order_release);
            break;
        case 11: // OEDCAnalogUp    -> Y axis
            atomic_store_explicit(&_analogStates[port][RETRO_DEVICE_INDEX_ANALOG_LEFT][RETRO_DEVICE_ID_ANALOG_Y], scaled, memory_order_release);
            break;
        case 12: // OEDCAnalogDown  -> Y axis
            atomic_store_explicit(&_analogStates[port][RETRO_DEVICE_INDEX_ANALOG_LEFT][RETRO_DEVICE_ID_ANALOG_Y], scaled, memory_order_release);
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

#pragma mark - Analog Joystick Responders

// Each system's OE<Sys>SystemResponder calls didMove<Sys>JoystickDirection: on
// its client. If we don't implement the selector here, the call crashes the
// helper with "unrecognized selector sent to instance". Verified mappings
// route to receiveLibretroAnalogIndex:axis:value:forPort: (same pattern as
// N64/DC above). Systems whose RetroPad analog layout we haven't verified
// keep an empty stub so the selector exists.

- (oneway void)didMovePSPJoystickDirection:(NSInteger)button withValue:(CGFloat)value forPlayer:(NSUInteger)player {
    // OEPSPAnalog{Up,Down,Left,Right} = 4..7 -> RetroPad LEFT analog stick.
    NSUInteger port = player > 0 ? player - 1 : 0;
    int16_t scaled = (int16_t)(value * 0x7FFF);
    switch (button) {
        case 4: // OEPSPAnalogUp
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_Y value:-scaled forPort:port];
            break;
        case 5: // OEPSPAnalogDown
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_Y value:scaled forPort:port];
            break;
        case 6: // OEPSPAnalogLeft
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_X value:-scaled forPort:port];
            break;
        case 7: // OEPSPAnalogRight
            [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_X value:scaled forPort:port];
            break;
        default:
            break;
    }
}

- (oneway void)didMoveGCJoystickDirection:(NSInteger)button withValue:(CGFloat)value forPlayer:(NSUInteger)player {
    // OEGCAnalog{Up=4,Down=5,Left=6,Right=7}  -> LEFT stick
    // OEGCAnalogC{Up=8,Down=9,Left=10,Right=11} -> RIGHT (C) stick
    NSUInteger port = player > 0 ? player - 1 : 0;
    int16_t scaled = (int16_t)(value * 0x7FFF);
    switch (button) {
        case 4:  [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT  axis:RETRO_DEVICE_ID_ANALOG_Y value:-scaled forPort:port]; break;
        case 5:  [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT  axis:RETRO_DEVICE_ID_ANALOG_Y value: scaled forPort:port]; break;
        case 6:  [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT  axis:RETRO_DEVICE_ID_ANALOG_X value:-scaled forPort:port]; break;
        case 7:  [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT  axis:RETRO_DEVICE_ID_ANALOG_X value: scaled forPort:port]; break;
        case 8:  [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_Y value:-scaled forPort:port]; break;
        case 9:  [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_Y value: scaled forPort:port]; break;
        case 10: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_X value:-scaled forPort:port]; break;
        case 11: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_X value: scaled forPort:port]; break;
        default: break;
    }
}

- (oneway void)didMovePS2JoystickDirection:(NSInteger)button withValue:(CGFloat)value forPlayer:(NSUInteger)player {
    // OEPS2LeftAnalog{Up=17,Down=18,Left=19,Right=20}  -> LEFT
    // OEPS2RightAnalog{Up=21,Down=22,Left=23,Right=24} -> RIGHT
    NSUInteger port = player > 0 ? player - 1 : 0;
    int16_t scaled = (int16_t)(value * 0x7FFF);
    switch (button) {
        case 17: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT  axis:RETRO_DEVICE_ID_ANALOG_Y value:-scaled forPort:port]; break;
        case 18: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT  axis:RETRO_DEVICE_ID_ANALOG_Y value: scaled forPort:port]; break;
        case 19: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT  axis:RETRO_DEVICE_ID_ANALOG_X value:-scaled forPort:port]; break;
        case 20: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT  axis:RETRO_DEVICE_ID_ANALOG_X value: scaled forPort:port]; break;
        case 21: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_Y value:-scaled forPort:port]; break;
        case 22: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_Y value: scaled forPort:port]; break;
        case 23: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_X value:-scaled forPort:port]; break;
        case 24: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_RIGHT axis:RETRO_DEVICE_ID_ANALOG_X value: scaled forPort:port]; break;
        default: break;
    }
}

- (oneway void)didMoveSaturnJoystickDirection:(NSInteger)button withValue:(CGFloat)value forPlayer:(NSUInteger)player {
    // OESaturnLeftAnalog{Up=14,Down=15,Left=16,Right=17} -> LEFT stick.
    // AnalogL/AnalogR (18/19) are triggers — left as no-op pending verified mapping.
    NSUInteger port = player > 0 ? player - 1 : 0;
    int16_t scaled = (int16_t)(value * 0x7FFF);
    switch (button) {
        case 14: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_Y value:-scaled forPort:port]; break;
        case 15: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_Y value: scaled forPort:port]; break;
        case 16: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_X value:-scaled forPort:port]; break;
        case 17: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_X value: scaled forPort:port]; break;
        default: break;
    }
}

- (oneway void)didMoveVectrexJoystickDirection:(NSInteger)button withValue:(CGFloat)value forPlayer:(NSUInteger)player {
    // OEVectrexAnalog{Up=0,Down=1,Left=2,Right=3} -> LEFT analog stick.
    NSUInteger port = player > 0 ? player - 1 : 0;
    int16_t scaled = (int16_t)(value * 0x7FFF);
    switch (button) {
        case 0: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_Y value:-scaled forPort:port]; break;
        case 1: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_Y value: scaled forPort:port]; break;
        case 2: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_X value:-scaled forPort:port]; break;
        case 3: [self receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_LEFT axis:RETRO_DEVICE_ID_ANALOG_X value: scaled forPort:port]; break;
        default: break;
    }
}

- (oneway void)didMoveWiiJoystickDirection:(NSInteger)button withValue:(CGFloat)value forPlayer:(NSUInteger)player {
    // Wii — Nunchuk + Classic Controller analog sticks are not yet mapped to a
    // verified RetroPad layout. Stub exists so the selector call doesn't crash.
    (void)button; (void)value; (void)player;
}

#pragma mark - Mouse/Keyboard Stubs

- (void)mouseMovedAtPoint:(OEIntPoint)aPoint {}
- (void)leftMouseDownAtPoint:(OEIntPoint)aPoint {}
- (void)leftMouseUp {}
- (void)rightMouseDownAtPoint:(OEIntPoint)aPoint {}
- (void)rightMouseUp {}
- (void)keyDown:(unsigned short)keyCode characters:(NSString *)characters charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers flags:(NSEventModifierFlags)flags {}
- (void)keyUp:(unsigned short)keyCode characters:(NSString *)characters charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers flags:(NSEventModifierFlags)flags {}

#pragma mark - Responder safety net

// Recognise the well-known OE responder selector shapes so we can swallow
// calls to systems that this translator hasn't been wired up for yet.
// Without this, the first input event for an unhandled system crashes the
// helper with "unrecognized selector". Better: log once, drop the input,
// let the user discover the limitation themselves.
static BOOL OELibretroIsKnownResponderSelector(SEL sel) {
    NSString *name = NSStringFromSelector(sel);
    static NSArray<NSString *> *patterns = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        patterns = @[
            @"^didPush.+Button:forPlayer:$",
            @"^didRelease.+Button:forPlayer:$",
            @"^didPush.+Button:$",
            @"^didRelease.+Button:$",
            @"^didMove.+JoystickDirection:withValue:forPlayer:$",
            @"^did(Move|Trigger)LightGun.+",
            @"^didTouch.+",
            @"^didReleaseTouch.*",
            @"^did(Press|Release)Key:.+",
        ];
    });
    for (NSString *pat in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:0 error:NULL];
        if ([re numberOfMatchesInString:name options:0 range:NSMakeRange(0, name.length)] > 0) {
            return YES;
        }
    }
    return NO;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    NSMethodSignature *sig = [super methodSignatureForSelector:sel];
    if (sig) return sig;
    if (OELibretroIsKnownResponderSelector(sel)) {
        NSUInteger argCount = 2; // self + _cmd
        NSString *name = NSStringFromSelector(sel);
        for (NSUInteger i = 0; i < name.length; i++) {
            if ([name characterAtIndex:i] == ':') argCount++;
        }
        NSMutableString *types = [NSMutableString stringWithString:@"v@:"];
        for (NSUInteger i = 2; i < argCount; i++) [types appendString:@"@"];
        return [NSMethodSignature signatureWithObjCTypes:[types UTF8String]];
    }
    return nil;
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    SEL sel = invocation.selector;
    if (OELibretroIsKnownResponderSelector(sel)) {
        static os_log_t log = NULL;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ log = os_log_create("org.openemu.libretro", "responder"); });
        static NSMutableSet<NSString *> *logged = nil;
        static dispatch_once_t loggedOnce;
        dispatch_once(&loggedOnce, ^{ logged = [NSMutableSet set]; });
        NSString *name = NSStringFromSelector(sel);
        @synchronized (logged) {
            if (![logged containsObject:name]) {
                [logged addObject:name];
                os_log_info(log, "Unhandled responder selector dropped: %{public}@", name);
            }
        }
        return;
    }
    [super forwardInvocation:invocation];
}

@end
