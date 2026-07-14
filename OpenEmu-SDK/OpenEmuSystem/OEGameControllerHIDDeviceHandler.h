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

#import "OEHIDDeviceHandler.h"

@class GCController;
@class GCControllerElement;
@class GCExtendedGamepad;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, OEGameControllerSyntheticCookie) {
    OEGameControllerCookieButtonA                = 0x10001,
    OEGameControllerCookieButtonB                = 0x10002,
    OEGameControllerCookieButtonX                = 0x10003,
    OEGameControllerCookieButtonY                = 0x10004,
    OEGameControllerCookieLeftShoulder           = 0x10005,
    OEGameControllerCookieRightShoulder          = 0x10006,
    OEGameControllerCookieButtonOptions          = 0x10007,
    OEGameControllerCookieButtonMenu             = 0x10008,
    OEGameControllerCookieLeftThumbstickButton   = 0x10009,
    OEGameControllerCookieRightThumbstickButton  = 0x1000A,
    OEGameControllerCookieButtonHome             = 0x1000B,
    OEGameControllerCookieDPad                   = 0x10100,
    OEGameControllerCookieLeftThumbstickX        = 0x10200,
    OEGameControllerCookieLeftThumbstickY        = 0x10201,
    OEGameControllerCookieRightThumbstickX       = 0x10202,
    OEGameControllerCookieRightThumbstickY       = 0x10203,
    OEGameControllerCookieLeftTrigger            = 0x10300,
    OEGameControllerCookieRightTrigger           = 0x10301,
};

@interface OEGameControllerHIDDeviceHandler : OEHIDDeviceHandler

+ (BOOL)OE_matchesVendorID:(NSUInteger)vendorID
                 productID:(NSUInteger)productID
    gameControllerSupported:(BOOL)gameControllerSupported;

+ (NSArray<OEHIDEvent *> *)OE_eventsForExtendedGamepad:(GCExtendedGamepad *)gamepad
                                        changedElement:(GCControllerElement *)element
                                         deviceHandler:(nullable OEDeviceHandler *)deviceHandler;

+ (NSArray<OEHIDEvent *> *)OE_neutralEventsWithDeviceHandler:(nullable OEDeviceHandler *)deviceHandler;

+ (nullable GCController *)OE_controllerForUnambiguousCandidates:(NSArray<GCController *> *)candidates
                                            waitingHandlerCount:(NSUInteger)waitingHandlerCount
                   hasExclusiveGameControllerSupportedHIDDevice:(BOOL)hasExclusiveGameControllerSupportedHIDDevice;

+ (BOOL)OE_shouldDispatchChangedGamepad:(GCExtendedGamepad *)changedGamepad
                         currentGamepad:(nullable GCExtendedGamepad *)currentGamepad
                           disconnected:(BOOL)disconnected
             capturedAttachmentGeneration:(NSUInteger)capturedAttachmentGeneration
              currentAttachmentGeneration:(NSUInteger)currentAttachmentGeneration;

@end

NS_ASSUME_NONNULL_END
