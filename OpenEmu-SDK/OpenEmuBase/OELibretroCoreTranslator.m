// Copyright (c) 2026, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// ...

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <os/log.h>
#import "OELibretroCoreTranslator.h"
#import "OELibretroInputReceiver.h"
#import "OEGameCore.h"
#import "OERingBuffer.h"
#import "OEGeometry.h"
#import "OEGameCoreController.h"
#import "OELogging.h"
#import <dlfcn.h>
#import "libretro.h"
#import <Accelerate/Accelerate.h>
#import <arm_neon.h>

#pragma mark - Pixel Conversion Helpers

static inline uint32_t convert_0rgb1555_to_bgra8888(uint16_t pix) {
    uint32_t r = (pix >> 10) & 0x1F;
    uint32_t g = (pix >> 5) & 0x1F;
    uint32_t b = (pix >> 0) & 0x1F;
    r = (r << 3) | (r >> 2);
    g = (g << 3) | (g >> 2);
    b = (b << 3) | (b >> 2);
    // On Little Endian: Byte 0:B, 1:G, 2:R, 3:A
    return 0xFF000000 | (r << 16) | (g << 8) | b;
}

static inline uint32_t convert_rgb565_to_bgra8888(uint16_t pix) {
    uint32_t r = (pix >> 11) & 0x1F;
    uint32_t g = (pix >> 5) & 0x3F;
    uint32_t b = (pix >> 0) & 0x1F;
    r = (r << 3) | (r >> 2);
    g = (g << 2) | (g >> 4);
    b = (b << 3) | (b >> 2);
    return 0xFF000000 | (r << 16) | (g << 8) | b;
}

// Environment defines — values must match the official libretro.h exactly.
// See: https://github.com/libretro/libretro-common/blob/master/include/libretro.h
#define RETRO_ENVIRONMENT_GET_CAN_DUPE 3
#define RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY 9
#define RETRO_ENVIRONMENT_SET_PIXEL_FORMAT 10
#define RETRO_ENVIRONMENT_GET_VARIABLE 15
#define RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE 17
#define RETRO_ENVIRONMENT_GET_LOG_INTERFACE 27
#define RETRO_ENVIRONMENT_GET_CONTENT_DIRECTORY 30
#define RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY 31
#define RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO 32
#define RETRO_ENVIRONMENT_SET_GEOMETRY 37
#define RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION 52
#define RETRO_ENVIRONMENT_SET_CORE_OPTIONS 53
#define RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2 67
#define RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS 11
#define RETRO_ENVIRONMENT_SET_CONTROLLER_INFO 35
#define RETRO_ENVIRONMENT_SET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE 26

@interface OELibretroCoreTranslator () <OELibretroInputReceiver>
@property (nonatomic, strong) NSBundle *coreBundle;
@property (nonatomic, assign) enum retro_pixel_format retroPixelFormat;
@property (nonatomic, assign) BOOL didExplicitlySetPixelFormat;
@property (nonatomic, assign) BOOL didClearSaturnBuffer;
@property (nonatomic, assign) BOOL isBufferSizeLocked;
@property (nonatomic, assign) BOOL isHW;
@property (nonatomic, assign) BOOL needsContextReset;
@property (nonatomic, assign) int clearFramesRemaining;
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
@end

static __thread __unsafe_unretained OELibretroCoreTranslator *_current = nil;

struct retro_variable {
    const char *key;
    const char *value;
};

// Define Libretro log levels if missing
#ifndef RETRO_LOG_DEBUG
enum retro_log_level {
    RETRO_LOG_DEBUG = 0,
    RETRO_LOG_INFO  = 1,
    RETRO_LOG_WARN  = 2,
    RETRO_LOG_ERROR = 3,
    RETRO_LOG_DUMMY = 0x7fffffff
};
#endif

// HW Render Interface
#define RETRO_ENVIRONMENT_SET_HW_RENDER 14
#define RETRO_ENVIRONMENT_GET_HW_RENDER_INTERFACE 41
#define RETRO_HW_FRAME_BUFFER_VALID ((void*)-1)

enum retro_hw_context_type {
    RETRO_HW_CONTEXT_NONE             = 0,
    RETRO_HW_CONTEXT_OPENGL           = 1,
    RETRO_HW_CONTEXT_OPENGLES2        = 2,
    RETRO_HW_CONTEXT_OPENGL_CORE      = 3,
    RETRO_HW_CONTEXT_OPENGLES3        = 4,
    RETRO_HW_CONTEXT_OPENGLES_ANY     = 5,
    RETRO_HW_CONTEXT_VULKAN           = 6,
    RETRO_HW_CONTEXT_D3D9             = 7,
    RETRO_HW_CONTEXT_D3D10            = 8,
    RETRO_HW_CONTEXT_D3D11            = 9,
    RETRO_HW_CONTEXT_D3D12            = 10,
    RETRO_HW_CONTEXT_DUMMY            = 0x7fffffff
};

