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

#ifndef OE_LIBRETRO_H
#define OE_LIBRETRO_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

// Minimal subset of upstream libretro.h sufficient to bridge the cores we
// support. Field types and ordering must match
// https://github.com/libretro/libretro-common/blob/master/include/libretro.h
// exactly, because libretro cores write into these structs by offset.
//
// Historical note (the "shift" bug): we previously declared the boolean
// flags in retro_hw_render_callback as `uint32_t`. The upstream ABI uses
// C99 `bool` (1 byte), so cores wrote three bools + padding into 4 bytes
// while the bridge expected three 4-byte ints. Every field after that
// (including version_major) was read from the wrong offset and appeared
// as zero, producing black screens during HW context init. Keep these
// types in sync with upstream — this is a struct-layout invariant, not
// an arm64-specific quirk.

// ── Environment commands ─────────────────────────────────────────────
#define RETRO_ENVIRONMENT_GET_CAN_DUPE                                 3
#define RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY                         9
#define RETRO_ENVIRONMENT_SET_PIXEL_FORMAT                             10
#define RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS                        11
#define RETRO_ENVIRONMENT_SET_HW_RENDER                                14
#define RETRO_ENVIRONMENT_GET_VARIABLE                                 15
#define RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE                          17
#define RETRO_ENVIRONMENT_GET_LOG_INTERFACE                            27
#define RETRO_ENVIRONMENT_GET_CONTENT_DIRECTORY                        30
#define RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY                           31
#define RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO                           32
#define RETRO_ENVIRONMENT_SET_CONTROLLER_INFO                          35
#define RETRO_ENVIRONMENT_SET_GEOMETRY                                 37
#define RETRO_ENVIRONMENT_GET_HW_RENDER_INTERFACE                      41
#define RETRO_ENVIRONMENT_SET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE  (43 | 0x10000)
#define RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS                     44
#define RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION                     52
#define RETRO_ENVIRONMENT_SET_CORE_OPTIONS                             53
#define RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2                          67

// ── Serialization quirk bitmask (RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS) ─
#define RETRO_SERIALIZATION_QUIRK_INCOMPLETE                  (1 << 0)
#define RETRO_SERIALIZATION_QUIRK_MUST_INITIALIZE             (1 << 1)
#define RETRO_SERIALIZATION_QUIRK_CORE_VARIABLE_SIZE          (1 << 2)
#define RETRO_SERIALIZATION_QUIRK_FRONT_VARIABLE_SIZE         (1 << 3)
#define RETRO_SERIALIZATION_QUIRK_SINGLE_SESSION              (1 << 4)
#define RETRO_SERIALIZATION_QUIRK_ENDIAN_DEPENDENT            (1 << 5)
#define RETRO_SERIALIZATION_QUIRK_PLATFORM_DEPENDENT          (1 << 6)

// ── Sentinel for HW-rendered frames ──────────────────────────────────
#define RETRO_HW_FRAME_BUFFER_VALID ((void*)-1)

// ── Input devices / IDs ──────────────────────────────────────────────
#define RETRO_DEVICE_JOYPAD              1
#define RETRO_DEVICE_ANALOG              2
#define RETRO_DEVICE_POINTER             6

#define RETRO_DEVICE_ID_JOYPAD_B         0
#define RETRO_DEVICE_ID_JOYPAD_Y         1
#define RETRO_DEVICE_ID_JOYPAD_SELECT    2
#define RETRO_DEVICE_ID_JOYPAD_START     3
#define RETRO_DEVICE_ID_JOYPAD_UP        4
#define RETRO_DEVICE_ID_JOYPAD_DOWN      5
#define RETRO_DEVICE_ID_JOYPAD_LEFT      6
#define RETRO_DEVICE_ID_JOYPAD_RIGHT     7
#define RETRO_DEVICE_ID_JOYPAD_A         8
#define RETRO_DEVICE_ID_JOYPAD_X         9
#define RETRO_DEVICE_ID_JOYPAD_L         10
#define RETRO_DEVICE_ID_JOYPAD_R         11
#define RETRO_DEVICE_ID_JOYPAD_L2        12
#define RETRO_DEVICE_ID_JOYPAD_R2        13
#define RETRO_DEVICE_ID_JOYPAD_L3        14
#define RETRO_DEVICE_ID_JOYPAD_R3        15

#define RETRO_DEVICE_INDEX_ANALOG_LEFT   0
#define RETRO_DEVICE_INDEX_ANALOG_RIGHT  1
#define RETRO_DEVICE_ID_ANALOG_X         0
#define RETRO_DEVICE_ID_ANALOG_Y         1

#define RETRO_DEVICE_ID_POINTER_X        0
#define RETRO_DEVICE_ID_POINTER_Y        1
#define RETRO_DEVICE_ID_POINTER_PRESSED  2

// ── Callback typedefs ────────────────────────────────────────────────
typedef bool    (*retro_environment_t)(unsigned cmd, void *data);
typedef void    (*retro_video_refresh_t)(const void *data, unsigned width, unsigned height, size_t pitch);
typedef void    (*retro_audio_sample_t)(int16_t left, int16_t right);
typedef size_t  (*retro_audio_sample_batch_t)(const int16_t *data, size_t frames);
typedef void    (*retro_input_poll_t)(void);
typedef int16_t (*retro_input_state_t)(unsigned port, unsigned device, unsigned index, unsigned id);
typedef void    (*retro_proc_address_t)(void);

