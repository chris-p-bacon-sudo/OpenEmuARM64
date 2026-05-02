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

#import "FCEUGameCore.h"
#import <OpenEmuBase/OERingBuffer.h>
#import "OENESSystemResponderClient.h"
#import <OpenGL/gl.h>

#include "src/fceu.h"
#include "src/driver.h"
#include "src/palette.h"
#include "src/state.h"
#include "src/emufile.h"
#include "src/cart.h"
#include "src/cheat.h"
#include "zlib.h"

#include <os/log.h>
#define RC_CLIENT_SUPPORTS_HASH 1
#include <rc_client.h>
#include <rc_consoles.h>
#import "OERetroAchievementsTransport.h"

extern uint8 *XBuf;
static uint32_t palette[256];

#define OVERSCAN_VERTICAL 8
#define OVERSCAN_HORIZONTAL 8

#define OptionDefault(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @YES, }
#define Option(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, }
#define OptionIndented(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, OEGameCoreDisplayModeIndentationLevelKey : @(1), }
#define OptionToggleable(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, OEGameCoreDisplayModeAllowsToggleKey : @YES, }
#define OptionToggleableNoSave(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, OEGameCoreDisplayModeAllowsToggleKey : @YES, OEGameCoreDisplayModeDisallowPrefSaveKey : @YES, }
#define Label(_NAME_) @{ OEGameCoreDisplayModeLabelKey : _NAME_, }
#define SeparatorItem() @{ OEGameCoreDisplayModeSeparatorItemKey : @"",}

@interface FCEUGameCore () <OENESSystemResponderClient>
{
    uint32_t *_videoBuffer;
    uint32_t *_videoBufferHint;
    int32_t  *_soundBuffer;
    int32_t   _soundSize;
    uint32_t  _pad;
    uint32_t  _arkanoid[3];
    uint32_t  _zapper[3];
    uint32_t  _hypershot[4];
    int       _videoWidth, _videoHeight;
    int       _videoOffsetX, _videoOffsetY;
    int       _aspectWidth, _aspectHeight;
    BOOL      _isHorzOverscanCropped;
    BOOL      _isVertOverscanCropped;
    NSMutableDictionary<NSString *, NSNumber *> *_cheatList;
    NSMutableArray <NSMutableDictionary <NSString *, id> *> *_availableDisplayModes;
    rc_client_t *_rcClient;
    id _raTokenObserver;
    NSString *_romPath;
}

- (void)loadDisplayModeOptions;
- (void)_beginLoadGame;

@end

// rcheevos memory callback.
//
// rcheevos NES address space (consoleinfo.c):
//   0x0000–0x07FF → 2 KB NES work RAM (mirrored at 0x0800–0x1FFF on hardware,
//                    but rcheevos only requests the base 2 KB range)
//
static uint32_t fceu_rc_read_memory(uint32_t address, uint8_t *buffer,
                                     uint32_t num_bytes, rc_client_t *client)
{
    for (uint32_t i = 0; i < num_bytes; i++) {
        uint32_t addr = address + i;
        if (addr <= 0x07FF)
            buffer[i] = RAM[addr];
        else
            return i;
    }
    return num_bytes;
}

static void fceu_rc_log(const char *message, const rc_client_t *client)
{
    os_log(OS_LOG_DEFAULT, "[rcheevos] %{public}s", message);
}

static void fceu_rc_load_game_callback(int result, const char *error_message,
                                        rc_client_t *client, void *userdata)
{
    if (result != RC_OK)
        NSLog(@"[RA-FCEU] game load failed — result=%d error=%s", result, error_message ?: "(none)");
}

static void fceu_rc_login_callback(int result, const char *error_message,
                                    rc_client_t *client, void *userdata)
{
    FCEUGameCore *s = (__bridge FCEUGameCore *)userdata;
    if (result == RC_OK) {
        [s _beginLoadGame];
    } else {
        NSLog(@"[RA-FCEU] login failed — result=%d error=%s", result, error_message ?: "(none)");
    }
}

static void fceu_rc_event_handler(const rc_client_event_t *event, rc_client_t *client)
{
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
}

@implementation FCEUGameCore

static __weak FCEUGameCore *_current;

- (id)init
{
    if((self = [super init]))
    {
        _cheatList = [NSMutableDictionary dictionary];
    }

	_current = self;

	return self;
}

- (void)_beginLoadGame
{
    if (!_rcClient || !_romPath) { return; }
    rc_client_begin_identify_and_load_game(_rcClient,
                                           RC_CONSOLE_NINTENDO,
                                           _romPath.fileSystemRepresentation,
                                           NULL, 0,
                                           fceu_rc_load_game_callback,
                                           (__bridge void *)self);
}

