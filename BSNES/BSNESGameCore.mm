/*
 Copyright (c) 2012, OpenEmu Team
 

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

#import <OpenGL/gl.h>
#import "BSNESGameCore.h"
#import "OESNESSystemResponderClient.h"

#define SYS_PARAM_H__BSD BSD
#undef BSD

#include "program.mm"

#include <os/log.h>
#define RC_CLIENT_SUPPORTS_HASH 1
#include <rc_client.h>
#include <rc_consoles.h>
#import "OERetroAchievementsTransport.h"


/*
 * TODO
 *  - Multitap support
 *  - Mouse support
 */


@interface BSNESGameCore (RetroAchievements)
- (void)_beginLoadGame;
- (void)_postRetroAchievementsSessionSnapshot;
@end

// rcheevos memory callback.
//
// rcheevos SNES address space (consoleinfo.c):
//   0x000000–0x01FFFF → 128 KB WRAM (bus 0x7E0000–0x7FFFFF)
//
// Reads via Emulator::Interface::read() which internally calls
// cpu.readDisassembler(address) — the same bus read used for the debugger.
//
static uint32_t bsnes_rc_read_memory(uint32_t address, uint8_t *buffer,
                                      uint32_t num_bytes, rc_client_t *client)
{
    if (!emulator) { return 0; }
    for (uint32_t i = 0; i < num_bytes; i++) {
        uint32_t addr = address + i;
        if (addr <= 0x01FFFF)
            buffer[i] = emulator->read(0x7E0000 + addr);
        else
            return i;
    }
    return num_bytes;
}

static void bsnes_rc_log(const char *message, const rc_client_t *client)
{
    os_log(OS_LOG_DEFAULT, "[rcheevos] %{public}s", message);
}

static void bsnes_rc_load_game_callback(int result, const char *error_message,
                                         rc_client_t *client, void *userdata)
{
    BSNESGameCore *self = (__bridge BSNESGameCore *)userdata;
    if (result != RC_OK) {
        NSLog(@"[RA-BSNES] game load failed — result=%d error=%s", result, error_message ?: "(none)");
        return;
    }
    [self _postRetroAchievementsSessionSnapshot];
}

static void bsnes_rc_login_callback(int result, const char *error_message,
                                     rc_client_t *client, void *userdata)
{
    BSNESGameCore *s = (__bridge BSNESGameCore *)userdata;
    if (result == RC_OK) {
        [s _beginLoadGame];
    } else {
        NSLog(@"[RA-BSNES] login failed — result=%d error=%s", result, error_message ?: "(none)");
    }
}

static void bsnes_rc_event_handler(const rc_client_event_t *event, rc_client_t *client)
{
    oeRetroAchievementsPostEventNotification(event, client);
    if (event->type != RC_CLIENT_EVENT_ACHIEVEMENT_TRIGGERED) { return; }
    const rc_client_achievement_t *ach = event->achievement;
    if (!ach) { return; }

    NSDictionary *info = @{
        OEAchievementIDKey:          @(ach->id),
        OEAchievementTitleKey:       @(ach->title       ?: ""),
        OEAchievementDescriptionKey: @(ach->description  ?: ""),
        OEAchievementBadgeURLKey:    @(ach->badge_name   ?: ""),
        OEAchievementPointsKey:      @(ach->points),
    };
    [[NSNotificationCenter defaultCenter]
        postNotificationName:OEAchievementUnlockedNotification
                      object:nil
                    userInfo:info];
    BSNESGameCore *core = (__bridge BSNESGameCore *)rc_client_get_userdata(client);
    [core _postRetroAchievementsSessionSnapshot];
}

@implementation BSNESGameCore {
    NSMutableSet <NSString *> *_activeCheats;
    NSMutableDictionary <NSString *, id> *_displayModes;
    rc_client_t *_rcClient;
    id _raTokenObserver;
    BOOL _raHardcoreEnabled;
    id _raHardcoreObserver;
    NSString *_romPath;
}

- (id)init
{
    self = [super init];
    emulator = new SuperFamicom::Interface;
    program = new Program(self);
    _activeCheats = [[NSMutableSet alloc] init];
    _displayModes = [[NSMutableDictionary alloc] init];
    screenRect = OEIntRectMake(0, 0, 256, 224);
    return self;
}

