#import <XCTest/XCTest.h>

/// UI tests run the app with generated demo photos: album "Demo A" (A-0...A-9) and "Demo B" (B-0...B-4).
/// The slideshow image exposes the shown photo identifier as its accessibility value.
@interface ISFUITests : XCTestCase
@end

@implementation ISFUITests

- (void)setUp {
    self.continueAfterFailure = NO;
}

- (XCUIApplication *)launchWithArguments:(NSArray<NSString *> *)arguments {
    XCUIApplication *app = [XCUIApplication new];
    app.launchArguments = [@[@"-ISFDemo", @"YES", @"-ISFResetSettings", @"YES"] arrayByAddingObjectsFromArray:arguments];
    [app launch];
    return app;
}

- (XCUIElement *)imageIn:(XCUIApplication *)app {
    return app.images[@"ISFSlideshowImage"];
}

- (NSString *)waitForPhotoIn:(XCUIApplication *)app differentFrom:(NSString *)previous {
    XCUIElement *image = [self imageIn:app];
    XCTAssertTrue([image waitForExistenceWithTimeout:10]);
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(XCUIElement *element, NSDictionary *bindings) {
        NSString *value = element.value;
        return value.length > 0 && ![value isEqualToString:previous];
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc] initWithPredicate:predicate object:image];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[expectation] timeout:10], XCTWaiterResultCompleted,
                   @"photo did not change from %@", previous);
    return image.value;
}

- (void)assertSettingsShownIn:(XCUIApplication *)app {
    XCTAssertTrue([app.cells[@"ISFStartCell"] waitForExistenceWithTimeout:10]);
}

- (void)testFirstLaunchShowsSettings {
    XCUIApplication *app = [self launchWithArguments:@[]];
    [self assertSettingsShownIn:app];
    XCTAssertTrue(app.cells[@"ISFAllPhotosCell"].exists);
    XCTAssertTrue(app.cells[@"ISFAlbumsCell"].exists);
    XCTAssertTrue(app.switches[@"ISFAutostartSwitch"].exists);
}

- (void)testStartWithoutSourceStaysInSettings {
    XCUIApplication *app = [self launchWithArguments:@[]];
    [self assertSettingsShownIn:app];
    [app.cells[@"ISFStartCell"] tap];
    XCTAssertTrue(app.cells[@"ISFStartCell"].exists);
    XCTAssertFalse([self imageIn:app].hittable);
}

- (void)testAllPhotosSwipesKeepOrder {
    XCUIApplication *app = [self launchWithArguments:@[@"-ISFInterval", @"3600"]];
    [self assertSettingsShownIn:app];
    [app.cells[@"ISFAllPhotosCell"] tap];
    [app.cells[@"ISFStartCell"] tap];

    NSString *first = [self waitForPhotoIn:app differentFrom:nil];
    XCUIElement *image = [self imageIn:app];
    [image swipeLeft];
    NSString *second = [self waitForPhotoIn:app differentFrom:first];
    [image swipeLeft];
    NSString *third = [self waitForPhotoIn:app differentFrom:second];
    [image swipeRight];
    XCTAssertEqualObjects([self waitForPhotoIn:app differentFrom:third], second);
    [image swipeRight];
    XCTAssertEqualObjects([self waitForPhotoIn:app differentFrom:second], first);
    [image swipeLeft];
    XCTAssertEqualObjects([self waitForPhotoIn:app differentFrom:first], second);
    [image swipeLeft];
    XCTAssertEqualObjects([self waitForPhotoIn:app differentFrom:second], third);
}

