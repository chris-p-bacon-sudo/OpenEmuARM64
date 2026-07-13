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

@interface OEDeviceManager (Testing)
- (void)OE_addDeviceHandler:(OEDeviceHandler *)handler;
@end

@interface OETestDeviceManager : OEDeviceManager
@end

@implementation OETestDeviceManager

- (void)OE_setUpCallbacks
{
}

@end

@interface OEZeroControlDeviceHandler : OEDeviceHandler
@property(nonatomic) BOOL disconnected;
@end

@implementation OEZeroControlDeviceHandler {
    OEControllerDescription *_testControllerDescription;
}

- (instancetype)initWithDeviceDescription:(OEDeviceDescription *)deviceDescription
{
    if((self = [super initWithDeviceDescription:deviceDescription]))
        _testControllerDescription = [[OEControllerDescription alloc] init];

    return self;
}

- (OEControllerDescription *)controllerDescription
{
    return _testControllerDescription;
}

- (NSString *)uniqueIdentifier
{
    return @"zero-control-test-device";
}

- (void)disconnect
{
    self.disconnected = YES;
}

@end

@interface OEDeviceManagerTests : XCTestCase
@end

@implementation OEDeviceManagerTests

- (void)testZeroControlControllerIsDisconnectedAndNotRegistered
{
    OETestDeviceManager *manager = [[OETestDeviceManager alloc] init];
    OEZeroControlDeviceHandler *handler = [[OEZeroControlDeviceHandler alloc] initWithDeviceDescription:nil];

    XCTAssertNoThrow([manager OE_addDeviceHandler:handler]);
    XCTAssertTrue(handler.disconnected);
    XCTAssertFalse([manager.controllerDeviceHandlers containsObject:handler]);
    XCTAssertNotEqual([manager deviceHandlerForUniqueIdentifier:handler.uniqueIdentifier], handler);
}

@end
