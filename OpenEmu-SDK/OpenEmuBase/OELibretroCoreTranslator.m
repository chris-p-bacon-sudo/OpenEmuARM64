// Copyright (c) 2026, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// ...

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <os/log.h>
#import "OELibretroCoreTranslator.h"
#import "OEGameCore.h"
#import "OERingBuffer.h"
#import "OEGeometry.h"
#import "OEGameCoreController.h"
#import "OELogging.h"
#import <dlfcn.h>
#import "libretro.h"

#pragma mark - Pixel Conversion Helpers

static inline uint32_t convert_0rgb1555_to_bgra8888(uint16_t pix) {
    uint32_t r = (pix >> 10) & 0x1F;
    uint32_t g = (pix >> 5) & 0x1F;
    uint32_t b = (pix >> 0) & 0x1F;
    r = (r << 3) | (r >> 2);
    g = (g << 3) | (g >> 2);
    b = (b << 3) | (b >> 2);
    // Produce BGRA in memory on Little Endian (Byte 0=B, 1=G, 2=R, 3=A)
    return 0xFF000000 | (r << 16) | (g << 8) | b;
}

static inline uint32_t convert_rgb565_to_bgra8888(uint16_t pix) {
    uint32_t r = (pix >> 11) & 0x1F;
    uint32_t g = (pix >> 5) & 0x3F;
    uint32_t b = (pix >> 0) & 0x1F;
    r = (r << 3) | (r >> 2);
    g = (g << 2) | (g >> 4);
    b = (b << 3) | (b >> 2);
    // Produce BGRA in memory on Little Endian (Byte 0=B, 1=G, 2=R, 3=A)
    return 0xFF000000 | (r << 16) | (g << 8) | b;
}

// Missing environment defines from minimal libretro.h
#define RETRO_ENVIRONMENT_GET_LOG_INTERFACE 27
#define RETRO_ENVIRONMENT_GET_CAN_DUPE 10
#define RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY 9
#define RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY 31
#define RETRO_ENVIRONMENT_GET_CONTENT_DIRECTORY 30
#define RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION 52
#define RETRO_ENVIRONMENT_SET_CORE_OPTIONS 53
#define RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2 67
#define RETRO_ENVIRONMENT_SET_PIXEL_FORMAT 1
#define RETRO_ENVIRONMENT_SET_GEOMETRY 37
#define RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO 32

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

static void libretro_log_cb(enum retro_log_level level, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    char buffer[4096];
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    
    switch (level) {
        case RETRO_LOG_DEBUG: os_log_debug(OE_LOG_DEFAULT, "[Libretro] %s", buffer); break;
        case RETRO_LOG_INFO:  os_log_info(OE_LOG_DEFAULT, "[Libretro] %s", buffer); break;
        case RETRO_LOG_WARN:  os_log_error(OE_LOG_DEFAULT, "[Libretro] %s", buffer); break;
        case RETRO_LOG_ERROR: os_log_error(OE_LOG_DEFAULT, "!!! [Libretro Error] %s", buffer); break;
        default: os_log(OE_LOG_DEFAULT, "[Libretro] %s", buffer); break;
    }
}

@interface OELibretroCoreTranslator ()
@property (nonatomic, strong) NSBundle *coreBundle;
@property (nonatomic, assign) enum retro_pixel_format retroPixelFormat;
@end

static __thread __unsafe_unretained OELibretroCoreTranslator *_current = nil;

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
@public
    uint32_t _oePixelFormat;
    uint32_t _oePixelType;
    uint32_t _bpp;
    const void *_videoBuffer;
    void *_oeBufferHint;
    NSData *_romData;
}

#pragma mark - Libretro Callbacks (C API)

