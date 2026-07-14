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

#import "OEGameControllerHIDDeviceHandler.h"

#import "OEControlDescription.h"
#import "OEControllerDescription.h"
#import "OEHIDEvent_Internal.h"
#import "OEDeviceManager_Internal.h"

#import <GameController/GameController.h>

NS_ASSUME_NONNULL_BEGIN

static const NSUInteger OEGameControllerEliteVendorID = 0x045E;
static const NSUInteger OEGameControllerEliteBluetoothProductID = 0x0B05;
static const NSInteger OEGameControllerTriggerMaximum = 0xFFFF;

static NSMapTable<GCController *, OEGameControllerHIDDeviceHandler *> *OEGameControllerClaims(void)
{
    static NSMapTable<GCController *, OEGameControllerHIDDeviceHandler *> *claims = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSPointerFunctionsOptions keyOptions = NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality;
        NSPointerFunctionsOptions valueOptions = NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality;
        claims = [NSMapTable mapTableWithKeyOptions:keyOptions valueOptions:valueOptions];
    });

    return claims;
}

static NSHashTable<OEGameControllerHIDDeviceHandler *> *OEGameControllerHandlers(void)
{
    static NSHashTable<OEGameControllerHIDDeviceHandler *> *handlers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSPointerFunctionsOptions options = NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality;
        handlers = [NSHashTable hashTableWithOptions:options];
    });

    return handlers;
}

static BOOL OEElementBelongsToDirectionPad(GCControllerElement *element, GCControllerDirectionPad *directionPad)
{
    return element == directionPad ||
           element == directionPad.xAxis ||
           element == directionPad.yAxis ||
           element == directionPad.up ||
           element == directionPad.down ||
           element == directionPad.left ||
           element == directionPad.right;
}

static OEHIDEvent *OEGameControllerButtonEvent(OEDeviceHandler * _Nullable deviceHandler,
                                                NSTimeInterval timestamp,
                                                GCControllerButtonInput *button,
                                                NSUInteger buttonNumber,
                                                NSUInteger cookie)
{
    OEHIDEventState state = button.isPressed ? OEHIDEventStateOn : OEHIDEventStateOff;
    return [OEHIDEvent buttonEventWithDeviceHandler:deviceHandler
                                          timestamp:timestamp
                                       buttonNumber:buttonNumber
                                              state:state
                                             cookie:cookie];
}

static OEHIDEvent *OEGameControllerAxisEvent(OEDeviceHandler * _Nullable deviceHandler,
                                              NSTimeInterval timestamp,
                                              GCControllerAxisInput *axisInput,
                                              OEHIDEventAxis axis,
                                              NSUInteger cookie)
{
    return [OEHIDEvent axisEventWithDeviceHandler:deviceHandler
                                         timestamp:timestamp
                                              axis:axis
                                             value:axisInput.value
                                            cookie:cookie];
}

static OEHIDEvent *OEGameControllerTriggerEvent(OEDeviceHandler * _Nullable deviceHandler,
                                                 NSTimeInterval timestamp,
                                                 GCControllerButtonInput *trigger,
                                                 OEHIDEventAxis axis,
                                                 NSUInteger cookie)
{
    NSInteger value = lroundf(trigger.value * OEGameControllerTriggerMaximum);
    return [OEHIDEvent triggerEventWithDeviceHandler:deviceHandler
                                            timestamp:timestamp
                                                 axis:axis
                                                value:value
                                              maximum:OEGameControllerTriggerMaximum
                                               cookie:cookie];
}

static void OEAddSyntheticControl(OEControllerDescription *description, NSString *name, OEHIDEvent *event)
{
    OEControlDescription *control = [description addControlWithIdentifier:nil name:name event:event];
    if(!description.isGeneric)
        [control setUpControlValuesUsingRepresentations:nil];
}

