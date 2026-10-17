#import "ISFPhotoSource.h"

NS_ASSUME_NONNULL_BEGIN

/// Photos from the device photo library via PhotoKit, including iCloud shared albums.
@interface ISFPhotoKitSource : NSObject <ISFPhotoSource>
@end

NS_ASSUME_NONNULL_END
