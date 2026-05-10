// Copyright (c) 2018, OpenEmu Team
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
#import "OEDiffQueue.h"


@interface OpenEmuBaseTests : XCTestCase

@end


@implementation OpenEmuBaseTests


- (NSData *)randomDataOfSize:(NSInteger)size
{
    /* using rand because the seed is deterministic */
    char *buf = malloc(size);
    for (NSInteger i=0; i<size; i++)
        buf[i] = rand();
    return [NSData dataWithBytesNoCopy:buf length:size freeWhenDone:YES];
}


- (NSData *)dataByMutatingData:(NSData *)orig withFrequency:(double)freq sizeDifference:(NSInteger)diff
{
    NSInteger oldsize = orig.length;
    NSInteger newsize = MAX(oldsize + diff, (NSInteger)0);
    NSInteger commonsize = MAX(MIN(newsize, oldsize), (NSInteger)0);
    
    char *newbuf = malloc(newsize);
    memcpy(newbuf, orig.bytes, commonsize);
    
    NSInteger i;
    for (i=0; i<commonsize; i++) {
        if ((rand() & 0x7FFFFF) / 8388607.0 <= freq)
            newbuf[i] = rand();
    }
    for (; i<newsize; i++) {
        newbuf[i] = rand();
    }
    
    return [NSData dataWithBytesNoCopy:newbuf length:newsize freeWhenDone:YES];
}


- (void)runComparisonTest:(NSArray<NSData *> *)dataset
{
    OEDiffQueue *dq = [[OEDiffQueue alloc] init];
    
    XCTAssertTrue([dq count] == 0, @"item count is wrong");
    for (NSInteger i=0; i<dataset.count; i++) {
        [dq push:dataset[i]];
        XCTAssertTrue([dq count] == i+1, @"item count is wrong");
    }
    for (NSInteger i=dataset.count-1; i >= 0; i--) {
        NSData *popped = [dq pop];
        XCTAssertTrue([dq count] == i, @"item count is wrong");
        XCTAssertTrue([popped isEqual:dataset[i]], @"popped different data than pushed");
    }
    XCTAssertNil([dq pop], @"emptied new diff queue not popping nil");
}


- (void)testNewIsEmpty
{
    [self runComparisonTest:@[]];
}


- (void)testFirstInsertion
{
    [self runComparisonTest:@[[self randomDataOfSize:100]]];
}


- (void)testDeltaInsertion
{
    NSMutableArray *dataset = [NSMutableArray arrayWithObject:[self randomDataOfSize:100]];
    [dataset addObject:[self dataByMutatingData:dataset[0] withFrequency:0.1 sizeDifference:0]];
    [dataset addObject:[self dataByMutatingData:dataset[1] withFrequency:0.1 sizeDifference:10]];
    [dataset addObject:[self dataByMutatingData:dataset[2] withFrequency:0.1 sizeDifference:-7]];
    [self runComparisonTest:dataset];
}


- (void)testNoDeltaInsertion
{
    [self runComparisonTest:@[
        [self randomDataOfSize:100],
        [self randomDataOfSize:100],
        [self randomDataOfSize:110],
        [self randomDataOfSize:90]
    ]];
}


- (void)testBigDeltas
{
    NSMutableArray *dataset = [NSMutableArray arrayWithObject:[self randomDataOfSize:10000]];
    for (int i=1; i<100; i++) {
        [dataset addObject:
            [self dataByMutatingData:dataset[i-1]
                withFrequency:arc4random_uniform(50) / 100.0
                sizeDifference:((int)arc4random_uniform(3000))-1500]];
    }
    [self runComparisonTest:dataset];
}


- (void)testCapacity
{
    OEDiffQueue *dq = [[OEDiffQueue alloc] initWithCapacity:10];
    NSMutableArray *dataset = [NSMutableArray arrayWithObject:[self randomDataOfSize:100]];
    [dq push:dataset[0]];
    for (int i=1; i<15; i++) {
        [dataset addObject:[self dataByMutatingData:dataset[i-1] withFrequency:0.1 sizeDifference:0]];
        [dq push:dataset[i]];
        XCTAssertEqual([dq count], MIN(i+1, 10), @"count exceeded capacity");
    }
    
    int j=15-1;
    for (int i=0; i<10; i++) {
        XCTAssertTrue([[dq pop] isEqual:dataset[j]], @"popped different data than pushed");
        j--;
    }
    XCTAssertNil([dq pop], @"popped data when it should have been discarded");
}


- (void)testEmptyData
{
    [self runComparisonTest:@[[NSData data]]];
    [self runComparisonTest:@[[NSData data], [NSData data]]];
}


- (void)testSmallDiff
{
    [self runComparisonTest:@[
        [NSData data],
        [self randomDataOfSize:1],
        [self randomDataOfSize:2],
        [self randomDataOfSize:3],
        [self randomDataOfSize:4],
        [self randomDataOfSize:6],
        [self randomDataOfSize:8]
    ]];
}


@end