@interface OEGameControllerHIDDeviceHandler ()
- (void)OE_addSyntheticControls;
- (void)OE_attachAvailableGameController;
- (void)OE_scheduleAttachmentEvaluation;
- (void)OE_tryAttachGameController:(GCController *)controller;
- (BOOL)OE_isEligibleGameController:(GCController *)controller;
- (void)OE_detachGameController;
- (void)OE_dispatchNeutralEvents;
- (void)OE_controllerDidConnect:(NSNotification *)notification;
- (void)OE_controllerDidDisconnect:(NSNotification *)notification;
@end

@implementation OEGameControllerHIDDeviceHandler {
    GCController *_gameController;
    GCExtendedGamepad *_extendedGamepad;
    GCExtendedGamepadValueChangedHandler _gamepadValueChangedHandler;
    BOOL _disconnected;
    NSUInteger _attachmentEvaluationGeneration;
    NSUInteger _attachmentGeneration;
}

+ (BOOL)OE_matchesVendorID:(NSUInteger)vendorID
                 productID:(NSUInteger)productID
    gameControllerSupported:(BOOL)gameControllerSupported
{
    return gameControllerSupported &&
           vendorID == OEGameControllerEliteVendorID &&
           productID == OEGameControllerEliteBluetoothProductID;
}

+ (nullable GCController *)OE_controllerForUnambiguousCandidates:(NSArray<GCController *> *)candidates
                                            waitingHandlerCount:(NSUInteger)waitingHandlerCount
                   hasExclusiveGameControllerSupportedHIDDevice:(BOOL)hasExclusiveGameControllerSupportedHIDDevice
{
    if(candidates.count != 1 ||
       waitingHandlerCount != 1 ||
       !hasExclusiveGameControllerSupportedHIDDevice)
        return nil;

    return candidates.firstObject;
}

+ (BOOL)OE_shouldDispatchChangedGamepad:(GCExtendedGamepad *)changedGamepad
                         currentGamepad:(nullable GCExtendedGamepad *)currentGamepad
                           disconnected:(BOOL)disconnected
             capturedAttachmentGeneration:(NSUInteger)capturedAttachmentGeneration
              currentAttachmentGeneration:(NSUInteger)currentAttachmentGeneration
{
    return !disconnected &&
           changedGamepad == currentGamepad &&
           capturedAttachmentGeneration == currentAttachmentGeneration;
}

+ (BOOL)canHandleDevice:(IOHIDDeviceRef)device
{
    if(device == NULL)
        return NO;

    NSUInteger vendorID = [(__bridge NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDVendorIDKey)) unsignedIntegerValue];
    NSUInteger productID = [(__bridge NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductIDKey)) unsignedIntegerValue];

    if(![self OE_matchesVendorID:vendorID productID:productID gameControllerSupported:YES])
        return NO;

    if(@available(macOS 11.0, *))
        return [GCController supportsHIDDevice:device];

    return NO;
}

