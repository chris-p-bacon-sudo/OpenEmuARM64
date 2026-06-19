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

// Regression tests for RetroAchievements hardcore mode gates at the OEGameCore
// layer. These gates exist because RA's hardcore contract forbids rewind,
// fast-forward, frame-step, and other state-rewriting affordances during a
// hardcore session. The gates are scattered across `OEGameCore.m` and easy to
// weaken in an unrelated refactor — these tests lock the contract in place.
//
// Hardcore gates under test (OEGameCore.m):
//   - fastForward:          line ~582
//   - fastForwardAtSpeed:   line ~630
//   - rewind:               line ~597
//   - rewindAtSpeed:        line ~636
//   - slowMotionAtSpeed:    line ~643
//   - stepFrameForward      line ~648
//   - stepFrameBackward     line ~654
//
// Internal flags `isRewinding` and `singleFrameStep` are private ivars; we
// read them via KVC, which falls back to ivar lookup when no accessor exists.
// If KVC stops finding them (e.g. the ivars are renamed), these tests fail
// loudly — which is the desired behavior for a regression suite.

#import <XCTest/XCTest.h>
#import "OEGameCore.h"


@interface OEGameCoreHardcoreTests : XCTestCase
@end


@implementation OEGameCoreHardcoreTests

#pragma mark - Helpers

- (BOOL)isRewindingForCore:(OEGameCore *)core
{
    return [[core valueForKey:@"isRewinding"] boolValue];
}

- (BOOL)singleFrameStepForCore:(OEGameCore *)core
{
    return [[core valueForKey:@"singleFrameStep"] boolValue];
}

#pragma mark - Defaults

- (void)testHardcoreDefaultsOff
{
    // OEGameCore default is OFF; the helper opts in by setting it true before
    // a session starts. If this default ever flipped, every non-RA session
    // would silently lose rewind/fast-forward/frame-step.
    OEGameCore *core = [[OEGameCore alloc] init];
    XCTAssertFalse(core.hardcoreEnabled,
                   @"OEGameCore.hardcoreEnabled default must remain OFF; the helper sets it true at session start.");
}

- (void)testRetroAchievementsPauseDefaultsAllowPause
{
    OEGameCore *core = [[OEGameCore alloc] init];
    uint32_t framesRemaining = UINT32_MAX;

    XCTAssertTrue([core canPauseRetroAchievementsHardcoreWithFramesRemaining:&framesRemaining],
                  @"Base OEGameCore must allow pause by default so non-RA cores keep existing pause behavior.");
    XCTAssertEqual(framesRemaining, 0u,
                   @"Base OEGameCore should report no retry delay when pause is allowed by default.");
}

- (void)testRetroAchievementsIdleDefaultIsNoOp
{
    OEGameCore *core = [[OEGameCore alloc] init];
    XCTAssertNoThrow([core retroAchievementsIdle],
                     @"Base OEGameCore idle hook must be safe for non-RA cores.");
}

#pragma mark - fastForward:

- (void)testFastForwardAllowedWhenHardcoreEnabled
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.rate = 1.0f;
    core.hardcoreEnabled = YES;

    [core fastForward:YES];

    XCTAssertEqualWithAccuracy(core.rate, 5.0f, 0.0001f,
                               @"fastForward: must speed up even when hardcoreEnabled is YES — RA's hardcore spec permits fast-forward.");
}

- (void)testFastForwardAllowedWhenHardcoreDisabled
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.rate = 1.0f;
    core.hardcoreEnabled = NO;

    [core fastForward:YES];

    XCTAssertGreaterThan(core.rate, 1.0f,
                         @"fastForward: must increase rate when hardcoreEnabled is NO (sanity check that the gate is the only thing blocking).");
}

- (void)testFastForwardAtSpeedAllowedWhenHardcoreEnabled
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.rate = 1.0f;
    core.hardcoreEnabled = YES;

    [core fastForwardAtSpeed:4.0f];

    XCTAssertEqualWithAccuracy(core.rate, 4.0f, 0.0001f,
                               @"fastForwardAtSpeed: must set the requested rate even when hardcoreEnabled is YES — analog fast-forward is permitted in hardcore.");
}

