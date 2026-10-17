#import <UIKit/UIKit.h>
#import "ISFPhotoSource.h"
#import "ISFSettings.h"

NS_ASSUME_NONNULL_BEGIN

@interface ISFSettingsViewController : UITableViewController

- (instancetype)initWithSource:(id<ISFPhotoSource>)source settings:(ISFSettings *)settings NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// Called when the user taps Start Slideshow.
@property (nonatomic, copy, nullable) void (^startHandler)(void);

@end

NS_ASSUME_NONNULL_END
