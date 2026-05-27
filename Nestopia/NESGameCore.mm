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

#import "NESGameCore.h"
#import <OpenEmuBase/OERingBuffer.h>
#import "OENESSystemResponderClient.h"
#import "OEFDSSystemResponderClient.h"
#import <OpenGL/gl.h>

#include <os/log.h>
#define RC_CLIENT_SUPPORTS_HASH 1
#include <rc_client.h>
#include <rc_consoles.h>
#import "OERetroAchievementsTransport.h"

#include <NstBase.hpp>
#include <NstApiEmulator.hpp>
#include <NstApiMachine.hpp>
#include <NstApiCartridge.hpp>
#include <NstApiInput.hpp>
#include <NstApiVideo.hpp>
#include <NstApiSound.hpp>
#include <NstApiUser.hpp>
#include <NstApiCheats.hpp>
#include <NstApiFds.hpp>
#include <NstMachine.hpp>
#include <iostream>
#include <fstream>
#include <sstream>

#define SAMPLERATE 48000
#define OVERSCAN_VERTICAL 8
#define OVERSCAN_HORIZONTAL 8

#define OptionDefault(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @YES, }
#define Option(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, }
#define OptionIndented(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, OEGameCoreDisplayModeIndentationLevelKey : @(1), }
#define OptionToggleable(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, OEGameCoreDisplayModeAllowsToggleKey : @YES, }
#define OptionToggleableNoSave(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, OEGameCoreDisplayModeAllowsToggleKey : @YES, OEGameCoreDisplayModeDisallowPrefSaveKey : @YES, }
#define Label(_NAME_) @{ OEGameCoreDisplayModeLabelKey : _NAME_, }
#define SeparatorItem() @{ OEGameCoreDisplayModeSeparatorItemKey : @"",}

static void NST_CALLBACK doFileIO(void *userData, Nes::Api::User::File &file);
static Nes::Api::User::Answer NST_CALLBACK doQuestion(void *userData, Nes::Api::User::Question question);
static void NST_CALLBACK doLog(void *userData, const char *text, unsigned long length);
static void NST_CALLBACK doEvent(void *userData, Nes::Api::Machine::Event event, Nes::Result result);

@interface NESGameCore () <OENESSystemResponderClient, OEFDSSystemResponderClient>
{
    NSURL               *_romURL;
    int                  _bufFrameSize;
    int                  _videoWidth, _videoHeight;
    int                  _videoOffsetX, _videoOffsetY;
    int                  _aspectWidth, _aspectHeight;
    const unsigned char *_indirectVideoBuffer;
    int16_t             *_soundBuffer;
    BOOL                 _isHorzOverscanCropped;
    BOOL                 _isVertOverscanCropped;

    Nes::Api::Emulator       _emu;
    Nes::Api::Sound::Output *_nesSound;
    Nes::Api::Video::Output *_nesVideo;
    Nes::Api::Input::Controllers *_controls;

    NSMutableDictionary<NSString *, NSNumber *> *_cheatList;
    NSMutableArray <NSMutableDictionary <NSString *, id> *> *_availableDisplayModes;
    rc_client_t *_rcClient;
    id _raTokenObserver;
    BOOL _raHardcoreEnabled;
    id _raHardcoreObserver;
    int _rcConsole;
}

- (void)loadDisplayModeOptions;
- (void)_beginLoadGame;
- (void)_postRetroAchievementsSessionSnapshot;
- (const uint8_t *)_nesRamBytesForRC;

@end

// rcheevos memory callback.
//
// rcheevos NES/FDS address space (consoleinfo.c):
//   0x0000–0x07FF → 2 KB NES work RAM
//
static uint32_t nestopia_rc_read_memory(uint32_t address, uint8_t *buffer,
                                         uint32_t num_bytes, rc_client_t *client)
{
    NESGameCore *s = (__bridge NESGameCore *)rc_client_get_userdata(client);
    const uint8_t *ram = [s _nesRamBytesForRC];
    if (!ram) { return 0; }
    for (uint32_t i = 0; i < num_bytes; i++) {
        uint32_t addr = address + i;
        if (addr <= 0x07FF)
            buffer[i] = ram[addr];
        else
            return i;
    }
    return num_bytes;
}

static void nestopia_rc_log(const char *message, const rc_client_t *client)
{
    os_log(OS_LOG_DEFAULT, "[rcheevos] %{public}s", message);
}

static void nestopia_rc_load_game_callback(int result, const char *error_message,
                                            rc_client_t *client, void *userdata)
{
    NESGameCore *self = (__bridge NESGameCore *)userdata;
    if (result != RC_OK) {
        NSLog(@"[RA-Nestopia] game load failed — result=%d error=%s", result, error_message ?: "(none)");
        oeRetroAchievementsPostSessionLoadFailure(result, error_message);
        return;
    }
    [self _postRetroAchievementsSessionSnapshot];
}

static void nestopia_rc_login_callback(int result, const char *error_message,
                                        rc_client_t *client, void *userdata)
{
    NESGameCore *s = (__bridge NESGameCore *)userdata;
    if (result == RC_OK) {
        [s _beginLoadGame];
    } else {
        oeRetroAchievementsPostLoginFailure(result, error_message);
        NSLog(@"[RA-Nestopia] login failed — result=%d error=%s", result, error_message ?: "(none)");
    }
}

static void nestopia_rc_event_handler(const rc_client_event_t *event, rc_client_t *client)
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
    NESGameCore *core = (__bridge NESGameCore *)rc_client_get_userdata(client);
    [core _postRetroAchievementsSessionSnapshot];
}

@implementation NESGameCore

static __weak NESGameCore *_current;

- (id)init;
{
    if((self = [super init]))
    {
        _current = self;
        _nesSound = new Nes::Api::Sound::Output;
        _nesVideo = new Nes::Api::Video::Output;
        _controls = new Nes::Api::Input::Controllers;
        _cheatList = [NSMutableDictionary dictionary];
    }

    return self;
}

- (const uint8_t *)_nesRamBytesForRC
{
    Nes::Core::Machine &machine = _emu;
    return (const uint8_t *)machine.cpu.GetRam();
}

