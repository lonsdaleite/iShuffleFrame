#import <Foundation/Foundation.h>
#import "ISFCycle.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ISFTransition) {
    ISFTransitionNone = 0,
    ISFTransitionFade = 1,
};

/// User settings stored in NSUserDefaults. Launch arguments like `-ISFInterval 5` override them for a run.
@interface ISFSettings : NSObject

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Show the whole library instead of the selected albums.
@property (nonatomic) BOOL useAllPhotos;
/// Local identifiers of the selected albums.
@property (nonatomic, copy) NSArray<NSString *> *albumIDs;
@property (nonatomic) ISFOrder order;
/// Seconds per photo, at least 1.
@property (nonatomic) NSTimeInterval interval;
@property (nonatomic) ISFTransition transition;
/// Start the slideshow on launch.
@property (nonatomic) BOOL autostart;

/// All photos or at least one album is selected.
@property (nonatomic, readonly) BOOL hasSource;

@end

NS_ASSUME_NONNULL_END