typedef void (*retro_hw_context_reset_t)(void);
typedef uintptr_t (*retro_hw_get_current_framebuffer_t)(void);
typedef void (*(*retro_hw_get_proc_address_t)(const char *sym))(void);

struct retro_hw_render_callback {
    enum retro_hw_context_type context_type;
    retro_hw_context_reset_t context_reset;
    retro_hw_get_current_framebuffer_t get_current_framebuffer;
    retro_hw_get_proc_address_t get_proc_address;
    
    // These must be bool to match the official libretro.h struct layout.
    // Using uint32_t shifted every field after them by 3 bytes each,
    // causing version_major/minor to be read from wrong offsets.
    bool depth;
    bool stencil;
    bool bottom_left_origin;
    unsigned version_major;
    unsigned version_minor;
    bool cache_context;
    retro_hw_context_reset_t context_destroy;
    bool debug_context;
};

// Define Libretro pixel formats if missing
#ifndef RETRO_PIXEL_FORMAT_0RGB1555
enum retro_pixel_format {
    RETRO_PIXEL_FORMAT_0RGB1555 = 0,
    RETRO_PIXEL_FORMAT_XRGB8888 = 1,
    RETRO_PIXEL_FORMAT_RGB565   = 2,
    RETRO_PIXEL_FORMAT_UNKNOWN  = 0x7fffffff
};
#endif

typedef void (*retro_log_printf_t)(enum retro_log_level level, const char *fmt, ...);
struct retro_log_callback { retro_log_printf_t log; };

// HW Callbacks
static void *_gl_handle = NULL;
typedef void (*glGetIntegerv_t)(uint32_t pname, int *params);

static void* get_gl_handle(void) {
    if (!_gl_handle) {
        _gl_handle = dlopen("/System/Library/Frameworks/OpenGL.framework/Versions/Current/OpenGL", RTLD_LAZY | RTLD_LOCAL);
    }
    return _gl_handle;
}

static uintptr_t libretro_get_current_framebuffer(void) {
    // 1. Ask OpenEmu's renderer for the authoritative FBO
    @autoreleasepool {
        if (_current && _current.renderDelegate) {
            id fb = _current.renderDelegate.presentationFramebuffer;
            if (fb && [fb isKindOfClass:[NSNumber class]]) {
                return (uintptr_t)[(NSNumber *)fb unsignedIntValue];
            }
        }
    }
    
    // 2. Fall back to querying the active CGL context
    void *gl = get_gl_handle();
    if (gl) {
        static glGetIntegerv_t _glGetIntegerv = NULL;
        if (!_glGetIntegerv) _glGetIntegerv = (glGetIntegerv_t)dlsym(gl, "glGetIntegerv");
        
        if (_glGetIntegerv) {
            int fbo = 0;
            _glGetIntegerv(0x8CA6, &fbo); // GL_FRAMEBUFFER_BINDING
            return (uintptr_t)fbo;
        }
    }
    return 0;
}

static void (*libretro_get_proc_address(const char *sym))(void) {
    if (!_current || !_current.isHW) return NULL;
    
    // First query actual OpenGL library, only fallback to global process symbols if missing
    void *gl = get_gl_handle();
    void *addr = NULL;
    if (gl) addr = dlsym(gl, sym);
    
    if (!addr) {
        addr = dlsym(RTLD_DEFAULT, sym);
    }
    
    if (addr) {
        // Log removed for Release
    } else {
        // Silent failure for Release - the caller will handle NULL
    }
    
    return (void(*)(void))addr;
}

// BIOS Audit Check
static BOOL verify_bios_files(NSString *biosPath, NSArray<NSString *> *files) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *file in files) {
        NSString *fullPath = [biosPath stringByAppendingPathComponent:file];
        if (![fm fileExistsAtPath:fullPath]) {
            return NO;
        }
    }
    return YES;
}