- (void)_beginLoadGame
{
    if (!_rcClient || !_romPath) { return; }
    rc_client_begin_identify_and_load_game(_rcClient,
                                           RC_CONSOLE_SUPER_NINTENDO,
                                           _romPath.fileSystemRepresentation,
                                           NULL, 0,
                                           bsnes_rc_load_game_callback,
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

- (void)dealloc
{
    delete emulator;
    delete program;
}


#pragma mark - Configuration & Cheats


- (void)setDisplayModeInfo:(NSDictionary<NSString *, id> *)displayModeInfo
{
    const struct {
        NSString *key;
        Class valueClass;
        id defaultValue;
    } defaultValues[] = {
        { @"bsnes/Video/BlurEmulation",         [NSNumber class], @NO  },
        { @"bsnes/Video/ColorEmulation",        [NSNumber class], @YES },
        { @"bsnes/Hacks/PPU/NoSpriteLimit",     [NSNumber class], @NO },
        { @"bsnes/Hacks/PPU/Mode7/Scale",       [NSString class], @"1" }};
    
    /* validate the defaults to avoid crashes caused by users playing
     * around where they shouldn't */
    _displayModes = [[NSMutableDictionary alloc] init];
    int n = sizeof(defaultValues)/sizeof(defaultValues[0]);
    for (int i=0; i<n; i++) {
        id thisPref = displayModeInfo[defaultValues[i].key];
        if ([thisPref isKindOfClass:defaultValues[i].valueClass])
            _displayModes[defaultValues[i].key] = thisPref;
        else
            _displayModes[defaultValues[i].key] = defaultValues[i].defaultValue;
    }
}

- (NSDictionary<NSString *,id> *)displayModeInfo
{
    return [_displayModes copy];
}

- (NSArray<NSDictionary<NSString *,id> *> *)displayModes
{
    #define OptionToggleable(n, k) \
        OEDisplayMode_OptionToggleableWithState(n, k, _displayModes[k])
    #define OptionWithValue(n, k, v) \
        OEDisplayMode_OptionWithStateValue(n, k, @([_displayModes[k] isEqual:v]), v)
    return @[
        OptionToggleable(@"Blur Emulation", @"bsnes/Video/BlurEmulation"),
        OptionToggleable(@"Color Emulation", @"bsnes/Video/ColorEmulation"),
        OEDisplayMode_SeparatorItem(),
        OEDisplayMode_Label(@"HD Mode 7"),
        OptionWithValue(@"240p (disabled)", @"bsnes/Hacks/PPU/Mode7/Scale", @"1"),
        OptionWithValue(@"480p", @"bsnes/Hacks/PPU/Mode7/Scale", @"2"),
        OptionWithValue(@"720p", @"bsnes/Hacks/PPU/Mode7/Scale", @"3"),
        OptionWithValue(@"960p", @"bsnes/Hacks/PPU/Mode7/Scale", @"4"),
        OptionWithValue(@"1200p", @"bsnes/Hacks/PPU/Mode7/Scale", @"5"),
        OptionWithValue(@"1440p", @"bsnes/Hacks/PPU/Mode7/Scale", @"6"),
        OptionWithValue(@"1680p", @"bsnes/Hacks/PPU/Mode7/Scale", @"7"),
        OptionWithValue(@"1920p", @"bsnes/Hacks/PPU/Mode7/Scale", @"8"),
        OEDisplayMode_SeparatorItem(),
        OptionToggleable(@"Disable Sprite Limit (requires reset)", @"bsnes/Hacks/PPU/NoSpriteLimit"),
    ];
    #undef OptionToggleable
    #undef OptionWithValue
}

- (void)changeDisplayWithMode:(NSString *)displayMode
{
    NSString *key;
    id currentVal;
    OEDisplayModeListGetPrefKeyValueFromModeName(self.displayModes, displayMode, &key, &currentVal);
    if ([currentVal isKindOfClass:[NSNumber class]])
        _displayModes[key] = @(![currentVal boolValue]);
    else
        _displayModes[key] = currentVal;
    [self loadConfiguration];
}

- (void)loadConfiguration
{
    [_displayModes enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
        if ([key hasPrefix:@"bsnes/"]) {
            NSString *keyNoPrefix = [key substringFromIndex:@"bsnes/".length];
            if ([obj isKindOfClass:[NSNumber class]])
                emulator->configure(keyNoPrefix.UTF8String, (bool)[obj boolValue]);
            else if ([obj isKindOfClass:[NSString class]])
                emulator->configure(keyNoPrefix.UTF8String, [obj UTF8String]);
        }
    }];
    program->updateVideoPalette();
}

- (void)setCheat:(NSString *)code setType:(NSString *)type setEnabled:(BOOL)enabled
{
    if ([type isEqual:@"Action Replay"])
        code = [code stringByReplacingOccurrencesOfString:@":" withString:@""];
    NSArray <NSString *> *codes = [code componentsSeparatedByString:@"+"];
    if (enabled)
        [_activeCheats addObjectsFromArray:codes];
    else
        [_activeCheats minusSet:[NSSet setWithArray:codes]];
    [self loadCheats];
}

- (void)loadCheats
{
    vector<string> newCheatList;
    for (NSString *cheat in _activeCheats) {
        string decodedCheat = string(cheat.UTF8String).downcase();
        if (OEBSNESCheatDecodeSNES(decodedCheat)) {
            NSLog(@"Successfully decoded cheat %@ to %s", cheat, decodedCheat.begin());
            newCheatList.append(decodedCheat);
        } else {
            NSLog(@"Could not decode cheat %@", cheat);
        }
    }
    emulator->cheats(newCheatList);
}


#pragma mark - Load / Save


- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
    memset(pad, 0, sizeof(pad));
    
    emulator->configure("Hacks/Hotfixes", true);
    emulator->configure("Hacks/PPU/Fast", true);
    [self loadConfiguration];
    
    NSString *batterySavesDirectory = [self batterySavesDirectoryPath];
    NSAssert(batterySavesDirectory.length > 0, @"no battery save directory!?");
    [[NSFileManager defaultManager] createDirectoryAtPath:batterySavesDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    
    const char *fullPath = path.fileSystemRepresentation;
    program->superFamicom.location = string(fullPath);
    program->base_name = string(fullPath);
    program->load();
    
    if (program->failedLoadingAtLeastOneRequiredFile) {
        NSError *outErr;
        if (program->lastFailedBiosLoad) {
            NSString *missing = [NSString stringWithUTF8String:program->lastFailedBiosLoad.get().begin()];
            outErr = [NSError
                errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError
                userInfo:@{
                    NSLocalizedDescriptionKey: @"Required chip dump file missing.",
                    NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:
                        @"To run this game you need the following file:\n"
                        @"\"%@\"\n\n"
                        @"Obtain this file, drag and drop onto the game library "
                        @"window and try again.", missing]}];
        }
        if (error)
            *error = outErr;
        return NO;
    }
    
    emulator->connect(SuperFamicom::ID::Port::Controller1, SuperFamicom::ID::Device::Gamepad);
    emulator->connect(SuperFamicom::ID::Port::Controller2, SuperFamicom::ID::Device::Gamepad);
    [self loadCheats];

    _romPath = path;
    _rcClient = rc_client_create(bsnes_rc_read_memory, oeRetroAchievementsServerCall);
    if (_rcClient) {
        rc_client_set_userdata(_rcClient, (__bridge void *)self);
        rc_client_set_event_handler(_rcClient, bsnes_rc_event_handler);
        _raHardcoreEnabled = YES;
        rc_client_set_hardcore_enabled(_rcClient, _raHardcoreEnabled ? 1 : 0);
        rc_client_enable_logging(_rcClient, RC_CLIENT_LOG_LEVEL_INFO, bsnes_rc_log);

        __weak BSNESGameCore *weakSelf = self;
        _raTokenObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:OERetroAchievementsTokenDidChangeNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) {
            BSNESGameCore *s = weakSelf;
            if (!s || !s->_rcClient) { return; }
            NSString *token    = note.userInfo[OERetroAchievementsTokenKey];
            NSString *username = note.userInfo[OERetroAchievementsUsernameKey];
            if (token && username) {
                rc_client_begin_login_with_token(s->_rcClient,
                                                 username.UTF8String,
                                                 token.UTF8String,
                                                 bsnes_rc_login_callback,
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

- (NSData *)serializeStateWithError:(NSError *__autoreleasing *)outError
{
    serializer s = emulator->serialize();
    return [NSData dataWithBytes:s.data() length:s.size()];
}

- (BOOL)deserializeState:(NSData *)state withError:(NSError *__autoreleasing *)outError
{
    serializer s(static_cast<const uint8_t *>(state.bytes), (uint)state.length);
    BOOL res = emulator->unserialize(s);
    if (!res && outError)
        *outError = [NSError
            errorWithDomain:OEGameCoreErrorDomain
            code:OEGameCoreCouldNotLoadStateError
            userInfo:@{
                NSLocalizedDescriptionKey: @"The save state data could not be read.",
                NSLocalizedRecoverySuggestionErrorKey: @"When the BSNES core is updated, existing save states may stop working. This is normal and unavoidable.\n\nPlease use in-game saves as much as possible instead."
            }];
    if (res && _rcClient)
        rc_client_reset(_rcClient);
    return res;
}

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    NSData *stateData = [self serializeStateWithError:nil];
    
    __autoreleasing NSError *error = nil;
    BOOL success = [stateData writeToFile:fileName options:NSDataWritingAtomic error:&error];
    
    block(success, success ? nil : error);
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    __autoreleasing NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:fileName options:NSDataReadingMappedIfSafe | NSDataReadingUncached error:&error];
    
    if(data == nil) {
        block(NO, error);
        return;
    }
    
    BOOL success = [self deserializeState:data withError:&error];
    block(success, success ? nil : error);
}


#pragma mark - Input


- (oneway void)didPushSNESButton:(OESNESButton)button forPlayer:(NSUInteger)player;
{
    NSAssert(player > 0 && player <= 2, @"too many players");
    pad[player-1][button] = YES;
}

- (oneway void)didReleaseSNESButton:(OESNESButton)button forPlayer:(NSUInteger)player;
{
    NSAssert(player > 0 && player <= 2, @"too many players");
    pad[player-1][button] = NO;
}

- (oneway void)leftMouseDownAtPoint:(OEIntPoint)point
{
}

- (oneway void)leftMouseUp
{
}

- (oneway void)mouseMovedAtPoint:(OEIntPoint)point
{
}

- (oneway void)rightMouseDownAtPoint:(OEIntPoint)point
{
}

- (oneway void)rightMouseUp
{
}


#pragma mark - Execution


- (void)executeFrame
{
    emulator->run();
    if (_rcClient)
        rc_client_do_frame(_rcClient);
}

- (void)resetEmulation
{
    if (_rcClient)
        rc_client_reset(_rcClient);
    emulator->reset();
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
    program->save();
    [super stopEmulation];
}


#pragma mark - Video


- (const void *)getVideoBufferWithHint:(void *)hint
{
    NSAssert(hint, @"no hint? bummer");
    videoBuffer = (uint32_t *)hint;
    return hint;
}

- (OEIntRect)screenRect
{
    return screenRect;
}

- (OEIntSize)bufferSize
{
    return OEIntSizeMake(OE_VIDEO_BUFFER_SIZE_W, OE_VIDEO_BUFFER_SIZE_H);
}

- (OEIntSize)aspectSize
{
    if (!(program->overscan)) {
        /* Overscan hiding removes the top and bottom 8 pixels. */
        return OEIntSizeMake(256 * 8, 224 * 7);
    }
    return OEIntSizeMake(8, 7);
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

- (NSTimeInterval)frameInterval
{
    if (program->superFamicom.region == "NTSC") {
        return 21477272.0 / 357366.0;
    }
    return 21281370.0 / 425568.0;
}


#pragma mark - Audio


- (double)audioSampleRate
{
    return Emulator::audio.frequency();
}

- (NSUInteger)channelCount
{
    return Emulator::audio.channels();
}


@end