- (void)dealloc
{
    free(_videoBuffer);
}

# pragma mark - Execution

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
    _romPath = path;
    _pad = 0;
    memset(_arkanoid, 0, sizeof(_arkanoid));
    memset(_zapper, 0, sizeof(_zapper));
    memset(_hypershot, 0, sizeof(_hypershot));

    //newppu = 0 default off, set 1 to enable

    FCEUI_Initialize();

    NSURL *batterySavesDirectory = [NSURL fileURLWithPath:self.batterySavesDirectoryPath];
    [NSFileManager.defaultManager createDirectoryAtURL:batterySavesDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    //FCEUI_SetBaseDirectory([[self biosDirectoryPath] fileSystemRepresentation]); unused for now
    FCEUI_SetDirOverride(FCEUIOD_NV, strdup(batterySavesDirectory.fileSystemRepresentation));

    FCEUI_SetSoundVolume(256);
    FCEUI_Sound(48000);

    FCEUGI *FCEUGameInfo;
    FCEUGameInfo = FCEUI_LoadGame(path.fileSystemRepresentation, 1, false);

    if(!FCEUGameInfo)
        return NO;

    //NSLog(@"FPS: %d", FCEUI_GetDesiredFPS() >> 24); // Hz

    FCEUI_SetInput(0, SI_GAMEPAD, &_pad, 0); // Controllers 1 and 3

    if(FCEUGameInfo->input[1] == SI_ZAPPER)
        FCEUI_SetInput(1, SI_ZAPPER, &_zapper, 0);
    else if(FCEUGameInfo->input[1] == SI_ARKANOID)
        FCEUI_SetInput(1, SI_ARKANOID, &_arkanoid, 0);
    else
        FCEUI_SetInput(1, SI_GAMEPAD, &_pad, 0); // Controllers 2 and 4

    if(FCEUGameInfo->inputfc == SIFC_SHADOW)
        FCEUI_SetInputFC(SIFC_SHADOW, &_hypershot, 0);
    else if(FCEUGameInfo->inputfc == SIFC_ARKANOID)
        FCEUI_SetInputFC(SIFC_ARKANOID, &_arkanoid, 0);

    extern uint32_t iNESGameCRC32;
    NSString *cartCRC32 = [NSString stringWithFormat:@"%08x", iNESGameCRC32];
    // Headerless cart data
    NSArray *fourscoreGames = @[@"1ebb5b42", // Bomberman II (USA)
                                //@"eac38105", // Championship Bowling (USA)
                                @"f99e37eb", // Chris Evert & Ivan Lendl in Top Players' Tennis (USA)
                                //@"c7f0c457", // Crash 'n' the Boys - Street Challenge (USA)
                                @"48b8ee58", // Four Players' Tennis (Europe)
                                @"27ca0679", // Danny Sullivan's Indy Heat (Europe)
                                @"c1b43207", // Danny Sullivan's Indy Heat (USA)
                                @"79f688bc", // Gauntlet II (Europe)
                                @"1b71ccdb", // Gauntlet II (USA)
                                @"1352f1b9", // Greg Norman's Golf Power (USA)
                                @"2e6ee98d", // Harlem Globetrotters (USA)
                                @"05104517", // Ivan 'Ironman' Stewart's Super Off Road (Europe)
                                @"4b041b6b", // Ivan 'Ironman' Stewart's Super Off Road (USA)
                                @"f54b34bd", // Kings of the Beach - Professional Beach Volleyball (USA)
                                @"c6c2edb5", // Magic Johnson's Fast Break (USA)
                                @"0939852f", // M.U.L.E. (USA)
                                @"2f698c4d", // Monster Truck Rally (USA)
                                @"b9b4d9e0", // NES Play Action Football (USA)
                                @"da2cb59a", // Nightmare on Elm Street, A (USA)
                                @"8da6667d", // Nintendo World Cup (Europe)
                                @"7c16f819", // Nintendo World Cup (Europe) (Rev A)
                                @"7f08d0d9", // Nintendo World Cup (Europe) (Rev B)
                                @"a22657fa", // Nintendo World Cup (USA)
                                @"308da987", // R.C. Pro-Am II (Europe)
                                @"9edd2159", // R.C. Pro-Am II (USA)
                                @"8fa6e92c", // Rackets & Rivals (Europe)
                                @"ad0394f0", // Roundball - 2-on-2 Challenge (Europe)
                                @"6e4dcfd2", // Roundball - 2-on-2 Challenge (USA)
                                @"0abdd5ca", // Spot - The Video Game (Japan)
                                @"cfae9dfa", // Spot - The Video Game (USA)
                                @"0b8f8128", // Smash T.V. (Europe)
                                @"6ee94d32", // Smash T.V. (USA)
                                @"cf4487a2", // Super Jeopardy! (USA)
                                @"c05a63b2", // Super Spike V'Ball (Europe)
                                @"e840fd21", // Super Spike V'Ball (USA)
                                @"407d6ffd", // Super Spike V'Ball + Nintendo World Cup (USA)
                                @"d153caf6", // Swords and Serpents (Europe)
                                @"46135141", // Swords and Serpents (France)
                                @"3417ec46", // Swords and Serpents (USA)
                                @"69977c9e", // Battle City (Japan) (4 Players Hack) http://www.romhacking.net/hacks/2142/
                                @"2da5ece0", // Bomberman 3 (Homebrew) http://tempect.de/senil/games.html
                                @"90d2e9f0", // K.Y.F.F. (Homebrew) http://slydogstudios.org/index.php/k-y-f-f/
                                @"1394ded0", // Super PakPak (Homebrew) http://wiki.nesdev.com/w/index.php/Super_PakPak
                                @"73298c87", // Super Mario Bros. + Tetris + Nintendo World Cup (Europe)
                                @"f46ef39a"  // Super Mario Bros. + Tetris + Nintendo World Cup (Europe) (Rev A)
                                ];

    // Most 3-4 player Famicom games need to set '4 player mode' in the expansion port
    NSArray *famicom4Player = @[@"c39b3bb2", // Bakutoushi Patton-Kun (Japan) (FDS)
                                @"0c401790", // Bomber Man II (Japan)
                                @"9992f445", // Championship Bowling (Japan)
                                @"3e470fe0", // Downtown - Nekketsu Koushinkyoku - Soreyuke Daiundoukai (Japan)
                                @"4f032933", // Ike Ike! Nekketsu Hockey-bu - Subette Koronde Dairantou (Japan)
                                @"4b5177e9", // Kunio-kun no Nekketsu Soccer League (Japan)
                                @"9f03b11f", // Moero TwinBee - Cinnamon Hakase o Sukue! (Japan)
                                @"13205221", // Moero TwinBee - Cinnamon Hakase wo Sukue! (Japan) (FDS)
                                @"37e24797", // Nekketsu Kakutou Densetsu (Japan)
                                @"62c67984", // Nekketsu Koukou Dodgeball-bu (Japan)
                                @"88062d9a", // Nekketsu! Street Basket - Ganbare Dunk Heroes (Japan)
                                @"689971f9", // Super Dodge Ball (USA) (3-4p with Game Genie code GEUOLZZA)
                                @"4ff17864", // Super Dodge Ball (USA) (patched) http://www.romhacking.net/hacks/71/
                                @"213cb3fb", // U.S. Championship V'Ball (Japan)
                                @"d7077d96", // U.S. Championship V'Ball (Japan) (Beta)
                                @"b1b16b8a"  // Wit's (Japan)
                                ];

    if([fourscoreGames containsObject:cartCRC32])
        FCEUI_SetInputFourscore(true);

    if([famicom4Player containsObject:cartCRC32])
        FCEUI_SetInputFC(SIFC_4PLAYER, &_pad, 0);

    FCEU_ResetPalette();

    // Only temporary, so core doesn't crash on an older OpenEmu version
    if ([self respondsToSelector:@selector(displayModeInfo)]) {
        [self loadDisplayModeOptions];
    }

    _rcClient = rc_client_create(fceu_rc_read_memory, oeRetroAchievementsServerCall);
    if (_rcClient) {
        rc_client_set_userdata(_rcClient, (__bridge void *)self);
        rc_client_set_event_handler(_rcClient, fceu_rc_event_handler);
        rc_client_set_hardcore_enabled(_rcClient, 0);
        rc_client_enable_logging(_rcClient, RC_CLIENT_LOG_LEVEL_INFO, fceu_rc_log);

        __weak FCEUGameCore *weakSelf = self;
        _raTokenObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:OERetroAchievementsTokenDidChangeNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) {
            FCEUGameCore *s = weakSelf;
            if (!s || !s->_rcClient) { return; }
            NSString *token    = note.userInfo[OERetroAchievementsTokenKey];
            NSString *username = note.userInfo[OERetroAchievementsUsernameKey];
            if (token && username) {
                rc_client_begin_login_with_token(s->_rcClient,
                                                 username.UTF8String,
                                                 token.UTF8String,
                                                 fceu_rc_login_callback,
                                                 (__bridge void *)s);
            } else {
                rc_client_logout(s->_rcClient);
            }
        }];
    }

    return YES;
}