static void libretro_log_cb(enum retro_log_level level, const char *fmt, ...) {
#if DEBUG
    va_list args;
    va_start(args, fmt);
    char buffer[4096];
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    
    os_log_type_t logType = OS_LOG_TYPE_DEFAULT;
    const char *prefix = "[OELibretro]";
    
    switch (level) {
        case RETRO_LOG_DEBUG: 
            logType = OS_LOG_TYPE_DEBUG; 
            break;
        case RETRO_LOG_INFO:  
            logType = OS_LOG_TYPE_INFO;  
            prefix = "[OELibretro Core]";
            break;
        case RETRO_LOG_WARN:  
            logType = OS_LOG_TYPE_ERROR; 
            prefix = "[OELibretro Core Warning]";
            break;
        case RETRO_LOG_ERROR: 
            logType = OS_LOG_TYPE_FAULT; 
            prefix = "!!! [OELibretro Core Error]";
            break;
        default: 
            break;
    }
    
    os_log_with_type(OE_LOG_DEFAULT, logType, "%{public}s %{public}s", prefix, buffer);
#endif
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
    
    // Input state: 4 ports × 16 buttons (RETRO_DEVICE_JOYPAD)
    int16_t _buttonStates[4][16];
    // Analog state: 4 ports × 2 sticks (index) × 2 axes
    int16_t _analogStates[4][2][2];
    
    // Logging: Resolution tracking
    unsigned _lastWidth;
    unsigned _lastHeight;
}

+ (NSString *)libraryVersionForCoreAtURL:(NSURL *)url {
    void *handle = dlopen(url.path.UTF8String, RTLD_LAZY | RTLD_LOCAL);
    if (!handle) return nil;
    
    typedef struct {
        const char *library_name;
        const char *library_version;
        const char *valid_extensions;
        bool need_fullpath;
        bool block_extract;
    } retro_system_info;
    
    void (*get_info)(retro_system_info*) = dlsym(handle, "retro_get_system_info");
    NSString *version = nil;
    if (get_info) {
        retro_system_info info = {0};
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
            // This is used for BIOS/Firmware
            if (data && _current) {
                const char *path = [[_current biosDirectoryPath] UTF8String];
                *(const char **)data = path;
                NSLog(@"[OELibretro] Core requested System/BIOS directory: %s", path);
                fprintf(stderr, "[OELibretro] Providing System/BIOS: %s\n", path);
                return true;
            }
            break;
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
            if (data && _current) {
                const char *path = [[_current batterySavesDirectoryPath] UTF8String];
                *(const char **)data = path;
                NSLog(@"[OELibretro] Core requested Save/Battery directory: %s", path);
                fprintf(stderr, "[OELibretro] Providing Save/Battery: %s\n", path);
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
            if (data && _current) {
                *(const char **)data = [[_current supportDirectoryPath] UTF8String];
                return true;
            }
            break;
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
                    NSLog(@"[OELibretro] PSP requested format %d, but bridge is forcing XRGB8888 for stability.", format);
                    format = RETRO_PIXEL_FORMAT_XRGB8888;
                }

                _current.retroPixelFormat = format;
                _current.didExplicitlySetPixelFormat = YES;
                NSLog(@"[OELibretro] Core requested Pixel Format: %d", _current.retroPixelFormat);
                fprintf(stderr, "[OELibretro] Pixel Format: %d\n", _current.retroPixelFormat);
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
                NSLog(@"[OELibretro] Geometry updated: %dx%d (Aspect: %.2f)", geom->base_width, geom->base_height, geom->aspect_ratio);
                return true;
            }
            break;
        case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
            if (data && _current) {
                const struct retro_system_av_info *info = (const struct retro_system_av_info *)data;
                @synchronized(_current) {
                    _current->_avInfo = *info;
                }
                NSLog(@"[OELibretro] AV Info updated: %dx%d @ %.2f fps", info->geometry.base_width, info->geometry.base_height, info->timing.fps);
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
                    NSLog(@"[OELibretro] PSP requested HW rendering, but the bridge is REJECTING it to force stable software mode.");
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
                        NSLog(@"[OELibretro] REJECTED HW context type %d (Vulkan/D3D not supported). Core should fall back to GL.", hw->context_type);
                        fprintf(stderr, "[OELibretro] REJECTED HW context type %d\n", hw->context_type);
                        return false;
                }
                
                hw->get_current_framebuffer = libretro_get_current_framebuffer;
                hw->get_proc_address = libretro_get_proc_address;
                _current->_hw_callback = *hw;
                _current.isHW = YES;
                NSLog(@"[OELibretro] Accepted HW Rendering (Type: %d, Version: %u.%u)", hw->context_type, hw->version_major, hw->version_minor);
                return true;
            }
            break;
        case RETRO_ENVIRONMENT_GET_HW_RENDER_INTERFACE:
            // This command expects a retro_hw_render_interface (not retro_hw_render_callback).
            // We don't implement a render interface — return false so the core uses fallbacks.
            return false;
        case RETRO_ENVIRONMENT_SET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE:
            // Modern cores use this to request specific OpenGL versions.
            // We acknowledge it but let the existing context handle it.
            NSLog(@"[OELibretro] Core requested context negotiation interface.");
            return true;
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
                    // For MelonDS: Fix white screen when booting with FreeBIOS by forcing direct boot
                    if (strcmp(var->key, "melonds_boot_directly") == 0) {
                        var->value = "true";
                        return true;
                    }
                    if (strcmp(var->key, "melonds_threaded_renderer") == 0) {
                        var->value = "false";
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
                
                // DeSmuME Defaults
                if ([systemID containsString:@"nds"]) {
                    if (strcmp(var->key, "desmume_jit_trust_unit") == 0) {
                        var->value = "enabled";
                        return true;
                    }
                }
                
                // Flycast/Reicast Defaults (core uses 'reicast_' prefix)
                if ([systemID containsString:@"dc"]) {
                    if (strcmp(var->key, "reicast_hle_bios") == 0) {
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
                
                NSLog(@"[OELibretro] Core queried variable: %s (System: %s)", var->key, [systemID UTF8String]);
            }
            break;
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
            if (data) *(bool *)data = false;
            return true;
        default:
            break;
    }
    return false;
}

