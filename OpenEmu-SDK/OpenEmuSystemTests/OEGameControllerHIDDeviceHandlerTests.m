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
#import <GameController/GameController.h>
#import <objc/runtime.h>
#import <OpenEmuSystem/OpenEmuSystem.h>
#import "../OpenEmuSystem/OEGameControllerHIDDeviceHandler.h"
#import "../OpenEmuSystem/OEHIDEvent_Internal.h"

@interface OEGameControllerHIDDeviceHandlerTests : XCTestCase
@end

@implementation OEGameControllerHIDDeviceHandlerTests

- (OEHIDEvent *)eventWithCookie:(NSUInteger)cookie inEvents:(NSArray<OEHIDEvent *> *)events
{
    for(OEHIDEvent *event in events) {
        if(event.cookie == cookie)
            return event;
    }

    return nil;
}

- (NSArray<OEHIDEvent *> *)eventsForGamepad:(GCExtendedGamepad *)gamepad changedElement:(GCControllerElement *)element
{
    return [OEGameControllerHIDDeviceHandler OE_eventsForExtendedGamepad:gamepad
                                                          changedElement:element
                                                           deviceHandler:nil];
}

- (void)testOnlyTheAppleSupportedBluetoothEliteDescriptorUsesTheBridge
{
    XCTAssertTrue([OEGameControllerHIDDeviceHandler OE_matchesVendorID:0x045E
                                                               productID:0x0B05
                                                  gameControllerSupported:YES]);
    XCTAssertFalse([OEGameControllerHIDDeviceHandler OE_matchesVendorID:0x045E
                                                                productID:0x0B05
                                                   gameControllerSupported:NO]);
    XCTAssertFalse([OEGameControllerHIDDeviceHandler OE_matchesVendorID:0x045E
                                                                productID:0x0B00
                                                   gameControllerSupported:YES]);
    XCTAssertFalse([OEGameControllerHIDDeviceHandler OE_matchesVendorID:0x045E
                                                                productID:0x0B06
                                                   gameControllerSupported:YES]);
    XCTAssertFalse([OEGameControllerHIDDeviceHandler OE_matchesVendorID:0x054C
                                                                productID:0x0CE6
                                                   gameControllerSupported:YES]);
}

- (void)testSyntheticControlCookiesAreStableUniqueAndNonzero
{
    NSArray<NSNumber *> *cookies = @[
        @(OEGameControllerCookieButtonA),
        @(OEGameControllerCookieButtonB),
        @(OEGameControllerCookieButtonX),
        @(OEGameControllerCookieButtonY),
        @(OEGameControllerCookieLeftShoulder),
        @(OEGameControllerCookieRightShoulder),
        @(OEGameControllerCookieButtonOptions),
        @(OEGameControllerCookieButtonMenu),
        @(OEGameControllerCookieLeftThumbstickButton),
        @(OEGameControllerCookieRightThumbstickButton),
        @(OEGameControllerCookieButtonHome),
        @(OEGameControllerCookieDPad),
        @(OEGameControllerCookieLeftThumbstickX),
        @(OEGameControllerCookieLeftThumbstickY),
        @(OEGameControllerCookieRightThumbstickX),
        @(OEGameControllerCookieRightThumbstickY),
        @(OEGameControllerCookieLeftTrigger),
        @(OEGameControllerCookieRightTrigger),
    ];

    XCTAssertFalse([cookies containsObject:@0]);
    XCTAssertEqual([NSSet setWithArray:cookies].count, cookies.count);
}

- (void)testFaceAndShoulderButtonsConvertToStableButtonEvents
{
    GCExtendedGamepad *gamepad = [GCController controllerWithExtendedGamepad].extendedGamepad;
    NSArray<GCControllerButtonInput *> *buttons = @[
        gamepad.buttonA,
        gamepad.buttonB,
        gamepad.buttonX,
        gamepad.buttonY,
        gamepad.leftShoulder,
        gamepad.rightShoulder,
    ];
    NSArray<NSNumber *> *cookies = @[
        @(OEGameControllerCookieButtonA),
        @(OEGameControllerCookieButtonB),
        @(OEGameControllerCookieButtonX),
        @(OEGameControllerCookieButtonY),
        @(OEGameControllerCookieLeftShoulder),
        @(OEGameControllerCookieRightShoulder),
    ];

    [buttons enumerateObjectsUsingBlock:^(GCControllerButtonInput *button, NSUInteger index, BOOL *stop) {
        [button setValue:1.0];
        OEHIDEvent *pressed = [self eventWithCookie:cookies[index].unsignedIntegerValue
                                          inEvents:[self eventsForGamepad:gamepad changedElement:button]];
        XCTAssertEqual(pressed.type, OEHIDEventTypeButton);
        XCTAssertEqual(pressed.state, OEHIDEventStateOn);

        [button setValue:0.0];
        OEHIDEvent *released = [self eventWithCookie:cookies[index].unsignedIntegerValue
                                           inEvents:[self eventsForGamepad:gamepad changedElement:button]];
        XCTAssertEqual(released.state, OEHIDEventStateOff);
    }];
}