- (void)executeFrame
{
    uint8_t *pXBuf;
    _soundSize = 0;

    FCEUI_Emulate(&pXBuf, &_soundBuffer, &_soundSize, 0);

    // Translate the freshly-emulated XBuf (palette-indexed) into the renderer's
    // 32-bit BGRA buffer. Doing this here (rather than in -getVideoBufferWithHint:)
    // ensures the buffer contains the latest frame whenever the renderer reads it,
    // matching the contract used by every other 2D pixel-buffer core.
    if (_videoBufferHint) {
        const uint8_t *src = XBuf;
        uint32_t *dst = _videoBufferHint;
        for (unsigned y = 0; y < 240; y++)
            for (unsigned x = 0; x < 256; x++, src++)
                dst[y * 256 + x] = palette[*src];
    }

    if (_rcClient)
        rc_client_do_frame(_rcClient);

    for (int i = 0; i < _soundSize; i++)
        _soundBuffer[i] = (_soundBuffer[i] << 16) | (_soundBuffer[i] & 0xffff);

    [[self audioBufferAtIndex:0] write:_soundBuffer maxLength:_soundSize << 2];
}

- (void)resetEmulation
{
    if (_rcClient)
        rc_client_reset(_rcClient);
    ResetNES();
}

- (void)stopEmulation
{
    if (_raTokenObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:_raTokenObserver];
        _raTokenObserver = nil;
    }
    if (_rcClient) {
        rc_client_unload_game(_rcClient);
        rc_client_destroy(_rcClient);
        _rcClient = NULL;
    }

    FCEUI_CloseGame();
    FCEUI_Kill();

    [super stopEmulation];
}