#pragma mark - Optimised Video Copy Handlers (Hot Path)

typedef void (*OEVideoCopyHandler)(const uint8_t *src, uint32_t *dst, unsigned width, unsigned height, size_t srcPitch, size_t dstPitchWords, BOOL swap);

static inline uint32_t convert_0rgb1555_to_bgra8888_optimized(uint16_t pix) {
    uint32_t r = (pix >> 10) & 0x1F;
    uint32_t g = (pix >> 5) & 0x1F;
    uint32_t b = (pix >> 0) & 0x1F;
    r = (r << 3) | (r >> 2);
    g = (g << 3) | (g >> 2);
    b = (b << 3) | (b >> 2);
    // BGRA Little Endian Memory: B, G, R, A
    return 0xFF000000 | (r << 16) | (g << 8) | b;
}

static inline uint32_t convert_rgb565_to_bgra8888_optimized(uint16_t pix) {
    uint32_t r = (pix >> 11) & 0x1F;
    uint32_t g = (pix >> 5) & 0x3F;
    uint32_t b = (pix >> 0) & 0x1F;
    r = (r << 3) | (r >> 2);
    g = (g << 2) | (g >> 4);
    b = (b << 3) | (b >> 2);
    return 0xFF000000 | (r << 16) | (g << 8) | b;
}

static void OEVideoCopy0RGB1555(const uint8_t *src, uint32_t *dst, unsigned width, unsigned height, size_t srcPitch, size_t dstPitchWords, BOOL swap) {
    const uint16_t *s_row = (const uint16_t *)src;
    uint32_t *d_row = dst;

    for (unsigned y = 0; y < height; y++) {
        const uint16_t *s = s_row;
        uint32_t *d = d_row;
        unsigned x = 0;

        // NEON path: process 8 pixels at a time
        for (; x + 7 < width; x += 8) {
            uint16x8_t pixels = vld1q_u16(s + x);
            
            uint16x8_t r_16, g_16, b_16;
            // Native 0RGB1555: 0RRRRRGGGGGBBBBB
            // We want BGRA in memory (Little Endian): Byte 0:B, 1:G, 2:R, 3:A
            
            if (swap) {
                // Core is providing BGR1555: 0BBBBBGGGGGRRRRR
                // Extract R from bits 0-4, B from 10-14
                r_16 = vandq_u16(pixels, vdupq_n_u16(0x1F));
                g_16 = vandq_u16(vshrq_n_u16(pixels, 5), vdupq_n_u16(0x1F));
                b_16 = vandq_u16(vshrq_n_u16(pixels, 10), vdupq_n_u16(0x1F));
            } else {
                // Extract R from bits 10-14, B from 0-4
                r_16 = vandq_u16(vshrq_n_u16(pixels, 10), vdupq_n_u16(0x1F));
                g_16 = vandq_u16(vshrq_n_u16(pixels, 5), vdupq_n_u16(0x1F));
                b_16 = vandq_u16(pixels, vdupq_n_u16(0x1F));
            }

            // Expand 5-bit to 8-bit: (x << 3) | (x >> 2)
            uint8x8_t r = vmovn_u16(vorrq_u16(vshlq_n_u16(r_16, 3), vshrq_n_u16(r_16, 2)));
            uint8x8_t g = vmovn_u16(vorrq_u16(vshlq_n_u16(g_16, 3), vshrq_n_u16(g_16, 2)));
            uint8x8_t b = vmovn_u16(vorrq_u16(vshlq_n_u16(b_16, 3), vshrq_n_u16(b_16, 2)));
            uint8x8_t a = vdup_n_u8(0xFF);

            // Interleave into BGRA pattern (Byte 0:B, 1:G, 2:R, 3:A)
            uint8x8x2_t bg = vzip_u8(b, g);
            uint8x8x2_t ra = vzip_u8(r, a);

            uint16x4x2_t bgra0 = vzip_u16(vreinterpret_u16_u8(bg.val[0]), vreinterpret_u16_u8(ra.val[0]));
            uint16x4x2_t bgra1 = vzip_u16(vreinterpret_u16_u8(bg.val[1]), vreinterpret_u16_u8(ra.val[1]));

            vst1q_u32(d + x + 0, vreinterpretq_u32_u16(vcombine_u16(bgra0.val[0], bgra0.val[1])));
            vst1q_u32(d + x + 4, vreinterpretq_u32_u16(vcombine_u16(bgra1.val[0], bgra1.val[1])));
        }

        // Scalar fallback
        for (; x < width; x++) {
            uint16_t pix = s[x];
            uint32_t r_val, g_val, b_val;
            if (swap) {
                // Treat input as BGR1555
                b_val = (pix >> 10) & 0x1F;
                g_val = (pix >> 5) & 0x1F;
                r_val = pix & 0x1F;
            } else {
                // Treat input as RGB1555
                r_val = (pix >> 10) & 0x1F;
                g_val = (pix >> 5) & 0x1F;
                b_val = pix & 0x1F;
            }
            r_val = (r_val << 3) | (r_val >> 2);
            g_val = (g_val << 3) | (g_val >> 2);
            b_val = (b_val << 3) | (b_val >> 2);
            // In little-endian d[x] is stored as Byte 0:B, 1:G, 2:R, 3:A
            d[x] = 0xFF000000 | (r_val << 16) | (g_val << 8) | b_val;
        }

        s_row = (const uint16_t *)((const uint8_t *)s_row + srcPitch);
        d_row += dstPitchWords;
    }
}

