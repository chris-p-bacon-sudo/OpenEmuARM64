/*
 Copyright (c) 2018, OpenEmu Team

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

// We need to mess with core internals
#define M64P_CORE_PROTOTYPES 1

#import "MupenGameCore.h"
#import <OpenEmuBase/OERingBuffer.h>
#import <OpenEmuBase/OETimingUtils.h>
#import "OEN64SystemResponderClient.h"
#import <OpenGL/gl.h>

#import "api/config.h"
#import "api/m64p_common.h"
#import "api/m64p_config.h"
#import "api/m64p_frontend.h"
#import "api/m64p_vidext.h"
#import "api/callbacks.h"
#import "main/rom.h"
#import "main/savestates.h"
#import "osal/dynamiclib.h"
#import "main/version.h"
#import "device/memory/memory.h"
#import "main/main.h"
//#import "r4300/r4300.h"
#import "device/r4300/r4300_core.h"
#import "device/rdram/rdram.h"
#import "device/device.h"
#import "device/rcp/vi/vi_controller.h"

#import "plugin/plugin.h"

#import <dlfcn.h>
#include <os/log.h>
#define RC_CLIENT_SUPPORTS_HASH 1
#include <rc_client.h>
#include <rc_consoles.h>
#import "OERetroAchievementsTransport.h"

NSString *MupenControlNames[] = {
    @"N64_DPadU", @"N64_DPadD", @"N64_DPadL", @"N64_DPadR",
    @"N64_CU", @"N64_CD", @"N64_CL", @"N64_CR",
    @"N64_B", @"N64_A", @"N64_R", @"N64_L", @"N64_Z", @"N64_Start"
};

@interface MupenGameCore () <OEN64SystemResponderClient>
{
    uint8_t _padData[4][OEN64ButtonCount];
    int8_t _xAxis[4];
    int8_t _yAxis[4];
    NSUInteger _frameCounter;
    double _sampleRate;
    BOOL _initializing;

    m64p_emu_state _emulatorState;

    dispatch_queue_t _callbackQueue;
    NSMutableDictionary *_callbackHandlers;

    rc_client_t *_rcClient;
    id _raTokenObserver;
    BOOL _raHardcoreEnabled;
    id _raHardcoreObserver;
    NSString *_romPath;
}

- (void)OE_didReceiveStateChangeForParamType:(m64p_core_param)paramType value:(int)newValue;
- (void)_beginLoadGame;
- (void)_postRetroAchievementsSessionSnapshot;

@end

__weak MupenGameCore *_current = 0;

static void (*ptr_OE_ForceUpdateWindowSize)(int width, int height);

static void MupenDebugCallback(void *context, int level, const char *message)
{
    NSDictionary<NSNumber *, NSString *> *levels = @{
        @(M64MSG_ERROR)   : @"Error",
        @(M64MSG_WARNING) : @"Warning",
        @(M64MSG_INFO)    : @"Info",
        @(M64MSG_STATUS)  : @"Status",
        @(M64MSG_VERBOSE) : @"Verbose",
    };

    // Ignore "Verbose" messages (maybe too console spammy?) and plugin warnings that aren't relevant
    if (level >= M64MSG_VERBOSE) return;
    if (strcmp(message, "No audio plugin attached.  There will be no sound output.") == 0) return;
    if (strcmp(message, "No input plugin attached.  You won't be able to control the game.") == 0) return;
    NSLog(@"[Mupen64Plus] (%@): %s", levels[@(level)], message);
}

static void MupenStateCallback(void *context, m64p_core_param paramType, int newValue)
{
    NSDictionary<NSNumber *, NSString *> *params = @{
        @(M64CORE_EMU_STATE)          : @"Emu State",
        @(M64CORE_STATE_LOADCOMPLETE) : @"State Load Complete",
        @(M64CORE_STATE_SAVECOMPLETE) : @"State Save Complete",
    };

    if (params[@(paramType)])
        NSLog(@"[Mupen64Plus] (state) %@ -> %d", params[@(paramType)], newValue);
    else
        NSLog(@"[Mupen64Plus] param %d -> %d", paramType, newValue);
    [((__bridge MupenGameCore *)context) OE_didReceiveStateChangeForParamType:paramType value:newValue];
}

#pragma mark - RetroAchievements

// Mupen stores RDRAM as host-native (little-endian) 32-bit words in g_dev.rdram.dram.
// N64 achievement conditions are authored against the raw LE host byte layout (the same
// layout RetroArch/mupen64plus-next exposes via retro_get_memory_data). Return bytes
// verbatim — no byte-swap. Multi-byte conditions in the achievement set use _BE size
// prefixes to handle endianness at the condition level.
static uint32_t mupen_rc_read_memory(uint32_t address, uint8_t *buffer,
                                     uint32_t num_bytes, rc_client_t *client)
{
    uint8_t *ram = (uint8_t *)g_dev.rdram.dram;
    size_t   sz  = g_dev.rdram.dram_size;
    if (!ram || sz == 0) { return 0; }
    uint32_t end = address + num_bytes;
    if (end > sz) { end = (uint32_t)sz; }
    uint32_t readable = end - address;
    memcpy(buffer, ram + address, readable);
    return readable;
}

static void mupen_rc_log(const char *message, const rc_client_t *client)
{
    os_log(OS_LOG_DEFAULT, "[rcheevos/n64] %{public}s", message);
}

static void mupen_rc_load_game_callback(int result, const char *error_message,
                                         rc_client_t *client, void *userdata)
{
    MupenGameCore *self = (__bridge MupenGameCore *)userdata;
    if (result != RC_OK) {
        NSLog(@"[RA-Mupen64Plus] game load failed — result=%d error=%s", result, error_message ?: "(none)");
        return;
    }
    [self _postRetroAchievementsSessionSnapshot];
}

static void mupen_rc_login_callback(int result, const char *error_message,
                                     rc_client_t *client, void *userdata)
{
    MupenGameCore *s = (__bridge MupenGameCore *)userdata;
    if (result == RC_OK) {
        [s _beginLoadGame];
    } else {
        NSLog(@"[RA-Mupen64Plus] login failed — result=%d error=%s", result, error_message ?: "(none)");
    }
}

static void mupen_rc_event_handler(const rc_client_event_t *event, rc_client_t *client)
{
    oeRetroAchievementsPostEventNotification(event, client);
    if (event->type != RC_CLIENT_EVENT_ACHIEVEMENT_TRIGGERED) { return; }
    const rc_client_achievement_t *ach = event->achievement;
    if (!ach) { return; }

    NSDictionary *info = @{
        OEAchievementIDKey:          @(ach->id),
        OEAchievementTitleKey:       @(ach->title       ?: ""),
        OEAchievementDescriptionKey: @(ach->description ?: ""),
        OEAchievementBadgeURLKey:    @(ach->badge_name  ?: ""),
        OEAchievementPointsKey:      @(ach->points),
    };
    [[NSNotificationCenter defaultCenter]
        postNotificationName:OEAchievementUnlockedNotification
                      object:nil
                    userInfo:info];
    MupenGameCore *core = (__bridge MupenGameCore *)rc_client_get_userdata(client);
    [core _postRetroAchievementsSessionSnapshot];
}

@implementation MupenGameCore

- (void)_beginLoadGame
{
    if (!_rcClient || !_romPath) { return; }
    rc_client_begin_identify_and_load_game(_rcClient,
                                           RC_CONSOLE_NINTENDO_64,
                                           _romPath.fileSystemRepresentation,
                                           NULL, 0,
                                           mupen_rc_load_game_callback,
                                           (__bridge void *)self);
}

- (void)_postRetroAchievementsSessionSnapshot
{
    if (!_rcClient || !rc_client_is_game_loaded(_rcClient)) { return; }
    const rc_client_game_t *game = rc_client_get_game_info(_rcClient);
    if (!game || game->id == 0) { return; }

    rc_client_user_game_summary_t summary;
    memset(&summary, 0, sizeof(summary));
    rc_client_get_user_game_summary(_rcClient, &summary);

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[OERAGameIDKey] = @(game->id);
    payload[OERAGameTitleKey] = [NSString stringWithUTF8String:game->title ?: ""];
    payload[OERAGameHashKey] = [NSString stringWithUTF8String:game->hash ?: ""];
    payload[OERAUnlockedCountKey] = @(summary.num_unlocked_achievements);
    payload[OERAAchievementCountKey] = @(summary.num_core_achievements);
    payload[OERAUnlockedPointsKey] = @(summary.points_unlocked);
    payload[OERATotalPointsKey] = @(summary.points_core);

    char gameImageURL[512];
    if (rc_client_game_get_image_url(game, gameImageURL, sizeof(gameImageURL)) == RC_OK)
        payload[OERAGameBadgeURLKey] = [NSString stringWithUTF8String:gameImageURL];

    NSMutableArray *sets = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, NSString *> *setTitlesByID = [NSMutableDictionary dictionary];
    rc_client_subset_list_t *subsetList = rc_client_create_subset_list(_rcClient);
    if (subsetList) {
        for (uint32_t i = 0; i < subsetList->num_subsets; i++) {
            const rc_client_subset_t *subset = subsetList->subsets[i];
            if (!subset) { continue; }
            NSString *subsetTitle = [NSString stringWithUTF8String:subset->title ?: "Achievement Set"];
            NSNumber *subsetID = @(subset->id);
            setTitlesByID[subsetID] = subsetTitle;
            NSMutableDictionary *setInfo = [NSMutableDictionary dictionary];
            setInfo[OERASetIDKey] = subsetID;
            setInfo[OERASetTitleKey] = subsetTitle;
            setInfo[OERASetAchievementCountKey] = @(subset->num_achievements);
            setInfo[OERASetLeaderboardCountKey] = @(subset->num_leaderboards);
            if (subset->badge_url)
                setInfo[OERASetBadgeURLKey] = [NSString stringWithUTF8String:subset->badge_url];
            [sets addObject:setInfo];
        }
        rc_client_destroy_subset_list(subsetList);
    }
    if (sets.count == 0) {
        NSNumber *gameID = @(game->id);
        NSString *gameTitle = [NSString stringWithUTF8String:game->title ?: "Achievement Set"];
        setTitlesByID[gameID] = gameTitle;
        [sets addObject:@{
            OERASetIDKey: gameID, OERASetTitleKey: gameTitle,
            OERASetAchievementCountKey: @(summary.num_core_achievements),
            OERASetLeaderboardCountKey: @0,
        }];
    }
    payload[OERASetsKey] = sets;

    NSMutableArray *achievements = [NSMutableArray array];
    rc_client_achievement_list_t *list = rc_client_create_achievement_list(
        _rcClient, RC_CLIENT_ACHIEVEMENT_CATEGORY_CORE,
        RC_CLIENT_ACHIEVEMENT_LIST_GROUPING_LOCK_STATE);
    if (list) {
        for (uint32_t b = 0; b < list->num_buckets; b++) {
            const rc_client_achievement_bucket_t bucket = list->buckets[b];
            NSString *bucketTitle = [NSString stringWithUTF8String:bucket.label ?: "Achievements"];
            for (uint32_t a = 0; a < bucket.num_achievements; a++) {
                const rc_client_achievement_t *ach = bucket.achievements[a];
                if (!ach) { continue; }
                NSNumber *subsetID = @(bucket.subset_id);
                NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                entry[OERASetIDKey] = subsetID;
                entry[OERASetTitleKey] = setTitlesByID[subsetID] ?: [NSString stringWithUTF8String:game->title ?: "Achievement Set"];
                entry[OERABucketTitleKey] = bucketTitle;
                entry[OERABucketTypeKey] = @(bucket.bucket_type);
                entry[OEAchievementIDKey] = @(ach->id);
                entry[OEAchievementTitleKey] = [NSString stringWithUTF8String:ach->title ?: ""];
                entry[OEAchievementDescriptionKey] = [NSString stringWithUTF8String:ach->description ?: ""];
                entry[OEAchievementPointsKey] = @(ach->points);
                entry[OERAStateKey] = @(ach->state);
                entry[OERATypeKey] = @(ach->type);
                entry[OERAUnlockedKey] = @(ach->unlocked);
                entry[OERARarityKey] = @(ach->rarity);
                entry[OERAHardcoreRarityKey] = @(ach->rarity_hardcore);
                entry[OERAMeasuredPercentKey] = @(ach->measured_percent);
                entry[OERAMeasuredProgressKey] = [NSString stringWithUTF8String:ach->measured_progress];
                if (ach->badge_url)
                    entry[OEAchievementBadgeURLKey] = [NSString stringWithUTF8String:ach->badge_url];
                if (ach->badge_locked_url)
                    entry[OERABadgeLockedURLKey] = [NSString stringWithUTF8String:ach->badge_locked_url];
                [achievements addObject:entry];
            }
        }
        rc_client_destroy_achievement_list(list);
    }
    payload[OERAAchievementsKey] = achievements;
    [[NSNotificationCenter defaultCenter] postNotificationName:OERASessionUpdatedNotification
                                                        object:nil
                                                      userInfo:payload];
}

- (instancetype)init
{
    if (self = [super init]) {
        _initializing = YES;
        _frameCounter = 0;

        _videoWidth  = 640;
        _videoHeight = 480;
        _videoBitDepth = 32; // ignored
        
        _sampleRate = 33600;

        _callbackQueue = dispatch_queue_create("org.openemu.MupenGameCore.CallbackHandlerQueue", DISPATCH_QUEUE_SERIAL);
        _callbackHandlers = [NSMutableDictionary dictionary];
    }
    _current = self;
    return self;
}

- (void)dealloc
{
    SetStateCallback(NULL, NULL);
    SetDebugCallback(NULL, NULL);
}

// Pass 0 as paramType to receive all state changes.
// Return YES from the block to keep watching the changes.
// Return NO to remove the block after the first received callback.
- (void)OE_addHandlerForType:(m64p_core_param)paramType usingBlock:(BOOL(^)(m64p_core_param paramType, int newValue))block
{
    // If we already have an emulator state, check if the block is satisfied with it or just add it to the queues.
    if(paramType == M64CORE_EMU_STATE && _emulatorState != 0 && !block(M64CORE_EMU_STATE, _emulatorState))
        return;

    dispatch_async(_callbackQueue, ^{
        NSMutableSet *callbacks = _callbackHandlers[@(paramType)];
        if(callbacks == nil)
        {
            callbacks = [NSMutableSet set];
            _callbackHandlers[@(paramType)] = callbacks;
        }

        [callbacks addObject:block];
    });
}

- (void)OE_didReceiveStateChangeForParamType:(m64p_core_param)paramType value:(int)newValue
{
    if(paramType == M64CORE_EMU_STATE) _emulatorState = newValue;

    void(^runCallbacksForType)(m64p_core_param) =
    ^(m64p_core_param type){
        NSMutableSet *callbacks = _callbackHandlers[@(type)];
        [callbacks filterUsingPredicate:
         [NSPredicate predicateWithBlock:
          ^ BOOL (BOOL(^evaluatedObject)(m64p_core_param, int), NSDictionary *bindings)
          {
              return evaluatedObject(paramType, newValue);
          }]];
    };

    dispatch_async(_callbackQueue, ^{
        runCallbacksForType(paramType);
        runCallbacksForType(0);
    });
}

static void *dlopen_myself()
{
    Dl_info info;
    
    dladdr(dlopen_myself, &info);
    
    return dlopen(info.dli_fname, 0);
}

static void MupenGetKeys(int Control, BUTTONS *Keys)
{
    GET_CURRENT_OR_RETURN();

    Keys->R_DPAD = current->_padData[Control][OEN64ButtonDPadRight];
    Keys->L_DPAD = current->_padData[Control][OEN64ButtonDPadLeft];
    Keys->D_DPAD = current->_padData[Control][OEN64ButtonDPadDown];
    Keys->U_DPAD = current->_padData[Control][OEN64ButtonDPadUp];
    Keys->START_BUTTON = current->_padData[Control][OEN64ButtonStart];
    Keys->Z_TRIG = current->_padData[Control][OEN64ButtonZ];
    Keys->B_BUTTON = current->_padData[Control][OEN64ButtonB];
    Keys->A_BUTTON = current->_padData[Control][OEN64ButtonA];
    Keys->R_CBUTTON = current->_padData[Control][OEN64ButtonCRight];
    Keys->L_CBUTTON = current->_padData[Control][OEN64ButtonCLeft];
    Keys->D_CBUTTON = current->_padData[Control][OEN64ButtonCDown];
    Keys->U_CBUTTON = current->_padData[Control][OEN64ButtonCUp];
    Keys->R_TRIG = current->_padData[Control][OEN64ButtonR];
    Keys->L_TRIG = current->_padData[Control][OEN64ButtonL];
    Keys->X_AXIS = current->_xAxis[Control];
    Keys->Y_AXIS = current->_yAxis[Control];
}

static void MupenInitiateControllers (CONTROL_INFO ControlInfo)
{
    ControlInfo.Controls[0].Present = 1;
    ControlInfo.Controls[0].Plugin = PLUGIN_MEMPAK;
    ControlInfo.Controls[1].Present = 1;
    ControlInfo.Controls[1].Plugin = PLUGIN_MEMPAK;
    ControlInfo.Controls[2].Present = 1;
    ControlInfo.Controls[2].Plugin = PLUGIN_MEMPAK;
    ControlInfo.Controls[3].Present = 1;
    ControlInfo.Controls[3].Plugin = PLUGIN_NONE;
}

static AUDIO_INFO AudioInfo;

static void MupenAudioSampleRateChanged(int SystemType)
{
    GET_CURRENT_OR_RETURN();

    double currentRate = current->_sampleRate;
    
    switch (SystemType)
    {
        default:
        case SYSTEM_NTSC:
            current->_sampleRate = 48681812 / (*AudioInfo.AI_DACRATE_REG + 1);
            break;
        case SYSTEM_PAL:
            current->_sampleRate = 49656530 / (*AudioInfo.AI_DACRATE_REG + 1);
            break;
    }

    [[current audioDelegate] audioSampleRateDidChange];
    NSLog(@"[Mupen64Plus] samplerate changed %f -> %f\n", currentRate, current->_sampleRate);
}

static void MupenAudioLenChanged()
{
    GET_CURRENT_OR_RETURN();

    int LenReg = *AudioInfo.AI_LEN_REG;
    uint8_t *ptr = (uint8_t*)(AudioInfo.RDRAM + (*AudioInfo.AI_DRAM_ADDR_REG & 0xFFFFFF));

    // Swap channels
    for (uint32_t i = 0; i < LenReg; i += 4)
    {
        ptr[i] ^= ptr[i + 2];
        ptr[i + 2] ^= ptr[i];
        ptr[i] ^= ptr[i + 2];
        ptr[i + 1] ^= ptr[i + 3];
        ptr[i + 3] ^= ptr[i + 1];
        ptr[i + 1] ^= ptr[i + 3];
    }

    [[current ringBufferAtIndex:0] write:ptr maxLength:LenReg];
}

static int MupenOpenAudio(AUDIO_INFO info)
{
    AudioInfo = info;

    return M64ERR_SUCCESS;
}

static void MupenSetAudioSpeed(int percent)
{
    // do we need this?
}

#pragma mark - Execution

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
    // Load ROM
    NSData *romData = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];

    if (romData == nil) return NO;

    NSBundle *coreBundle = [NSBundle bundleForClass:[self class]];
    NSURL *dataURL = coreBundle.resourceURL;

    NSURL *configURL = [NSURL fileURLWithPath:self.supportDirectoryPath];

    NSURL *batterySavesDirectory = [NSURL fileURLWithPath:self.batterySavesDirectoryPath];
    [NSFileManager.defaultManager createDirectoryAtURL:batterySavesDirectory withIntermediateDirectories:YES attributes:nil error:nil];

    // open core here
    CoreStartup(FRONTEND_API_VERSION, configURL.fileSystemRepresentation, dataURL.fileSystemRepresentation, (__bridge void *)self, MupenDebugCallback, (__bridge void *)self, MupenStateCallback);

    // set SRAM path
    m64p_handle config;
    ConfigOpenSection("Core", &config);
    ConfigSetParameter(config, "SaveSRAMPath", M64TYPE_STRING, batterySavesDirectory.fileSystemRepresentation);
    ConfigSetParameter(config, "SharedDataPath", M64TYPE_STRING, dataURL.fileSystemRepresentation);
    ConfigSaveSection("Core");

    // NOTE: The ARM64 dynarec (NEW_DYNAREC_ARM64) is compiled in and the
    // required JIT infrastructure is in place (MAP_JIT allocation, proper
    // pthread_jit_write_protect_np scoping, sys_icache_invalidate — see
    // new_dynarec.c and assem_arm64.c).  However the ARM64 JIT backend
    // currently produces incorrect results for SM64 and likely other titles:
    // the game boots but enters an idle spin that it never exits, producing
    // a black screen with no audio.  This is a dynarec emulation-correctness
    // bug (not a JIT plumbing issue) that needs a separate investigation.
    //
    // Until that is resolved, keep the pure interpreter on aarch64 so that
    // games that were working continue to work.  Track as issue #463.
    //
    // On x86_64 the dynarec is known-good and is used as before.
    m64p_handle section;
#ifdef __aarch64__
    int ival = EMUMODE_PURE_INTERPRETER;
#else
    int ival = EMUMODE_DYNAREC;
#endif

    ConfigOpenSection("Core", &section);
    ConfigSetParameter(section, "R4300Emulator", M64TYPE_INT, &ival);

    if (CoreDoCommand(M64CMD_ROM_OPEN, (int)romData.length, (void *)romData.bytes) != M64ERR_SUCCESS)
        return NO;

    // RetroAchievements: create rc_client and observe the OE token. Game identification
    // happens in the login callback so we never miss the token notification that fires
    // immediately after setRetroAchievementsToken.
    _romPath = path;
    _rcClient = rc_client_create(mupen_rc_read_memory, oeRetroAchievementsServerCall);
    if (_rcClient) {
        rc_client_set_userdata(_rcClient, (__bridge void *)self);
        rc_client_set_event_handler(_rcClient, mupen_rc_event_handler);
        _raHardcoreEnabled = YES;
        rc_client_set_hardcore_enabled(_rcClient, _raHardcoreEnabled ? 1 : 0);
        // Defer memory validation to do_frame (videoInterrupt) so RDRAM is live before rcheevos
        // validates achievement addresses. Without this, activation runs on the HTTP callback thread
        // before M64CMD_EXECUTE sets up g_dev.rdram.dram, returning 0 for every address and
        // deactivating all achievements before the game even starts.
        rc_client_set_allow_background_memory_reads(_rcClient, 0);
        rc_client_enable_logging(_rcClient, RC_CLIENT_LOG_LEVEL_INFO, mupen_rc_log);

        __weak MupenGameCore *weakSelf = self;
        _raTokenObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:OERetroAchievementsTokenDidChangeNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) {
            MupenGameCore *s = weakSelf;
            if (!s || !s->_rcClient) { return; }
            NSString *token    = note.userInfo[OERetroAchievementsTokenKey];
            NSString *username = note.userInfo[OERetroAchievementsUsernameKey];
            if (token && username) {
                rc_client_begin_login_with_token(s->_rcClient,
                                                 username.UTF8String,
                                                 token.UTF8String,
                                                 mupen_rc_login_callback,
                                                 (__bridge void *)s);
            } else {
                rc_client_logout(s->_rcClient);
            }
        }];

        _raHardcoreObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:OEHardcoreModeDidChangeNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) {
            NSNumber *enabled = note.userInfo[OEHardcoreEnabledKey];
            if (enabled) {
                self->_raHardcoreEnabled = enabled.boolValue;
                if (self->_rcClient) {
                    rc_client_set_hardcore_enabled(self->_rcClient, self->_raHardcoreEnabled ? 1 : 0);
                }
            }
        }];
    }

    return YES;
}

- (void)setupEmulation
{
    NSBundle *coreBundle = [NSBundle bundleForClass:[self class]];

    m64p_dynlib_handle core_handle = dlopen_myself();

    void (^LoadPlugin)(m64p_plugin_type, NSString *) = ^(m64p_plugin_type pluginType, NSString *pluginName){
        m64p_dynlib_handle rsp_handle;
        NSString *rspPath = [coreBundle.builtInPlugInsPath stringByAppendingPathComponent:pluginName];

        rsp_handle = dlopen(rspPath.fileSystemRepresentation, RTLD_NOW);
        ptr_PluginStartup rsp_start = (ptr_PluginStartup) osal_dynlib_getproc(rsp_handle, "PluginStartup");
        rsp_start(core_handle, (__bridge void *)self, MupenDebugCallback);
        
        CoreAttachPlugin(pluginType, rsp_handle);
    };

    // Load Video
    LoadPlugin(M64PLUGIN_GFX, @"mupen64plus-video-GLideN64.so");
    //LoadPlugin(M64PLUGIN_GFX, @"mupen64plus-video-angrylion-rdp-plus.so");

    ptr_OE_ForceUpdateWindowSize = dlsym(RTLD_DEFAULT, "_OE_ForceUpdateWindowSize");

    // Load Audio
    audio.aiDacrateChanged = MupenAudioSampleRateChanged;
    audio.aiLenChanged = MupenAudioLenChanged;
    audio.initiateAudio = MupenOpenAudio;
    audio.setSpeedFactor = MupenSetAudioSpeed;
    plugin_start(M64PLUGIN_AUDIO);

    // Load Input
    input.getKeys = MupenGetKeys;
    input.initiateControllers = MupenInitiateControllers;
    plugin_start(M64PLUGIN_INPUT);

    // Load RSP
    //LoadPlugin(M64PLUGIN_RSP, @"mupen64plus-rsp-hle.so");

    const char *ROMname = (const char *)ROM_HEADER.Name;
    const char *gfxPluginName;
    gfx.getVersion(NULL, NULL, NULL, &gfxPluginName, NULL);

    if(strstr(gfxPluginName, "GLideN64") != 0) {
        m64p_handle configGfx;
        ConfigOpenSection("Video-GLideN64", &configGfx);

        // Workaround for https://github.com/gonetz/GLideN64/issues/1568
        if(strstr(ROMname, "DR.MARIO 64") != 0) {
            int enableCopyAuxToRDRAM = 1;
            ConfigSetParameter(configGfx, "EnableCopyAuxiliaryToRDRAM", M64TYPE_BOOL, &enableCopyAuxToRDRAM);
        }
    }

    // Configure if using rsp-cxd4 plugin
    m64p_handle configRSP;
    ConfigOpenSection("rsp-cxd4", &configRSP);
    int usingHLE = 1;
    if(strstr(gfxPluginName, "angrylion's RDP Plus") != 0)
        usingHLE = 0; // LLE GPU plugin
    ConfigSetParameter(configRSP, "DisplayListToGraphicsPlugin", M64TYPE_BOOL, &usingHLE);

    LoadPlugin(M64PLUGIN_RSP, @"mupen64plus-rsp-cxd4.so");
}

- (void)startEmulation
{
    [NSThread detachNewThreadSelector:@selector(runMupenEmuThread) toTarget:self withObject:nil];
    [super startEmulation];
}

- (void)runMupenEmuThread
{
    @autoreleasepool
    {
        OESetThreadRealtime(1. / 50, .007, .03); // guessed from bsnes
        [self.renderDelegate willRenderFrameOnAlternateThread];

        CoreDoCommand(M64CMD_EXECUTE, 0, NULL);
    }
}

- (void)videoInterrupt
{
    [self.renderDelegate didRenderFrameOnAlternateThread];

    if (_rcClient) {
        rc_client_do_frame(_rcClient);
    }
}

- (void)swapBuffers
{
}

- (void)executeFrame
{
    // Do nothing
    if(_frameCounter >= 10)
        _initializing = NO;

    _frameCounter ++;
}

- (void)stopEmulation
{
    if (_raTokenObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:_raTokenObserver];
        _raTokenObserver = nil;
    }
    if (_raHardcoreObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:_raHardcoreObserver];
        _raHardcoreObserver = nil;
    }
    if (_rcClient) {
        rc_client_unload_game(_rcClient);
        rc_client_destroy(_rcClient);
        _rcClient = NULL;
    }
    // Break the render-semaphore deadlock before asking the emulation thread to stop.
    //
    // The Mupen emulation thread and the OpenEmu core-loop thread synchronize each
    // rendered frame through two DispatchSemaphores in BaseOpenGLGameRenderer:
    //
    //   renderingThreadCanProceed  — signaled by willExecuteFrame (core-loop thread)
    //   executeThreadCanProceed    — signaled by didRenderFrameOnAlternateThread (Mupen thread)
    //
    // When isFPSLimiting is non-zero the Mupen thread blocks inside the VI handler
    // waiting for renderingThreadCanProceed, while the core-loop thread blocks in
    // didExecuteFrame waiting for executeThreadCanProceed.  Neither can proceed, so
    // r4300_stop is never polled and CoreDoCommand(M64CMD_STOP) never takes effect.
    //
    // suspendFPSLimiting() sets isFPSLimiting to 0 AND immediately signals
    // renderingThreadCanProceed once, which unblocks the Mupen thread.  With
    // isFPSLimiting == 0, both didExecuteFrame and didRenderFrameOnAlternateThread
    // skip their semaphore waits from that point forward, draining any pending
    // handshake cleanly before the stop command propagates.
    [self.renderDelegate suspendFPSLimiting];
    CoreDoCommand(M64CMD_STOP, 0, NULL);
    [super stopEmulation];
}

- (void)resetEmulation
{
    // FIXME: do we want/need soft reset? It doesn’t seem to work well with sending M64CMD_RESET alone
    // FIXME: might need to explicitly kick other thread
    CoreDoCommand(M64CMD_RESET, 1 /* hard reset */, NULL);
    if (_rcClient) {
        rc_client_reset(_rcClient);
    }
}