- (NSTimeInterval)frameInterval
{
    return FCEUI_GetDesiredFPS() / 16777216.0;
}

# pragma mark - Video

- (const void *)getVideoBufferWithHint:(void *)hint
{
    if (!hint) {
        if (!_videoBuffer) _videoBuffer = (uint32_t *)malloc(256 * 240 * sizeof(uint32_t));
        hint = _videoBuffer;
    }

    // Cache the renderer's buffer pointer; -executeFrame writes pixels here.
    _videoBufferHint = (uint32_t *)hint;

    // Clear the buffer to black for the first frame, before any emulation has
    // run. This avoids briefly displaying uninitialised memory through the
    // palette table (which previously appeared as a solid grey screen in
    // builds that called this method only at renderer setup).
    memset(hint, 0, 256 * 240 * sizeof(uint32_t));

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

- (OEIntSize)aspectSize
{
    _aspectWidth  = _isHorzOverscanCropped ? (256 - (OVERSCAN_HORIZONTAL * 2)) * (8.0/7.0) : 256 * (8.0/7.0);
    _aspectHeight = _isVertOverscanCropped ?  240 - (OVERSCAN_VERTICAL   * 2)              : 240;

    return OEIntSizeMake(_aspectWidth, _aspectHeight);
}

- (OEIntSize)bufferSize
{
    return OEIntSizeMake(256, 240);
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
    return FSettings.SndRate;
}

- (NSUInteger)channelCount
{
    return 2;
}

# pragma mark - Save States

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    FCEUSS_Save(fileName.fileSystemRepresentation, false);
    block(YES, nil);
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    block(FCEUSS_Load(fileName.fileSystemRepresentation, false), nil);
}

- (NSData *)serializeStateWithError:(NSError **)outError
{
    std::vector<u8> byteVector;
    EMUFILE *emuFile = new EMUFILE_MEMORY(&byteVector);
    NSData *data = nil;
    
    if(FCEUSS_SaveMS(emuFile, Z_NO_COMPRESSION)) {
        const void *bytes = (const void *)(&byteVector[0]);
        NSUInteger length = byteVector.size();
        
        data = [NSData dataWithBytes:bytes length:length];
    }
    
    delete emuFile;
    return data;
}

- (BOOL)deserializeState:(NSData *)state withError:(NSError **)outError
{
    u8 *bytes = (u8 *)state.bytes;
    size_t length = state.length;
    std::vector<u8> byteVector(bytes, bytes + length);
    EMUFILE *emuFile = new EMUFILE_MEMORY(&byteVector);
    
    BOOL result = FCEUSS_LoadFP(emuFile, SSLOADPARAM_NOBACKUP);
    
    delete emuFile;

    if (result && _rcClient)
        rc_client_reset(_rcClient);

    return result;
}

