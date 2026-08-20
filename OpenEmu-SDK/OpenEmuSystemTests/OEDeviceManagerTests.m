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

#import "../OpenEmuSystem/OEDeviceManager_Internal.h"
#import "../OpenEmuSystem/OEControllerDescription_Internal.h"

// Regression coverage for OES-300: a controller that macOS hands to OpenEmu
// without any readable buttons/axes (seen in the field with an Xbox
// controller on macOS 26) used to trip an NSAssert in
// -[OEDeviceManager OE_addDeviceHandler:] and crash the app on launch.
// That handler should now be ignored instead of asserted on.
@interface OEDeviceManagerTests : XCTestCase

@end

@implementation OEDeviceManagerTests

- (void)testDeviceHandlerWithNoControlsIsIgnoredRatherThanCrashing {
    // An unrecognized vendor/product pair produces a generic controller
    // description with zero controls, the same shape as the field crash.
    OEControllerDescription *controllerDescription =
        [OEControllerDescription OE_controllerDescriptionForVendorID:0xFFFF
                                                             productID:0xFFFF
                                                               product:@"Unit Test Fake Controller"];
    XCTAssertEqual(controllerDescription.numberOfControls, 0);

    OEDeviceDescription *deviceDescription = [controllerDescription deviceDescriptionForVendorID:0xFFFF
                                                                                         productID:0xFFFF
                                                                                            cookie:0];

    OEDeviceHandler *handler = [[OEDeviceHandler alloc] initWithDeviceDescription:deviceDescription];
    OEDeviceManager *manager = [OEDeviceManager sharedDeviceManager];

    XCTAssertNoThrow([manager OE_addDeviceHandler:handler]);
    XCTAssertFalse([manager.controllerDeviceHandlers containsObject:handler],
                    @"A controller with zero readable controls should be skipped, not registered.");
}

@end