- (NSTimeInterval)frameInterval
{
    return vi_expected_refresh_rate_from_tv_standard(ROM_PARAMS.systemtype);
}

#pragma mark - Video

- (OEIntSize)aspectSize
{
    return OEIntSizeMake(ROM_PARAMS.systemtype == SYSTEM_NTSC ? _videoWidth * (120.0 / 119.0) : _videoWidth, _videoHeight);
}

- (OEIntSize)bufferSize
{
    return OEIntSizeMake(_videoWidth, _videoHeight);
}

- (BOOL)tryToResizeVideoTo:(OEIntSize)size
{
    VidExt_SetVideoMode(size.width, size.height, 32, M64VIDEO_WINDOWED, 0);
    if (ptr_OE_ForceUpdateWindowSize) ptr_OE_ForceUpdateWindowSize(size.width, size.height);
    return YES;
}

- (OEGameCoreRendering)gameCoreRendering
{
    //return OEGameCoreRenderingOpenGL2Video;
    return OEGameCoreRenderingOpenGL3Video; // Set for GLideN64
}

- (BOOL)hasAlternateRenderingThread
{
    return YES;
}

//- (BOOL)needsDoubleBufferedFBO
//{
//    return YES;
//}

- (const void *)videoBuffer
{
    return NULL;
}

