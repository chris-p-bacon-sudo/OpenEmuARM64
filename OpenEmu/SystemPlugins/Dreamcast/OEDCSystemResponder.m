/*
 Copyright (c) 2015, OpenEmu Team
 
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

#import "OEDCSystemResponder.h"
#import "OEDCSystemResponderClient.h"
#import <OpenEmuBase/OELibretroCoreTranslator.h>

#define RETRO_DEVICE_INDEX_ANALOG_BUTTON 2
#define RETRO_DEVICE_ID_JOYPAD_L2 12
#define RETRO_DEVICE_ID_JOYPAD_R2 13

@implementation OEDCSystemResponder
static const uint8_t kDCLibretroMap[] = { 4, 5, 6, 7, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 8, 9, 3, 2, 0, 1 };
@dynamic client;

+ (Protocol *)gameSystemResponderClientProtocol;
{
    return @protocol(OEDCSystemResponderClient);
}

- (void)changeAnalogEmulatorKey:(OESystemKey *)aKey value:(CGFloat)value
{
    NSUInteger k = aKey.key;
    id client = (id)self.client;
    if ([client conformsToProtocol:@protocol(OEBridgeInputTranslation)]) {
        int16_t val = (int16_t)round(value * 32767.0);
        switch (k) {
            case OEDCAnalogUp:    [(id<OEBridgeInputTranslation>)client receiveLibretroAnalogIndex:0 axis:1 value:-val forPort:aKey.player - 1]; break;
            case OEDCAnalogDown:  [(id<OEBridgeInputTranslation>)client receiveLibretroAnalogIndex:0 axis:1 value:val  forPort:aKey.player - 1]; break;
            case OEDCAnalogLeft:  [(id<OEBridgeInputTranslation>)client receiveLibretroAnalogIndex:0 axis:0 value:-val forPort:aKey.player - 1]; break;
            case OEDCAnalogRight: [(id<OEBridgeInputTranslation>)client receiveLibretroAnalogIndex:0 axis:0 value:val  forPort:aKey.player - 1]; break;
            case OEDCAnalogL:     [(id<OEBridgeInputTranslation>)client receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_BUTTON axis:RETRO_DEVICE_ID_JOYPAD_L2 value:val forPort:aKey.player - 1]; break;
            case OEDCAnalogR:     [(id<OEBridgeInputTranslation>)client receiveLibretroAnalogIndex:RETRO_DEVICE_INDEX_ANALOG_BUTTON axis:RETRO_DEVICE_ID_JOYPAD_R2 value:val forPort:aKey.player - 1]; break;
        }
        return;
    }
    [client didMoveDCJoystickDirection:(OEDCButton)k withValue:value forPlayer:aKey.player];
}

- (void)pressEmulatorKey:(OESystemKey *)aKey
{
    id client = (id)self.client;
    NSUInteger k = aKey.key;
    if ([client conformsToProtocol:@protocol(OEBridgeInputTranslation)]) {
        uint8_t btn = (k < sizeof(kDCLibretroMap)) ? kDCLibretroMap[k] : 0xFF;
        [(id<OEBridgeInputTranslation>)client receiveLibretroButton:btn forPort:aKey.player - 1 pressed:YES];
        return;
    }
    [client didPushDCButton:(OEDCButton)k forPlayer:aKey.player];
}

- (void)releaseEmulatorKey:(OESystemKey *)aKey
{
    id client = (id)self.client;
    NSUInteger k = aKey.key;
    if ([client conformsToProtocol:@protocol(OEBridgeInputTranslation)]) {
        uint8_t btn = (k < sizeof(kDCLibretroMap)) ? kDCLibretroMap[k] : 0xFF;
        [(id<OEBridgeInputTranslation>)client receiveLibretroButton:btn forPort:aKey.player - 1 pressed:NO];
        return;
    }
    [client didReleaseDCButton:(OEDCButton)k forPlayer:aKey.player];
}

@end