+ (NSArray<OEHIDEvent *> *)OE_eventsForExtendedGamepad:(GCExtendedGamepad *)gamepad
                                        changedElement:(GCControllerElement *)element
                                         deviceHandler:(nullable OEDeviceHandler *)deviceHandler
{
    NSMutableArray<OEHIDEvent *> *events = [NSMutableArray arrayWithCapacity:2];
    NSTimeInterval timestamp = NSProcessInfo.processInfo.systemUptime;

    if(element == gamepad.buttonA)
        [events addObject:OEGameControllerButtonEvent(deviceHandler, timestamp, gamepad.buttonA, 1, OEGameControllerCookieButtonA)];
    else if(element == gamepad.buttonB)
        [events addObject:OEGameControllerButtonEvent(deviceHandler, timestamp, gamepad.buttonB, 2, OEGameControllerCookieButtonB)];
    else if(element == gamepad.buttonX)
        [events addObject:OEGameControllerButtonEvent(deviceHandler, timestamp, gamepad.buttonX, 3, OEGameControllerCookieButtonX)];
    else if(element == gamepad.buttonY)
        [events addObject:OEGameControllerButtonEvent(deviceHandler, timestamp, gamepad.buttonY, 4, OEGameControllerCookieButtonY)];
    else if(element == gamepad.leftShoulder)
        [events addObject:OEGameControllerButtonEvent(deviceHandler, timestamp, gamepad.leftShoulder, 5, OEGameControllerCookieLeftShoulder)];
    else if(element == gamepad.rightShoulder)
        [events addObject:OEGameControllerButtonEvent(deviceHandler, timestamp, gamepad.rightShoulder, 6, OEGameControllerCookieRightShoulder)];
    else if(element == gamepad.leftTrigger)
        [events addObject:OEGameControllerTriggerEvent(deviceHandler, timestamp, gamepad.leftTrigger, OEHIDEventAxisBrake, OEGameControllerCookieLeftTrigger)];
    else if(element == gamepad.rightTrigger)
        [events addObject:OEGameControllerTriggerEvent(deviceHandler, timestamp, gamepad.rightTrigger, OEHIDEventAxisAccelerator, OEGameControllerCookieRightTrigger)];

    if(events.count != 0)
        return events;

    if(@available(macOS 10.15, *)) {
        if(element == gamepad.buttonOptions)
            [events addObject:OEGameControllerButtonEvent(deviceHandler, timestamp, gamepad.buttonOptions, 7, OEGameControllerCookieButtonOptions)];
        else if(element == gamepad.buttonMenu)
            [events addObject:OEGameControllerButtonEvent(deviceHandler, timestamp, gamepad.buttonMenu, 8, OEGameControllerCookieButtonMenu)];
    }

    if(events.count != 0)
        return events;

    if(element == gamepad.leftThumbstickButton)
        [events addObject:OEGameControllerButtonEvent(deviceHandler, timestamp, gamepad.leftThumbstickButton, 9, OEGameControllerCookieLeftThumbstickButton)];
    else if(element == gamepad.rightThumbstickButton)
        [events addObject:OEGameControllerButtonEvent(deviceHandler, timestamp, gamepad.rightThumbstickButton, 10, OEGameControllerCookieRightThumbstickButton)];

    if(events.count != 0)
        return events;

    if(@available(macOS 11.0, *)) {
        if(element == gamepad.buttonHome)
            [events addObject:OEGameControllerButtonEvent(deviceHandler, timestamp, gamepad.buttonHome, 11, OEGameControllerCookieButtonHome)];
    }

    if(events.count != 0)
        return events;

    if(OEElementBelongsToDirectionPad(element, gamepad.dpad)) {
        OEHIDEventHatDirection direction = OEHIDEventHatDirectionNull;
        if(gamepad.dpad.up.isPressed)
            direction |= OEHIDEventHatDirectionNorth;
        if(gamepad.dpad.right.isPressed)
            direction |= OEHIDEventHatDirectionEast;
        if(gamepad.dpad.down.isPressed)
            direction |= OEHIDEventHatDirectionSouth;
        if(gamepad.dpad.left.isPressed)
            direction |= OEHIDEventHatDirectionWest;

        [events addObject:[OEHIDEvent hatSwitchEventWithDeviceHandler:deviceHandler
                                                            timestamp:timestamp
                                                                 type:OEHIDEventHatSwitchType8Ways
                                                            direction:direction
                                                               cookie:OEGameControllerCookieDPad]];
        return events;
    }

    GCControllerDirectionPad *leftThumbstick = gamepad.leftThumbstick;
    if(element == leftThumbstick || element == leftThumbstick.xAxis || element == leftThumbstick.left || element == leftThumbstick.right)
        [events addObject:OEGameControllerAxisEvent(deviceHandler, timestamp, leftThumbstick.xAxis, OEHIDEventAxisX, OEGameControllerCookieLeftThumbstickX)];
    if(element == leftThumbstick || element == leftThumbstick.yAxis || element == leftThumbstick.up || element == leftThumbstick.down)
        [events addObject:OEGameControllerAxisEvent(deviceHandler, timestamp, leftThumbstick.yAxis, OEHIDEventAxisY, OEGameControllerCookieLeftThumbstickY)];

    if(events.count != 0)
        return events;

    GCControllerDirectionPad *rightThumbstick = gamepad.rightThumbstick;
    if(element == rightThumbstick || element == rightThumbstick.xAxis || element == rightThumbstick.left || element == rightThumbstick.right)
        [events addObject:OEGameControllerAxisEvent(deviceHandler, timestamp, rightThumbstick.xAxis, OEHIDEventAxisRx, OEGameControllerCookieRightThumbstickX)];
    if(element == rightThumbstick || element == rightThumbstick.yAxis || element == rightThumbstick.up || element == rightThumbstick.down)
        [events addObject:OEGameControllerAxisEvent(deviceHandler, timestamp, rightThumbstick.yAxis, OEHIDEventAxisRy, OEGameControllerCookieRightThumbstickY)];

    return events;
}

