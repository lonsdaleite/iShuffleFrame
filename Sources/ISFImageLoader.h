#import <Foundation/Foundation.h>
#import "ISFPhotoSource.h"

NS_ASSUME_NONNULL_BEGIN

/// Loads photos at screen size and keeps the recently used ones, so that swiping back and forth does not decode
/// the same photo again. One request per photo: callers waiting for the same photo share it. Main thread only.
@interface ISFImageLoader : NSObject

- (instancetype)initWithSource:(id<ISFPhotoSource>)source
                    targetSize:(CGSize)targetSize
                      capacity:(NSUInteger)capacity NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (nullable UIImage *)cachedImageForItem:(NSString *)item;
/// Calls `completion` with the image, or nil if the photo could not be loaded. Never calls it synchronously.
- (void)loadItem:(NSString *)item completion:(void (^)(UIImage *_Nullable image))completion;
/// Drops the waiters of `item`: nobody needs the result now, but the load goes on in the background.
- (void)stopWaitingForItem:(NSString *)item;
/// Starts loading `items` in the background and cancels background loads of other photos nobody waits for.
- (void)prefetchItems:(NSArray<NSString *> *)items;
/// Cancels the request for `item` (it may be stuck), so that the next load makes a new one. Its waiters get nil.
- (void)dropItem:(NSString *)item;
/// Frees the cached images except `item`.
- (void)trimExceptItem:(nullable NSString *)item;
/// Cancels everything and empties the cache. Waiters are not called.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