# pragma mark - Input

const int NESMap[] = {JOY_UP, JOY_DOWN, JOY_LEFT, JOY_RIGHT, JOY_A, JOY_B, JOY_START, JOY_SELECT};
- (oneway void)didPushNESButton:(OENESButton)button forPlayer:(NSUInteger)player;
{
    int playerShift = 0;
    switch (player) {
        case 1:
            playerShift = 0;
            break;
        case 2:
            playerShift = 8;
            break;
        case 3:
            playerShift = 16;
            break;
        case 4:
            playerShift = 24;
            break;
    }

    _pad |= NESMap[button] << playerShift;
}

- (oneway void)didReleaseNESButton:(OENESButton)button forPlayer:(NSUInteger)player;
{
    int playerShift = 0;
    switch (player) {
        case 1:
            playerShift = 0;
            break;
        case 2:
            playerShift = 8;
            break;
        case 3:
            playerShift = 16;
            break;
        case 4:
            playerShift = 24;
            break;
    }

    _pad &= ~(NESMap[button] << playerShift);
}

- (oneway void)didTriggerGunAtPoint:(OEIntPoint)aPoint
{
    [self mouseMovedAtPoint:aPoint];

    int xcoord = _isHorzOverscanCropped ? (aPoint.x + OVERSCAN_HORIZONTAL) * 0.876712 : aPoint.x * 0.876712;
    int ycoord = _isVertOverscanCropped ? aPoint.y + OVERSCAN_VERTICAL : aPoint.y;

    _arkanoid[2] = 1;

    _zapper[0] = xcoord;
    _zapper[1] = ycoord;
    _zapper[2] = 1;

    _hypershot[0] = xcoord;
    _hypershot[1] = ycoord;
    _hypershot[2] = 1;
}

- (oneway void)didReleaseTrigger
{
    _arkanoid[2] = 0;
    _zapper[2] = 0;
    _hypershot[2] = 0;
}

- (oneway void)mouseMovedAtPoint:(OEIntPoint)aPoint
{
    _arkanoid[0] = _isHorzOverscanCropped ? (aPoint.x + OVERSCAN_HORIZONTAL) * 0.876712 : aPoint.x * 0.876712;
}

- (oneway void)rightMouseDownAtPoint:(OEIntPoint)point
{
    _hypershot[3] = 1; // "move" button
}

- (oneway void)rightMouseUp;
{
    _hypershot[3] = 0;
}

#pragma mark - Cheats