static void OEVideoCopyRGB565(const uint8_t *src, uint32_t *dst, unsigned width, unsigned height, size_t srcPitch, size_t dstPitchWords, BOOL swap) {
    const uint16_t *s_line = (const uint16_t *)src;
    uint32_t *d_line = dst;

    for (unsigned y = 0; y < height; y++) {
        const uint16_t *s = s_line;
        uint32_t *d = d_line;
        unsigned x = 0;

        // NEON path: process 8 pixels at a time
        for (; x + 7 < width; x += 8) {
            uint16x8_t pixels = vld1q_u16(s + x);
            
            uint16x8_t r_16, g_16, b_16;
            // Native RGB565: RRRRRGGGGGGBBBBB
            
            if (swap) {
                // Core is providing BGR565: BBBBBGGGGGGRRRRR
                b_16 = vandq_u16(vshrq_n_u16(pixels, 11), vdupq_n_u16(0x1F));
                g_16 = vandq_u16(vshrq_n_u16(pixels, 5), vdupq_n_u16(0x3F));
                r_16 = vandq_u16(pixels, vdupq_n_u16(0x1F));
            } else {
                r_16 = vandq_u16(vshrq_n_u16(pixels, 11), vdupq_n_u16(0x1F));
                g_16 = vandq_u16(vshrq_n_u16(pixels, 5), vdupq_n_u16(0x3F));
                b_16 = vandq_u16(pixels, vdupq_n_u16(0x1F));
            }

            // Expand components to 8-bit
            // R: (x << 3) | (x >> 2)
            uint8x8_t r = vmovn_u16(vorrq_u16(vshlq_n_u16(r_16, 3), vshrq_n_u16(r_16, 2)));
            // G: (x << 2) | (x >> 4) -- 6-bit to 8-bit
            uint8x8_t g = vmovn_u16(vorrq_u16(vshlq_n_u16(g_16, 2), vshrq_n_u16(g_16, 4)));
            // B: (x << 3) | (x >> 2)
            uint8x8_t b = vmovn_u16(vorrq_u16(vshlq_n_u16(b_16, 3), vshrq_n_u16(b_16, 2)));
            uint8x8_t a = vdup_n_u8(0xFF);

            // Interleave into BGRA pattern (Byte 0:B, 1:G, 2:R, 3:A)
            uint8x8x2_t bg = vzip_u8(b, g);
            uint8x8x2_t ra = vzip_u8(r, a);

            uint16x4x2_t bgra0 = vzip_u16(vreinterpret_u16_u8(bg.val[0]), vreinterpret_u16_u8(ra.val[0]));
            uint16x4x2_t bgra1 = vzip_u16(vreinterpret_u16_u8(bg.val[1]), vreinterpret_u16_u8(ra.val[1]));

            vst1q_u32(d + x + 0, vreinterpretq_u32_u16(vcombine_u16(bgra0.val[0], bgra0.val[1])));
            vst1q_u32(d + x + 4, vreinterpretq_u32_u16(vcombine_u16(bgra1.val[0], bgra1.val[1])));
        }

        // Scalar fallback
        for (; x < width; x++) {
            uint16_t pix = s[x];
            uint32_t r_val, g_val, b_val;
            if (swap) {
                b_val = (pix >> 11) & 0x1F;
                g_val = (pix >> 5) & 0x3F;
                r_val = pix & 0x1F;
            } else {
                r_val = (pix >> 11) & 0x1F;
                g_val = (pix >> 5) & 0x3F;
                b_val = pix & 0x1F;
            }
            r_val = (r_val << 3) | (r_val >> 2);
            g_val = (g_val << 2) | (g_val >> 4);
            b_val = (b_val << 3) | (b_val >> 2);
            d[x] = 0xFF000000 | (r_val << 16) | (g_val << 8) | b_val;
        }

        s_line = (const uint16_t *)((const uint8_t *)s_line + srcPitch);
        d_line += dstPitchWords;
    }
}

