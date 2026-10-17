#import <UIKit/UIKit.h>

@interface ISFAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;

/// Shows the slideshow in `window` and starts it or opens the settings. Called once: from launch on systems
/// without scenes (iOS 9–12 and the legacy build), from the scene delegate otherwise.
- (void)connectWindow:(UIWindow *)window launchURL:(NSURL *)url;
/// Handles ishuffleframe:// URLs.
- (BOOL)handleURL:(NSURL *)url;
@end