- (void)_beginLoadGame
{
    if (!_rcClient || !_romURL) { return; }
    rc_client_begin_identify_and_load_game(_rcClient,
                                           (uint32_t)_rcConsole,
                                           _romURL.fileSystemRepresentation,
                                           NULL, 0,
                                           nestopia_rc_load_game_callback,
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


- (void)retroAchievementsIdle
{
    if (_rcClient) {
        rc_client_idle(_rcClient);
    }
}

- (BOOL)canPauseRetroAchievementsHardcoreWithFramesRemaining:(uint32_t *)framesRemaining
{
    if (!_rcClient) { return YES; }
    return rc_client_can_pause(_rcClient, framesRemaining) != 0;
}

- (NSData *)retroAchievementsSerializedProgress {
    if (!_rcClient) return nil;
    size_t size = rc_client_progress_size(_rcClient);
    if (size == 0) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:size];
    rc_client_serialize_progress(_rcClient, data.mutableBytes);
    return data;
}

- (void)retroAchievementsDeserializeProgress:(NSData *)data {
    if (!_rcClient) return;
    rc_client_deserialize_progress(_rcClient, data ? data.bytes : NULL);
}

- (void)dealloc
{
    delete[] _soundBuffer;
    delete[] _indirectVideoBuffer;
    delete _nesSound;
    delete _nesVideo;
    delete _controls;
}

# pragma mark - Execution

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
    Nes::Result result;
    Nes::Api::Machine machine(_emu);
    Nes::Api::Cartridge::Database database(_emu);

    // Load database
    if(!database.IsLoaded())
    {
        NSURL *databaseURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"NstDatabase" withExtension:@"xml"];
        if ([databaseURL checkResourceIsReachableAndReturnError:nil])
        {
            std::ifstream databaseStream(databaseURL.fileSystemRepresentation, std::ifstream::in | std::ifstream::binary);
            database.Load(databaseStream);
            database.Enable(true);
            databaseStream.close();
        }
        else
            NSLog(@"[Nestopia] NstDatabase.xml not found!");
    }

    _romURL = [NSURL fileURLWithPath:path];

    // Setup callbacks
    Nes::Api::User::fileIoCallback.Set(doFileIO, 0);
    Nes::Api::User::logCallback.Set(doLog, 0);
    Nes::Api::Machine::eventCallback.Set(doEvent, 0);
    Nes::Api::User::questionCallback.Set(doQuestion, 0);

    // Load FDS BIOS
    Nes::Api::Fds fds(_emu);
    if([self.systemIdentifier isEqualToString:@"openemu.system.fds"])
    {
        NSString *biosFilePath = [self.biosDirectoryPath stringByAppendingPathComponent:@"disksys.rom"];
        std::ifstream biosFile(biosFilePath.fileSystemRepresentation, std::ios::in | std::ios::binary);
        fds.SetBIOS(&biosFile);
    }

    // Load ROM
    std::ifstream romFile(path.fileSystemRepresentation, std::ios::in | std::ios::binary);
    result = machine.Load(romFile, Nes::Api::Machine::FAVORED_NES_NTSC, Nes::Api::Machine::ASK_PROFILE);

    if(NES_FAILED(result))
    {
        NSString *errorDescription = nil;
        switch(result)
        {
            case Nes::RESULT_ERR_INVALID_FILE :
                errorDescription = NSLocalizedStringFromTableInBundle(@"Invalid file.", nil, [NSBundle bundleForClass:[self class]], @"Invalid file.");
                break;
            case Nes::RESULT_ERR_OUT_OF_MEMORY :
                errorDescription = NSLocalizedStringFromTableInBundle(@"Out of memory.", nil, [NSBundle bundleForClass:[self class]], @"Out of memory.");
                break;
            case Nes::RESULT_ERR_CORRUPT_FILE :
                errorDescription = NSLocalizedStringFromTableInBundle(@"Corrupt file.", nil, [NSBundle bundleForClass:[self class]], @"Corrupt file.");
                break;
            case Nes::RESULT_ERR_UNSUPPORTED_MAPPER :
                errorDescription = NSLocalizedStringFromTableInBundle(@"Unsupported mapper.", nil, [NSBundle bundleForClass:[self class]], @"Unsupported mapper.");
                break;
            case Nes::RESULT_ERR_MISSING_BIOS :
                errorDescription = NSLocalizedStringFromTableInBundle(@"Can't find disksys.rom for FDS game.", nil, [NSBundle bundleForClass:[self class]], @"Can't find disksys.rom for FDS game.");
                break;
            default :
                errorDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unknown nestopia error #%d.", nil, [NSBundle bundleForClass:[self class]], @"Unknown nestopia error #%d."), result];
                break;
        }

        NSError *outErr = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{
                //NSLocalizedDescriptionKey : @"Could not load ROM.",
                NSDebugDescriptionErrorKey : @"Could not load ROM.",
                NSLocalizedDescriptionKey : errorDescription,
                //NSLocalizedRecoverySuggestionErrorKey : errorDescription
                }];

        if (error) {
            *error = outErr;
        }

        return NO;
    }
    machine.Power(true);
    
    if (machine.Is(Nes::Api::Machine::DISK))
        fds.InsertDisk(0, 0);

    // Only temporary, so core doesn't crash on an older OpenEmu version
    if ([self respondsToSelector:@selector(displayModeInfo)]) {
        [self loadDisplayModeOptions];
    }

    _rcConsole = [self.systemIdentifier isEqualToString:@"openemu.system.fds"]
        ? RC_CONSOLE_FAMICOM_DISK_SYSTEM
        : RC_CONSOLE_NINTENDO;

    _rcClient = rc_client_create(nestopia_rc_read_memory, oeRetroAchievementsServerCall);
    if (_rcClient) {
        rc_client_set_userdata(_rcClient, (__bridge void *)self);
        rc_client_set_event_handler(_rcClient, nestopia_rc_event_handler);
        _raHardcoreEnabled = YES;
        rc_client_set_hardcore_enabled(_rcClient, _raHardcoreEnabled ? 1 : 0);
        rc_client_set_allow_background_memory_reads(_rcClient, 0);
        rc_client_enable_logging(_rcClient, RC_CLIENT_LOG_LEVEL_INFO, nestopia_rc_log);

        __weak NESGameCore *weakSelf = self;
        _raTokenObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:OERetroAchievementsTokenDidChangeNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) {
            NESGameCore *s = weakSelf;
            if (!s || !s->_rcClient) { return; }
            NSString *token    = note.userInfo[OERetroAchievementsTokenKey];
            NSString *username = note.userInfo[OERetroAchievementsUsernameKey];
            if (token && username) {
                rc_client_begin_login_with_token(s->_rcClient,
                                                 username.UTF8String,
                                                 token.UTF8String,
                                                 nestopia_rc_login_callback,
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
    // Auto connect controllers/adapter, info from database
    Nes::Api::Cartridge::Database database(_emu);

    if(database.IsLoaded())
    {
        Nes::Api::Input(_emu).AutoSelectControllers();
        Nes::Api::Input(_emu).AutoSelectAdapter();
    }
    else
        Nes::Api::Input(_emu).ConnectController(0, Nes::Api::Input::PAD1);

    // Auto set video format, info from database
    Nes::Api::Machine machine(_emu);
    machine.SetMode(machine.GetDesiredMode());

    // Setup Video
    Nes::Api::Video::RenderState renderState;

    renderState.bits.count = 32;
    renderState.bits.mask.r = 0xFF0000;
    renderState.bits.mask.g = 0x00FF00;
    renderState.bits.mask.b = 0x0000FF;

    renderState.filter = Nes::Api::Video::RenderState::FILTER_NONE;
    renderState.width = Nes::Api::Video::Output::WIDTH;
    renderState.height = Nes::Api::Video::Output::HEIGHT;

    Nes::Api::Video video(_emu);
    // set the render state, make use of the NES_FAILED macro, expands to: "if(function(...) < Nes::RESULT_OK)"
    if(NES_FAILED(video.SetRenderState(renderState)))
    {
        NSLog(@"[Nestopia] core rejected render state");
        exit(0);
    }

    // Setup Audio
    Nes::Api::Sound sound(_emu);
    sound.SetSampleRate(SAMPLERATE);
    sound.SetVolume(Nes::Api::Sound::ALL_CHANNELS, 100);
    sound.SetSpeaker(Nes::Api::Sound::SPEAKER_MONO);
    sound.SetSpeed(self.frameInterval);

    _bufFrameSize = (SAMPLERATE / self.frameInterval);

    _soundBuffer = new int16_t[_bufFrameSize * self.channelCount];
    //[[self ringBufferAtIndex:0] setLength:(sizeof(int16_t) * _bufFrameSize * self.channelCount * 5)];

    memset(_soundBuffer, 0, _bufFrameSize * self.channelCount * sizeof(int16_t));
    _nesSound->samples[0] = _soundBuffer;
    _nesSound->length[0] = _bufFrameSize;
    _nesSound->samples[1] = NULL;
    _nesSound->length[1] = 0;
}

- (void)executeFrame
{
    _emu.Execute(_nesVideo, _nesSound, _controls);

    if (_rcClient)
        rc_client_do_frame(_rcClient);

    [[self audioBufferAtIndex:0] write:_soundBuffer maxLength:self.channelCount * _bufFrameSize * sizeof(int16_t)];
}

- (void)resetEmulation
{
    if (_rcClient)
        rc_client_reset(_rcClient);

    Nes::Api::Machine machine(_emu);
    machine.Reset(true);

    // put the disk system back to disk 0 side 0
    if (machine.Is(Nes::Api::Machine::DISK))
    {
        Nes::Api::Fds fds(_emu);
        fds.EjectDisk();
        fds.InsertDisk(0, 0);
    }
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

    Nes::Api::Machine machine(_emu);
    //machine.Power(false);
    machine.Unload(); // this allows FDS to save
    [super stopEmulation];
}

- (NSTimeInterval)frameInterval
{
    Nes::Api::Machine machine(_emu);

    if(machine.GetMode() == Nes::Api::Machine::NTSC)
        return Nes::Api::Machine::CLK_NTSC_DOT / Nes::Api::Machine::CLK_NTSC_VSYNC; // 60.0988138974
    else
        return Nes::Api::Machine::CLK_PAL_DOT / Nes::Api::Machine::CLK_PAL_VSYNC; // 50.0069789082
}

# pragma mark - Video

- (const void *)getVideoBufferWithHint:(void *)hint
{
    if (!hint)
    {
        if(!_indirectVideoBuffer)
        {
            _indirectVideoBuffer = new unsigned char[Nes::Api::Video::Output::WIDTH * Nes::Api::Video::Output::HEIGHT * 4];
        }
        hint = (void *)_indirectVideoBuffer;
    }
    _nesVideo->pixels = hint;
    _nesVideo->pitch = Nes::Api::Video::Output::WIDTH * 4;
    return hint;
}

- (OEIntRect)screenRect
{
    _videoOffsetX = _isHorzOverscanCropped ? OVERSCAN_HORIZONTAL : 0;
    _videoOffsetY = _isVertOverscanCropped ? OVERSCAN_VERTICAL   : 0;
    _videoWidth   = _isHorzOverscanCropped ? 256 - (OVERSCAN_HORIZONTAL * 2) : 256;
    _videoHeight  = _isVertOverscanCropped ? 240 - (OVERSCAN_VERTICAL   * 2) : 240;

    return OEIntRectMake(_videoOffsetX, _videoOffsetY, _videoWidth, _videoHeight);
}

- (OEIntSize)bufferSize
{
    return OEIntSizeMake(Nes::Api::Video::Output::WIDTH, Nes::Api::Video::Output::HEIGHT);
}

- (OEIntSize)aspectSize
{
    _aspectWidth  = _isHorzOverscanCropped ? (256 - (OVERSCAN_HORIZONTAL * 2)) * (8.0/7.0) : 256 * (8.0/7.0);
    _aspectHeight = _isVertOverscanCropped ?  240 - (OVERSCAN_VERTICAL   * 2)              : 240;

    return OEIntSizeMake(_aspectWidth, _aspectHeight);
}

- (GLenum)pixelFormat
{
    return GL_BGRA;
}

- (GLenum)pixelType
{
    return GL_UNSIGNED_INT_8_8_8_8_REV;
}

# pragma mark - Audio

- (double)audioSampleRate
{
    return SAMPLERATE;
}

- (NSUInteger)channelCount
{
    return 1;
}

# pragma mark - Save States

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    Nes::Result result;

    Nes::Api::Machine machine(_emu);
    std::ofstream stateFile(fileName.fileSystemRepresentation, std::ifstream::out|std::ifstream::binary);

    if(stateFile.is_open())
        result = machine.SaveState(stateFile, Nes::Api::Machine::NO_COMPRESSION);
    else {
        NSError *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotSaveStateError userInfo:@{
            NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"The save state file could not be written", nil, [NSBundle bundleForClass:[self class]], @"Nestopia state file could not be written description."),
            NSDebugDescriptionErrorKey : @"The save state file could not be written",
            NSLocalizedRecoverySuggestionErrorKey : [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Could not write the file state in %@.", nil, [NSBundle bundleForClass:[self class]], @"Nestopia state file could not be written suggestion."), fileName]
        }];

        block(NO, error);
        return;
    }

    if(NES_FAILED(result))  {
        NSString *errorDescription = nil;
        switch(result)
        {
            case Nes::RESULT_ERR_NOT_READY :
                errorDescription = NSLocalizedStringFromTableInBundle(@"Not ready to save state.", nil, [NSBundle bundleForClass:[self class]], @"Not ready to save state.");
                break;
            case Nes::RESULT_ERR_OUT_OF_MEMORY :
                errorDescription = NSLocalizedStringFromTableInBundle(@"Out of memory.", nil, [NSBundle bundleForClass:[self class]], @"Out of memory.");
                break;
            default :
                errorDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unknown nestopia error #%d.", nil, [NSBundle bundleForClass:[self class]], @"Unknown nestopia error #%d."), result];
                break;
        }

        NSError *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotSaveStateError userInfo:@{
            NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"The save state data could not be read", nil, [NSBundle bundleForClass:[self class]], @"The save state data could not be read"),
            NSDebugDescriptionErrorKey : @"The save state data could not be read",
            NSLocalizedRecoverySuggestionErrorKey : errorDescription
        }];

        block(NO, error);
        return;
    }

    stateFile.close();
    block(YES, nil);
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    Nes::Result result;

    Nes::Api::Machine machine(_emu);
    std::ifstream stateFile(fileName.fileSystemRepresentation, std::ifstream::in|std::ifstream::binary);

    if(stateFile.is_open())
        result = machine.LoadState(stateFile);
    else {
        NSError *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadStateError userInfo:@{
            NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"The save state file could not be opened", nil, [NSBundle bundleForClass:[self class]], @"Nestopia state file could not be opened description."),
            NSDebugDescriptionErrorKey : @"The save state file could not be opened",
            NSLocalizedRecoverySuggestionErrorKey : [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Could not read the file state in %@.", nil, [NSBundle bundleForClass:[self class]], @"Nestopia state file could not be opened suggestion."), fileName]
        }];

        block(NO, error);
        return;
    }

    if(NES_FAILED(result)) {
        NSString *errorDescription = nil;
        switch(result) {
            case Nes::RESULT_ERR_NOT_READY :
                errorDescription = NSLocalizedStringFromTableInBundle(@"Not ready to save state.", nil, [NSBundle bundleForClass:[self class]], @"Not ready to save state.");
                break;
            case Nes::RESULT_ERR_INVALID_CRC :
                errorDescription = NSLocalizedStringFromTableInBundle(@"Invalid CRC checksum.", nil, [NSBundle bundleForClass:[self class]], @"Invalid CRC checksum.");
                break;
            case Nes::RESULT_ERR_OUT_OF_MEMORY :
                errorDescription = NSLocalizedStringFromTableInBundle(@"Out of memory.", nil, [NSBundle bundleForClass:[self class]], @"Out of memory.");
                break;
            default :
                errorDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unknown nestopia error #%d.", nil, [NSBundle bundleForClass:[self class]], @"Unknown nestopia error #%d."), result];
                break;
        }
        NSError *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreStateHasWrongSizeError userInfo:@{
            NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Save state has wrong file size.", nil, [NSBundle bundleForClass:[self class]], @"Save state has wrong file size."),
            NSDebugDescriptionErrorKey : @"Save state has wrong file size.",
            NSLocalizedRecoverySuggestionErrorKey : errorDescription,
        }];

        block(NO, error);
        return;
    }

    // Notify the rcheevos client that emulator state has been externally replaced.
    // Without this, the RA library keeps evaluating achievement conditions against
    // stale pre-load state. Matches the reset already present in deserializeState:.
    if (_rcClient)
        rc_client_reset(_rcClient);
    block(YES, nil);
}