- (void)testAlbumSelectionInOrder {
    XCUIApplication *app = [self launchWithArguments:@[@"-ISFInterval", @"3600"]];
    [self assertSettingsShownIn:app];
    [app.cells[@"ISFAlbumsCell"] tap];
    XCUIElement *albumB = app.cells[@"ISFAlbum-Demo B"];
    XCTAssertTrue([albumB waitForExistenceWithTimeout:5]);
    XCTAssertTrue(app.staticTexts[@"Shared Albums"].exists);
    [albumB tap];
    [app.navigationBars.buttons.firstMatch tap];
    XCTAssertTrue([app.cells[@"ISFAlbumsCell"].staticTexts[@"1 selected"] waitForExistenceWithTimeout:5]);
    [app.cells[@"ISFSequentialCell"] tap];
    [app.cells[@"ISFStartCell"] tap];

    XCTAssertEqualObjects([self waitForPhotoIn:app differentFrom:nil], @"B-0");
    NSString *previous = @"B-0";
    for (NSString *expected in @[@"B-1", @"B-2", @"B-3", @"B-4", @"B-0"]) {
        [[self imageIn:app] swipeLeft];
        previous = [self waitForPhotoIn:app differentFrom:previous];
        XCTAssertEqualObjects(previous, expected);
    }
}

- (void)testAutostartAdvancesByTimer {
    XCUIApplication *app = [self launchWithArguments:@[@"-ISFUseAllPhotos", @"YES", @"-ISFInterval", @"1"]];
    NSString *first = [self waitForPhotoIn:app differentFrom:nil];
    NSString *second = [self waitForPhotoIn:app differentFrom:first];
    [self waitForPhotoIn:app differentFrom:second];
    XCTAssertFalse(app.cells[@"ISFStartCell"].exists);
}

- (void)testFadeTransitionAdvances {
    XCUIApplication *app = [self launchWithArguments:@[@"-ISFUseAllPhotos", @"YES", @"-ISFInterval", @"1",
                                                       @"-ISFTransition", @"1"]];
    NSString *first = [self waitForPhotoIn:app differentFrom:nil];
    [self waitForPhotoIn:app differentFrom:first];
}

- (void)testAutostartOffOpensSettings {
    XCUIApplication *app = [self launchWithArguments:@[@"-ISFUseAllPhotos", @"YES", @"-ISFAutostart", @"NO"]];
    [self assertSettingsShownIn:app];
    XCTAssertFalse([app.switches[@"ISFAutostartSwitch"].value boolValue]);
}

- (void)testPauseResumeRestartAndSettings {
    XCUIApplication *app = [self launchWithArguments:@[@"-ISFUseAllPhotos", @"YES", @"-ISFInterval", @"3600",
                                                       @"-ISFOrder", @"1"]];
    XCTAssertEqualObjects([self waitForPhotoIn:app differentFrom:nil], @"A-0");
    XCUIElement *image = [self imageIn:app];
    [image swipeLeft];
    XCTAssertEqualObjects([self waitForPhotoIn:app differentFrom:@"A-0"], @"A-1");

    [image tap];
    XCUIElement *menu = app.alerts[@"Paused"];
    XCTAssertTrue([menu waitForExistenceWithTimeout:5]);
    [menu.buttons[@"Resume"] tap];
    XCTAssertFalse(menu.exists);
    XCTAssertEqualObjects(image.value, @"A-1");

    [image tap];
    XCTAssertTrue([menu waitForExistenceWithTimeout:5]);
    [menu.buttons[@"Restart"] tap];
    XCTAssertEqualObjects([self waitForPhotoIn:app differentFrom:@"A-1"], @"A-0");

    [image tap];
    XCTAssertTrue([menu waitForExistenceWithTimeout:5]);
    [menu.buttons[@"Settings"] tap];
    [self assertSettingsShownIn:app];
    [app.cells[@"ISFStartCell"] tap];
    // Starting from the settings continues the cycle.
    XCTAssertEqualObjects([self waitForPhotoIn:app differentFrom:@"A-0"], @"A-1");
}

