#import <UIKit/UIKit.h>
#import "ISFPhotoSource.h"
#import "ISFSettings.h"

NS_ASSUME_NONNULL_BEGIN

/// Full-screen slideshow. Swipes go to the next/previous photo; a tap pauses and offers Resume, Restart
/// and Settings.
@interface ISFSlideshowViewController : UIViewController

- (instancetype)initWithSource:(id<ISFPhotoSource>)source settings:(ISFSettings *)settings NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// Called when the user picks Settings in the pause menu, or when there is nothing to show yet.
@property (nonatomic, copy, nullable) void (^settingsHandler)(void);

/// The slideshow is running and not paused.
@property (nonatomic, readonly, getter=isRunning) BOOL running;

/// Starts showing photos with the current settings, continuing the saved cycle.
- (void)start;
/// Starts showing photos with a fresh cycle.
- (void)restart;
/// Stops the slideshow and dismisses the pause menu.
- (void)stop;

@end

NS_ASSUME_NONNULL_END