// ── Structs ──────────────────────────────────────────────────────────
struct retro_variable {
    const char *key;
    const char *value;
};

enum retro_pixel_format {
    RETRO_PIXEL_FORMAT_0RGB1555 = 0,
    RETRO_PIXEL_FORMAT_XRGB8888 = 1,
    RETRO_PIXEL_FORMAT_RGB565   = 2,
    RETRO_PIXEL_FORMAT_UNKNOWN  = 0x7fffffff
};

enum retro_log_level {
    RETRO_LOG_DEBUG = 0,
    RETRO_LOG_INFO  = 1,
    RETRO_LOG_WARN  = 2,
    RETRO_LOG_ERROR = 3,
    RETRO_LOG_DUMMY = 0x7fffffff
};

typedef void (*retro_log_printf_t)(enum retro_log_level level, const char *fmt, ...);
struct retro_log_callback { retro_log_printf_t log; };

enum retro_hw_context_type {
    RETRO_HW_CONTEXT_NONE         = 0,
    RETRO_HW_CONTEXT_OPENGL       = 1,
    RETRO_HW_CONTEXT_OPENGLES2    = 2,
    RETRO_HW_CONTEXT_OPENGL_CORE  = 3,
    RETRO_HW_CONTEXT_OPENGLES3    = 4,
    RETRO_HW_CONTEXT_OPENGLES_ANY = 5,
    RETRO_HW_CONTEXT_VULKAN       = 6,
    RETRO_HW_CONTEXT_DUMMY        = 2147483647
};

typedef void      (*retro_hw_context_reset_t)(void);
typedef uintptr_t (*retro_hw_get_current_framebuffer_t)(void);
typedef retro_proc_address_t (*retro_hw_get_proc_address_t)(const char *sym);

struct retro_hw_render_callback {
    enum retro_hw_context_type         context_type;
    retro_hw_context_reset_t           context_reset;
    retro_hw_get_current_framebuffer_t get_current_framebuffer;
    retro_hw_get_proc_address_t        get_proc_address;

    // Must remain `bool` (1 byte) to match upstream layout — see header
    // comment above for the cautionary tale of declaring these as uint32_t.
    bool                               depth;
    bool                               stencil;
    bool                               bottom_left_origin;
    unsigned                           version_major;
    unsigned                           version_minor;
    bool                               cache_context;
    retro_hw_context_reset_t           context_destroy;
    bool                               debug_context;
};

struct retro_system_info {
    const char *library_name;
    const char *library_version;
    const char *valid_extensions;
    bool        need_fullpath;
    bool        block_extract;
};

struct retro_game_geometry {
    unsigned base_width;
    unsigned base_height;
    unsigned max_width;
    unsigned max_height;
    float    aspect_ratio;
};

struct retro_system_timing {
    double fps;
    double sample_rate;
};

struct retro_system_av_info {
    struct retro_game_geometry geometry;
    struct retro_system_timing timing;
};

struct retro_game_info {
    const char *path;
    const void *data;
    size_t      size;
    const char *meta;
};

#ifdef __cplusplus
}
#endif

// ── ABI Verification ────────────────────────────────────────────────
// These assertions pin the struct layout to the upstream Libretro ABI
// under any LP64 target (Apple Silicon, macOS x86_64, Linux x86_64, ...).
// A failure here means a field type or order changed and the bridge will
// read cores at the wrong offsets — see the header comment at the top of
// this file for the cautionary tale.
#include <stddef.h>

#ifdef __cplusplus
#define RETRO_STATIC_ASSERT(cond, msg) static_assert(cond, msg)
#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
#define RETRO_STATIC_ASSERT(cond, msg) _Static_assert(cond, msg)
#else
#define RETRO_STATIC_ASSERT(cond, msg)
#endif

RETRO_STATIC_ASSERT(sizeof(struct retro_hw_render_callback) == 64,
    "retro_hw_render_callback size mismatch — check field types against upstream libretro ABI");
RETRO_STATIC_ASSERT(sizeof(struct retro_system_info)        == 32,
    "retro_system_info layout drift from upstream libretro ABI");
RETRO_STATIC_ASSERT(sizeof(struct retro_game_geometry)      == 20,
    "retro_game_geometry layout drift from upstream libretro ABI");
RETRO_STATIC_ASSERT(sizeof(struct retro_system_timing)      == 16,
    "retro_system_timing layout drift from upstream libretro ABI");
RETRO_STATIC_ASSERT(sizeof(struct retro_system_av_info)     == 40,
    "retro_system_av_info layout drift from upstream libretro ABI");
RETRO_STATIC_ASSERT(sizeof(struct retro_game_info)          == 32,
    "retro_game_info layout drift from upstream libretro ABI");
RETRO_STATIC_ASSERT(sizeof(struct retro_variable)           == 16,
    "retro_variable layout drift from upstream libretro ABI");
RETRO_STATIC_ASSERT(sizeof(struct retro_log_callback)       == 8,
    "retro_log_callback layout drift from upstream libretro ABI");

// Offset assertion on the exact field that motivated this hardening.
// If a future change reverts the bool flags to uint32_t (or reorders any
// of depth/stencil/bottom_left_origin), version_major moves and the
// bridge silently reads zero — the original "shift crash" failure mode.
RETRO_STATIC_ASSERT(offsetof(struct retro_hw_render_callback, version_major) == 36,
    "version_major must remain at offset 36 — see the bool/uint32_t shift-bug note in this header");

#endif /* OE_LIBRETRO_H */