static void OEVideoCopyXRGB8888(const uint8_t *src, uint32_t *dst, unsigned width, unsigned height, size_t srcPitch, size_t dstPitchWords, BOOL swap) {
    // Libretro XRGB8888 (Little Endian words 0xRRGGBB) are natively identical to BGRA in memory (B, G, R, X).
    // Row-by-row memcpy is the most stable and performant restoration path.
    for (unsigned y = 0; y < height; y++) {
        memcpy(dst + (y * dstPitchWords), src + (y * srcPitch), width * 4);
    }
}

static void libretro_video_refresh_cb(const void *data, unsigned width, unsigned height, size_t pitch) {
    if (data && _current) {
        if (width != _current->_lastWidth || height != _current->_lastHeight) {
            NSLog(@"[OELibretro] Resolution change detected: %ux%u (Pitch: %zu)", width, height, pitch);
            fprintf(stderr, "[OELibretro] Resolution change: %ux%u (Pitch: %zu)\n", width, height, pitch);
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
                NSLog(@"[OELibretro] WARNING: Core resolution %dx%d exceeds window buffer %zux%zu. Clipping to safety.", width, height, destRowWords, bufferHeight);
                width = (unsigned)MIN(width, destRowWords);
                height = (unsigned)MIN(height, bufferHeight);
            }

            OEVideoCopyHandler handler = NULL;
            switch (_current.retroPixelFormat) {
                case RETRO_PIXEL_FORMAT_0RGB1555: handler = OEVideoCopy0RGB1555; break;
                case RETRO_PIXEL_FORMAT_RGB565:   handler = OEVideoCopyRGB565;   break;
                case RETRO_PIXEL_FORMAT_XRGB8888: handler = OEVideoCopyXRGB8888; break;
                default: break;
            }
            
            if (handler) {
                // Copy to (0,0) and let OpenEmu Metal handle centering of the viewport.
                // No R/B swap — the pixel conversion functions handle format correctly.
                handler((const uint8_t *)data, dst, width, height, pitch, destRowWords, NO);
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
                return _current->_buttonStates[port][id];
            }
            return 0;
        case RETRO_DEVICE_ANALOG:
            // Analog sticks: index 0 = left stick, 1 = right stick; id 0 = X, 1 = Y.
            if (port < 4 && index < 2 && id < 2) {
                return _current->_analogStates[port][index][id];
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

static void* bridge_dlsym(void *handle, const char *symbol) {
    void *ptr = dlsym(handle, symbol);
    if (!ptr) {
        // Try with leading underscore (fallback for some macOS builds)
        char fallback[512];
        snprintf(fallback, sizeof(fallback), "_%s", symbol);
        ptr = dlsym(handle, fallback);
    }
    return ptr;
}

- (instancetype)init {
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
    }
    return self;
}

- (void)dealloc {
    if (_current == self) _current = nil;
    if (_coreHandle) {
        if (_retro_deinit) _retro_deinit();
        dlclose(_coreHandle);
    }
}

#pragma mark - OEGameCore Overrides

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error {
    _current = self;
    self.coreBundle = [[self owner] bundle];
    NSString *corePath = [[self coreBundle] objectForInfoDictionaryKey:@"OELibretroCorePath"];
    
    if (!corePath) {
        corePath = [self.coreBundle executablePath];
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
    
    NSLog(@"[OELibretro] System: %@ | Flags: PSP=%d NDS=%d DC=%d Saturn=%d N64=%d",
          systemID, _isPSP, _isNDS, _isDC, _isSaturn, _isN64);
    
    // Trust the core to set its own pixel format via RETRO_ENVIRONMENT_SET_PIXEL_FORMAT.
    // The Libretro spec default (0RGB1555) is set in -init; the core overrides it
    // during retro_set_environment or retro_init via the environment callback.
    
    _cachedMaxWidth = 0; 
    _cachedMaxHeight = 0;

    NSLog(@"[OELibretro] Attempting to load core from: %@", corePath);
    fprintf(stderr, "[OELibretro] Loading core: %s\n", [corePath UTF8String]);
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:corePath]) {
        NSLog(@"[OELibretro] Core file NOT found at path!");
        fprintf(stderr, "[OELibretro] ERROR: Core file missing at %s\n", [corePath UTF8String]);
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Libretro core not found at %@", corePath]}];
        }
        return NO;
    }
    
    _coreHandle = dlopen([corePath UTF8String], RTLD_LAZY | RTLD_LOCAL);
    if (!_coreHandle) {
        const char *err = dlerror();
        NSLog(@"[OELibretro] dlopen failed: %s", err ?: "unknown error");
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to load libretro core: %s", err ?: "unknown error"]}];
        }
        return NO;
    }
    
    // Resolve all mandatory symbols with fallback and logging
    #define RESOLVE(name) _##name = bridge_dlsym(_coreHandle, #name); \
        if (!_##name) NSLog(@"[OELibretro] CRITICAL: Symbol %s not found!", #name); \
        else NSLog(@"[OELibretro] Core symbol resolved: %s", #name);
    
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
    
    // Safety check for absolute minimum required to function
    if (!_retro_init || !_retro_run || !_retro_load_game) {
        NSLog(@"[OELibretro] Aborting: Essential Libretro symbols are missing.");
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{NSLocalizedDescriptionKey: @"Core is missing essential Libretro functions."}];
        }
        dlclose(_coreHandle);
        _coreHandle = NULL;
        return NO;
    }
    
    // Register callbacks
    _retro_set_environment(libretro_environment_cb);
    _retro_set_video_refresh(libretro_video_refresh_cb);
    _retro_set_audio_sample(libretro_audio_sample_cb);
    _retro_set_audio_sample_batch(libretro_audio_sample_batch_cb);
    _retro_set_input_poll(libretro_input_poll_cb);
    _retro_set_input_state(libretro_input_state_cb);
    
    NSLog(@"[OELibretro] Calling retro_init()...");
    _retro_init();
    
    // BIOS Verification Stage
    NSString *biosPath = [self biosDirectoryPath];
    NSLog(@"[OELibretro] BIOS Directory: %@", biosPath);
    
    NSString *errorMsg = nil;
    if ([systemID containsString:@"dc"]) {
        if (!verify_bios_files(biosPath, @[@"dc_boot.bin", @"dc_flash.bin"])) {
             errorMsg = @"Dreamcast requires dc_boot.bin and dc_flash.bin in your BIOS folder.";
        }
    } else if ([systemID containsString:@"nds"]) {
        if (!verify_bios_files(biosPath, @[@"bios7.bin", @"bios9.bin", @"firmware.bin"])) {
             errorMsg = @"Nintendo DS (MelonDS) requires bios7.bin, bios9.bin, and firmware.bin in your BIOS folder.";
        }
    }
    
    if (errorMsg) {
        NSLog(@"[OELibretro] BIOS DIAGNOSTIC: %@", errorMsg);
    }
    
    struct retro_system_info sysInfo = {0};
    _retro_get_system_info(&sysInfo);
    NSLog(@"[OELibretro] Core System Info: %s (Version: %s)", sysInfo.library_name ?: "Unknown", sysInfo.library_version ?: "Unknown");
    
    struct retro_game_info gameInfo = {0};
    gameInfo.path = [path UTF8String];
    
    if (sysInfo.need_fullpath) {
        NSLog(@"[OELibretro] Core needs fullpath, skipping data buffer loading.");
        gameInfo.data = NULL;
        gameInfo.size = 0;
    } else {
        _romData = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        gameInfo.data = [_romData bytes];
        gameInfo.size = [_romData length];
        NSLog(@"[OELibretro] ROM Mapped into memory: %zu bytes", [_romData length]);
    }
    
    _clearFramesRemaining = 20; // Warm-up: Clear buffer for 20 frames to avoid memory artifacts

    NSLog(@"[OELibretro] Successfully prepared game info. Calling retro_load_game...");
    if (!_retro_load_game(&gameInfo)) {
        errorMsg = @"The core rejected the ROM load. This is usually due to missing BIOS or corrupted files.";
        
        // Comprehensive BIOS Dependency Diagnostic
        if ([systemID containsString:@"dc"]) {
             errorMsg = @"Dreamcast ROM load failed. Ensure you have dc_boot.bin and dc_flash.bin in a 'dc' subfolder inside your BIOS directory.";
        } else if ([systemID containsString:@"nds"]) {
             errorMsg = @"Nintendo DS load failed. Ensure bios7.bin, bios9.bin, firmware.bin are in your BIOS folder.";
        }
        
        NSLog(@"[OELibretro] !!! CRITICAL LOAD FAILURE: %@", errorMsg);
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain 
                                         code:OEGameCoreCouldNotLoadROMError 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    
    // Update geometry and log handshake
    if (_retro_get_system_av_info) {
        _retro_get_system_av_info(&_avInfo);
        
        // Finalize the cached geometry to ensure buffer stability
        if (_cachedMaxWidth == 0) {
            _cachedMaxWidth  = _avInfo.geometry.max_width ?: 640;
            _cachedMaxHeight = _avInfo.geometry.max_height ?: 480;
        }
        
        NSLog(@"[OELibretro] Core Handshake: %dx%d (max), Audio: %.0fHz", (int)_cachedMaxWidth, (int)_cachedMaxHeight, _avInfo.timing.sample_rate);
    }
    
    return YES;
}

