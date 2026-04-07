// Copyright (c) 2026, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// ...

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "OELibretroCoreTranslator.h"
#import "OEGameCore.h"
#import "OEGeometry.h"
#import "OEGameCoreController.h"
#import "OEEvents.h"
#import <dlfcn.h>
#import "libretro.h"

@interface OELibretroCoreTranslator ()
@property (nonatomic, strong) NSBundle *coreBundle;
@end

static __thread OELibretroCoreTranslator *_current = nil;

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
    const void *_videoBuffer;
    void *_oeBufferHint;
}

#pragma mark - Libretro Callbacks (C API)

static bool libretro_environment_cb(unsigned cmd, void *data) {
    switch (cmd) {
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
            if (data && _current) {
                *(const char **)data = [_current.supportDirectoryPath UTF8String];
                return true;
            }
            break;
        case RETRO_ENVIRONMENT_GET_CAN_DUPE:
            if (data) *(bool *)data = true;
            return true;
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
            if (data && _current) {
                enum retro_pixel_format fmt = *(enum retro_pixel_format *)data;
                switch (fmt) {
                    case RETRO_PIXEL_FORMAT_0RGB1555:
                        _current->_oePixelFormat = OEPixelFormat_RGBA;
                        _current->_oePixelType   = OEPixelType_UNSIGNED_SHORT_1_5_5_5_REV;
                        break;
                    case RETRO_PIXEL_FORMAT_XRGB8888:
                        _current->_oePixelFormat = OEPixelFormat_BGRA;
                        _current->_oePixelType   = OEPixelType_UNSIGNED_INT_8_8_8_8_REV;
                        break;
                    case RETRO_PIXEL_FORMAT_RGB565:
                        _current->_oePixelFormat = OEPixelFormat_RGB;
                        _current->_oePixelType   = OEPixelType_UNSIGNED_SHORT_5_6_5;
                        break;
                    default:
                        return false;
                }
                return true;
            }
            return false;
        default:
            break;
    }
    return false;
}

static void libretro_video_refresh_cb(const void *data, unsigned width, unsigned height, size_t pitch) {
    if (data && _current) {
        _current->_videoBuffer = data;
        
        // If we have a target buffer from OpenEmu and the core is drawing elsewhere, sync them
        if (_current->_oeBufferHint) {
            size_t frameSize = pitch * height;
            
            if (_current->_oePixelFormat == OEPixelFormat_BGRA && _current->_oePixelType == OEPixelType_UNSIGNED_INT_8_8_8_8_REV) {
                // XRGB8888 - force Alpha channel to 0xFF to avoid black screen transparent pixels
                if (frameSize > 0) {
                    uint32_t *dst = _current->_oeBufferHint;
                    const uint32_t *src = (const uint32_t *)data;
                    size_t count = frameSize / 4;
                    for (size_t i = 0; i < count; i++) {
                        dst[i] = src[i] | 0xFF000000;
                    }
                }
            } else if (data != _current->_oeBufferHint) {
                if (frameSize > 0) {
                    memcpy(_current->_oeBufferHint, data, frameSize);
                }
            }
        }
    }
}
static void libretro_audio_sample_cb(int16_t left, int16_t right) {}
static size_t libretro_audio_sample_batch_cb(const int16_t *data, size_t frames) { return frames; }
static void libretro_input_poll_cb(void) {}
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
        // Default to 0RGB1555 as per libretro spec, mapped to OE supported formats
        _oePixelFormat = OEPixelFormat_RGBA;
        _oePixelType   = OEPixelType_UNSIGNED_SHORT_1_5_5_5_REV;
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
    self.coreBundle = self.owner.bundle;
    NSString *corePath = [self.coreBundle objectForInfoDictionaryKey:@"OELibretroCorePath"];
    
    if (!corePath) {
        corePath = [self.coreBundle executablePath];
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
    
    struct retro_game_info gameInfo = {0};
    gameInfo.path = [path UTF8String];
    
    NSData *romData = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    gameInfo.data = [romData bytes];
    gameInfo.size = [romData length];
    
    NSLog(@"[OELibretro] Loading game: %s", gameInfo.path);
    if (!_retro_load_game(&gameInfo)) {
        NSLog(@"[OELibretro] retro_load_game TRUE-FALSE rejection!");
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:nil];
        }
        return NO;
    }
    
    if (_retro_get_system_av_info) {
        _retro_get_system_av_info(&_avInfo);
        NSLog(@"[OELibretro] Video: %dx%d, Audio: %.0fHz", _avInfo.geometry.base_width, _avInfo.geometry.base_height, _avInfo.timing.sample_rate);
    }
    
    return YES;
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
        size_t height = _avInfo.geometry.base_height ?: 3;
        size_t width = (size_t)roundf(height * aspect);
        return OEIntSizeMake((int)width, (int)height);
    }
    size_t width = _avInfo.geometry.base_width ?: 4;
    size_t height = _avInfo.geometry.base_height ?: 3;
    return OEIntSizeMake((int)width, (int)height);
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
- (void)didPushOEButton:(OEButton)button forPlayer:(NSUInteger)player {}
- (void)didReleaseOEButton:(OEButton)button forPlayer:(NSUInteger)player {}

@end