- (NSData *)serializeStateWithError:(NSError **)outError
{
    Nes::Result result;
    Nes::Api::Machine machine(_emu);

    std::stringstream stateStream(std::ios::in|std::ios::out|std::ios::binary);

    result = machine.SaveState(stateStream, Nes::Api::Machine::NO_COMPRESSION);

    if(NES_FAILED(result)) {
        if (!outError)
            return nil;

        NSString *errorDescription = nil;
        switch(result) {
            case Nes::RESULT_ERR_NOT_READY :
                errorDescription = NSLocalizedStringFromTableInBundle(@"Not ready to save state.", nil, [NSBundle bundleForClass:[self class]], @"Not ready to save state.");
                break;
            case Nes::RESULT_ERR_OUT_OF_MEMORY :
                errorDescription = NSLocalizedStringFromTableInBundle(@"Out of memory.", nil, [NSBundle bundleForClass:[self class]], @"Out of memory.");
                break;
            default :
                errorDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unknown nestopia error #%d.", nil, [NSBundle bundleForClass:[self class]], @"Unknown nestopia error #%d."), result];
                break;
        }

        *outError = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotSaveStateError userInfo:@{
            NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"The save state data could not be read", nil, [NSBundle bundleForClass:[self class]], @"The save state data could not be read"),
            NSDebugDescriptionErrorKey : @"The save state data could not be read",
            NSLocalizedRecoverySuggestionErrorKey : errorDescription
        }];

        return nil;
    }

    stateStream.seekg(0, std::ios::end);
    NSUInteger length = stateStream.tellg();
    stateStream.seekg(0, std::ios::beg);

    NSMutableData *data = [NSMutableData dataWithLength:length];
    stateStream.read((char *)data.mutableBytes, length);
    return data;
}

