#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ISFOrder) {
    ISFOrderShuffle = 0,
    ISFOrderSequential = 1,
};

/// Returns a uniformly distributed number in [0, upperBound).
typedef uint32_t (^ISFRandom)(uint32_t upperBound);

/// Display order of slideshow items.
///
/// Shuffle shows every item once per cycle in random order and reshuffles when the cycle ends.
/// Sequential shows items in source order and starts over at the end.
/// Shown items are kept in a history, so going back and forward again replays the same items
/// without disturbing the cycle.
@interface ISFCycle : NSObject

- (instancetype)initWithItems:(NSArray<NSString *> *)items
                        order:(ISFOrder)order
                       random:(nullable ISFRandom)random NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) NSArray<NSString *> *items;
@property (nonatomic, readonly) ISFOrder order;
@property (nonatomic, readonly, nullable) NSString *current;

/// Moves forward and returns the new current item; nil when there are no items.
- (nullable NSString *)next;
/// Moves back in history and returns the new current item; nil (and no move) at the start of history.
- (nullable NSString *)previous;
/// The item `next` would return, without moving.
- (nullable NSString *)peekNext;

/// Replaces the item set, keeping the history and the rest of the current cycle.
/// Removed items disappear from both; added items join the rest of the current cycle.
- (void)updateItems:(NSArray<NSString *> *)items;

/// A property-list snapshot (items, rest of the cycle, recent history) for continuing in a later run.
- (NSDictionary *)state;

/// Restores a cycle from `state` when it was saved with the same order, then applies `items` as an update.
/// Returns a fresh cycle when the state is missing, broken or saved with another order.
+ (instancetype)cycleWithItems:(NSArray<NSString *> *)items
                         order:(ISFOrder)order
                         state:(nullable NSDictionary *)state
                        random:(nullable ISFRandom)random;

@end

NS_ASSUME_NONNULL_END