+ (NSArray<OEHIDEvent *> *)OE_neutralEventsWithDeviceHandler:(nullable OEDeviceHandler *)deviceHandler
{
    NSTimeInterval timestamp = NSProcessInfo.processInfo.systemUptime;
    NSArray<NSNumber *> *buttonCookies = @[
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
    ];
    NSMutableArray<OEHIDEvent *> *events = [NSMutableArray arrayWithCapacity:18];
    [buttonCookies enumerateObjectsUsingBlock:^(NSNumber *cookie, NSUInteger index, BOOL *stop) {
        [events addObject:[OEHIDEvent buttonEventWithDeviceHandler:deviceHandler
                                                        timestamp:timestamp
                                                     buttonNumber:index + 1
                                                            state:OEHIDEventStateOff
                                                           cookie:cookie.unsignedIntegerValue]];
    }];
    [events addObject:[OEHIDEvent hatSwitchEventWithDeviceHandler:deviceHandler timestamp:timestamp type:OEHIDEventHatSwitchType8Ways direction:OEHIDEventHatDirectionNull cookie:OEGameControllerCookieDPad]];
    [events addObject:[OEHIDEvent axisEventWithDeviceHandler:deviceHandler timestamp:timestamp axis:OEHIDEventAxisX value:0.0 cookie:OEGameControllerCookieLeftThumbstickX]];
    [events addObject:[OEHIDEvent axisEventWithDeviceHandler:deviceHandler timestamp:timestamp axis:OEHIDEventAxisY value:0.0 cookie:OEGameControllerCookieLeftThumbstickY]];
    [events addObject:[OEHIDEvent axisEventWithDeviceHandler:deviceHandler timestamp:timestamp axis:OEHIDEventAxisRx value:0.0 cookie:OEGameControllerCookieRightThumbstickX]];
    [events addObject:[OEHIDEvent axisEventWithDeviceHandler:deviceHandler timestamp:timestamp axis:OEHIDEventAxisRy value:0.0 cookie:OEGameControllerCookieRightThumbstickY]];
    [events addObject:[OEHIDEvent triggerEventWithDeviceHandler:deviceHandler timestamp:timestamp axis:OEHIDEventAxisBrake value:0 maximum:OEGameControllerTriggerMaximum cookie:OEGameControllerCookieLeftTrigger]];
    [events addObject:[OEHIDEvent triggerEventWithDeviceHandler:deviceHandler timestamp:timestamp axis:OEHIDEventAxisAccelerator value:0 maximum:OEGameControllerTriggerMaximum cookie:OEGameControllerCookieRightTrigger]];
    return events;
}