- (GLenum)pixelFormat
{
    return GL_BGRA;
}

- (GLenum)pixelType
{
    return GL_UNSIGNED_INT_8_8_8_8_REV;
}

- (GLenum)internalPixelFormat
{
    return GL_RGB8;
}

#pragma mark - Audio

- (double)audioSampleRate
{
    return _sampleRate;
}

- (NSUInteger)channelCount
{
    return 2;
}

#pragma mark - Save States

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    /*
     Blocks run in this order:
     scheduleSaveState -> M64CORE_STATE_SAVECOMPLETE
     */

    [self OE_addHandlerForType:M64CORE_STATE_SAVECOMPLETE usingBlock:
     ^ BOOL (m64p_core_param paramType, int newValue)
     {
         // Reset the paused state back to where it was.
         [self endPausedExecution];
         NSAssert(paramType == M64CORE_STATE_SAVECOMPLETE, @"This block should only be called for save completion!");
         dispatch_async(dispatch_get_main_queue(), ^{
             if(newValue == 0)
             {
                 NSError *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotSaveStateError userInfo:@{
                     NSLocalizedDescriptionKey : @"Mupen Could not save the current state.",
                     NSFilePathErrorKey : fileName
                 }];
                 block(NO, error);
                 return;
             }

             block(YES, nil);
         });
         return NO;
     }];

    BOOL (^scheduleSaveState)(void) =
    ^ BOOL {
        if(CoreDoCommand(M64CMD_STATE_SAVE, 1, (void *)fileName.fileSystemRepresentation) == M64ERR_SUCCESS)
        {
            // Mupen needs to be running to process the save.
            [self beginPausedExecution];
            return YES;
        }

        return NO;
    };

    if(scheduleSaveState()) return;

    [self OE_addHandlerForType:M64CORE_EMU_STATE usingBlock:
     ^ BOOL (m64p_core_param paramType, int newValue)
     {
         NSAssert(paramType == M64CORE_EMU_STATE, @"This block should only be called for load completion!");
         if(newValue != M64EMU_RUNNING && newValue != M64EMU_PAUSED)
             return YES;

         return !scheduleSaveState();
     }];
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    if(_initializing)
    {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1000 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            int success = CoreDoCommand(M64CMD_STATE_LOAD, 1, (void *)fileName.fileSystemRepresentation);
            if (success == M64ERR_SUCCESS && self->_rcClient) {
                rc_client_reset(self->_rcClient);
            }
            if(block) block(success==M64ERR_SUCCESS, nil);
       });
    }
    else
    {
        [self OE_addHandlerForType:M64CORE_STATE_LOADCOMPLETE usingBlock:
         ^ BOOL (m64p_core_param paramType, int newValue)
         {
             NSAssert(paramType == M64CORE_STATE_LOADCOMPLETE, @"This block should only be called for load completion!");

             [self endPausedExecution];
             dispatch_async(dispatch_get_main_queue(), ^{
                 if(newValue == 0)
                 {
                     NSError *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadStateError userInfo:@{
                         NSLocalizedDescriptionKey : @"Mupen Could not load the save state",
                         NSLocalizedRecoverySuggestionErrorKey : @"The loaded file is probably corrupted.",
                         NSFilePathErrorKey : fileName
                     }];
                     block(NO, error);
                     return;
                 }

                 if (self->_rcClient) {
                     rc_client_reset(self->_rcClient);
                 }
                 block(YES, nil);
             });
             return NO;
         }];

        BOOL (^scheduleLoadState)(void) =
        ^ BOOL {
            if(CoreDoCommand(M64CMD_STATE_LOAD, 1, (void *)fileName.fileSystemRepresentation) == M64ERR_SUCCESS)
            {
                // Mupen needs to be running to process the save.
                [self beginPausedExecution];
                return YES;
            }

            return NO;
        };

        if(scheduleLoadState()) return;

        [self OE_addHandlerForType:M64CORE_EMU_STATE usingBlock:
         ^ BOOL (m64p_core_param paramType, int newValue)
         {
             NSAssert(paramType == M64CORE_EMU_STATE, @"This block should only be called for load completion!");
             if(newValue != M64EMU_RUNNING && newValue != M64EMU_PAUSED)
                 return YES;

             return !scheduleLoadState();
         }];
    }
}