static bool libretro_environment_cb(unsigned cmd, void *data) {
    switch (cmd) {
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
            // This is used for BIOS/Firmware
            if (data && _current) {
                *(const char **)data = [[_current biosDirectoryPath] UTF8String];
                return true;
            }
            break;
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
            if (data && _current) {
                *(const char **)data = [[_current batterySavesDirectoryPath] UTF8String];
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
                _current.retroPixelFormat = *(enum retro_pixel_format *)data;
                return true;
            }
            return false;
        case RETRO_ENVIRONMENT_SET_GEOMETRY:
            if (data && _current) {
                const struct retro_game_geometry *geom = (const struct retro_game_geometry *)data;
                _current->_avInfo.geometry = *geom;
                NSLog(@"[OELibretro] Geometry updated: %dx%d (Aspect: %.2f)", geom->base_width, geom->base_height, geom->aspect_ratio);
                return true;
            }
            break;
        case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
            if (data && _current) {
                const struct retro_system_av_info *info = (const struct retro_system_av_info *)data;
                _current->_avInfo = *info;
                NSLog(@"[OELibretro] AV Info updated: %dx%d @ %.2f fps", info->geometry.base_width, info->geometry.base_height, info->timing.fps);
                return true;
            }
            break;
        default:
            break;
    }
    return false;
}

static void libretro_video_refresh_cb(const void *data, unsigned width, unsigned height, size_t pitch) {
    if (data && _current) {
        _current->_videoBuffer = data;
        
        if (_current->_oeBufferHint) {
            uint32_t *dst = (uint32_t *)_current->_oeBufferHint;
            size_t destRowWords = _current.bufferSize.width;
            enum retro_pixel_format coreFormat = _current.retroPixelFormat;
            const uint8_t *src = (const uint8_t *)data;
            
            for (unsigned y = 0; y < height; y++) {
                uint32_t *d = dst + (y * destRowWords);
                const uint16_t *s16 = (const uint16_t *)(src + (y * pitch));
                const uint32_t *s32 = (const uint32_t *)(src + (y * pitch));

                // Auto-detect 32-bit pitch (XRGB8888) if the core hasn't explicitly set its format or if it matches 32-bit.
                enum retro_pixel_format effectiveFormat = coreFormat;
                if (pitch == width * 4) {
                    effectiveFormat = RETRO_PIXEL_FORMAT_XRGB8888;
                }
                
                for (unsigned x = 0; x < width; x++) {
                    switch (effectiveFormat) {
                        case RETRO_PIXEL_FORMAT_0RGB1555:
                            d[x] = convert_0rgb1555_to_bgra8888(s16[x]);
                            break;
                        case RETRO_PIXEL_FORMAT_RGB565:
                            d[x] = convert_rgb565_to_bgra8888(s16[x]);
                            break;
                        case RETRO_PIXEL_FORMAT_XRGB8888: {
                            uint32_t pix = s32[x];
                            // Libretro XRGB8888 is 0xRRGGBB. Match BGRA output (0xFFRRGGBB).
                            d[x] = 0xFF000000 | pix;
                            break;
                        }
                        default:
                            break;
                    }
                }
            }
        }
    }
}
static void libretro_audio_sample_cb(int16_t left, int16_t right) {
    if (_current) {
        int16_t samples[2] = {left, right};
        [[_current ringBufferAtIndex:0] write:samples maxLength:sizeof(samples)];
    }
}

static size_t libretro_audio_sample_batch_cb(const int16_t *data, size_t frames) {
    if (_current && data) {
        [[_current ringBufferAtIndex:0] write:data maxLength:frames * 2 * sizeof(int16_t)];
        return frames;
    }
    return 0;
}
static void libretro_input_poll_cb(void) {
    // OpenEmu's model is push-based, but we give the core a chance to poll if it needs to.
}
static int16_t libretro_input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id) { return 0; }

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
        // Libretro bridge now defaults to 32-bit BGRA8888 unified output
        _oePixelFormat = OEPixelFormat_BGRA;
        _oePixelType   = OEPixelType_UNSIGNED_INT_8_8_8_8_REV;
        _bpp           = 4;
        _retroPixelFormat = RETRO_PIXEL_FORMAT_0RGB1555; // Libretro spec default
    }
    return self;
}