- (void)setCheat:(NSString *)code setType:(NSString *)type setEnabled:(BOOL)enabled
{
    // Sanitize
    code = [code stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    // Remove any spaces
    code = [code stringByReplacingOccurrencesOfString:@" " withString:@""];

    if (enabled)
        _cheatList[code] = @YES;
    else
        [_cheatList removeObjectForKey:code];

    FCEU_FlushGameCheats(0, 1);

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

                int address, value, compare;
                int type = 1;

                if (singleCode.length == 7 && [singleCode characterAtIndex:4] == ':')
                {
                    address = (int)strtoul([singleCode substringToIndex:4].UTF8String, NULL, 16);
                    value = (int)strtoul([singleCode substringFromIndex:5].UTF8String, NULL, 16);
                    compare = -1;
                    FCEUI_AddCheat(cCode, address, value, compare, type);
                }
                else if (singleCode.length == 10 && [singleCode characterAtIndex:4] == '?' && [singleCode characterAtIndex:7] == ':')
                {
                    address = (int)strtoul([singleCode substringToIndex:4].UTF8String, NULL, 16);
                    compare = (int)strtoul([singleCode substringWithRange:NSMakeRange(5, 2)].UTF8String, NULL, 16);
                    value = (int)strtoul([singleCode substringFromIndex:8].UTF8String, NULL, 16);
                    FCEUI_AddCheat(cCode, address, value, compare, type);
                }
                else if (FCEUI_DecodeGG(cCode, &address, &value, &compare))
                    FCEUI_AddCheat(cCode, address, value, compare, type);
                // Does not work
//                else if (FCEUI_DecodePAR(cCode, &address, &value, &compare, &type))
//                    FCEUI_AddCheat(cCode, address, value, compare, type);
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
          OptionDefault(@"Default — FCEUX", @"palette"),
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
        FCEUI_DisableSpriteLimitation(!displayModeState);
    }
    else if ([displayMode isEqualToString:@"Default — FCEUX"])
    {
        FCEU_ResetPalette();
    }
    else if ([displayMode isEqualToString:@"RGB (PlayChoice-10)"])
    {
        unsigned int pc10_palette[64] =
        {
            0x6D6D6D, 0x002492, 0x0000DB, 0x6D49DB,
            0x92006D, 0xB6006D, 0xB62400, 0x924900,
            0x6D4900, 0x244900, 0x006D24, 0x009200,
            0x004949, 0x000000, 0x000000, 0x000000,
            0xB6B6B6, 0x006DDB, 0x0049FF, 0x9200FF,
            0xB600FF, 0xFF0092, 0xFF0000, 0xDB6D00,
            0x926D00, 0x249200, 0x009200, 0x00B66D,
            0x009292, 0x242424, 0x000000, 0x000000,
            0xFFFFFF, 0x6DB6FF, 0x9292FF, 0xDB6DFF,
            0xFF00FF, 0xFF6DFF, 0xFF9200, 0xFFB600,
            0xDBDB00, 0x6DDB00, 0x00FF00, 0x49FFDB,
            0x00FFFF, 0x494949, 0x000000, 0x000000,
            0xFFFFFF, 0xB6DBFF, 0xDBB6FF, 0xFFB6FF,
            0xFF92FF, 0xFFB6B6, 0xFFDB92, 0xFFFF49,
            0xFFFF6D, 0xB6FF49, 0x92FF6D, 0x49FFDB,
            0x92DBFF, 0x929292, 0x000000, 0x000000
        };

        for (int i = 0; i < 64; i++)
        {
            int r = pc10_palette[i] >> 16;
            int g = (pc10_palette[i] & 0xff00) >> 8;
            int b = pc10_palette[i] & 0xff;
            FCEUD_SetPalette(i, r, g, b);
            FCEUD_SetPalette(i + 64, r, g, b);
            FCEUD_SetPalette(i + 128, r, g, b);
            FCEUD_SetPalette(i + 192, r, g, b);
        }
    }
    else if ([displayMode isEqualToString:@"NESCAP"])
    {
        unsigned int nescap_palette[64] =
        {
            0x646365, 0x001580, 0x1D0090, 0x380082,
            0x56005D, 0x5A001A, 0x4F0900, 0x381B00,
            0x1E3100, 0x003D00, 0x004100, 0x003A1B,
            0x002F55, 0x000000, 0x000000, 0x000000,
            0xAFADAF, 0x164BCA, 0x472AE7, 0x6B1BDB,
            0x9617B0, 0x9F185B, 0x963001, 0x7B4800,
            0x5A6600, 0x237800, 0x017F00, 0x00783D,
            0x006C8C, 0x000000, 0x000000, 0x000000,
            0xFFFFFF, 0x60A6FF, 0x8F84FF, 0xB473FF,
            0xE26CFF, 0xF268C3, 0xEF7E61, 0xD89527,
            0xBAB307, 0x81C807, 0x57D43D, 0x47CF7E,
            0x4BC5CD, 0x4C4B4D, 0x000000, 0x000000,
            0xFFFFFF, 0xC2E0FF, 0xD5D2FF, 0xE3CBFF,
            0xF7C8FF, 0xFEC6EE, 0xFECEC6, 0xF6D7AE,
            0xE9E49F, 0xD3ED9D, 0xC0F2B2, 0xB9F1CC,
            0xBAEDED, 0xBAB9BB, 0x000000, 0x000000
        };

        for (int i = 0; i < 64; i++)
        {
            int r = nescap_palette[i] >> 16;
            int g = (nescap_palette[i] & 0xff00) >> 8;
            int b = nescap_palette[i] & 0xff;
            FCEUD_SetPalette(i, r, g, b);
            FCEUD_SetPalette(i + 64, r, g, b);
            FCEUD_SetPalette(i + 128, r, g, b);
            FCEUD_SetPalette(i + 192, r, g, b);
        }
    }
    else if ([displayMode isEqualToString:@"Sony CXA2025AS"])
    {
        unsigned int cxa2025as_palette[64] =
        {
            0x585858, 0x00238C, 0x00139B, 0x2D0585,
            0x5D0052, 0x7A0017, 0x7A0800, 0x5F1800,
            0x352A00, 0x093900, 0x003F00, 0x003C22,
            0x00325D, 0x000000, 0x000000, 0x000000,
            0xA1A1A1, 0x0053EE, 0x153CFE, 0x6028E4,
            0xA91D98, 0xD41E41, 0xD22C00, 0xAA4400,
            0x6C5E00, 0x2D7300, 0x007D06, 0x007852,
            0x0069A9, 0x000000, 0x000000, 0x000000,
            0xFFFFFF, 0x1FA5FE, 0x5E89FE, 0xB572FE,
            0xFE65F6, 0xFE6790, 0xFE773C, 0xFE9308,
            0xC4B200, 0x79CA10, 0x3AD54A, 0x11D1A4,
            0x06BFFE, 0x424242, 0x000000, 0x000000,
            0xFFFFFF, 0xA0D9FE, 0xBDCCFE, 0xE1C2FE,
            0xFEBCFB, 0xFEBDD0, 0xFEC5A9, 0xFED18E,
            0xE9DE86, 0xC7E992, 0xA8EEB0, 0x95ECD9,
            0x91E4FE, 0xACACAC, 0x000000, 0x000000
        };

        for (int i = 0; i < 64; i++)
        {
            int r = cxa2025as_palette[i] >> 16;
            int g = (cxa2025as_palette[i] & 0xff00) >> 8;
            int b = cxa2025as_palette[i] & 0xff;
            FCEUD_SetPalette(i, r, g, b);
            FCEUD_SetPalette(i + 64, r, g, b);
            FCEUD_SetPalette(i + 128, r, g, b);
            FCEUD_SetPalette(i + 192, r, g, b);
        }
    }
    else if ([displayMode isEqualToString:@"Smooth (FBX)"])
    {
        unsigned int smoothfbx_palette[64] =
        {
            0x6A6D6A, 0x001380, 0x1E008A, 0x39007A,
            0x550056, 0x5A0018, 0x4F1000, 0x3D1C00,
            0x253200, 0x003D00, 0x004000, 0x003924,
            0x002E55, 0x000000, 0x000000, 0x000000,
            0xB9BCB9, 0x1850C7, 0x4B30E3, 0x7322D6,
            0x951FA9, 0x9D285C, 0x983700, 0x7F4C00,
            0x5E6400, 0x227700, 0x027E02, 0x007645,
            0x006E8A, 0x000000, 0x000000, 0x000000,
            0xFFFFFF, 0x68A6FF, 0x8C9CFF, 0xB586FF,
            0xD975FD, 0xE377B9, 0xE58D68, 0xD49D29,
            0xB3AF0C, 0x7BC211, 0x55CA47, 0x46CB81,
            0x47C1C5, 0x4A4D4A, 0x000000, 0x000000,
            0xFFFFFF, 0xCCEAFF, 0xDDDEFF, 0xECDAFF,
            0xF8D7FE, 0xFCD6F5, 0xFDDBCF, 0xF9E7B5,
            0xF1F0AA, 0xDAFAA9, 0xC9FFBC, 0xC3FBD7,
            0xC4F6F6, 0xBEC1BE, 0x000000, 0x000000
        };

        for (int i = 0; i < 64; i++)
        {
            int r = smoothfbx_palette[i] >> 16;
            int g = (smoothfbx_palette[i] & 0xff00) >> 8;
            int b = smoothfbx_palette[i] & 0xff;
            FCEUD_SetPalette(i, r, g, b);
            FCEUD_SetPalette(i + 64, r, g, b);
            FCEUD_SetPalette(i + 128, r, g, b);
            FCEUD_SetPalette(i + 192, r, g, b);
        }
    }
    else if ([displayMode isEqualToString:@"Wavebeam"])
    {
        unsigned int wavebeam_palette[64] =
        {
            0x6B6B6B, 0x001B88, 0x21009A, 0x40008C,
            0x600067, 0x64001E, 0x590800, 0x481600,
            0x283600, 0x004500, 0x004908, 0x00421D,
            0x003659, 0x000000, 0x000000, 0x000000,
            0xB4B4B4, 0x1555D3, 0x4337EF, 0x7425DF,
            0x9C19B9, 0xAC0F64, 0xAA2C00, 0x8A4B00,
            0x666B00, 0x218300, 0x008A00, 0x008144,
            0x007691, 0x000000, 0x000000, 0x000000,
            0xFFFFFF, 0x63B2FF, 0x7C9CFF, 0xC07DFE,
            0xE977FF, 0xF572CD, 0xF4886B, 0xDDA029,
            0xBDBD0A, 0x89D20E, 0x5CDE3E, 0x4BD886,
            0x4DCFD2, 0x525252, 0x000000, 0x000000,
            0xFFFFFF, 0xBCDFFF, 0xD2D2FF, 0xE1C8FF,
            0xEFC7FF, 0xFFC3E1, 0xFFCAC6, 0xF2DAAD,
            0xEBE3A0, 0xD2EDA2, 0xBCF4B4, 0xB5F1CE,
            0xB6ECF1, 0xBFBFBF, 0x000000, 0x000000
        };

        for (int i = 0; i < 64; i++)
        {
            int r = wavebeam_palette[i] >> 16;
            int g = (wavebeam_palette[i] & 0xff00) >> 8;
            int b = wavebeam_palette[i] & 0xff;
            FCEUD_SetPalette(i, r, g, b);
            FCEUD_SetPalette(i + 64, r, g, b);
            FCEUD_SetPalette(i + 128, r, g, b);
            FCEUD_SetPalette(i + 192, r, g, b);
        }
    }
}