#pragma mark - Input

- (oneway void)didMoveN64JoystickDirection:(OEN64Button)button withValue:(CGFloat)value forPlayer:(NSUInteger)player
{
    // N64 Programming Manual: The 3D Control Stick data is of type signed char and in the range between 80 and -80
    // TODO: handle analog gamepad deadzone and peak through API, e.g.
    /*
    int deadzone = 4096;
    int peak = 32767;
    int range = peak - deadzone;

    int joyVal = value * 32767;
    int axisVal = ((abs(joyVal) - deadzone) * 80 / range);
     */

    player -= 1;
    switch (button)
    {
        case OEN64AnalogUp:
            _yAxis[player] = value * 80;
            break;
        case OEN64AnalogDown:
            _yAxis[player] = value * -80;
            break;
        case OEN64AnalogLeft:
            _xAxis[player] = value * -80;
            break;
        case OEN64AnalogRight:
            _xAxis[player] = value * 80;
            break;
        default:
            break;
    }
}

- (oneway void)didPushN64Button:(OEN64Button)button forPlayer:(NSUInteger)player
{
    player -= 1;
    _padData[player][button] = 1;
}

- (oneway void)didReleaseN64Button:(OEN64Button)button forPlayer:(NSUInteger)player
{
    player -= 1;
    _padData[player][button] = 0;
}

