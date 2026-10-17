#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Keeps the slideshow cycle state in Application Support so that a relaunch continues the same cycle.
@interface ISFCycleStore : NSObject

+ (nullable NSDictionary *)loadState;
/// Writes in the background; the latest state wins.
+ (void)save:(NSDictionary *)state;
/// Writes before returning, e.g. when the app is about to be suspended or killed.
+ (void)saveNow:(NSDictionary *)state;
+ (void)clear;

@end

NS_ASSUME_NONNULL_END