- (void)stopEmulation {
    [super stopEmulation];
    _current = self;
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
            NSLog(@"[OELibretro] Calling context_reset for Hardware Accelerated core (on thread with active context)...");
            fprintf(stderr, "[OELibretro] Calling context_reset for HW core\n");
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
        // Senior Programmer Choice: Global 1:1 Scaling for maximum sharpness as requested.
        // Returning base dimensions ensures pixel-perfect results in the Metal renderer.
        int width  = _avInfo.geometry.base_width;
        int height = _avInfo.geometry.base_height;
        
        // Fallback to max dimensions if base is invalid
        if (width <= 0) width = (int)_avInfo.geometry.max_width;
        if (height <= 0) height = (int)_avInfo.geometry.max_height;
        
        // Final safety: ensure we never return zero-size
        if (width <= 0) width = 320;
        if (height <= 0) height = 240;
        
        return OEIntSizeMake(width, height);
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
        return _videoBuffer;
    }
    // For the Metal renderer, we MUST return the hint to satisfy the direct rendering assertion.
    // We handle cores with internal buffers by copying the data in libretro_video_refresh_cb.
    return hint;
}

#pragma mark - Input: OELibretroInputReceiver

- (void)receiveLibretroButton:(uint8_t)buttonID forPort:(NSUInteger)port pressed:(BOOL)pressed {
    if (port < 4 && buttonID < 16) {
        _buttonStates[port][buttonID] = pressed ? 1 : 0;
    }
}

