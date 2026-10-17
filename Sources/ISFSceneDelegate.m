#import "ISFSceneDelegate.h"
#import "ISFAppDelegate.h"

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
@implementation ISFSceneDelegate

- (ISFAppDelegate *)appDelegate {
    return (ISFAppDelegate *)[UIApplication sharedApplication].delegate;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    [[self appDelegate] connectWindow:self.window launchURL:connectionOptions.URLContexts.anyObject.URL];
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    for (UIOpenURLContext *context in URLContexts) [[self appDelegate] handleURL:context.URL];
}

@end
#endif