- (instancetype)initWithIOHIDDevice:(IOHIDDeviceRef)device deviceDescription:(nullable OEDeviceDescription *)deviceDescription
{
    if((self = [super initWithIOHIDDevice:device deviceDescription:deviceDescription])) {
        [OEGameControllerHandlers() addObject:self];
        [self OE_addSyntheticControls];

        if(@available(macOS 11.3, *))
            GCController.shouldMonitorBackgroundEvents = YES;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(OE_controllerDidConnect:)
                                                     name:GCControllerDidConnectNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(OE_controllerDidDisconnect:)
                                                     name:GCControllerDidDisconnectNotification
                                                   object:nil];

        [self OE_scheduleAttachmentEvaluation];
    }

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)disconnect
{
    _disconnected = YES;
    [OEGameControllerHandlers() removeObject:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self OE_dispatchNeutralEvents];
    [self OE_detachGameController];

    NSArray<OEGameControllerHIDDeviceHandler *> *remainingHandlers = OEGameControllerHandlers().allObjects;
    dispatch_async(dispatch_get_main_queue(), ^{
        for(OEGameControllerHIDDeviceHandler *handler in remainingHandlers)
            [handler OE_scheduleAttachmentEvaluation];
    });
    [super disconnect];
}

- (void)dispatchEventWithHIDValue:(IOHIDValueRef)value
{
}

- (void)OE_addSyntheticControls
{
    OEControllerDescription *description = self.controllerDescription;
    if(description == nil)
        return;

    NSTimeInterval timestamp = 0;
    OEAddSyntheticControl(description, @"A", [OEHIDEvent buttonEventWithDeviceHandler:self timestamp:timestamp buttonNumber:1 state:OEHIDEventStateOn cookie:OEGameControllerCookieButtonA]);
    OEAddSyntheticControl(description, @"B", [OEHIDEvent buttonEventWithDeviceHandler:self timestamp:timestamp buttonNumber:2 state:OEHIDEventStateOn cookie:OEGameControllerCookieButtonB]);
    OEAddSyntheticControl(description, @"X", [OEHIDEvent buttonEventWithDeviceHandler:self timestamp:timestamp buttonNumber:3 state:OEHIDEventStateOn cookie:OEGameControllerCookieButtonX]);
    OEAddSyntheticControl(description, @"Y", [OEHIDEvent buttonEventWithDeviceHandler:self timestamp:timestamp buttonNumber:4 state:OEHIDEventStateOn cookie:OEGameControllerCookieButtonY]);
    OEAddSyntheticControl(description, @"Left Shoulder", [OEHIDEvent buttonEventWithDeviceHandler:self timestamp:timestamp buttonNumber:5 state:OEHIDEventStateOn cookie:OEGameControllerCookieLeftShoulder]);
    OEAddSyntheticControl(description, @"Right Shoulder", [OEHIDEvent buttonEventWithDeviceHandler:self timestamp:timestamp buttonNumber:6 state:OEHIDEventStateOn cookie:OEGameControllerCookieRightShoulder]);
    OEAddSyntheticControl(description, @"View", [OEHIDEvent buttonEventWithDeviceHandler:self timestamp:timestamp buttonNumber:7 state:OEHIDEventStateOn cookie:OEGameControllerCookieButtonOptions]);
    OEAddSyntheticControl(description, @"Menu", [OEHIDEvent buttonEventWithDeviceHandler:self timestamp:timestamp buttonNumber:8 state:OEHIDEventStateOn cookie:OEGameControllerCookieButtonMenu]);
    OEAddSyntheticControl(description, @"Left Stick Click", [OEHIDEvent buttonEventWithDeviceHandler:self timestamp:timestamp buttonNumber:9 state:OEHIDEventStateOn cookie:OEGameControllerCookieLeftThumbstickButton]);
    OEAddSyntheticControl(description, @"Right Stick Click", [OEHIDEvent buttonEventWithDeviceHandler:self timestamp:timestamp buttonNumber:10 state:OEHIDEventStateOn cookie:OEGameControllerCookieRightThumbstickButton]);
    OEAddSyntheticControl(description, @"Home", [OEHIDEvent buttonEventWithDeviceHandler:self timestamp:timestamp buttonNumber:11 state:OEHIDEventStateOn cookie:OEGameControllerCookieButtonHome]);
    OEAddSyntheticControl(description, @"D-Pad", [OEHIDEvent hatSwitchEventWithDeviceHandler:self timestamp:timestamp type:OEHIDEventHatSwitchType8Ways direction:OEHIDEventHatDirectionNull cookie:OEGameControllerCookieDPad]);
    OEAddSyntheticControl(description, @"Left Stick X", [OEHIDEvent axisEventWithDeviceHandler:self timestamp:timestamp axis:OEHIDEventAxisX value:0.0 cookie:OEGameControllerCookieLeftThumbstickX]);
    OEAddSyntheticControl(description, @"Left Stick Y", [OEHIDEvent axisEventWithDeviceHandler:self timestamp:timestamp axis:OEHIDEventAxisY value:0.0 cookie:OEGameControllerCookieLeftThumbstickY]);
    OEAddSyntheticControl(description, @"Right Stick X", [OEHIDEvent axisEventWithDeviceHandler:self timestamp:timestamp axis:OEHIDEventAxisRx value:0.0 cookie:OEGameControllerCookieRightThumbstickX]);
    OEAddSyntheticControl(description, @"Right Stick Y", [OEHIDEvent axisEventWithDeviceHandler:self timestamp:timestamp axis:OEHIDEventAxisRy value:0.0 cookie:OEGameControllerCookieRightThumbstickY]);
    OEAddSyntheticControl(description, @"Left Trigger", [OEHIDEvent triggerEventWithDeviceHandler:self timestamp:timestamp axis:OEHIDEventAxisBrake value:0 maximum:OEGameControllerTriggerMaximum cookie:OEGameControllerCookieLeftTrigger]);
    OEAddSyntheticControl(description, @"Right Trigger", [OEHIDEvent triggerEventWithDeviceHandler:self timestamp:timestamp axis:OEHIDEventAxisAccelerator value:0 maximum:OEGameControllerTriggerMaximum cookie:OEGameControllerCookieRightTrigger]);
}