- (void)dealloc {
    _current = self;
    if (_coreHandle) {
        if (_retro_deinit) _retro_deinit();
        dlclose(_coreHandle);
    }
    if (_current == self) _current = nil;
}

#pragma mark - OEGameCore Overrides

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error {
    _current = self;
    self.coreBundle = [[self owner] bundle];
    NSString *corePath = [[self coreBundle] objectForInfoDictionaryKey:@"OELibretroCorePath"];
    
    if (!corePath) {
        corePath = [self.coreBundle executablePath];
    }
    
    NSString *bundleID = [self.coreBundle bundleIdentifier];
    if ([bundleID containsString:@"Snes9x"] || [bundleID containsString:@"BSNES"] || [bundleID containsString:@"SNES"]) {
        NSLog(@"[OELibretro] Core %@ detected: defaulting to RGB565", bundleID);
        _retroPixelFormat = RETRO_PIXEL_FORMAT_RGB565;
    }

    NSLog(@"[OELibretro] Attempting to load core from: %@", corePath);
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:corePath]) {
        NSLog(@"[OELibretro] Core file NOT found at path!");
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
    #define RESOLVE(name) _##name = bridge_dlsym(_coreHandle, #name); if (!_##name) NSLog(@"[OELibretro] CRITICAL: Symbol %s not found!", #name)
    
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
    
    NSLog(@"[OELibretro] Initializing core...");
    _retro_init();
    
    struct retro_system_info sysInfo = {0};
    _retro_get_system_info(&sysInfo);
    
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
    }
    
    NSLog(@"[OELibretro] Loading game: %s", gameInfo.path);
    if (!_retro_load_game(&gameInfo)) {
        NSLog(@"[OELibretro] retro_load_game TRUE-FALSE rejection!");
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:nil];
        }
        dlclose(_coreHandle);
        _coreHandle = NULL;
        return NO;
    }
    
    if (_retro_get_system_av_info) {
        _retro_get_system_av_info(&_avInfo);
        NSLog(@"[OELibretro] Video: %dx%d, Audio: %.0fHz", _avInfo.geometry.base_width, _avInfo.geometry.base_height, _avInfo.timing.sample_rate);
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
    if (_retro_run) _retro_run();
}

- (OEIntSize)bufferSize {
    size_t width = _avInfo.geometry.max_width ?: 640;
    size_t height = _avInfo.geometry.max_height ?: 480;
    return OEIntSizeMake((int)width, (int)height);
}

- (OEIntRect)screenRect {
    size_t width = _avInfo.geometry.base_width ?: 640;
    size_t height = _avInfo.geometry.base_height ?: 480;
    return OEIntRectMake(0, 0, (int)width, (int)height);
}

- (OEIntSize)aspectSize {
    float aspect = _avInfo.geometry.aspect_ratio;
    if (aspect > 0.0f) {
        // If the core provides an aspect ratio, use it to calculate the size.
        // We use a high base to avoid rounding issues in the UI.
        int height = _avInfo.geometry.base_height ?: 240;
        int width = (int)roundf(height * aspect);
        return OEIntSizeMake(width, height);
    }
    // Fallback to 1:1 if no aspect ratio is provided.
    int width = _avInfo.geometry.base_width ?: 4;
    int height = _avInfo.geometry.base_height ?: 3;
    return OEIntSizeMake(width, height);
}

- (double)audioSampleRate {
    return _avInfo.timing.sample_rate ?: 44100.0;
}

- (double)frameDuration {
    return _avInfo.timing.fps > 0 ? 1.0 / _avInfo.timing.fps : 1.0 / 60.0;
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

- (void)fastForwardAtSpeed:(CGFloat)speed {
    self.rate = (float)speed;
}

- (void)rewindAtSpeed:(CGFloat)speed {
    self.rate = -(float)speed;
}

- (void)slowMotionAtSpeed:(CGFloat)speed {
    self.rate = (float)speed;
}

@end
