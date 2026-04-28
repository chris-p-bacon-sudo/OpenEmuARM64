/*
 Copyright (c) 2016, Jeffrey Pfau

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS ''AS IS''
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 */

#import "mGBAGameCore.h"


#include <mgba-util/common.h>

#include <mgba/core/blip_buf.h>
#include <mgba/core/core.h>
#include <mgba/core/cheats.h>
#include <mgba/core/serialize.h>
#include <mgba/gba/core.h>
#include <mgba/internal/gba/cheats.h>
#include <mgba/internal/gba/input.h>
#include <mgba-util/circle-buffer.h>
#include <mgba-util/memory.h>
#include <mgba-util/vfs.h>

#import <OpenEmuBase/OERingBuffer.h>
#import "OEGBASystemResponderClient.h"
#import <OpenGL/gl.h>

#define RC_CLIENT_SUPPORTS_HASH 1
#include <rc_client.h>
#include <rc_consoles.h>
#import "OERetroAchievementsTransport.h"

#define SAMPLES 1024

#ifdef DEBUG
    #error "Cores should not be compiled in DEBUG! Follow the guide https://github.com/OpenEmu/OpenEmu/wiki/Compiling-From-Source-Guide"
#endif

const char* const binaryName = "mGBA";
const char* const projectName = "mGBA";
const char* projectVersion;

@interface mGBAGameCore () <OEGBASystemResponderClient>
{
	struct mCore* core;
	void* outputBuffer;
	NSMutableDictionary *cheatSets;
	rc_client_t *_rcClient;
    id _raTokenObserver;
    NSString *_romPath;
}
- (struct mCore *)mCore;
- (void)_beginLoadGame;
@end

// rcheevos GBA address space → hardware bus address:
//   0x000000–0x007FFF  →  IWRAM  0x03000000
//   0x008000–0x047FFF  →  EWRAM  0x02000000
//   0x048000–0x057FFF  →  SRAM   0x0E000000
static uint32_t gba_rc_to_hw(uint32_t addr) {
    if (addr < 0x008000) return 0x03000000 + addr;
    if (addr < 0x048000) return 0x02000000 + (addr - 0x008000);
    if (addr < 0x058000) return 0x0E000000 + (addr - 0x048000);
    return addr;
}

static uint32_t mGBA_rc_read_memory(uint32_t address, uint8_t *buffer,
                                     uint32_t num_bytes, rc_client_t *client)
{
    mGBAGameCore *c = (__bridge mGBAGameCore *)rc_client_get_userdata(client);
    struct mCore *mcore = [c mCore];
    if (!mcore) { return 0; }
    for (uint32_t i = 0; i < num_bytes; i++) {
        buffer[i] = mcore->busRead8(mcore, gba_rc_to_hw(address + i));
    }
    return num_bytes;
}


static void mGBA_rc_load_game_callback(int result, const char *error_message,
                                        rc_client_t *client, void *userdata)
{
    mGBAGameCore *self = (__bridge mGBAGameCore *)userdata;
    if (result != RC_OK) {
        NSLog(@"[RA-mGBA] game load failed — result=%d error=%s", result, error_message ?: "(none)");
    }
    (void)self;
}

static void mGBA_rc_login_callback(int result, const char *error_message,
                                    rc_client_t *client, void *userdata)
{
    mGBAGameCore *self = (__bridge mGBAGameCore *)userdata;
    if (result == RC_OK) {
        [self _beginLoadGame];
    } else {
        NSLog(@"[RA-mGBA] login failed — result=%d error=%s", result, error_message ?: "(none)");
    }
}

static void mGBA_rc_event_handler(const rc_client_event_t *event, rc_client_t *client)
{
    if (event->type != RC_CLIENT_EVENT_ACHIEVEMENT_TRIGGERED) { return; }
    const rc_client_achievement_t *ach = event->achievement;
    if (!ach) { return; }

    NSString *title       = [NSString stringWithUTF8String:ach->title       ?: ""];
    NSString *desc        = [NSString stringWithUTF8String:ach->description  ?: ""];
    NSString *badge       = [NSString stringWithUTF8String:ach->badge_name   ?: ""];
    NSNumber *achId       = @(ach->id);
    NSNumber *points      = @(ach->points);

    NSDictionary *info = @{
        OEAchievementIDKey:          achId,
        OEAchievementTitleKey:       title,
        OEAchievementDescriptionKey: desc,
        OEAchievementBadgeURLKey:    badge,
        OEAchievementPointsKey:      points,
    };
    [[NSNotificationCenter defaultCenter]
        postNotificationName:OEAchievementUnlockedNotification
                      object:nil
                    userInfo:info];
}

static void _log(struct mLogger* log,
                 int category,
                 enum mLogLevel level,
                 const char* format,
                 va_list args)
{}

static struct mLogger logger = { .log = _log };

@implementation mGBAGameCore

- (struct mCore *)mCore { return core; }