- (void)testRelaunchContinuesCycle {
    NSArray *settings = @[@"-ISFDemo", @"YES", @"-ISFUseAllPhotos", @"YES", @"-ISFInterval", @"3600", @"-ISFOrder", @"1"];
    XCUIApplication *app = [self launchWithArguments:settings];
    XCTAssertEqualObjects([self waitForPhotoIn:app differentFrom:nil], @"A-0");
    [[self imageIn:app] swipeLeft];
    XCTAssertEqualObjects([self waitForPhotoIn:app differentFrom:@"A-0"], @"A-1");
    // Like the photo frame scripts: the device is locked (the app saves its state) before the app is killed.
    [[XCUIDevice sharedDevice] pressButton:XCUIDeviceButtonHome];
    [NSThread sleepForTimeInterval:1];
    [app terminate];

    XCUIApplication *again = [XCUIApplication new];
    again.launchArguments = settings;
    [again launch];
    XCTAssertEqualObjects([self waitForPhotoIn:again differentFrom:nil], @"A-2");
}

- (void)testURLStartContinuesCycle {
    NSArray *settings = @[@"-ISFDemo", @"YES", @"-ISFUseAllPhotos", @"YES", @"-ISFInterval", @"3600", @"-ISFOrder", @"1"];
    XCUIApplication *first = [self launchWithArguments:settings];
    XCTAssertEqualObjects([self waitForPhotoIn:first differentFrom:nil], @"A-0");
    [first terminate];

    XCUIApplication *app = [XCUIApplication new];
    app.launchArguments = settings; // no settings reset from here on
    [app launch];
    XCTAssertEqualObjects([self waitForPhotoIn:app differentFrom:nil], @"A-1");
    NSString *process = [self imageIn:app].label; // "pid N" in debug builds
    if (@available(iOS 16.4, *)) {
        [app openURL:[NSURL URLWithString:@"ishuffleframe://start"]];
    } else {
        XCTSkip(@"XCUIApplication.openURL needs iOS 16.4");
    }
    XCTAssertTrue([[self imageIn:app] waitForExistenceWithTimeout:10]);
    [NSThread sleepForTimeInterval:2];
    if ([[self imageIn:app].label isEqualToString:process]) {
        // The running slideshow ignores the start command.
        XCTAssertEqualObjects([self imageIn:app].value, @"A-1");
    } else {
        // XCUITest relaunched the app with the URL (like a killed app opened by a script): the cycle continues.
        XCTAssertEqualObjects([self imageIn:app].value, @"A-2");
    }
}

- (void)testIntervalPicker {
    XCUIApplication *app = [self launchWithArguments:@[]];
    [self assertSettingsShownIn:app];
    XCTAssertTrue(app.cells[@"ISFIntervalCell"].staticTexts[@"20 s"].exists);
    [app.cells[@"ISFIntervalCell"] tap];
    [app.staticTexts[@"5 min"] tap];
    XCTAssertTrue([app.cells[@"ISFIntervalCell"].staticTexts[@"5 min"] waitForExistenceWithTimeout:5]);
}

- (void)testSettingsPersistAcrossLaunches {
    XCUIApplication *app = [self launchWithArguments:@[]];
    [self assertSettingsShownIn:app];
    [app.cells[@"ISFAllPhotosCell"] tap];
    [app.switches[@"ISFAutostartSwitch"] tap]; // off
    [app terminate];

    XCUIApplication *again = [XCUIApplication new];
    again.launchArguments = @[@"-ISFDemo", @"YES"];
    [again launch];
    [self assertSettingsShownIn:again];
    XCTAssertFalse([again.switches[@"ISFAutostartSwitch"].value boolValue]);
    [again.switches[@"ISFAutostartSwitch"] tap]; // on
    [again terminate];
    [again launch];
    [self waitForPhotoIn:again differentFrom:nil];
}

- (void)testURLSchemeStartsSlideshow {
    XCUIApplication *app = [self launchWithArguments:@[@"-ISFUseAllPhotos", @"YES", @"-ISFAutostart", @"NO"]];
    [self assertSettingsShownIn:app];
    if (@available(iOS 16.4, *)) {
        [app openURL:[NSURL URLWithString:@"ishuffleframe://start"]];
    } else {
        XCTSkip(@"XCUIApplication.openURL needs iOS 16.4");
    }
    [self waitForPhotoIn:app differentFrom:nil];
    XCTAssertTrue([app.cells[@"ISFStartCell"] waitForNonExistenceWithTimeout:5]);
}

@end