- (void)OE_scheduleAttachmentEvaluation
{
    if(_disconnected || _gameController != nil)
        return;

    if(!NSThread.isMainThread) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf OE_scheduleAttachmentEvaluation];
        });
        return;
    }

    NSUInteger generation = ++_attachmentEvaluationGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        OEGameControllerHIDDeviceHandler *strongSelf = weakSelf;
        if(strongSelf != nil && generation == strongSelf->_attachmentEvaluationGeneration)
            [strongSelf OE_attachAvailableGameController];
    });
}

- (void)OE_attachAvailableGameController
{
    if(_disconnected || _gameController != nil)
        return;

    if(!NSThread.isMainThread) {
        [self OE_scheduleAttachmentEvaluation];
        return;
    }

    NSUInteger waitingHandlerCount = 0;
    for(OEGameControllerHIDDeviceHandler *handler in OEGameControllerHandlers()) {
        if(!handler->_disconnected && handler->_gameController == nil)
            waitingHandlerCount++;
    }

    BOOL hasExclusiveGameControllerSupportedHIDDevice =
        [[OEDeviceManager sharedDeviceManager] OE_hasSingleGameControllerSupportedHIDDeviceMatchingDevice:self.device];

    NSMutableArray<GCController *> *candidates = [NSMutableArray array];
    for(GCController *controller in GCController.controllers) {
        if([self OE_isEligibleGameController:controller])
            [candidates addObject:controller];
    }

    GCController *controller = [OEGameControllerHIDDeviceHandler OE_controllerForUnambiguousCandidates:candidates
                                                                                   waitingHandlerCount:waitingHandlerCount
                                                          hasExclusiveGameControllerSupportedHIDDevice:hasExclusiveGameControllerSupportedHIDDevice];
    if(controller != nil)
        [self OE_tryAttachGameController:controller];
}

