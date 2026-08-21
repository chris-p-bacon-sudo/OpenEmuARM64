/*
 Copyright (c) 2014, OpenEmu Team
 

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

#import "StellaGameCore.h"
#import <OpenEmuBase/OERingBuffer.h>
#import <OpenEmuBase/OEMemoryRegionDescriptor.h>
#import "OE2600SystemResponderClient.h"
#import <OpenGL/gl.h>

#define RC_CLIENT_SUPPORTS_HASH 1
#include <rc_client.h>
#include <rc_consoles.h>
#import "OERetroAchievementsTransport.h"
#import "OERetroAchievementsBridge.h"

#include "Console.hxx"
#include "Cart.hxx"
#include "Props.hxx"
#include "MD5.hxx"
#include "Sound.hxx"
#include "SerialPort.hxx"
#include "TIA.hxx"
#include "Switches.hxx"
#include "StateManager.hxx"
#include "PropsSet.hxx"
#include "Paddles.hxx"
#include "SoundSDL.hxx"

static SoundSDL *vcsSound = 0;
#include "Stubs.hh"

static Console *console = 0;
static Settings *settings = 0;
static OSystem osystem;
static StateManager stateManager(&osystem);
const uint32_t *Palette;

#define OptionDefault(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @YES, }
#define Option(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, }
#define OptionIndented(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, OEGameCoreDisplayModeIndentationLevelKey : @(1), }
#define OptionToggleable(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, OEGameCoreDisplayModeAllowsToggleKey : @YES, }
#define OptionToggleableNoSave(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, OEGameCoreDisplayModeAllowsToggleKey : @YES, OEGameCoreDisplayModeDisallowPrefSaveKey : @YES, }
#define Label(_NAME_) @{ OEGameCoreDisplayModeLabelKey : _NAME_, }
#define SeparatorItem() @{ OEGameCoreDisplayModeSeparatorItemKey : @"",}

// Set the palette for the current Stella instance
void stellaOESetPalette(const uInt32 *palette)
{
    Palette = palette;
}

@interface StellaGameCore () <OE2600SystemResponderClient>
{
    uint32_t *_videoBuffer;
    uint32_t *_activeVideoBuffer;
    int16_t *_sampleBuffer;
    int _videoWidth, _videoHeight;
    NSMutableArray <NSMutableDictionary <NSString *, id> *> *_availableDisplayModes;
    NSMutableDictionary<NSString *, NSNumber *> *_cheatList;
    OERetroAchievementsBridge *_raBridge;
}

- (void)loadDisplayModeOptions;

@end

// rcheevos address 0x0000–0x007F → hardware 0x0080–0x00FF (128 bytes system RAM)
static uint32_t stella_rc_read_memory(uint32_t address, uint8_t *buffer,
                                       uint32_t num_bytes, rc_client_t *client)
{
    if (!console) return 0;
    for (uint32_t i = 0; i < num_bytes; i++) {
        uint32_t addr = 0x80 + address + i;
        if (addr > 0xFF)
            return i;
        buffer[i] = console->system().peek((uInt16)addr);
    }
    return num_bytes;
}

@implementation StellaGameCore

- (id)init
{
    if((self = [super init]))
    {
        _videoBuffer = (uint32_t *)malloc(160 * 256 * sizeof(uint32_t));
        _activeVideoBuffer = _videoBuffer;
        _sampleBuffer = (int16_t *)malloc(2048 * sizeof(int16_t));
    }

	return self;
}

- (void)retroAchievementsIdle
{
    [_raBridge idle];
}

- (BOOL)canPauseRetroAchievementsHardcoreWithFramesRemaining:(uint32_t *)framesRemaining
{
    return _raBridge ? [_raBridge canPauseWithFramesRemaining:framesRemaining] : YES;
}

- (NSData *)retroAchievementsSerializedProgress
{
    return [_raBridge serializeProgress];
}

- (void)retroAchievementsDeserializeProgress:(NSData *)data
{
    [_raBridge deserializeProgress:data];
}

- (void)dealloc
{
    free(_videoBuffer);
    _videoBuffer = nil;
    free(_sampleBuffer);
    _sampleBuffer = nil;
    
    if (console) {
        delete console;
        console = nullptr;
    }
    
    if (settings) {
        delete settings;
        settings = nullptr;
    }
}

# pragma mark - Execution

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
    // Load ROM to memory
    NSData *dataObj = [NSData dataWithContentsOfFile:path.stringByStandardizingPath];
    if(dataObj == nil) return NO;
    const void *data = dataObj.bytes;
    NSUInteger size = dataObj.length;

    // Get the game properties
    string cartMD5 = MD5((const uint8_t*)data, (uint32_t)size);
    Properties props;
    osystem.propSet().getMD5(cartMD5, props);

    // Load the cart
    string cartType = props.get(Cartridge_Type);
    string cartId;//, romType("AUTO-DETECT");
    settings = new Settings(&osystem);
    settings->setValue("romloadcount", 0);
    Cartridge *cartridge = Cartridge::create((const uint8_t*)data, (uint32_t)size, cartMD5, cartType, cartId, osystem, *settings);

    if(cartridge == 0)
    {
        return NO;
    }

    console = new Console(&osystem, cartridge, props);
    osystem.myConsole = console;

    //tia.enableAutoFrame(false);
    console->initializeVideo();
    console->initializeAudio();

    // Get the ROM's width and height
    TIA &tia = console->tia();
    _videoWidth = tia.width();
    _videoHeight = tia.height();

    // Only temporary, so core doesn't crash on an older OpenEmu version
    if ([self respondsToSelector:@selector(displayModeInfo)]) {
        [self loadDisplayModeOptions];
    }

    _raBridge = [[OERetroAchievementsBridge alloc] initWithGameCore:self
                                                        memoryReader:stella_rc_read_memory
                                                           consoleID:RC_CONSOLE_ATARI_2600];
    [_raBridge startWithROMPath:path];
    [_raBridge markROMReady];

    return YES;
}

- (void)executeFrame
{
    uint32_t tiaSamplesPerFrame = 31400.0f/console->getFramerate();

    console->controller(Controller::Left).update();
    console->controller(Controller::Right).update();
    console->switches().update();

    TIA &tia = console->tia();
    tia.update();

    for (NSString *key in _cheatList) {
        if (![_cheatList[key] boolValue]) continue;
        NSArray<NSString *> *codes = [key componentsSeparatedByString:@"+"];
        for (NSString *singleCode in codes) {
            NSRange colonRange = [singleCode rangeOfString:@":"];
            if (colonRange.location != NSNotFound) {
                unsigned int addr = 0, val = 0;
                if (![[NSScanner scannerWithString:[singleCode substringToIndex:colonRange.location]] scanHexInt:&addr]) continue;
                if (![[NSScanner scannerWithString:[singleCode substringFromIndex:colonRange.location + 1]] scanHexInt:&val]) continue;
                console->system().poke((uInt16)addr, (uInt8)val);
            }
        }
    }

    // Video
    _videoWidth = tia.width();
    _videoHeight = tia.height();

    for (unsigned int i = 0; i < _videoHeight * _videoWidth; ++i)
        _activeVideoBuffer[i] = Palette[tia.currentFrameBuffer()[i]];

    [_raBridge doFrame];

    // Audio
    vcsSound->processFragment(_sampleBuffer, tiaSamplesPerFrame);
    [[self ringBufferAtIndex:0] write:_sampleBuffer maxLength:tiaSamplesPerFrame << 2];
}

- (void)setupEmulation
{
}

- (void)resetEmulation
{
    [_raBridge reset];
    console->system().reset();
}

- (void)stopEmulation
{
    [_raBridge shutdown];
    _raBridge = nil;
    [super stopEmulation];
}

- (NSTimeInterval)frameInterval
{
    return console->getFramerate();
}

# pragma mark - Video

- (const void *)getVideoBufferWithHint:(void *)hint
{
    return _activeVideoBuffer = (uint32_t*)(hint ?: _videoBuffer);
}

- (OEIntRect)screenRect
{
    return OEIntRectMake(0, 0, _videoWidth, _videoHeight);
}

- (OEIntSize)bufferSize
{
    return OEIntSizeMake(160, 256);
}

- (OEIntSize)aspectSize
{
    BOOL isPAL = console->getFramerate() < 59 ? YES : NO;
    // PAL: 7375000.0 / ((283.75 * 15625.0 + 25.0) * 4.0 / 5.0)
    double PAR = isPAL ? 2.079283 : 12.0/7.0;
    return OEIntSizeMake(_videoWidth * PAR, _videoHeight);
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
    return 31400;
}

- (NSUInteger)channelCount
{
    return 2;
}

# pragma mark - Save States

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    Serializer state(fileName.fileSystemRepresentation, 0);
    block(stateManager.saveState(state), nil);
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    Serializer state(fileName.fileSystemRepresentation, 1);
    block(stateManager.loadState(state), nil);
}

- (NSData *)serializeStateWithError:(NSError **)outError
{
    Serializer serializer;
    if(stateManager.saveState(serializer)) {
        serializer.myStream->seekg(0, std::ios::end);
        NSUInteger length = serializer.myStream->tellg();
        serializer.myStream->seekg(0, std::ios::beg);

        NSMutableData *data = [NSMutableData dataWithLength:length];
        serializer.myStream->read((char *)data.mutableBytes, length);
        return data;
    }

    if (outError) {
        *outError = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotSaveStateError userInfo:@{
            NSLocalizedDescriptionKey : @"Could not serialize save state data"
        }];
    }

    return nil;
}

- (BOOL)deserializeState:(NSData *)state withError:(NSError **)outError
{
    char const *bytes = (char const *)state.bytes;
    std::streamsize size = state.length;

    Serializer serializer;
    serializer.myStream->write(bytes, size);

    if(stateManager.loadState(serializer))
        return YES;

    if(outError) {
        *outError = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadStateError userInfo:@{
            NSLocalizedDescriptionKey : @"The save state data could not be loaded"
        }];
    }

    return NO;
}

# pragma mark - Input

- (oneway void)didPush2600Button:(OE2600Button)button forPlayer:(NSUInteger)player
{
    Event &ev = osystem.eventHandler().event();
    int playerShift = player != 1 ? 7 : 0;

    switch (button) {
        case OE2600ButtonUp:
            ev.set(Event::Type(Event::JoystickZeroUp + playerShift), 1);
            break;
        case OE2600ButtonDown:
            ev.set(Event::Type(Event::JoystickZeroDown + playerShift), 1);
            break;
        case OE2600ButtonLeft:
            ev.set(Event::Type(Event::JoystickZeroLeft + playerShift), 1);
            break;
        case OE2600ButtonRight:
            ev.set(Event::Type(Event::JoystickZeroRight + playerShift), 1);
            break;
        case OE2600ButtonFire1:
            ev.set(Event::Type(Event::JoystickZeroFire + playerShift), 1);
            break;
        case OE2600ButtonLeftDiffA:
            ev.set(Event::Type(Event::ConsoleLeftDiffA), 1);
            break;
        case OE2600ButtonLeftDiffB:
            ev.set(Event::Type(Event::ConsoleLeftDiffB), 1);
            break;
        case OE2600ButtonRightDiffA:
            ev.set(Event::Type(Event::ConsoleRightDiffA), 1);
            break;
        case OE2600ButtonRightDiffB:
            ev.set(Event::Type(Event::ConsoleRightDiffB), 1);
            break;
        case OE2600ButtonTVTypeColor:
            ev.set(Event::Type(Event::ConsoleColor), 1);
            break;
        case OE2600ButtonTVTypeBlackAndWhite:
            ev.set(Event::Type(Event::ConsoleBlackWhite), 1);
            break;
        case OE2600ButtonReset:
            ev.set(Event::Type(Event::ConsoleReset), 1);
            break;
        case OE2600ButtonSelect:
            ev.set(Event::Type(Event::ConsoleSelect), 1);
            break;

        default:
            break;
    }
}

- (oneway void)didRelease2600Button:(OE2600Button)button forPlayer:(NSUInteger)player
{
    Event &ev = osystem.eventHandler().event();
    int playerShift = player != 1 ? 7 : 0;

    switch (button) {
        case OE2600ButtonUp:
            ev.set(Event::Type(Event::JoystickZeroUp + playerShift), 0);
            break;
        case OE2600ButtonDown:
            ev.set(Event::Type(Event::JoystickZeroDown + playerShift), 0);
            break;
        case OE2600ButtonLeft:
            ev.set(Event::Type(Event::JoystickZeroLeft + playerShift), 0);
            break;
        case OE2600ButtonRight:
            ev.set(Event::Type(Event::JoystickZeroRight + playerShift), 0);
            break;
        case OE2600ButtonFire1:
            ev.set(Event::Type(Event::JoystickZeroFire + playerShift), 0);
            break;
        case OE2600ButtonLeftDiffA:
            ev.set(Event::Type(Event::ConsoleLeftDiffA), 0);
            break;
        case OE2600ButtonLeftDiffB:
            ev.set(Event::Type(Event::ConsoleLeftDiffB), 0);
            break;
        case OE2600ButtonRightDiffA:
            ev.set(Event::Type(Event::ConsoleRightDiffA), 0);
            break;
        case OE2600ButtonRightDiffB:
            ev.set(Event::Type(Event::ConsoleRightDiffB), 0);
            break;
        case OE2600ButtonTVTypeColor:
            ev.set(Event::Type(Event::ConsoleColor), 0);
            break;
        case OE2600ButtonTVTypeBlackAndWhite:
            ev.set(Event::Type(Event::ConsoleBlackWhite), 0);
            break;
        case OE2600ButtonReset:
            ev.set(Event::Type(Event::ConsoleReset), 0);
            break;
        case OE2600ButtonSelect:
            ev.set(Event::Type(Event::ConsoleSelect), 0);
            break;

        default:
            break;
    }
}

- (oneway void)mouseMovedAtPoint:(OEIntPoint)point
{
}

- (oneway void)leftMouseDownAtPoint:(OEIntPoint)point
{
}

- (oneway void)leftMouseUp
{
}

# pragma mark - Display Mode

- (NSArray <NSDictionary <NSString *, id> *> *)displayModes
{
    if (_availableDisplayModes.count == 0)
    {
        _availableDisplayModes = [NSMutableArray array];

        BOOL isPAL = console->getFramerate() < 59 ? YES : NO;

        NSArray <NSDictionary <NSString *, id> *> *availableModesWithDefault =
        @[
          Label(@"Format"),
          OptionDefault(@"Auto", @"format"),
          isPAL ? Option(@"NTSC50", @"format") : Option(@"NTSC", @"format"),
          isPAL ? Option(@"PAL", @"format")    : Option(@"PAL60", @"format"),
          isPAL ? Option(@"SECAM", @"format")  : Option(@"SECAM60", @"format"),
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
    BOOL isValidDisplayMode = NO;

    for (NSDictionary *modeDict in _availableDisplayModes) {
        if ([modeDict[OEGameCoreDisplayModeNameKey] isEqualToString:displayMode]) {
            isValidDisplayMode = YES;
            break;
        }
    }

    // Disallow a 'displayMode' not found in _availableDisplayModes
    if (!isValidDisplayMode)
        return;

    // Handle option state changes
    for (NSMutableDictionary *optionDict in _availableDisplayModes) {
        if (!optionDict[OEGameCoreDisplayModeNameKey])
            continue;
        // Mutually exclusive option state change
        else if ([optionDict[OEGameCoreDisplayModeNameKey] isEqualToString:displayMode])
            optionDict[OEGameCoreDisplayModeStateKey] = @YES;
        // Reset
        else
            optionDict[OEGameCoreDisplayModeStateKey] = @NO;
    }

    if ([displayMode isEqualToString:@"Auto"])
        console->setFormat(0);
    else if ([displayMode isEqualToString:@"NTSC"])
        console->setFormat(1);
    else if ([displayMode isEqualToString:@"PAL"])
        console->setFormat(2);
    else if ([displayMode isEqualToString:@"SECAM"])
        console->setFormat(3);
    else if ([displayMode isEqualToString:@"NTSC50"])
        console->setFormat(4);
    else if ([displayMode isEqualToString:@"PAL60"])
        console->setFormat(5);
    else if ([displayMode isEqualToString:@"SECAM60"])
        console->setFormat(6);
}

- (void)loadDisplayModeOptions
{
    // Restore format
    NSString *lastFormat = self.displayModeInfo[@"format"];
    if (lastFormat && ![lastFormat isEqualToString:@"Auto"]) {
        [self changeDisplayWithMode:lastFormat];
    }
}

- (void)setCheat:(NSString *)code setType:(NSString *)type setEnabled:(BOOL)enabled
{
    if (!_cheatList)
        _cheatList = [NSMutableDictionary dictionary];

    code = [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    code = [code stringByReplacingOccurrencesOfString:@" " withString:@""];

    if (enabled)
        _cheatList[code] = @YES;
    else
        [_cheatList removeObjectForKey:code];
}

- (NSArray<OEMemoryRegionDescriptor *> *)readableMemoryRegions
{
    if (!console) return @[];
    uint8_t ram[128];
    for (int i = 0; i < 128; i++)
        ram[i] = console->system().peek((uInt16)(0x80 + i));

    NSData *data = [NSData dataWithBytes:ram length:128];
    OEMemoryRegionDescriptor *descriptor = [OEMemoryRegionDescriptor descriptorWithName:@"RAM"
                                                                              address:0x80
                                                                         addressBytes:1
                                                                                 data:data];
    return @[descriptor];
}

@end
