#import "ISFCycle.h"

static const NSUInteger ISFMaxHistory = 1000;
/// History entries kept in a saved state; enough to swipe back a while after a restart.
static const NSUInteger ISFSavedHistory = 100;

static NSArray<NSString *> *ISFStringArray(id value) {
    if (![value isKindOfClass:[NSArray class]]) return nil;
    for (id item in value) {
        if (![item isKindOfClass:[NSString class]]) return nil;
    }
    return value;
}

@implementation ISFCycle {
    ISFRandom _random;
    NSMutableArray<NSString *> *_queue;   // not yet shown in the current cycle
    NSMutableArray<NSString *> *_history; // shown items, oldest first
    NSInteger _position;                  // index of the current item in _history, -1 before the first one
    NSMutableSet<NSString *> *_cycleShown; // shown in the current shuffle cycle, even if gone from the items since
}

- (instancetype)initWithItems:(NSArray<NSString *> *)items order:(ISFOrder)order random:(ISFRandom)random {
    if ((self = [super init])) {
        _items = [items copy];
        _order = order;
        _random = random ? (ISFRandom)[random copy] : ^uint32_t(uint32_t upperBound) { return arc4random_uniform(upperBound); };
        _queue = [NSMutableArray array];
        _history = [NSMutableArray array];
        _position = -1;
        _cycleShown = [NSMutableSet set];
    }
    return self;
}

- (NSString *)current {
    return _position >= 0 ? _history[_position] : nil;
}

- (NSString *)next {
    if (_position + 1 < (NSInteger)_history.count) {
        _position++;
        return _history[_position];
    }
    if (_queue.count == 0) [self refill];
    if (_queue.count == 0) return nil;

    NSString *item = _queue.firstObject;
    [_queue removeObjectAtIndex:0];
    [_cycleShown addObject:item];
    [_history addObject:item];
    if (_history.count > ISFMaxHistory) [_history removeObjectAtIndex:0];
    _position = (NSInteger)_history.count - 1;
    return item;
}

- (NSString *)previous {
    if (_position <= 0) return nil;
    _position--;
    return _history[_position];
}

- (NSString *)peekNext {
    if (_position + 1 < (NSInteger)_history.count) return _history[_position + 1];
    if (_queue.count == 0) [self refill];
    return _queue.firstObject;
}

- (NSArray<NSString *> *)peekNext:(NSUInteger)count {
    NSMutableArray<NSString *> *items = [NSMutableArray arrayWithCapacity:count];
    for (NSInteger i = _position + 1; i < (NSInteger)_history.count && items.count < count; i++) {
        [items addObject:_history[i]];
    }
    if (items.count < count && _queue.count == 0) [self refill];
    for (NSString *item in _queue) {
        if (items.count >= count) break;
        [items addObject:item];
    }
    return items;
}

- (NSString *)peekPrevious {
    return _position > 0 ? _history[_position - 1] : nil;
}

- (void)refill {
    if (_items.count == 0) return;
    [_cycleShown removeAllObjects];
    if (_order == ISFOrderSequential) {
        [_queue setArray:_items];
        return;
    }
    NSMutableArray<NSString *> *cycle = [_items mutableCopy];
    for (NSUInteger i = cycle.count - 1; i > 0; i--) {
        [cycle exchangeObjectAtIndex:i withObjectAtIndex:_random((uint32_t)i + 1)];
    }
    // Do not show the same photo twice in a row across the cycle boundary.
    if (cycle.count > 1 && [cycle.firstObject isEqualToString:_history.lastObject]) {
        [cycle exchangeObjectAtIndex:0 withObjectAtIndex:1 + _random((uint32_t)cycle.count - 1)];
    }
    [_queue setArray:cycle];
}

- (void)updateItems:(NSArray<NSString *> *)items {
    NSSet<NSString *> *newSet = [NSSet setWithArray:items];
    NSSet<NSString *> *oldSet = [NSSet setWithArray:_items];

    // History: drop removed items; the current item becomes the closest kept one before it.
    NSMutableArray<NSString *> *history = [NSMutableArray arrayWithCapacity:_history.count];
    NSInteger position = -1;
    for (NSInteger i = 0; i < (NSInteger)_history.count; i++) {
        if (![newSet containsObject:_history[i]]) continue;
        [history addObject:_history[i]];
        if (i <= _position) position = (NSInteger)history.count - 1;
    }
    _history = history;
    _position = position;

    if (_order == ISFOrderSequential) {
        // Items not shown in this cycle, in source order, continuing after the latest shown item
        // and wrapping around to the ones before it.
        NSUInteger anchor = _history.lastObject ? [items indexOfObject:_history.lastObject] : NSNotFound;
        NSUInteger start = anchor == NSNotFound ? 0 : anchor + 1;
        NSMutableArray<NSString *> *queue = [NSMutableArray arrayWithCapacity:items.count];
        for (NSUInteger i = 0; i < items.count; i++) {
            NSString *item = items[(start + i) % items.count];
            if (![_cycleShown containsObject:item]) [queue addObject:item];
        }
        _queue = queue;
    } else {
        NSMutableArray<NSString *> *queue = [NSMutableArray arrayWithCapacity:_queue.count];
        for (NSString *item in _queue) {
            if ([newSet containsObject:item]) [queue addObject:item];
        }
        for (NSString *item in items) {
            // An album that was briefly unavailable comes back: do not show its photos twice in this cycle.
            if ([oldSet containsObject:item] || [_cycleShown containsObject:item]) continue;
            [queue insertObject:item atIndex:_random((uint32_t)queue.count + 1)];
        }
        _queue = queue;
    }
    _items = [items copy];
}

#pragma mark - State

- (NSDictionary *)state {
    NSUInteger start = _history.count > ISFSavedHistory ? _history.count - ISFSavedHistory : 0;
    NSArray *history = [_history subarrayWithRange:NSMakeRange(start, _history.count - start)];
    return @{
        @"order": @(_order),
        @"items": _items,
        @"queue": [_queue copy],
        @"history": history,
        @"position": @(_position - (NSInteger)start),
        @"shown": _cycleShown.allObjects,
    };
}

+ (instancetype)cycleWithItems:(NSArray<NSString *> *)items
                         order:(ISFOrder)order
                         state:(NSDictionary *)state
                        random:(ISFRandom)random {
    NSArray<NSString *> *savedItems = ISFStringArray(state[@"items"]);
    NSArray<NSString *> *queue = ISFStringArray(state[@"queue"]);
    NSArray<NSString *> *history = ISFStringArray(state[@"history"]);
    NSNumber *savedOrder = state[@"order"];
    NSNumber *position = state[@"position"];
    BOOL usable = savedItems && queue && history && [savedOrder isKindOfClass:[NSNumber class]] &&
                  savedOrder.integerValue == order && [position isKindOfClass:[NSNumber class]];
    ISFCycle *cycle = [[self alloc] initWithItems:usable ? savedItems : items order:order random:random];
    if (!usable) return cycle;

    NSSet<NSString *> *known = [NSSet setWithArray:savedItems];
    for (NSString *item in queue) {
        if ([known containsObject:item]) [cycle->_queue addObject:item];
    }
    for (NSString *item in history) {
        if ([known containsObject:item]) [cycle->_history addObject:item];
    }
    cycle->_position = MIN(MAX(position.integerValue, (NSInteger)-1), (NSInteger)cycle->_history.count - 1);
    NSArray<NSString *> *shown = ISFStringArray(state[@"shown"]);
    if (shown) [cycle->_cycleShown addObjectsFromArray:shown];
    [cycle updateItems:items];
    return cycle;
}

@end