- (void)_beginLoadGame
{
    if (!_rcClient || !_romPath) { return; }
    rc_client_begin_identify_and_load_game(_rcClient,
                                           RC_CONSOLE_GAMEBOY_ADVANCE,
                                           [_romPath fileSystemRepresentation],
                                           NULL, 0,
                                           mGBA_rc_load_game_callback,
                                           (__bridge void *)self);
}


- (id)init
{
	if ((self = [super init]))
	{
		core = GBACoreCreate();
		mCoreInitConfig(core, nil);

		struct mCoreOptions opts = {
			.useBios = true,
		};
        
        // Set up a logger. The default logger prints everything to STDOUT, which is not usually desirable.
        mLogSetDefaultLogger(&logger);

		mCoreConfigLoadDefaults(&core->config, &opts);
		core->init(core);
		outputBuffer = nil;

		unsigned width, height;
		core->desiredVideoDimensions(core, &width, &height);
		outputBuffer = malloc(width * height * BYTES_PER_PIXEL);
		core->setVideoBuffer(core, outputBuffer, width);
		core->setAudioBufferSize(core, SAMPLES);

		cheatSets = [[NSMutableDictionary alloc] init];
	}

	return self;
}

- (void)dealloc
{
    mCoreConfigDeinit(&core->config);
	core->deinit(core);
	free(outputBuffer);
}

#pragma mark - Execution

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
    RALog(@"[RA-mGBA] loadFileAtPath entered: %@", path);
    projectVersion = [self.owner.bundle.infoDictionary[@"CFBundleVersion"] UTF8String];

	NSString *batterySavesDirectory = [self batterySavesDirectoryPath];
	[[NSFileManager defaultManager] createDirectoryAtURL:[NSURL fileURLWithPath:batterySavesDirectory]
	                                withIntermediateDirectories:YES
	                                attributes:nil
	                                error:nil];
	if (core->dirs.save) {
		core->dirs.save->close(core->dirs.save);
	}
	core->dirs.save = VDirOpen([batterySavesDirectory fileSystemRepresentation]);

	if (!mCoreLoadFile(core, [path fileSystemRepresentation])) {
		if (error) {
			*error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:nil];
		}
		return NO;
	}
	mCoreAutoloadSave(core);

	core->reset(core);

    _rcClient = rc_client_create(mGBA_rc_read_memory, oeRetroAchievementsServerCall);
    if (_rcClient) {
        _romPath = path;
        rc_client_set_userdata(_rcClient, (__bridge void *)self);
        rc_client_set_event_handler(_rcClient, mGBA_rc_event_handler);
        rc_client_set_hardcore_enabled(_rcClient, 0);

        // Register token observer before game identification so we don't miss
        // the notification that fires immediately after setRetroAchievementsToken.
        // Login happens first; game identification runs in the login callback.
        __weak mGBAGameCore *weakSelf = self;
        _raTokenObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:OERetroAchievementsTokenDidChangeNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) {
            mGBAGameCore *s = weakSelf;
            if (!s || !s->_rcClient) { return; }
            NSString *token    = note.userInfo[OERetroAchievementsTokenKey];
            NSString *username = note.userInfo[OERetroAchievementsUsernameKey];
            if (token && username) {
                rc_client_begin_login_with_token(s->_rcClient,
                                                 username.UTF8String,
                                                 token.UTF8String,
                                                 mGBA_rc_login_callback,
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
	core->runFrame(core);

	if (_rcClient) {
        rc_client_do_frame(_rcClient);
    }

	int16_t samples[SAMPLES * 2];
	size_t available = 0;
	available = blip_samples_avail(core->getAudioChannel(core, 0));
	blip_read_samples(core->getAudioChannel(core, 0), samples, available, true);
	blip_read_samples(core->getAudioChannel(core, 1), samples + 1, available, true);
	[[self audioBufferAtIndex:0] write:samples maxLength:available * 4];
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
    [super stopEmulation];
}

- (void)resetEmulation
{
	if (_rcClient) {
        rc_client_reset(_rcClient);
    }
	core->reset(core);
}

- (void)setupEmulation
{
	blip_set_rates(core->getAudioChannel(core, 0), core->frequency(core), 32768);
	blip_set_rates(core->getAudioChannel(core, 1), core->frequency(core), 32768);
}

#pragma mark - Video

- (OEIntSize)aspectSize
{
	return OEIntSizeMake(3, 2);
}

- (OEIntRect)screenRect
{
	unsigned width, height;
	core->desiredVideoDimensions(core, &width, &height);
    return OEIntRectMake(0, 0, width, height);
}

- (OEIntSize)bufferSize
{
	unsigned width, height;
	core->desiredVideoDimensions(core, &width, &height);
    return OEIntSizeMake(width, height);
}

- (const void *)getVideoBufferWithHint:(void *)hint
{
	OEIntSize bufferSize = [self bufferSize];

	if (!hint)
	{
		hint = outputBuffer;
	}

	outputBuffer = hint;
	core->setVideoBuffer(core, hint, bufferSize.width);

	return hint;
}

- (GLenum)pixelFormat
{
    return GL_RGBA;
}

- (GLenum)pixelType
{
    return GL_UNSIGNED_INT_8_8_8_8_REV;
}

- (NSTimeInterval)frameInterval
{
	return core->frequency(core) / (double) core->frameCycles(core);
}

#pragma mark - Audio

- (NSUInteger)channelCount
{
    return 2;
}

- (double)audioSampleRate
{
    return 32768;
}

#pragma mark - Save State

- (NSData *)serializeStateWithError:(NSError **)outError
{
	struct VFile* vf = VFileMemChunk(nil, 0);
	if (!mCoreSaveStateNamed(core, vf, SAVESTATE_SAVEDATA)) {
		if (outError) {
			*outError = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadStateError userInfo:nil];
		}
		vf->close(vf);
		return nil;
	}
	size_t size = vf->size(vf);
	void* data = vf->map(vf, size, MAP_READ);
	NSData *nsdata = [NSData dataWithBytes:data length:size];
	vf->unmap(vf, data, size);
	vf->close(vf);
	return nsdata;
}

- (BOOL)deserializeState:(NSData *)state withError:(NSError **)outError
{
	struct VFile* vf = VFileFromConstMemory(state.bytes, state.length);
	if (!mCoreLoadStateNamed(core, vf, SAVESTATE_SAVEDATA)) {
		if (outError) {
			*outError = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadStateError userInfo:nil];
		}
		vf->close(vf);
		return NO;
	}
	vf->close(vf);
	return YES;
}

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
	struct VFile* vf = VFileOpen([fileName fileSystemRepresentation], O_CREAT | O_TRUNC | O_RDWR);
	block(mCoreSaveStateNamed(core, vf, 0), nil);
	vf->close(vf);
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
	struct VFile* vf = VFileOpen([fileName fileSystemRepresentation], O_RDONLY);
	BOOL ok = mCoreLoadStateNamed(core, vf, 0);
	vf->close(vf);
	if (ok && _rcClient) {
		rc_client_reset(_rcClient);
	}
	block(ok, nil);
}