- (BOOL)OE_isEligibleGameController:(GCController *)controller
{
    GCExtendedGamepad *gamepad = controller.extendedGamepad;
    if(gamepad == nil)
        return NO;

    if(@available(macOS 11.0, *)) {
        if(controller.isSnapshot)
            return NO;
        if(![gamepad isKindOfClass:GCXboxGamepad.class])
            return NO;

    } else {
        return NO;
    }

    OEGameControllerHIDDeviceHandler *owner = [OEGameControllerClaims() objectForKey:controller];
    return owner == nil || owner == self;
}

- (void)OE_tryAttachGameController:(GCController *)controller
{
    if(_disconnected || _gameController != nil || !NSThread.isMainThread)
        return;

    if(![self OE_isEligibleGameController:controller])
        return;

    GCExtendedGamepad *gamepad = controller.extendedGamepad;

    [OEGameControllerClaims() setObject:self forKey:controller];
    _gameController = controller;
    _extendedGamepad = gamepad;
    controller.handlerQueue = dispatch_get_main_queue();
    NSUInteger attachmentGeneration = ++_attachmentGeneration;

    __weak typeof(self) weakSelf = self;
    _gamepadValueChangedHandler = ^(GCExtendedGamepad *changedGamepad, GCControllerElement *changedElement) {
        OEGameControllerHIDDeviceHandler *strongSelf = weakSelf;
        if(strongSelf == nil ||
           ![OEGameControllerHIDDeviceHandler OE_shouldDispatchChangedGamepad:changedGamepad
                                                                currentGamepad:strongSelf->_extendedGamepad
                                                                  disconnected:strongSelf->_disconnected
                                                    capturedAttachmentGeneration:attachmentGeneration
                                                     currentAttachmentGeneration:strongSelf->_attachmentGeneration])
            return;

        NSArray<OEHIDEvent *> *events = [OEGameControllerHIDDeviceHandler OE_eventsForExtendedGamepad:changedGamepad
                                                                                         changedElement:changedElement
                                                                                          deviceHandler:strongSelf];
        for(OEHIDEvent *event in events)
            [strongSelf dispatchEvent:event];
    };
    _extendedGamepad.valueChangedHandler = _gamepadValueChangedHandler;
}

- (void)OE_dispatchNeutralEvents
{
    if(_gameController == nil)
        return;

    for(OEHIDEvent *event in [OEGameControllerHIDDeviceHandler OE_neutralEventsWithDeviceHandler:self])
        [self dispatchEvent:event];
}

- (void)OE_detachGameController
{
    if(_gameController == nil)
        return;

    ++_attachmentGeneration;

    if(_extendedGamepad.valueChangedHandler == _gamepadValueChangedHandler)
        _extendedGamepad.valueChangedHandler = nil;

    if([OEGameControllerClaims() objectForKey:_gameController] == self)
        [OEGameControllerClaims() removeObjectForKey:_gameController];

    _gamepadValueChangedHandler = nil;
    _extendedGamepad = nil;
    _gameController = nil;
}

- (void)OE_controllerDidConnect:(NSNotification *)notification
{
    [self OE_scheduleAttachmentEvaluation];
}

- (void)OE_controllerDidDisconnect:(NSNotification *)notification
{
    GCController *controller = notification.object;
    if(!NSThread.isMainThread) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf OE_controllerDidDisconnect:notification];
        });
        return;
    }

    if(controller == _gameController) {
        [self OE_dispatchNeutralEvents];
        [self OE_detachGameController];
    }

    [self OE_scheduleAttachmentEvaluation];
}

@end

NS_ASSUME_NONNULL_END