- (void)testFastForwardAtSpeedAllowedWhenHardcoreDisabled
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.rate = 1.0f;
    core.hardcoreEnabled = NO;

    [core fastForwardAtSpeed:4.0f];

    XCTAssertEqualWithAccuracy(core.rate, 4.0f, 0.0001f,
                               @"fastForwardAtSpeed: must set the requested rate when hardcoreEnabled is NO.");
}

#pragma mark - rewind:

- (void)testRewindBlockedWhenHardcoreEnabled
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.hardcoreEnabled = YES;

    [core rewind:YES];

    XCTAssertFalse([self isRewindingForCore:core],
                   @"rewind: must not flip isRewinding to YES when hardcoreEnabled is YES.");
}

- (void)testRewindForceClearedWhenHardcoreEnabledMidRewind
{
    // If a rewind is already in progress and hardcore turns on, the next
    // rewind: call must clear isRewinding rather than leave it stuck on.
    OEGameCore *core = [[OEGameCore alloc] init];
    core.hardcoreEnabled = NO;
    [core rewindAtSpeed:1.0]; // sets isRewinding = YES via setter path
    XCTAssertTrue([self isRewindingForCore:core],
                  @"precondition: rewind must be active before we test the hardcore-on transition.");

    core.hardcoreEnabled = YES;
    [core rewind:YES];

    XCTAssertFalse([self isRewindingForCore:core],
                   @"rewind: must force-clear isRewinding when hardcoreEnabled is YES.");
}

- (void)testRewindAtSpeedBlockedWhenHardcoreEnabled
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.rate = 1.0f;
    core.hardcoreEnabled = YES;

    [core rewindAtSpeed:1.0f];

    XCTAssertEqualWithAccuracy(core.rate, 1.0f, 0.0001f,
                               @"rewindAtSpeed: must not change rate when hardcoreEnabled is YES.");
    XCTAssertFalse([self isRewindingForCore:core],
                   @"rewindAtSpeed: must not flip isRewinding to YES when hardcoreEnabled is YES.");
}

- (void)testRewindAtSpeedForceClearedWhenHardcoreEnabledMidRewind
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.hardcoreEnabled = NO;
    [core rewindAtSpeed:1.0f];
    XCTAssertTrue([self isRewindingForCore:core],
                  @"precondition: rewind must be active before we test the hardcore-on transition.");

    core.hardcoreEnabled = YES;
    [core rewindAtSpeed:1.0f];

    XCTAssertFalse([self isRewindingForCore:core],
                   @"rewindAtSpeed: must force-clear isRewinding when hardcoreEnabled is YES.");
}

#pragma mark - slowMotionAtSpeed:

- (void)testSlowMotionAtSpeedBlockedWhenHardcoreEnabled
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.rate = 1.0f;
    core.hardcoreEnabled = YES;

    [core slowMotionAtSpeed:0.5f];

    XCTAssertEqualWithAccuracy(core.rate, 1.0f, 0.0001f,
                               @"slowMotionAtSpeed: must be a no-op when hardcoreEnabled is YES — latent bindings must not bypass hardcore.");
}

- (void)testSlowMotionAtSpeedAllowedWhenHardcoreDisabled
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.rate = 1.0f;
    core.hardcoreEnabled = NO;

    [core slowMotionAtSpeed:0.5f];

    XCTAssertEqualWithAccuracy(core.rate, 0.5f, 0.0001f,
                               @"slowMotionAtSpeed: must set the requested rate when hardcoreEnabled is NO.");
}

#pragma mark - stepFrameForward / stepFrameBackward

- (void)testStepFrameForwardBlockedWhenHardcoreEnabled
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.hardcoreEnabled = YES;

    [core stepFrameForward];

    XCTAssertFalse([self singleFrameStepForCore:core],
                   @"stepFrameForward must be a no-op when hardcoreEnabled is YES.");
}