- (BOOL)deserializeState:(NSData *)state withError:(NSError **)outError
{
    Nes::Result result;
    Nes::Api::Machine machine(_emu);

    std::stringstream stateStream(std::ios::in|std::ios::out|std::ios::binary);

    char const *bytes = (char const *)(state.bytes);
    std::streamsize size = state.length;
    stateStream.write(bytes, size);

    result = machine.LoadState(stateStream);

    if(NES_FAILED(result)) {
        if (!outError)
            return NO;

        NSString *errorDescription = nil;
        switch(result) {
            case Nes::RESULT_ERR_NOT_READY :
                errorDescription = NSLocalizedStringFromTableInBundle(@"Not ready to save state.", nil, [NSBundle bundleForClass:[self class]], @"Not ready to save state.");
                break;
            case Nes::RESULT_ERR_INVALID_CRC :
                errorDescription = NSLocalizedStringFromTableInBundle(@"Invalid CRC checksum.", nil, [NSBundle bundleForClass:[self class]], @"Invalid CRC checksum.");
                break;
            case Nes::RESULT_ERR_OUT_OF_MEMORY :
                errorDescription = NSLocalizedStringFromTableInBundle(@"Out of memory.", nil, [NSBundle bundleForClass:[self class]], @"Out of memory.");
                break;
            default :
                errorDescription = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unknown nestopia error #%d.", nil, [NSBundle bundleForClass:[self class]], @"Unknown nestopia error #%d."), result];
                break;
        }
        *outError = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreStateHasWrongSizeError userInfo:@{
            NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Save state has wrong file size.", nil, [NSBundle bundleForClass:[self class]], @"Save state has wrong file size."),
            NSDebugDescriptionErrorKey : @"Save state has wrong file size.",
            NSLocalizedRecoverySuggestionErrorKey : errorDescription,
        }];

        return NO;
    }

    if (_rcClient)
        rc_client_reset(_rcClient);

    return YES;
}

# pragma mark - Input

NSUInteger NESControlValues[] = { Nes::Api::Input::Controllers::Pad::UP, Nes::Api::Input::Controllers::Pad::DOWN, Nes::Api::Input::Controllers::Pad::LEFT, Nes::Api::Input::Controllers::Pad::RIGHT, Nes::Api::Input::Controllers::Pad::A, Nes::Api::Input::Controllers::Pad::B, Nes::Api::Input::Controllers::Pad::START, Nes::Api::Input::Controllers::Pad::SELECT
};
- (oneway void)didPushNESButton:(OENESButton)button forPlayer:(NSUInteger)player
{
    _controls->pad[player - 1].buttons |=  NESControlValues[button];
}

- (oneway void)didReleaseNESButton:(OENESButton)button forPlayer:(NSUInteger)player
{
    _controls->pad[player - 1].buttons &= ~NESControlValues[button];
}

