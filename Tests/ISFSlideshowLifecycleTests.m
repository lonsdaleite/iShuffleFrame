#import <XCTest/XCTest.h>
#import "ISFCycleStore.h"
#import "ISFDemoSource.h"
#import "ISFSettings.h"
#import "ISFSlideshowViewController.h"

@interface ISFSlideshowLifecycleTests : XCTestCase
@end

@implementation ISFSlideshowLifecycleTests {
    NSString *_suite;
    NSUserDefaults *_defaults;
    ISFSlideshowViewController *_slideshow;
}

- (void)setUp {
    [ISFCycleStore clear];
    _suite = [NSString stringWithFormat:@"ISFSlideshowLifecycleTests-%@", [NSUUID UUID].UUIDString];
    _defaults = [[NSUserDefaults alloc] initWithSuiteName:_suite];
    ISFSettings *settings = [[ISFSettings alloc] initWithDefaults:_defaults];
    settings.useAllPhotos = YES;
    settings.interval = 1;
    _slideshow = [[ISFSlideshowViewController alloc] initWithSource:[ISFDemoSource new] settings:settings];
    [_slideshow start];
}

- (void)tearDown {
    [_slideshow stop];
    _slideshow = nil;
    [_defaults removePersistentDomainForName:_suite];
    [ISFCycleStore clear];
}

- (NSString *)shownItem {
    for (UIView *view in _slideshow.view.subviews) {
        if ([view.accessibilityIdentifier isEqualToString:@"ISFSlideshowImage"]) return view.accessibilityValue;
    }
    return nil;
}

- (void)waitSeconds:(NSTimeInterval)seconds {
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

- (NSString *)waitForFirstPhoto {
    for (int i = 0; i < 50 && ![self shownItem]; i++) [self waitSeconds:0.1];
    XCTAssertNotNil([self shownItem]);
    return [self shownItem];
}

- (void)post:(NSNotificationName)name {
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:[UIApplication sharedApplication]];
}

- (void)testKeepsGoingWhenInactiveWithoutBecomingActiveAgain {
    NSString *first = [self waitForFirstPhoto];
    // The screen goes dark and comes back without a lock: the app may get a resign and no become-active.
    [self post:UIApplicationWillResignActiveNotification];
    [self waitSeconds:2.5];
    XCTAssertNotEqualObjects([self shownItem], first);
}

- (void)testStopsInTheBackgroundAndContinuesInTheForeground {
    [self waitForFirstPhoto];
    [self post:UIApplicationWillResignActiveNotification];
    [self post:UIApplicationDidEnterBackgroundNotification];
    NSString *shown = [self shownItem];
    [self waitSeconds:2.5];
    XCTAssertEqualObjects([self shownItem], shown);

    [self post:UIApplicationWillEnterForegroundNotification];
    [self waitSeconds:2.5];
    XCTAssertNotEqualObjects([self shownItem], shown);
}

@end