- (void)testStepFrameBackwardBlockedWhenHardcoreEnabled
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.hardcoreEnabled = YES;

    [core stepFrameBackward];

    XCTAssertFalse([self singleFrameStepForCore:core],
                   @"stepFrameBackward must be a no-op when hardcoreEnabled is YES.");
    XCTAssertFalse([self isRewindingForCore:core],
                   @"stepFrameBackward must not flip isRewinding when hardcoreEnabled is YES.");
}

- (void)testStepFrameForwardAllowedWhenHardcoreDisabled
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.hardcoreEnabled = NO;

    [core stepFrameForward];

    XCTAssertTrue([self singleFrameStepForCore:core],
                  @"stepFrameForward must set singleFrameStep when hardcoreEnabled is NO (sanity check).");
}

#pragma mark - Toggle behavior

- (void)testEnablingHardcoreClearsActiveRewind
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.hardcoreEnabled = NO;
    [core rewindAtSpeed:1.0f];
    XCTAssertTrue([self isRewindingForCore:core],
                  @"precondition: rewind must be active before hardcore is enabled.");

    core.hardcoreEnabled = YES;

    XCTAssertFalse([self isRewindingForCore:core],
                   @"setHardcoreEnabled: must clear active rewind immediately, even before the next rewind event arrives.");
}

- (void)testEnablingHardcoreClearsPendingFrameStep
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.hardcoreEnabled = NO;
    [core stepFrameForward];
    XCTAssertTrue([self singleFrameStepForCore:core],
                  @"precondition: frame-step must be pending before hardcore is enabled.");

    core.hardcoreEnabled = YES;

    XCTAssertFalse([self singleFrameStepForCore:core],
                   @"setHardcoreEnabled: must clear pending frame-step immediately.");
}

- (void)testEnablingHardcorePreservesActiveFastForwardRate
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.hardcoreEnabled = NO;
    [core fastForwardAtSpeed:4.0f];
    XCTAssertEqualWithAccuracy(core.rate, 4.0f, 0.0001f,
                               @"precondition: fast-forward rate must be active before hardcore is enabled.");

    core.hardcoreEnabled = YES;

    XCTAssertEqualWithAccuracy(core.rate, 4.0f, 0.0001f,
                               @"setHardcoreEnabled: must preserve an active fast-forward rate — fast-forward is permitted in hardcore.");
}

- (void)testEnablingHardcoreClearsActiveSlowMotionRate
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.hardcoreEnabled = NO;
    [core slowMotionAtSpeed:0.5f];
    XCTAssertEqualWithAccuracy(core.rate, 0.5f, 0.0001f,
                               @"precondition: slow-motion rate must be active before hardcore is enabled.");

    core.hardcoreEnabled = YES;

    XCTAssertEqualWithAccuracy(core.rate, 1.0f, 0.0001f,
                               @"setHardcoreEnabled: must return active slow motion to normal speed immediately.");
}

- (void)testEnablingHardcorePreservesPausedFastForwardResumeRate
{
    OEGameCore *core = [[OEGameCore alloc] init];
    core.hardcoreEnabled = NO;
    [core fastForwardAtSpeed:4.0f];
    [core setPauseEmulation:YES];
    XCTAssertTrue(core.isEmulationPaused,
                  @"precondition: core must be paused before testing lastRate normalization.");

    core.hardcoreEnabled = YES;
    [core setPauseEmulation:NO];

    XCTAssertEqualWithAccuracy(core.rate, 4.0f, 0.0001f,
                               @"setHardcoreEnabled: must preserve the paused fast-forward resume rate — fast-forward is permitted in hardcore.");
}

- (void)testToggleReEnablesAffordances
{
    // Hardcore on → block. Hardcore off → allow. Catches regressions where the
    // gate is stuck-on (e.g. a refactor that initializes a flag once and never
    // re-reads it).
    OEGameCore *core = [[OEGameCore alloc] init];

    core.hardcoreEnabled = YES;
    [core stepFrameForward];
    XCTAssertFalse([self singleFrameStepForCore:core],
                   @"stepFrameForward should be blocked while hardcore is on.");

    core.hardcoreEnabled = NO;
    [core stepFrameForward];
    XCTAssertTrue([self singleFrameStepForCore:core],
                  @"stepFrameForward should be allowed once hardcore is turned off.");
}

@end
