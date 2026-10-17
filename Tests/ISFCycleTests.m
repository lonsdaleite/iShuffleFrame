#import <XCTest/XCTest.h>
#import "ISFCycle.h"

/// Deterministic random numbers (LCG) so that shuffles are reproducible.
static ISFRandom ISFSeededRandom(uint32_t seed) {
    __block uint32_t state = seed;
    return ^uint32_t(uint32_t upperBound) {
        state = state * 1664525u + 1013904223u;
        return upperBound ? (state >> 8) % upperBound : 0;
    };
}

static NSArray<NSString *> *ISFItems(NSUInteger count) {
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) [items addObject:[NSString stringWithFormat:@"p%lu", (unsigned long)i]];
    return items;
}

@interface ISFCycleTests : XCTestCase
@end

@implementation ISFCycleTests

- (NSArray<NSString *> *)take:(NSUInteger)count from:(ISFCycle *)cycle {
    NSMutableArray *result = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) [result addObject:[cycle next] ?: @"<nil>"];
    return result;
}

- (void)testEmptyCycle {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:@[] order:ISFOrderShuffle random:nil];
    XCTAssertNil([cycle next]);
    XCTAssertNil([cycle peekNext]);
    XCTAssertNil([cycle previous]);
    XCTAssertNil(cycle.current);
}

- (void)testSequentialLoops {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(3) order:ISFOrderSequential random:nil];
    XCTAssertEqualObjects([self take:7 from:cycle], (@[@"p0", @"p1", @"p2", @"p0", @"p1", @"p2", @"p0"]));
}

- (void)testShuffleShowsEveryItemOncePerCycle {
    NSArray *items = ISFItems(20);
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:items order:ISFOrderShuffle random:ISFSeededRandom(1)];
    for (int round = 0; round < 5; round++) {
        NSArray *shown = [self take:20 from:cycle];
        XCTAssertEqualObjects([NSSet setWithArray:shown], [NSSet setWithArray:items], @"round %d", round);
        XCTAssertEqual([NSSet setWithArray:shown].count, (NSUInteger)20);
    }
}

- (void)testShuffleActuallyShuffles {
    NSArray *items = ISFItems(20);
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:items order:ISFOrderShuffle random:ISFSeededRandom(7)];
    XCTAssertNotEqualObjects([self take:20 from:cycle], items);
}

- (void)testNoImmediateRepeatAcrossCycles {
    for (uint32_t seed = 0; seed < 200; seed++) {
        ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(3) order:ISFOrderShuffle random:ISFSeededRandom(seed)];
        NSString *previous = nil;
        for (int i = 0; i < 30; i++) {
            NSString *item = [cycle next];
            XCTAssertNotEqualObjects(item, previous, @"seed %u step %d", seed, i);
            previous = item;
        }
    }
}

- (void)testSingleItemRepeats {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:@[@"only"] order:ISFOrderShuffle random:nil];
    XCTAssertEqualObjects([self take:3 from:cycle], (@[@"only", @"only", @"only"]));
}

- (void)testPeekMatchesNext {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(5) order:ISFOrderShuffle random:ISFSeededRandom(3)];
    for (int i = 0; i < 17; i++) {
        NSString *peeked = [cycle peekNext];
        XCTAssertEqualObjects([cycle next], peeked, @"step %d", i);
    }
}

- (void)testBackAndForwardKeepsOrder {
    ISFCycle *reference = [[ISFCycle alloc] initWithItems:ISFItems(10) order:ISFOrderShuffle random:ISFSeededRandom(5)];
    NSArray *expected = [self take:15 from:reference];

    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(10) order:ISFOrderShuffle random:ISFSeededRandom(5)];
    NSArray *firstFour = [self take:4 from:cycle];
    XCTAssertEqualObjects(firstFour, [expected subarrayWithRange:NSMakeRange(0, 4)]);
    XCTAssertEqualObjects([cycle previous], expected[2]);
    XCTAssertEqualObjects([cycle previous], expected[1]);
    XCTAssertEqualObjects(cycle.current, expected[1]);
    XCTAssertEqualObjects([cycle peekNext], expected[2]);
    // Going forward replays history, then continues the same cycle.
    XCTAssertEqualObjects([self take:13 from:cycle], [expected subarrayWithRange:NSMakeRange(2, 13)]);
}

- (void)testPreviousAtStart {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(3) order:ISFOrderSequential random:nil];
    XCTAssertNil([cycle previous]);
    [cycle next];
    XCTAssertNil([cycle previous]);
    XCTAssertEqualObjects(cycle.current, @"p0");
}

- (void)testShuffleUpdateAddsNewItemsToCurrentCycle {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(6) order:ISFOrderShuffle random:ISFSeededRandom(11)];
    NSArray *shown = [self take:3 from:cycle];
    [cycle updateItems:[ISFItems(6) arrayByAddingObjectsFromArray:@[@"new1", @"new2"]]];
    NSArray *rest = [self take:5 from:cycle];
    NSMutableSet *cycleItems = [NSMutableSet setWithArray:shown];
    [cycleItems addObjectsFromArray:rest];
    XCTAssertEqual(cycleItems.count, (NSUInteger)8, @"the first cycle covers old and new items without repeats");
    XCTAssertTrue([cycleItems containsObject:@"new1"]);
    XCTAssertTrue([cycleItems containsObject:@"new2"]);
}

