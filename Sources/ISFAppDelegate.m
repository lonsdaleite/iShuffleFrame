#import "ISFAppDelegate.h"
#import "ISFCycleStore.h"
#import "ISFDemoSource.h"
#import "ISFPhotoKitSource.h"
#import "ISFSettingsViewController.h"
#import "ISFSlideshowViewController.h"

@implementation ISFAppDelegate {
    id<ISFPhotoSource> _source;
    ISFSettings *_settings;
    ISFSlideshowViewController *_slideshow;
    NSURL *_launchURL; // handled in didFinishLaunching; openURL: comes right after with the same URL
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    _source = [ISFPhotoKitSource new];
#if DEBUG
    // Test hooks: `-ISFResetSettings YES` starts from default settings and a fresh cycle,
    // `-ISFDemo YES` uses generated photos.
    if ([defaults boolForKey:@"ISFResetSettings"]) {
        [defaults removePersistentDomainForName:[NSBundle mainBundle].bundleIdentifier];
        [ISFCycleStore clear];
    }
    if ([defaults boolForKey:@"ISFDemo"]) _source = [ISFDemoSource new];
#endif
    _settings = [[ISFSettings alloc] initWithDefaults:defaults];

    _slideshow = [[ISFSlideshowViewController alloc] initWithSource:_source settings:_settings];
    __weak typeof(self) weakSelf = self;
    _slideshow.settingsHandler = ^{ [weakSelf showSettingsAnimated:YES]; };

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    self.window.rootViewController = _slideshow;
    [self.window makeKeyAndVisible];

    NSURL *url = launchOptions[UIApplicationLaunchOptionsURLKey];
    BOOL startRequested = [[url.host lowercaseString] isEqualToString:@"start"];
    if (startRequested) _launchURL = url;
    if ((_settings.autostart || startRequested) && _settings.hasSource) {
        [_slideshow start];
    } else {
        // Not animated: an openURL: right after launch may need to dismiss it again.
        [self showSettingsAnimated:NO];
    }
    return YES;
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<NSString *, id> *)options {
    if (_launchURL && [url isEqual:_launchURL]) {
        _launchURL = nil;
        return YES;
    }
    _launchURL = nil;
    NSString *command = url.host.lowercaseString;
    if ([command isEqualToString:@"start"]) {
        [self startSlideshow];
        return YES;
    }
    if ([command isEqualToString:@"settings"]) {
        [self showSettingsAnimated:YES];
        return YES;
    }
    return NO;
}

- (void)showSettingsAnimated:(BOOL)animated {
    UIViewController *presented = _slideshow.presentedViewController;
    if ([presented isKindOfClass:[UINavigationController class]]) return; // settings are already open
    [_slideshow stop];
    if (_slideshow.presentedViewController) [_slideshow dismissViewControllerAnimated:NO completion:nil];

    ISFSettingsViewController *settingsController = [[ISFSettingsViewController alloc] initWithSource:_source
                                                                                             settings:_settings];
    __weak typeof(self) weakSelf = self;
    settingsController.startHandler = ^{ [weakSelf startSlideshow]; };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settingsController];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [_slideshow presentViewController:navigation animated:animated completion:nil];
}

- (void)startSlideshow {
    if (!_settings.hasSource) {
        [self showSettingsAnimated:YES];
        return;
    }
    UIViewController *presented = _slideshow.presentedViewController;
    if ([presented isKindOfClass:[UINavigationController class]]) {
        [_slideshow dismissViewControllerAnimated:YES completion:nil];
    } else if (!presented && _slideshow.running) {
        return; // already showing photos: keep going
    }
    [_slideshow start]; // also closes the pause menu
}

@end