- (void)receiveLibretroAnalogIndex:(uint8_t)index axis:(uint8_t)axis value:(int16_t)value forPort:(NSUInteger)port {
    if (port < 4 && index < 2 && axis < 2) {
        _analogStates[port][index][axis] = value;
    }
}

#pragma mark - Input Stubs

- (void)mouseMovedAtPoint:(OEIntPoint)aPoint {}
- (void)leftMouseDownAtPoint:(OEIntPoint)aPoint {}
- (void)leftMouseUpAtPoint:(OEIntPoint)aPoint {}
- (void)rightMouseDownAtPoint:(OEIntPoint)aPoint {}
- (void)rightMouseUpAtPoint:(OEIntPoint)aPoint {}
- (void)keyDown:(unsigned short)keyCode characters:(NSString *)characters charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers flags:(NSEventModifierFlags)flags {}
- (void)keyUp:(unsigned short)keyCode characters:(NSString *)characters charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers flags:(NSEventModifierFlags)flags {}
- (void)didPushOEButton:(NSInteger)button forPlayer:(NSUInteger)player {}
- (void)didReleaseOEButton:(NSInteger)button forPlayer:(NSUInteger)player {}

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
    self.rate = -(float)speed;
}

- (void)slowMotionAtSpeed:(CGFloat)speed {
    self.rate = (float)speed;
}

#pragma mark - NDS Specific Responder
- (oneway void)didPushNDSButton:(NSInteger)button forPlayer:(NSUInteger)player {}
- (oneway void)didReleaseNDSButton:(NSInteger)button forPlayer:(NSUInteger)player {}

- (oneway void)didTouchScreenPoint:(OEIntPoint)point {
    _touchX = point.x;
    _touchY = point.y;
    _isTouching = YES;
}

- (oneway void)didReleaseTouch {
    _isTouching = NO;
}

@end