- (void)testDPadConvertsCardinalDiagonalAndNeutralDirections
{
    GCExtendedGamepad *gamepad = [GCController controllerWithExtendedGamepad].extendedGamepad;

    [gamepad.dpad setValueForXAxis:0.0 yAxis:1.0];
    OEHIDEvent *north = [self eventWithCookie:OEGameControllerCookieDPad
                                    inEvents:[self eventsForGamepad:gamepad changedElement:gamepad.dpad]];
    XCTAssertEqual(north.hatDirection, OEHIDEventHatDirectionNorth);

    [gamepad.dpad setValueForXAxis:1.0 yAxis:1.0];
    OEHIDEvent *northEast = [self eventWithCookie:OEGameControllerCookieDPad
                                        inEvents:[self eventsForGamepad:gamepad changedElement:gamepad.dpad.right]];
    XCTAssertEqual(northEast.hatDirection, OEHIDEventHatDirectionNorth | OEHIDEventHatDirectionEast);

    [gamepad.dpad setValueForXAxis:0.0 yAxis:0.0];
    OEHIDEvent *neutral = [self eventWithCookie:OEGameControllerCookieDPad
                                      inEvents:[self eventsForGamepad:gamepad changedElement:gamepad.dpad.xAxis]];
    XCTAssertEqual(neutral.hatDirection, OEHIDEventHatDirectionNull);
}

- (void)testThumbsticksConvertNormalizedAxes
{
    GCExtendedGamepad *gamepad = [GCController controllerWithExtendedGamepad].extendedGamepad;
    [gamepad.leftThumbstick setValueForXAxis:-0.75 yAxis:0.5];
    [gamepad.rightThumbstick setValueForXAxis:0.25 yAxis:-1.0];

    NSArray<OEHIDEvent *> *leftEvents = [self eventsForGamepad:gamepad changedElement:gamepad.leftThumbstick];
    XCTAssertEqualWithAccuracy([self eventWithCookie:OEGameControllerCookieLeftThumbstickX inEvents:leftEvents].value, -0.75, 0.001);
    XCTAssertEqualWithAccuracy([self eventWithCookie:OEGameControllerCookieLeftThumbstickY inEvents:leftEvents].value, 0.5, 0.001);

    NSArray<OEHIDEvent *> *rightEvents = [self eventsForGamepad:gamepad changedElement:gamepad.rightThumbstick.yAxis];
    XCTAssertNil([self eventWithCookie:OEGameControllerCookieRightThumbstickX inEvents:rightEvents]);
    XCTAssertEqualWithAccuracy([self eventWithCookie:OEGameControllerCookieRightThumbstickY inEvents:rightEvents].value, -1.0, 0.001);
}

- (void)testTriggersUsePositiveNormalizedTriggerEvents
{
    GCExtendedGamepad *gamepad = [GCController controllerWithExtendedGamepad].extendedGamepad;
    [gamepad.leftTrigger setValue:0.75];
    [gamepad.rightTrigger setValue:0.25];

    OEHIDEvent *left = [self eventWithCookie:OEGameControllerCookieLeftTrigger
                                   inEvents:[self eventsForGamepad:gamepad changedElement:gamepad.leftTrigger]];
    OEHIDEvent *right = [self eventWithCookie:OEGameControllerCookieRightTrigger
                                    inEvents:[self eventsForGamepad:gamepad changedElement:gamepad.rightTrigger]];

    XCTAssertEqual(left.type, OEHIDEventTypeTrigger);
    XCTAssertEqual(left.direction, OEHIDEventAxisDirectionPositive);
    XCTAssertEqualWithAccuracy(left.value, 0.75, 0.001);
    XCTAssertEqualWithAccuracy(right.value, 0.25, 0.001);
}

- (void)testMenuOptionsHomeAndStickClicksConvertToButtons
{
    GCExtendedGamepad *gamepad = [GCController controllerWithExtendedGamepad].extendedGamepad;
    NSArray<GCControllerButtonInput *> *buttons = @[
        gamepad.buttonOptions,
        gamepad.buttonMenu,
        gamepad.leftThumbstickButton,
        gamepad.rightThumbstickButton,
        gamepad.buttonHome,
    ];
    NSArray<NSNumber *> *cookies = @[
        @(OEGameControllerCookieButtonOptions),
        @(OEGameControllerCookieButtonMenu),
        @(OEGameControllerCookieLeftThumbstickButton),
        @(OEGameControllerCookieRightThumbstickButton),
        @(OEGameControllerCookieButtonHome),
    ];

    [buttons enumerateObjectsUsingBlock:^(GCControllerButtonInput *button, NSUInteger index, BOOL *stop) {
        XCTAssertNotNil(button);
        [button setValue:1.0];
        OEHIDEvent *event = [self eventWithCookie:cookies[index].unsignedIntegerValue
                                        inEvents:[self eventsForGamepad:gamepad changedElement:button]];
        XCTAssertEqual(event.type, OEHIDEventTypeButton);
        XCTAssertEqual(event.state, OEHIDEventStateOn);
    }];
}