- (void)testBrieflyMissingItemsAreNotRepeated {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(6) order:ISFOrderShuffle random:ISFSeededRandom(21)];
    NSArray *shown = [self take:3 from:cycle];
    NSArray *queued = [cycle state][@"queue"];
    // Two shown items and one queued item disappear for a while (e.g. their album is syncing), then come back.
    NSMutableArray *partial = [ISFItems(6) mutableCopy];
    [partial removeObjectsInArray:@[shown[0], shown[1], queued[0]]];
    [cycle updateItems:partial];
    [cycle updateItems:ISFItems(6)];

    ISFCycle *restored = [ISFCycle cycleWithItems:ISFItems(6) order:ISFOrderShuffle state:[cycle state] random:nil];
    XCTAssertEqualObjects([NSSet setWithArray:[self take:3 from:restored]], [NSSet setWithArray:queued]);
}

- (void)testShuffleUpdateRemovesItems {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(6) order:ISFOrderShuffle random:ISFSeededRandom(2)];
    [self take:2 from:cycle];
    NSMutableArray *items = [ISFItems(6) mutableCopy];
    [items removeObject:@"p5"];
    [items removeObject:@"p4"];
    [cycle updateItems:items];
    NSArray *shown = [self take:12 from:cycle];
    XCTAssertFalse([shown containsObject:@"p5"]);
    XCTAssertFalse([shown containsObject:@"p4"]);
}

- (void)testUpdateRemovingCurrentKeepsHistoryConsistent {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(4) order:ISFOrderSequential random:nil];
    [self take:3 from:cycle]; // p0 p1 p2, current p2
    [cycle updateItems:@[@"p0", @"p1", @"p3"]];
    XCTAssertEqualObjects(cycle.current, @"p1");
    XCTAssertEqualObjects([cycle next], @"p3");
    XCTAssertEqualObjects([cycle previous], @"p1");
    XCTAssertEqualObjects([cycle previous], @"p0");
}

- (void)testSequentialUpdateContinuesAfterLastShown {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:@[@"a", @"c", @"e"] order:ISFOrderSequential random:nil];
    [self take:2 from:cycle]; // a c
    [cycle updateItems:@[@"a", @"b", @"c", @"d", @"e"]];
    // b was added before the current position: it is still shown in this cycle, at its end.
    XCTAssertEqualObjects([self take:4 from:cycle], (@[@"d", @"e", @"b", @"a"]));
}

- (void)testSequentialBrieflyMissingItemsAreNotRepeated {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(6) order:ISFOrderSequential random:nil];
    [self take:3 from:cycle]; // p0 p1 p2
    // The album with everything shown so far disappears for a while, then comes back.
    [cycle updateItems:@[@"p3", @"p4", @"p5"]];
    [cycle updateItems:ISFItems(6)];

    ISFCycle *restored = [ISFCycle cycleWithItems:ISFItems(6) order:ISFOrderSequential state:[cycle state] random:nil];
    XCTAssertEqualObjects([self take:4 from:restored], (@[@"p3", @"p4", @"p5", @"p0"]));
}

- (void)testUpdateFromEmpty {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:@[] order:ISFOrderShuffle random:nil];
    XCTAssertNil([cycle next]);
    [cycle updateItems:@[@"x"]];
    XCTAssertEqualObjects([cycle next], @"x");
}

- (void)testUpdateToEmpty {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(3) order:ISFOrderShuffle random:nil];
    [cycle next];
    [cycle updateItems:@[]];
    XCTAssertNil(cycle.current);
    XCTAssertNil([cycle next]);
    XCTAssertNil([cycle previous]);
}

- (void)testStateRestoreContinuesShuffleCycle {
    ISFCycle *reference = [[ISFCycle alloc] initWithItems:ISFItems(10) order:ISFOrderShuffle random:ISFSeededRandom(9)];
    NSArray *expected = [self take:10 from:reference];

    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(10) order:ISFOrderShuffle random:ISFSeededRandom(9)];
    [self take:4 from:cycle];
    NSDictionary *state = [NSPropertyListSerialization propertyListWithData:
        [NSPropertyListSerialization dataWithPropertyList:[cycle state] format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL]
        options:0 format:NULL error:NULL];
    ISFCycle *restored = [ISFCycle cycleWithItems:ISFItems(10) order:ISFOrderShuffle state:state random:nil];
    XCTAssertEqualObjects(restored.current, expected[3]);
    XCTAssertEqualObjects([self take:6 from:restored], [expected subarrayWithRange:NSMakeRange(4, 6)]);
    XCTAssertEqualObjects([restored previous], expected[8]);
}

