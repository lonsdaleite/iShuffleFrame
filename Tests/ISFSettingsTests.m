#import <XCTest/XCTest.h>
#import "ISFSettings.h"

@interface ISFSettingsTests : XCTestCase
@end

@implementation ISFSettingsTests {
    NSUserDefaults *_defaults;
    NSString *_suite;
}

- (void)setUp {
    _suite = [NSString stringWithFormat:@"ISFSettingsTests-%@", [NSUUID UUID].UUIDString];
    _defaults = [[NSUserDefaults alloc] initWithSuiteName:_suite];
}

- (void)tearDown {
    [_defaults removePersistentDomainForName:_suite];
}

- (void)testDefaults {
    ISFSettings *settings = [[ISFSettings alloc] initWithDefaults:_defaults];
    XCTAssertFalse(settings.useAllPhotos);
    XCTAssertEqualObjects(settings.albumIDs, @[]);
    XCTAssertFalse(settings.hasSource);
    XCTAssertEqual(settings.order, ISFOrderShuffle);
    XCTAssertEqual(settings.interval, 20);
    XCTAssertEqual(settings.transition, ISFTransitionNone);
    XCTAssertTrue(settings.autostart);
}

- (void)testRoundTrip {
    ISFSettings *settings = [[ISFSettings alloc] initWithDefaults:_defaults];
    settings.albumIDs = @[@"a", @"b"];
    settings.order = ISFOrderSequential;
    settings.interval = 45;
    settings.transition = ISFTransitionFade;
    settings.autostart = NO;

    ISFSettings *reloaded = [[ISFSettings alloc] initWithDefaults:_defaults];
    XCTAssertEqualObjects(reloaded.albumIDs, (@[@"a", @"b"]));
    XCTAssertTrue(reloaded.hasSource);
    XCTAssertEqual(reloaded.order, ISFOrderSequential);
    XCTAssertEqual(reloaded.interval, 45);
    XCTAssertEqual(reloaded.transition, ISFTransitionFade);
    XCTAssertFalse(reloaded.autostart);
}

- (void)testAllPhotosIsASource {
    ISFSettings *settings = [[ISFSettings alloc] initWithDefaults:_defaults];
    settings.useAllPhotos = YES;
    XCTAssertTrue(settings.hasSource);
}

- (void)testIntervalIsAtLeastOneSecond {
    ISFSettings *settings = [[ISFSettings alloc] initWithDefaults:_defaults];
    settings.interval = 0;
    XCTAssertEqual(settings.interval, 1);
    [_defaults setDouble:-5 forKey:@"ISFInterval"];
    XCTAssertEqual(settings.interval, 1);
}

- (void)testGarbageValuesFallBack {
    [_defaults setInteger:42 forKey:@"ISFOrder"];
    [_defaults setInteger:-1 forKey:@"ISFTransition"];
    [_defaults setObject:@[@"ok", @7, [NSDate date]] forKey:@"ISFAlbumIDs"];
    ISFSettings *settings = [[ISFSettings alloc] initWithDefaults:_defaults];
    XCTAssertEqual(settings.order, ISFOrderShuffle);
    XCTAssertEqual(settings.transition, ISFTransitionNone);
    XCTAssertEqualObjects(settings.albumIDs, @[@"ok"]);
}

@end