- (void)testUnrelatedElementProducesNoSyntheticEvents
{
    GCExtendedGamepad *first = [GCController controllerWithExtendedGamepad].extendedGamepad;
    GCExtendedGamepad *second = [GCController controllerWithExtendedGamepad].extendedGamepad;

    XCTAssertEqual([self eventsForGamepad:first changedElement:second.buttonA].count, 0);
}

- (void)testSubclassOverridesRawHIDDispatchToPreventDuplicateEvents
{
    Method baseMethod = class_getInstanceMethod(OEHIDDeviceHandler.class, @selector(dispatchEventWithHIDValue:));
    Method bridgeMethod = class_getInstanceMethod(OEGameControllerHIDDeviceHandler.class, @selector(dispatchEventWithHIDValue:));

    XCTAssertNotEqual(method_getImplementation(baseMethod), method_getImplementation(bridgeMethod));
}

- (void)testControllerClaimRejectsAmbiguityAndAcceptsAfterResolution
{
    GCController *first = [GCController controllerWithExtendedGamepad];
    GCController *second = [GCController controllerWithExtendedGamepad];
    NSArray<GCController *> *ambiguousCandidates = @[first, second];
    NSArray<GCController *> *resolvedCandidates = @[first];

    XCTAssertNil([OEGameControllerHIDDeviceHandler OE_controllerForUnambiguousCandidates:ambiguousCandidates
                                                                     waitingHandlerCount:1
                                  hasExclusiveGameControllerSupportedHIDDevice:YES]);
    XCTAssertNil([OEGameControllerHIDDeviceHandler OE_controllerForUnambiguousCandidates:resolvedCandidates
                                                                     waitingHandlerCount:2
                                  hasExclusiveGameControllerSupportedHIDDevice:YES]);
    XCTAssertNil([OEGameControllerHIDDeviceHandler OE_controllerForUnambiguousCandidates:resolvedCandidates
                                                                     waitingHandlerCount:1
                                  hasExclusiveGameControllerSupportedHIDDevice:NO]);
    XCTAssertNil([OEGameControllerHIDDeviceHandler OE_controllerForUnambiguousCandidates:@[]
                                                                     waitingHandlerCount:1
                                  hasExclusiveGameControllerSupportedHIDDevice:YES]);
    XCTAssertEqual([OEGameControllerHIDDeviceHandler OE_controllerForUnambiguousCandidates:resolvedCandidates
                                                                      waitingHandlerCount:1
                                   hasExclusiveGameControllerSupportedHIDDevice:YES],
                   first);
}

- (void)testDisconnectNeutralEventsReleaseEverySyntheticControl
{
    NSArray<OEHIDEvent *> *events = [OEGameControllerHIDDeviceHandler OE_neutralEventsWithDeviceHandler:nil];
    NSMutableSet<NSNumber *> *cookies = [NSMutableSet set];

    XCTAssertEqual(events.count, 18);
    for(OEHIDEvent *event in events) {
        [cookies addObject:@(event.cookie)];
        if(event.type == OEHIDEventTypeButton)
            XCTAssertEqual(event.state, OEHIDEventStateOff);
        else if(event.type == OEHIDEventTypeHatSwitch)
            XCTAssertEqual(event.hatDirection, OEHIDEventHatDirectionNull);
        else
            XCTAssertEqualWithAccuracy(event.value, 0.0, 0.001);
    }
    XCTAssertEqual(cookies.count, events.count);
}

- (void)testStaleQueuedCallbacksAreRejectedAfterDetach
{
    GCExtendedGamepad *first = [GCController controllerWithExtendedGamepad].extendedGamepad;
    GCExtendedGamepad *second = [GCController controllerWithExtendedGamepad].extendedGamepad;

    XCTAssertTrue([OEGameControllerHIDDeviceHandler OE_shouldDispatchChangedGamepad:first
                                                                      currentGamepad:first
                                                                        disconnected:NO
                                                  capturedAttachmentGeneration:4
                                                   currentAttachmentGeneration:4]);
    XCTAssertFalse([OEGameControllerHIDDeviceHandler OE_shouldDispatchChangedGamepad:first
                                                                       currentGamepad:first
                                                                         disconnected:YES
                                                   capturedAttachmentGeneration:4
                                                    currentAttachmentGeneration:4]);
    XCTAssertFalse([OEGameControllerHIDDeviceHandler OE_shouldDispatchChangedGamepad:first
                                                                       currentGamepad:second
                                                                         disconnected:NO
                                                   capturedAttachmentGeneration:4
                                                    currentAttachmentGeneration:4]);
    XCTAssertFalse([OEGameControllerHIDDeviceHandler OE_shouldDispatchChangedGamepad:first
                                                                       currentGamepad:first
                                                                         disconnected:NO
                                                   capturedAttachmentGeneration:4
                                                    currentAttachmentGeneration:5]);
}

@end