- (void)loadDisplayModeOptions
{
    // Restore palette
    NSString *lastPalette = self.displayModeInfo[@"palette"];
    if (lastPalette && ![lastPalette isEqualToString:@"Default — FCEUX"]) {
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

// FCEUX internal functions and stubs
void FCEUD_SetPalette(unsigned char index, unsigned char r, unsigned char g, unsigned char b)
{
    palette[index] = ( r << 16 ) | ( g << 8 ) | b;
}

void FCEUD_GetPalette(unsigned char i, unsigned char *r, unsigned char *g, unsigned char *b) {}
uint64 FCEUD_GetTime(void) {return 0;}
uint64 FCEUD_GetTimeFreq(void) {return 0;}
const char *GetKeyboard(void) {return "";}
bool turbo = false;
bool swapDuty = 0; // some Famicom and NES clones had duty cycle bits swapped
int dendy = 0;
int eoptions = 0;
int closeFinishedMovie = 0;
int KillFCEUXonFrame = 0;
int FCEUD_ShowStatusIcon(void) {return 0;}
int FCEUD_SendData(void *data, uint32 len) {return 1;}
int FCEUD_RecvData(void *data, uint32 len) {return 1;}
FILE *FCEUD_UTF8fopen(const char *fn, const char *mode)
{
    return fopen(fn, mode);
}
EMUFILE_FILE *FCEUD_UTF8_fstream(const char *fn, const char *m)
{
    std::ios_base::openmode mode = std::ios_base::binary;
    if(!strcmp(m,"r") || !strcmp(m,"rb"))
        mode |= std::ios_base::in;
    else if(!strcmp(m,"w") || !strcmp(m,"wb"))
        mode |= std::ios_base::out | std::ios_base::trunc;
    else if(!strcmp(m,"a") || !strcmp(m,"ab"))
        mode |= std::ios_base::out | std::ios_base::app;
    else if(!strcmp(m,"r+") || !strcmp(m,"r+b"))
        mode |= std::ios_base::in | std::ios_base::out;
    else if(!strcmp(m,"w+") || !strcmp(m,"w+b"))
        mode |= std::ios_base::in | std::ios_base::out | std::ios_base::trunc;
    else if(!strcmp(m,"a+") || !strcmp(m,"a+b"))
        mode |= std::ios_base::in | std::ios_base::out | std::ios_base::app;
    return new EMUFILE_FILE(fn, m);
    //return new std::fstream(fn,mode);
}
void FCEUD_NetplayText(uint8 *text) {};
void FCEUD_NetworkClose(void) {}
void FCEUD_FlushTrace(void) {}
void FCEUD_VideoChanged (void) {}
bool FCEUD_ShouldDrawInputAids() {return false;}
bool FCEUD_PauseAfterPlayback() {return false;}
void FCEUI_AviVideoUpdate(const unsigned char* buffer) {}
bool FCEUI_AviEnableHUDrecording() {return false;}
bool FCEUI_AviIsRecording(void) {return false;}
bool FCEUI_AviDisableMovieMessages() {return true;}
FCEUFILE *FCEUD_OpenArchiveIndex(ArchiveScanRecord &asr, std::string &fname, int innerIndex) {return 0;}
FCEUFILE *FCEUD_OpenArchive(ArchiveScanRecord &asr, std::string &fname, std::string *innerFilename) {return 0;}
FCEUFILE *FCEUD_OpenArchiveIndex(ArchiveScanRecord &asr, std::string &fname, int innerIndex, int *userCancel) {return 0;}
FCEUFILE *FCEUD_OpenArchive(ArchiveScanRecord &asr, std::string &fname, std::string *innerFilename, int *userCancel) {return 0;}
ArchiveScanRecord FCEUD_ScanArchive(std::string fname) { return ArchiveScanRecord(); }
void GetMouseData(uint32 (&md)[3]) {}
void FCEUD_PrintError(const char *s)
{
    NSLog(@"[FCEUX] error: %s", s);
}
void FCEUD_Message(const char *s)
{
    NSLog(@"[FCEUX] message: %s", s);
}

@end
