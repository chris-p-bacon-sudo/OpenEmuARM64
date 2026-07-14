// Copyright (c) 2026, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the OpenEmu Team nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import <XCTest/XCTest.h>
#import <OpenEmuSystem/OpenEmuSystem.h>
#import "../OpenEmuSystem/OEHIDDeviceHandler_Internal.h"

@interface OEDeviceManager (ClassificationTesting)
- (void)OE_addDeviceHandler:(OEDeviceHandler *)handler;
- (BOOL)OE_hasDeviceHandlerForDeviceRef:(nullable IOHIDDeviceRef)deviceRef
                        registryEntryID:(nullable NSNumber *)registryEntryID;
- (nullable NSNumber *)OE_registryEntryIDForDeviceHandler:(OEDeviceHandler *)handler;
@end

@interface OEClassificationTestDeviceManager : OEDeviceManager {
    NSMapTable<OEDeviceHandler *, NSNumber *> *_testRegistryEntryIDs;
}
- (void)setRegistryEntryID:(NSNumber *)registryEntryID forDeviceHandler:(OEDeviceHandler *)handler;
@end

@implementation OEClassificationTestDeviceManager

- (instancetype)init
{
    if((self = [super init]))
        _testRegistryEntryIDs = [NSMapTable strongToStrongObjectsMapTable];

    return self;
}

- (void)OE_setUpCallbacks
{
}

- (void)setRegistryEntryID:(NSNumber *)registryEntryID forDeviceHandler:(OEDeviceHandler *)handler
{
    [_testRegistryEntryIDs setObject:registryEntryID forKey:handler];
}

- (NSNumber *)OE_registryEntryIDForDeviceHandler:(OEDeviceHandler *)handler
{
    return [_testRegistryEntryIDs objectForKey:handler];
}

@end

@interface OEClassificationTestControllerDescription : OEControllerDescription
@end

@implementation OEClassificationTestControllerDescription

- (NSUInteger)numberOfControls
{
    return 1;
}

@end

@interface OEClassificationTestDeviceHandler : OEDeviceHandler
- (instancetype)initWithIdentifier:(NSString *)identifier
                       isKeyboard:(BOOL)isKeyboard
                       isJoystick:(BOOL)isJoystick
                        isGamepad:(BOOL)isGamepad;
@end

@implementation OEClassificationTestDeviceHandler {
    NSString *_testIdentifier;
    BOOL _testIsKeyboard;
    BOOL _testIsJoystick;
    BOOL _testIsGamepad;
    OEControllerDescription *_testControllerDescription;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                       isKeyboard:(BOOL)isKeyboard
                       isJoystick:(BOOL)isJoystick
                        isGamepad:(BOOL)isGamepad
{
    if((self = [super initWithDeviceDescription:nil])) {
        _testIdentifier = [identifier copy];
        _testIsKeyboard = isKeyboard;
        _testIsJoystick = isJoystick;
        _testIsGamepad = isGamepad;
        _testControllerDescription = [[OEClassificationTestControllerDescription alloc] init];
    }

    return self;
}

- (OEControllerDescription *)controllerDescription
{
    return _testControllerDescription;
}

- (NSString *)uniqueIdentifier
{
    return _testIdentifier;
}

- (BOOL)isKeyboardDevice
{
    return OEHIDDeviceConformanceIsKeyboardOnly(_testIsKeyboard, _testIsJoystick, _testIsGamepad);
}

@end

@interface OEHIDDeviceClassificationTests : XCTestCase
@end

@implementation OEHIDDeviceClassificationTests

- (void)testOnlyPureKeyboardsUseTheKeyboardRole
{
    XCTAssertTrue(OEHIDDeviceConformanceIsKeyboardOnly(YES, NO, NO));
    XCTAssertFalse(OEHIDDeviceConformanceIsKeyboardOnly(YES, YES, NO));
    XCTAssertFalse(OEHIDDeviceConformanceIsKeyboardOnly(YES, NO, YES));
    XCTAssertFalse(OEHIDDeviceConformanceIsKeyboardOnly(NO, NO, NO));
}

- (void)testHybridGamepadRegistersAsControllerWhilePureKeyboardStaysKeyboard
{
    OEClassificationTestDeviceManager *manager = [[OEClassificationTestDeviceManager alloc] init];
    OEClassificationTestDeviceHandler *hybridGamepad = [[OEClassificationTestDeviceHandler alloc] initWithIdentifier:@"hybrid-gamepad"
                                                                                                          isKeyboard:YES
                                                                                                          isJoystick:NO
                                                                                                           isGamepad:YES];
    OEClassificationTestDeviceHandler *pureKeyboard = [[OEClassificationTestDeviceHandler alloc] initWithIdentifier:@"pure-keyboard"
                                                                                                         isKeyboard:YES
                                                                                                         isJoystick:NO
                                                                                                          isGamepad:NO];

    [manager OE_addDeviceHandler:hybridGamepad];
    [manager OE_addDeviceHandler:pureKeyboard];

    XCTAssertTrue([manager.controllerDeviceHandlers containsObject:hybridGamepad]);
    XCTAssertFalse([manager.keyboardDeviceHandlers containsObject:hybridGamepad]);
    XCTAssertTrue([manager.keyboardDeviceHandlers containsObject:pureKeyboard]);
    XCTAssertFalse([manager.controllerDeviceHandlers containsObject:pureKeyboard]);
}

- (void)testRegistryIdentityDetectsDuplicateHIDDeviceWrappers
{
    OEClassificationTestDeviceManager *manager = [[OEClassificationTestDeviceManager alloc] init];
    OEClassificationTestDeviceHandler *registeredHandler = [[OEClassificationTestDeviceHandler alloc] initWithIdentifier:@"registered-gamepad"
                                                                                                               isKeyboard:NO
                                                                                                               isJoystick:NO
                                                                                                                isGamepad:YES];
    NSNumber *registryEntryID = @(0x1000189EC);

    [manager setRegistryEntryID:registryEntryID forDeviceHandler:registeredHandler];
    [manager OE_addDeviceHandler:registeredHandler];

    XCTAssertTrue([manager OE_hasDeviceHandlerForDeviceRef:NULL registryEntryID:registryEntryID]);
    XCTAssertFalse([manager OE_hasDeviceHandlerForDeviceRef:NULL registryEntryID:@(0x1000189ED)]);
    XCTAssertFalse([manager OE_hasDeviceHandlerForDeviceRef:NULL registryEntryID:nil]);
}

@end