- (oneway void)didTriggerGunAtPoint:(OEIntPoint)aPoint
{
    [self mouseMovedAtPoint:aPoint];

    // Nes::Api::Video::Output::WIDTH / (Nes::Api::Video::Output::WIDTH * 8.0/7.0) = 0.876712
    int xcoord = _isHorzOverscanCropped ? (aPoint.x + OVERSCAN_HORIZONTAL) * 0.876712 : aPoint.x * 0.876712;
    int ycoord = _isVertOverscanCropped ? aPoint.y + OVERSCAN_VERTICAL : aPoint.y;

    _controls->paddle.button = 1;
    _controls->zapper.x = xcoord;
    _controls->zapper.y = ycoord;
    _controls->zapper.fire = 1;
    _controls->bandaiHyperShot.x = xcoord;
    _controls->bandaiHyperShot.y = ycoord;
    _controls->bandaiHyperShot.fire = 1;
}

- (oneway void)didReleaseTrigger
{
    _controls->paddle.button = 0;
    _controls->zapper.fire = 0;
    _controls->bandaiHyperShot.fire = 0;
}

- (oneway void)mouseMovedAtPoint:(OEIntPoint)aPoint
{
    _controls->paddle.x = _isHorzOverscanCropped ? (aPoint.x + OVERSCAN_HORIZONTAL) * 0.876712 : aPoint.x * 0.876712;
}

- (oneway void)rightMouseDownAtPoint:(OEIntPoint)point
{
    _controls->bandaiHyperShot.move = 1;
}

- (oneway void)rightMouseUp
{
    _controls->bandaiHyperShot.move = 0;
}

- (oneway void)didPushFDSChangeSideButton
{
    Nes::Api::Fds fds(_emu);
    //fds.ChangeSide();
    Nes::Result result;
    if (fds.IsAnyDiskInserted() && fds.CanChangeDiskSide())
        result = fds.ChangeSide();
    else
        result = fds.InsertDisk(0, 0);
    NSLog(@"[Nestopia] didPushFDSChangeSideButton: %d", result);
}

- (oneway void)didReleaseFDSChangeSideButton
{

}

- (oneway void)didPushFDSChangeDiskButton
{
    Nes::Api::Fds fds(_emu);
    // if multi-disk game, eject and insert the other disk
    if (fds.GetNumDisks() > 1)
    {
        int currdisk = fds.GetCurrentDisk();
        fds.EjectDisk();
        fds.InsertDisk(!currdisk, 0);

        NSLog(@"[Nestopia] didPushFDSChangeDiskButton");
    }
}

- (oneway void)didReleaseFDSChangeDiskButton;
{

}

#pragma mark - Cheats