#pragma mark - Cheats

- (void)setCheat:(NSString *)code setType:(NSString *)type setEnabled:(BOOL)enabled
{
    // Sanitize
    code = [code stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    
    // Remove any spaces
    code = [code stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    NSString *singleCode;
    NSArray<NSString *> *multipleCodes = [code componentsSeparatedByString:@"+"];
    m64p_cheat_code *gsCode = (m64p_cheat_code*) calloc(multipleCodes.count, sizeof(m64p_cheat_code));
    int codeCounter = 0;
    
    for (singleCode in multipleCodes)
    {
        if (singleCode.length == 12) // GameShark
        {
            // GameShark N64 format: XXXXXXXX YYYY
            NSString *address = [singleCode substringWithRange:NSMakeRange(0, 8)];
            NSString *value = [singleCode substringWithRange:NSMakeRange(8, 4)];
            
            // Convert GS hex to int
            unsigned int outAddress, outValue;
            NSScanner *scanAddress = [NSScanner scannerWithString:address];
            NSScanner *scanValue = [NSScanner scannerWithString:value];
            [scanAddress scanHexInt:&outAddress];
            [scanValue scanHexInt:&outValue];
            
            gsCode[codeCounter].address = outAddress;
            gsCode[codeCounter].value = outValue;
            codeCounter++;
        }
    }
    
    // Remap button-activated GS codes (require physical GS button) to always-on
    // equivalents — OpenEmu has no GS button so they would never fire otherwise.
    for (int i = 0; i < codeCounter; i++) {
        uint32_t addrType = gsCode[i].address & 0xFF000000;
        if (addrType == 0x88000000 || addrType == 0xA8000000)
            gsCode[i].address = (gsCode[i].address & 0x00FFFFFF) | 0x80000000;
        else if (addrType == 0x89000000 || addrType == 0xA9000000)
            gsCode[i].address = (gsCode[i].address & 0x00FFFFFF) | 0x81000000;
    }

    if (codeCounter > 0) {
        if (enabled)
            CoreAddCheat(code.UTF8String, gsCode, codeCounter);
        else
            CoreCheatEnabled(code.UTF8String, 0);
    }

    free(gsCode);
}

@end
