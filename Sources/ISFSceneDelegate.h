#import <UIKit/UIKit.h>

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
/// Scene lifecycle for the regular build; the window and URL handling stay in ISFAppDelegate.
@interface ISFSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
#endif