- (void)setCheat:(NSString *)code setType:(NSString *)type setEnabled:(BOOL)enabled
{
    // Sanitize
    code = [code stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    // Remove any spaces
    code = [code stringByReplacingOccurrencesOfString:@" " withString:@""];

    Nes::Api::Cheats cheater(_emu);
    Nes::Api::Cheats::Code ggCode;

    if (enabled)
        _cheatList[code] = @YES;
    else
        [_cheatList removeObjectForKey:code];

    cheater.ClearCodes();

    NSArray<NSString *> *multipleCodes = [NSArray array];

    // Apply enabled cheats found in dictionary
    for (NSString *key in _cheatList)
    {
        if ([_cheatList[key] boolValue])
        {
            // Handle multi-line cheats
            multipleCodes = [key componentsSeparatedByString:@"+"];
            for (NSString *singleCode in multipleCodes) {
                const char *cCode = singleCode.UTF8String;

                if (singleCode.length == 7 && [singleCode characterAtIndex:4] == ':')
                {
                    ggCode.address = strtoul([singleCode substringToIndex:4].UTF8String, NULL, 16);
                    ggCode.value = strtoul([singleCode substringFromIndex:5].UTF8String, NULL, 16);
                    cheater.SetCode(ggCode);
                }
                else if (singleCode.length == 10 && [singleCode characterAtIndex:4] == '?' && [singleCode characterAtIndex:7] == ':')
                {
                    ggCode.address = strtoul([singleCode substringToIndex:4].UTF8String, NULL, 16);
                    ggCode.compare = strtoul([singleCode substringWithRange:NSMakeRange(5, 2)].UTF8String, NULL, 16);
                    ggCode.useCompare = true;
                    ggCode.value = strtoul([singleCode substringFromIndex:8].UTF8String, NULL, 16);
                    cheater.SetCode(ggCode);
                }
                else if (Nes::Api::Cheats::GameGenieDecode(cCode, ggCode) == Nes::RESULT_OK)
                    cheater.SetCode(ggCode);
                else if (Nes::Api::Cheats::ProActionRockyDecode(cCode, ggCode) == Nes::RESULT_OK)
                    cheater.SetCode(ggCode);
            }
        }
    }
}

# pragma mark - Display Mode

- (NSArray <NSDictionary <NSString *, id> *> *)displayModes
{
    if (_availableDisplayModes.count == 0)
    {
        _availableDisplayModes = [NSMutableArray array];

        NSArray <NSDictionary <NSString *, id> *> *availableModesWithDefault =
        @[
          OptionToggleableNoSave(@"No Sprite Limit", @"noSpriteLimit"),
          SeparatorItem(),
          Label(@"Overscan"),
          OptionToggleable(@"Crop Horizontal", @"cropHorizontalOverscan"),
          OptionToggleable(@"Crop Vertical", @"cropVerticalOverscan"),
          SeparatorItem(),
          Label(@"Palette"),
          OptionDefault(@"15° Canonical — Nestopia", @"palette"),
          Option(@"Consumer — Nestopia", @"palette"),
          Option(@"Alternative — Nestopia", @"palette"),
          Option(@"RGB (PlayChoice-10)", @"palette"),
          Option(@"NESCAP", @"palette"),
          Option(@"Sony CXA2025AS", @"palette"),
          Option(@"Smooth (FBX)", @"palette"),
          Option(@"Wavebeam", @"palette"),
          ];

        // Deep mutable copy
        _availableDisplayModes = (NSMutableArray *)CFBridgingRelease(CFPropertyListCreateDeepCopy(kCFAllocatorDefault, (CFArrayRef)availableModesWithDefault, kCFPropertyListMutableContainers));
    }

    return [_availableDisplayModes copy];
}

- (void)changeDisplayWithMode:(NSString *)displayMode
{
    if (_availableDisplayModes.count == 0)
        [self displayModes];

    // First check if 'displayMode' is valid
    BOOL isDisplayModeToggleable = NO;
    BOOL isValidDisplayMode = NO;
    BOOL displayModeState = NO;
    NSString *displayModePrefKey;

    for (NSDictionary *modeDict in _availableDisplayModes) {
        if ([modeDict[OEGameCoreDisplayModeNameKey] isEqualToString:displayMode]) {
            displayModeState = [modeDict[OEGameCoreDisplayModeStateKey] boolValue];
            displayModePrefKey = modeDict[OEGameCoreDisplayModePrefKeyNameKey];
            isDisplayModeToggleable = [modeDict[OEGameCoreDisplayModeAllowsToggleKey] boolValue];
            isValidDisplayMode = YES;
            break;
        }
    }

    // Disallow a 'displayMode' not found in _availableDisplayModes
    if (!isValidDisplayMode)
        return;

    // Handle option state changes
    for (NSMutableDictionary *optionDict in _availableDisplayModes) {
        NSString *modeName =  optionDict[OEGameCoreDisplayModeNameKey];
        NSString *prefKey  =  optionDict[OEGameCoreDisplayModePrefKeyNameKey];

        if (!modeName)
            continue;
        // Mutually exclusive option state change
        else if ([modeName isEqualToString:displayMode] && !isDisplayModeToggleable)
            optionDict[OEGameCoreDisplayModeStateKey] = @YES;
        // Reset mutually exclusive options that are the same prefs group as 'displayMode'
        else if (!isDisplayModeToggleable && [prefKey isEqualToString:displayModePrefKey])
            optionDict[OEGameCoreDisplayModeStateKey] = @NO;
        // Toggleable option state change
        else if ([modeName isEqualToString:displayMode] && isDisplayModeToggleable)
            optionDict[OEGameCoreDisplayModeStateKey] = @(!displayModeState);
    }

    Nes::Api::Video video(_emu);
    if ([displayMode isEqualToString:@"Crop Horizontal"])
    {
        _isHorzOverscanCropped = !_isHorzOverscanCropped;
    }
    else if ([displayMode isEqualToString:@"Crop Vertical"])
    {
        _isVertOverscanCropped = !_isVertOverscanCropped;
    }
    else if ([displayMode isEqualToString:@"No Sprite Limit"])
    {
        video.EnableUnlimSprites(!displayModeState);
    }
    else if ([displayMode isEqualToString:@"15° Canonical — Nestopia"])
    {
        video.GetPalette().SetMode(Nes::Api::Video::Palette::MODE_YUV);
        video.SetDecoder(Nes::Api::Video::DECODER_CANONICAL);
    }
    else if ([displayMode isEqualToString:@"Consumer — Nestopia"])
    {
        video.GetPalette().SetMode(Nes::Api::Video::Palette::MODE_YUV);
        video.SetDecoder(Nes::Api::Video::DECODER_CONSUMER);
    }
    else if ([displayMode isEqualToString:@"Alternative — Nestopia"])
    {
        video.GetPalette().SetMode(Nes::Api::Video::Palette::MODE_YUV);
        video.SetDecoder(Nes::Api::Video::DECODER_ALTERNATIVE);
    }
    else if ([displayMode isEqualToString:@"RGB (PlayChoice-10)"])
    {
        video.GetPalette().SetMode(Nes::Api::Video::Palette::MODE_RGB);
    }
    else if ([displayMode isEqualToString:@"NESCAP"])
    {
        static const unsigned char nescap_palette[64][3] =
        {
            {0x64, 0x63, 0x65}, {0x00, 0x15, 0x80}, {0x1D, 0x00, 0x90}, {0x38, 0x00, 0x82},
            {0x56, 0x00, 0x5D}, {0x5A, 0x00, 0x1A}, {0x4F, 0x09, 0x00}, {0x38, 0x1B, 0x00},
            {0x1E, 0x31, 0x00}, {0x00, 0x3D, 0x00}, {0x00, 0x41, 0x00}, {0x00, 0x3A, 0x1B},
            {0x00, 0x2F, 0x55}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00},
            {0xAF, 0xAD, 0xAF}, {0x16, 0x4B, 0xCA}, {0x47, 0x2A, 0xE7}, {0x6B, 0x1B, 0xDB},
            {0x96, 0x17, 0xB0}, {0x9F, 0x18, 0x5B}, {0x96, 0x30, 0x01}, {0x7B, 0x48, 0x00},
            {0x5A, 0x66, 0x00}, {0x23, 0x78, 0x00}, {0x01, 0x7F, 0x00}, {0x00, 0x78, 0x3D},
            {0x00, 0x6C, 0x8C}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00},
            {0xFF, 0xFF, 0xFF}, {0x60, 0xA6, 0xFF}, {0x8F, 0x84, 0xFF}, {0xB4, 0x73, 0xFF},
            {0xE2, 0x6C, 0xFF}, {0xF2, 0x68, 0xC3}, {0xEF, 0x7E, 0x61}, {0xD8, 0x95, 0x27},
            {0xBA, 0xB3, 0x07}, {0x81, 0xC8, 0x07}, {0x57, 0xD4, 0x3D}, {0x47, 0xCF, 0x7E},
            {0x4B, 0xC5, 0xCD}, {0x4C, 0x4B, 0x4D}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00},
            {0xFF, 0xFF, 0xFF}, {0xC2, 0xE0, 0xFF}, {0xD5, 0xD2, 0xFF}, {0xE3, 0xCB, 0xFF},
            {0xF7, 0xC8, 0xFF}, {0xFE, 0xC6, 0xEE}, {0xFE, 0xCE, 0xC6}, {0xF6, 0xD7, 0xAE},
            {0xE9, 0xE4, 0x9F}, {0xD3, 0xED, 0x9D}, {0xC0, 0xF2, 0xB2}, {0xB9, 0xF1, 0xCC},
            {0xBA, 0xED, 0xED}, {0xBA, 0xB9, 0xBB}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00}
        };
        video.GetPalette().SetMode(Nes::Api::Video::Palette::MODE_CUSTOM);
        video.GetPalette().SetCustom(nescap_palette, Nes::Api::Video::Palette::STD_PALETTE);
    }
    else if ([displayMode isEqualToString:@"Sony CXA2025AS"])
    {
        static const unsigned char cxa2025as_palette[64][3] =
        {
            {0x58,0x58,0x58}, {0x00,0x23,0x8C}, {0x00,0x13,0x9B}, {0x2D,0x05,0x85},
            {0x5D,0x00,0x52}, {0x7A,0x00,0x17}, {0x7A,0x08,0x00}, {0x5F,0x18,0x00},
            {0x35,0x2A,0x00}, {0x09,0x39,0x00}, {0x00,0x3F,0x00}, {0x00,0x3C,0x22},
            {0x00,0x32,0x5D}, {0x00,0x00,0x00}, {0x00,0x00,0x00}, {0x00,0x00,0x00},
            {0xA1,0xA1,0xA1}, {0x00,0x53,0xEE}, {0x15,0x3C,0xFE}, {0x60,0x28,0xE4},
            {0xA9,0x1D,0x98}, {0xD4,0x1E,0x41}, {0xD2,0x2C,0x00}, {0xAA,0x44,0x00},
            {0x6C,0x5E,0x00}, {0x2D,0x73,0x00}, {0x00,0x7D,0x06}, {0x00,0x78,0x52},
            {0x00,0x69,0xA9}, {0x00,0x00,0x00}, {0x00,0x00,0x00}, {0x00,0x00,0x00},
            {0xFF,0xFF,0xFF}, {0x1F,0xA5,0xFE}, {0x5E,0x89,0xFE}, {0xB5,0x72,0xFE},
            {0xFE,0x65,0xF6}, {0xFE,0x67,0x90}, {0xFE,0x77,0x3C}, {0xFE,0x93,0x08},
            {0xC4,0xB2,0x00}, {0x79,0xCA,0x10}, {0x3A,0xD5,0x4A}, {0x11,0xD1,0xA4},
            {0x06,0xBF,0xFE}, {0x42,0x42,0x42}, {0x00,0x00,0x00}, {0x00,0x00,0x00},
            {0xFF,0xFF,0xFF}, {0xA0,0xD9,0xFE}, {0xBD,0xCC,0xFE}, {0xE1,0xC2,0xFE},
            {0xFE,0xBC,0xFB}, {0xFE,0xBD,0xD0}, {0xFE,0xC5,0xA9}, {0xFE,0xD1,0x8E},
            {0xE9,0xDE,0x86}, {0xC7,0xE9,0x92}, {0xA8,0xEE,0xB0}, {0x95,0xEC,0xD9},
            {0x91,0xE4,0xFE}, {0xAC,0xAC,0xAC}, {0x00,0x00,0x00}, {0x00,0x00,0x00}
        };
        video.GetPalette().SetMode(Nes::Api::Video::Palette::MODE_CUSTOM);
        video.GetPalette().SetCustom(cxa2025as_palette, Nes::Api::Video::Palette::STD_PALETTE);
    }
    else if ([displayMode isEqualToString:@"Smooth (FBX)"])
    {
        static const unsigned char smoothfbx_palette[64][3] =
        {
            {0x6A, 0x6D, 0x6A}, {0x00, 0x13, 0x80}, {0x1E, 0x00, 0x8A}, {0x39, 0x00, 0x7A},
            {0x55, 0x00, 0x56}, {0x5A, 0x00, 0x18}, {0x4F, 0x10, 0x00}, {0x3D, 0x1C, 0x00},
            {0x25, 0x32, 0x00}, {0x00, 0x3D, 0x00}, {0x00, 0x40, 0x00}, {0x00, 0x39, 0x24},
            {0x00, 0x2E, 0x55}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00},
            {0xB9, 0xBC, 0xB9}, {0x18, 0x50, 0xC7}, {0x4B, 0x30, 0xE3}, {0x73, 0x22, 0xD6},
            {0x95, 0x1F, 0xA9}, {0x9D, 0x28, 0x5C}, {0x98, 0x37, 0x00}, {0x7F, 0x4C, 0x00},
            {0x5E, 0x64, 0x00}, {0x22, 0x77, 0x00}, {0x02, 0x7E, 0x02}, {0x00, 0x76, 0x45},
            {0x00, 0x6E, 0x8A}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00},
            {0xFF, 0xFF, 0xFF}, {0x68, 0xA6, 0xFF}, {0x8C, 0x9C, 0xFF}, {0xB5, 0x86, 0xFF},
            {0xD9, 0x75, 0xFD}, {0xE3, 0x77, 0xB9}, {0xE5, 0x8D, 0x68}, {0xD4, 0x9D, 0x29},
            {0xB3, 0xAF, 0x0C}, {0x7B, 0xC2, 0x11}, {0x55, 0xCA, 0x47}, {0x46, 0xCB, 0x81},
            {0x47, 0xC1, 0xC5}, {0x4A, 0x4D, 0x4A}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00},
            {0xFF, 0xFF, 0xFF}, {0xCC, 0xEA, 0xFF}, {0xDD, 0xDE, 0xFF}, {0xEC, 0xDA, 0xFF},
            {0xF8, 0xD7, 0xFE}, {0xFC, 0xD6, 0xF5}, {0xFD, 0xDB, 0xCF}, {0xF9, 0xE7, 0xB5},
            {0xF1, 0xF0, 0xAA}, {0xDA, 0xFA, 0xA9}, {0xC9, 0xFF, 0xBC}, {0xC3, 0xFB, 0xD7},
            {0xC4, 0xF6, 0xF6}, {0xBE, 0xC1, 0xBE}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00}
        };
        video.GetPalette().SetMode(Nes::Api::Video::Palette::MODE_CUSTOM);
        video.GetPalette().SetCustom(smoothfbx_palette, Nes::Api::Video::Palette::STD_PALETTE);
    }
    else if ([displayMode isEqualToString:@"Wavebeam"])
    {
        static const unsigned char wavebeam_palette[64][3] =
        {
            {0x6B, 0x6B, 0x6B}, {0x00, 0x1B, 0x88}, {0x21, 0x00, 0x9A}, {0x40, 0x00, 0x8C},
            {0x60, 0x00, 0x67}, {0x64, 0x00, 0x1E}, {0x59, 0x08, 0x00}, {0x48, 0x16, 0x00},
            {0x28, 0x36, 0x00}, {0x00, 0x45, 0x00}, {0x00, 0x49, 0x08}, {0x00, 0x42, 0x1D},
            {0x00, 0x36, 0x59}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00},
            {0xB4, 0xB4, 0xB4}, {0x15, 0x55, 0xD3}, {0x43, 0x37, 0xEF}, {0x74, 0x25, 0xDF},
            {0x9C, 0x19, 0xB9}, {0xAC, 0x0F, 0x64}, {0xAA, 0x2C, 0x00}, {0x8A, 0x4B, 0x00},
            {0x66, 0x6B, 0x00}, {0x21, 0x83, 0x00}, {0x00, 0x8A, 0x00}, {0x00, 0x81, 0x44},
            {0x00, 0x76, 0x91}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00},
            {0xFF, 0xFF, 0xFF}, {0x63, 0xB2, 0xFF}, {0x7C, 0x9C, 0xFF}, {0xC0, 0x7D, 0xFE},
            {0xE9, 0x77, 0xFF}, {0xF5, 0x72, 0xCD}, {0xF4, 0x88, 0x6B}, {0xDD, 0xA0, 0x29},
            {0xBD, 0xBD, 0x0A}, {0x89, 0xD2, 0x0E}, {0x5C, 0xDE, 0x3E}, {0x4B, 0xD8, 0x86},
            {0x4D, 0xCF, 0xD2}, {0x52, 0x52, 0x52}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00},
            {0xFF, 0xFF, 0xFF}, {0xBC, 0xDF, 0xFF}, {0xD2, 0xD2, 0xFF}, {0xE1, 0xC8, 0xFF},
            {0xEF, 0xC7, 0xFF}, {0xFF, 0xC3, 0xE1}, {0xFF, 0xCA, 0xC6}, {0xF2, 0xDA, 0xAD},
            {0xEB, 0xE3, 0xA0}, {0xD2, 0xED, 0xA2}, {0xBC, 0xF4, 0xB4}, {0xB5, 0xF1, 0xCE},
            {0xB6, 0xEC, 0xF1}, {0xBF, 0xBF, 0xBF}, {0x00, 0x00, 0x00}, {0x00, 0x00, 0x00}
        };
        video.GetPalette().SetMode(Nes::Api::Video::Palette::MODE_CUSTOM);
        video.GetPalette().SetCustom(wavebeam_palette, Nes::Api::Video::Palette::STD_PALETTE);
    }
}