- (void)testStateRestoreAppliesItemChanges {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(6) order:ISFOrderShuffle random:ISFSeededRandom(4)];
    NSArray *shown = [self take:2 from:cycle];
    NSMutableArray *items = [ISFItems(6) mutableCopy];
    NSString *removed = [items firstObjectCommonWithArray:[[cycle state][@"queue"] subarrayWithRange:NSMakeRange(0, 1)]];
    [items removeObject:removed];
    [items addObject:@"new"];

    ISFCycle *restored = [ISFCycle cycleWithItems:items order:ISFOrderShuffle state:[cycle state] random:nil];
    // 4 left in the cycle: 4 queued - 1 removed + 1 new.
    NSArray *rest = [self take:4 from:restored];
    XCTAssertFalse([rest containsObject:removed]);
    XCTAssertTrue([rest containsObject:@"new"]);
    NSMutableSet *all = [NSMutableSet setWithArray:shown];
    [all addObjectsFromArray:rest];
    XCTAssertEqual(all.count, (NSUInteger)6, @"the cycle finishes without repeats");
}

- (void)testStateRestoreSequential {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(5) order:ISFOrderSequential random:nil];
    [self take:3 from:cycle];
    ISFCycle *restored = [ISFCycle cycleWithItems:ISFItems(5) order:ISFOrderSequential state:[cycle state] random:nil];
    XCTAssertEqualObjects([self take:3 from:restored], (@[@"p3", @"p4", @"p0"]));
}

- (void)testStateForOtherOrderIsIgnored {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(5) order:ISFOrderShuffle random:ISFSeededRandom(1)];
    [self take:3 from:cycle];
    ISFCycle *restored = [ISFCycle cycleWithItems:ISFItems(5) order:ISFOrderSequential state:[cycle state] random:nil];
    XCTAssertNil(restored.current);
    XCTAssertEqualObjects([self take:2 from:restored], (@[@"p0", @"p1"]));
}

- (void)testBrokenStateIsIgnored {
    for (NSDictionary *state in @[@{}, @{@"order": @0, @"items": @[@1], @"queue": @[], @"history": @[], @"position": @0},
                                   @{@"order": @"x"}, @{@"order": @0, @"items": @"p1"}]) {
        ISFCycle *restored = [ISFCycle cycleWithItems:ISFItems(3) order:ISFOrderShuffle state:state random:nil];
        XCTAssertEqual([NSSet setWithArray:[self take:3 from:restored]].count, (NSUInteger)3);
    }
    ISFCycle *outOfRange = [ISFCycle cycleWithItems:ISFItems(3) order:ISFOrderSequential
                                             state:@{@"order": @1, @"items": ISFItems(3), @"queue": @[@"p2"],
                                                     @"history": @[@"p0", @"p1"], @"position": @99}
                                            random:nil];
    XCTAssertEqualObjects(outOfRange.current, @"p1");
    XCTAssertEqualObjects([outOfRange next], @"p2");
}

- (void)testSavedHistoryIsBounded {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(50) order:ISFOrderSequential random:nil];
    [self take:300 from:cycle];
    NSDictionary *state = [cycle state];
    XCTAssertEqual([state[@"history"] count], (NSUInteger)100);
    ISFCycle *restored = [ISFCycle cycleWithItems:ISFItems(50) order:ISFOrderSequential state:state random:nil];
    XCTAssertEqualObjects(restored.current, cycle.current);
}

- (void)testLongHistoryIsBounded {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(50) order:ISFOrderSequential random:nil];
    [self take:2500 from:cycle];
    NSUInteger steps = 0;
    while ([cycle previous]) steps++;
    XCTAssertEqual(steps, (NSUInteger)999);
}

- (void)testPeekSeveralMatchesNext {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(5) order:ISFOrderShuffle random:ISFSeededRandom(4)];
    [self take:3 from:cycle];
    [cycle previous];
    [cycle previous];
    NSArray *peeked = [cycle peekNext:4];
    XCTAssertEqual(peeked.count, 4u);
    XCTAssertEqualObjects([self take:4 from:cycle], peeked);
}

- (void)testPeekSeveralStartsTheNextCycleWhenThisOneIsDone {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(3) order:ISFOrderSequential random:nil];
    [self take:2 from:cycle];
    XCTAssertEqualObjects([cycle peekNext:3], (@[@"p2"]));
    [cycle next];
    XCTAssertEqualObjects([cycle peekNext:2], (@[@"p0", @"p1"]));
    XCTAssertEqualObjects([self take:2 from:cycle], (@[@"p0", @"p1"]));
}

- (void)testPeekPrevious {
    ISFCycle *cycle = [[ISFCycle alloc] initWithItems:ISFItems(3) order:ISFOrderSequential random:nil];
    XCTAssertNil([cycle peekPrevious]);
    [self take:2 from:cycle];
    XCTAssertEqualObjects([cycle peekPrevious], @"p0");
    XCTAssertEqualObjects(cycle.current, @"p1");
}

@end
