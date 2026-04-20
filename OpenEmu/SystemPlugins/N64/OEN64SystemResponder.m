/*
 Copyright (c) 2011, OpenEmu Team
 
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

#import "OEN64SystemResponder.h"
#import "OEN64SystemResponderClient.h"
#import <OpenEmuBase/OELibretroCoreTranslator.h>

@implementation OEN64SystemResponder
// OEN64Button enum → RETRO_DEVICE_ID_JOYPAD mapping:
//   0 DPadUp→UP(4), 1 DPadDown→DOWN(5), 2 DPadLeft→LEFT(6), 3 DPadRight→RIGHT(7),
//   4 CUp→X(9),     5 CDown→A(8),       6 CLeft→Y(1),       7 CRight→B(0) [C-pad as face],
//   8 A→A(8),        9 B→B(0),           10 L→L(10),         11 R→R(11),
//   12 Z→L2(12),     13 Start→START(3)
// NOTE: must stay in sync with translator-side tables if any exist.
static const uint8_t kN64LibretroMap[] = { 4, 5, 6, 7, 9, 8, 1, 0, 8, 0, 10, 11, 12, 3 };
@dynamic client;

+ (Protocol *)gameSystemResponderClientProtocol;
{
    return @protocol(OEN64SystemResponderClient);
}

- (void)changeAnalogEmulatorKey:(OESystemKey *)aKey value:(CGFloat)value
{
    NSUInteger k = aKey.key;
    id client = (id)self.client;
    if ([client conformsToProtocol:@protocol(OEBridgeInputTranslation)]) {
        int16_t val = (int16_t)round(value * 32767.0);
        switch (k) {
            case OEN64AnalogUp:    [(id<OEBridgeInputTranslation>)client receiveLibretroAnalogIndex:0 axis:1 value:-val forPort:aKey.player - 1]; break;
            case OEN64AnalogDown:  [(id<OEBridgeInputTranslation>)client receiveLibretroAnalogIndex:0 axis:1 value:val  forPort:aKey.player - 1]; break;
            case OEN64AnalogLeft:  [(id<OEBridgeInputTranslation>)client receiveLibretroAnalogIndex:0 axis:0 value:-val forPort:aKey.player - 1]; break;
            case OEN64AnalogRight: [(id<OEBridgeInputTranslation>)client receiveLibretroAnalogIndex:0 axis:0 value:val  forPort:aKey.player - 1]; break;
        }
        return;
    }
    [client didMoveN64JoystickDirection:(OEN64Button)k withValue:value forPlayer:aKey.player];
}

- (void)pressEmulatorKey:(OESystemKey *)aKey
{
    id client = (id)self.client;
    NSUInteger k = aKey.key;
    if ([client conformsToProtocol:@protocol(OEBridgeInputTranslation)]) {
        uint8_t btn = (k < sizeof(kN64LibretroMap)) ? kN64LibretroMap[k] : 0xFF;
        [(id<OEBridgeInputTranslation>)client receiveLibretroButton:btn forPort:aKey.player - 1 pressed:YES];
        return;
    }
    [client didPushN64Button:(OEN64Button)k forPlayer:aKey.player];
}

- (void)releaseEmulatorKey:(OESystemKey *)aKey
{
    id client = (id)self.client;
    NSUInteger k = aKey.key;
    if ([client conformsToProtocol:@protocol(OEBridgeInputTranslation)]) {
        uint8_t btn = (k < sizeof(kN64LibretroMap)) ? kN64LibretroMap[k] : 0xFF;
        [(id<OEBridgeInputTranslation>)client receiveLibretroButton:btn forPort:aKey.player - 1 pressed:NO];
        return;
    }
    [client didReleaseN64Button:(OEN64Button)k forPlayer:aKey.player];
}

@end