- (void)loadDisplayModeOptions
{
    // Restore palette
    NSString *lastPalette = self.displayModeInfo[@"palette"];
    if (lastPalette && ![lastPalette isEqualToString:@"15° Canonical — Nestopia"]) {
        [self changeDisplayWithMode:lastPalette];
    }

    // Crop horizontal overscan
    BOOL isHorizontalOverscanCropped = [self.displayModeInfo[@"cropHorizontalOverscan"] boolValue];
    if (isHorizontalOverscanCropped) {
        [self changeDisplayWithMode:@"Crop Horizontal"];
    }

    // Crop vertical overscan
    BOOL isVerticalOverscanCropped = [self.displayModeInfo[@"cropVerticalOverscan"] boolValue];
    if (isVerticalOverscanCropped) {
        [self changeDisplayWithMode:@"Crop Vertical"];
    }
}

# pragma mark - Callbacks

// for various file operations, usually called during image file load, power on/off and reset
void NST_CALLBACK doFileIO(void *userData, Nes::Api::User::File &file)
{
    GET_CURRENT_OR_RETURN();

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *url = current->_romURL;

    NSString *extensionlessFilename = url.lastPathComponent.stringByDeletingPathExtension;
    NSURL *batterySavesDirectory = [NSURL fileURLWithPath:current.batterySavesDirectoryPath];
    [fileManager createDirectoryAtURL:batterySavesDirectory withIntermediateDirectories:YES attributes:nil error:nil];

    NSData *theData;
    NSURL *saveFileURL;

    switch(file.GetAction())
    {
        case Nes::Api::User::File::LOAD_SAMPLE :
        case Nes::Api::User::File::LOAD_ROM :
            break;

        case Nes::Api::User::File::LOAD_BATTERY : // load in battery data from a file
        case Nes::Api::User::File::LOAD_EEPROM : // used by some Bandai games, can be treated the same as battery files
        {
            saveFileURL = [batterySavesDirectory URLByAppendingPathComponent:[extensionlessFilename stringByAppendingPathExtension:@"sav"]];
            if(![saveFileURL checkResourceIsReachableAndReturnError:nil])
            {
                NSLog(@"[Nestopia] Couldn't find Battery/EEPROM save at: %@", saveFileURL);
                return;
            }
            NSLog(@"[Nestopia] Loading Battery/EEPROM save: %@", saveFileURL);
            theData = [NSData dataWithContentsOfURL:saveFileURL];
            file.SetContent(theData.bytes, theData.length);
            break;
        }
        case Nes::Api::User::File::SAVE_BATTERY : // save battery data to a file
        case Nes::Api::User::File::SAVE_EEPROM : // can be treated the same as battery files
        {
            NSLog(@"[Nestopia] Saving Battery/EEPROM");
            const void *saveData;
            unsigned long saveDataSize;
            file.GetContent(saveData, saveDataSize);
            saveFileURL = [batterySavesDirectory URLByAppendingPathComponent:[extensionlessFilename stringByAppendingPathExtension:@"sav"]];
            theData = [NSData dataWithBytes:saveData length:saveDataSize];
            [theData writeToURL:saveFileURL atomically:YES];
            break;
        }
        case Nes::Api::User::File::LOAD_FDS:
        {
            NSLog(@"[Nestopia] Loading FDS save");
            saveFileURL = [batterySavesDirectory URLByAppendingPathComponent:[extensionlessFilename stringByAppendingPathExtension:@"sav"]];
            std::ifstream in_tmp(saveFileURL.fileSystemRepresentation, std::ifstream::in|std::ifstream::binary);

            if (!in_tmp.is_open())
                return;

            file.SetPatchContent(in_tmp);
            break;
        }
        case Nes::Api::User::File::SAVE_FDS: // for saving modified Famicom Disk System files
        {
            NSLog(@"[Nestopia] Saving FDS");
            saveFileURL = [batterySavesDirectory URLByAppendingPathComponent:[extensionlessFilename stringByAppendingPathExtension:@"sav"]];
            std::ofstream out_tmp(saveFileURL.fileSystemRepresentation, std::ifstream::out|std::ifstream::binary);

            if (out_tmp.is_open())
                file.GetPatchContent(Nes::Api::User::File::PATCH_UPS, out_tmp);
            break;
        }
        case Nes::Api::User::File::LOAD_TAPE : // for loading Famicom cassette tapes
        case Nes::Api::User::File::SAVE_TAPE : // for saving Famicom cassette tapes
        case Nes::Api::User::File::LOAD_TURBOFILE : // for loading turbofile data
        case Nes::Api::User::File::SAVE_TURBOFILE : // for saving turbofile data
            break;

        case Nes::Api::User::File::LOAD_SAMPLE_MOERO_PRO_YAKYUU :
        case Nes::Api::User::File::LOAD_SAMPLE_MOERO_PRO_YAKYUU_88 :
        case Nes::Api::User::File::LOAD_SAMPLE_MOERO_PRO_TENNIS :
        case Nes::Api::User::File::LOAD_SAMPLE_TERAO_NO_DOSUKOI_OOZUMOU :
        case Nes::Api::User::File::LOAD_SAMPLE_AEROBICS_STUDIO :
            break;
    }
}

