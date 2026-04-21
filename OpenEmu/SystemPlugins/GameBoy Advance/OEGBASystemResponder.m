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

#import "OEGBASystemResponder.h"
#import "OEGBASystemResponderClient.h"
#import <OpenEmuBase/OELibretroCoreTranslator.h>

@implementation OEGBASystemResponder
static const uint8_t kGBALibretroMap[] = { 4, 5, 6, 7, 8, 0, 10, 11, 3, 2 };
@dynamic client;

+ (Protocol *)gameSystemResponderClientProtocol;
{
    return @protocol(OEGBASystemResponderClient);
}

- (void)pressEmulatorKey:(OESystemKey *)aKey
{
    id client = (id)self.client;
    NSUInteger k = aKey.key;
    if ([client conformsToProtocol:@protocol(OEBridgeInputTranslation)]) {
        uint8_t btn = (k < sizeof(kGBALibretroMap)) ? kGBALibretroMap[k] : 0xFF;
        [(id<OEBridgeInputTranslation>)client receiveLibretroButton:btn forPort:aKey.player - 1 pressed:YES];
        return;
    }
    [client didPushGBAButton:(OEGBAButton)k forPlayer:aKey.player];
}

- (void)releaseEmulatorKey:(OESystemKey *)aKey
{
    id client = (id)self.client;
    NSUInteger k = aKey.key;
    if ([client conformsToProtocol:@protocol(OEBridgeInputTranslation)]) {
        uint8_t btn = (k < sizeof(kGBALibretroMap)) ? kGBALibretroMap[k] : 0xFF;
        [(id<OEBridgeInputTranslation>)client receiveLibretroButton:btn forPort:aKey.player - 1 pressed:NO];
        return;
    }
    [client didReleaseGBAButton:(OEGBAButton)k forPlayer:aKey.player];
}

@end