#pragma mark - Input

const int GBAMap[] = {
	GBA_KEY_UP,
	GBA_KEY_DOWN,
	GBA_KEY_LEFT,
	GBA_KEY_RIGHT,
	GBA_KEY_A,
	GBA_KEY_B,
	GBA_KEY_L,
	GBA_KEY_R,
	GBA_KEY_START,
	GBA_KEY_SELECT
};

- (oneway void)didPushGBAButton:(OEGBAButton)button forPlayer:(NSUInteger)player
{
	UNUSED(player);
	core->addKeys(core, 1 << GBAMap[button]);
}

- (oneway void)didReleaseGBAButton:(OEGBAButton)button forPlayer:(NSUInteger)player
{
	UNUSED(player);
	core->clearKeys(core, 1 << GBAMap[button]);
}

#pragma mark - Cheats

- (void)setCheat:(NSString *)code setType:(NSString *)type setEnabled:(BOOL)enabled
{
	code = [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	code = [code stringByReplacingOccurrencesOfString:@" " withString:@""];

	NSString *codeId = [code stringByAppendingFormat:@"/%@", type];
	struct mCheatSet* cheatSet = [[cheatSets objectForKey:codeId] pointerValue];
	if (cheatSet) {
		cheatSet->enabled = enabled;
		return;
	}
	struct mCheatDevice* cheats = core->cheatDevice(core);
	cheatSet = cheats->createSet(cheats, [codeId UTF8String]);
	size_t size = mCheatSetsSize(&cheats->cheats);
	if (size) {
		cheatSet->copyProperties(cheatSet, *mCheatSetsGetPointer(&cheats->cheats, size - 1));
	}
	int codeType = GBA_CHEAT_AUTODETECT;
	// NOTE: This is deprecated and was only meant to test cheats with the UI using cheats-database.xml
	// Will be replaced with a sqlite database in the future.
//    if ([type isEqual:@"GameShark"]) {
//        codeType = GBA_CHEAT_GAMESHARK;
//    } else if ([type isEqual:@"Action Replay"]) {
//        codeType = GBA_CHEAT_PRO_ACTION_REPLAY;
//    }
	NSArray *codeSet = [code componentsSeparatedByString:@"+"];
	for (id c in codeSet) {
//        if ([c length] == 12)
//            codeType = GBA_CHEAT_CODEBREAKER;
//        if ([c length] == 16) // default to GS/AR v1/v2 code (can't determine GS/AR v1/v2 vs AR v3 because same length)
//            codeType = GBA_CHEAT_GAMESHARK;
		mCheatAddLine(cheatSet, [c UTF8String], codeType);
	}
	cheatSet->enabled = enabled;
	[cheatSets setObject:[NSValue valueWithPointer:cheatSet] forKey:codeId];
	mCheatAddSet(cheats, cheatSet);
}
@end

