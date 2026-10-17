#import <UIKit/UIKit.h>
#import "ISFPhotoSource.h"
#import "ISFSettings.h"

NS_ASSUME_NONNULL_BEGIN

/// Multi-select list of albums grouped by kind. Each tap saves the selection right away.
@interface ISFAlbumPickerViewController : UITableViewController

- (instancetype)initWithSource:(id<ISFPhotoSource>)source settings:(ISFSettings *)settings NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