Nes::Api::User::Answer NST_CALLBACK doQuestion(void *userData, Nes::Api::User::Question question)
{
    switch(question)
    {
        case Nes::Api::User::QUESTION_NST_PRG_CRC_FAIL_CONTINUE :
            break;
        case Nes::Api::User::QUESTION_NSV_PRG_CRC_FAIL_CONTINUE :
            break;
    }

    NSLog(@"[Nestopia] CRC Failed");
    return Nes::Api::User::ANSWER_DEFAULT;
}

void NST_CALLBACK doLog(void *userData, const char *text, unsigned long length)
{
    NSLog(@"[Nestopia] %@", [NSString stringWithUTF8String:text]);
}

void NST_CALLBACK doEvent(void *userData, Nes::Api::Machine::Event event, Nes::Result result)
{
    switch(event)
    {
        case Nes::Api::Machine::EVENT_LOAD :
        case Nes::Api::Machine::EVENT_UNLOAD :
        case Nes::Api::Machine::EVENT_POWER_ON :
        case Nes::Api::Machine::EVENT_POWER_OFF :
        case Nes::Api::Machine::EVENT_RESET_SOFT :
        case Nes::Api::Machine::EVENT_RESET_HARD :
        case Nes::Api::Machine::EVENT_MODE_NTSC :
        case Nes::Api::Machine::EVENT_MODE_PAL :
            break;
    }
}

@end
