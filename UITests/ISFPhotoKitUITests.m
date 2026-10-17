#import <XCTest/XCTest.h>

/// Smoke tests against the real photo library of the simulator (it ships with sample photos).
/// The tests answer the Photos permission prompt themselves.
@interface ISFPhotoKitUITests : XCTestCase
@end

@implementation ISFPhotoKitUITests

- (void)setUp {
    self.continueAfterFailure = NO;
}

- (XCUIApplication *)launchWithArguments:(NSArray<NSString *> *)arguments {
    XCUIApplication *app = [XCUIApplication new];
    app.launchArguments = [@[@"-ISFResetSettings", @"YES"] arrayByAddingObjectsFromArray:arguments];
    [app launch];
    return app;
}

/// Taps the full-access button of the Photos permission prompt if it shows up.
- (void)allowPhotosIfAskedIn:(XCUIApplication *)app {
    XCUIApplication *springboard = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.apple.springboard"];
    for (NSString *title in @[@"Allow Full Access", @"Allow Access to All Photos", @"OK"]) {
        for (XCUIApplication *owner in @[springboard, app]) {
            XCUIElement *button = owner.buttons[title];
            if ([button waitForExistenceWithTimeout:title == (id)@"Allow Full Access" ? 5 : 1]) {
                [button tap];
                return;
            }
        }
    }
}

- (NSString *)waitForPhotoIn:(XCUIApplication *)app differentFrom:(NSString *)previous timeout:(NSTimeInterval)timeout {
    XCUIElement *image = app.images[@"ISFSlideshowImage"];
    XCTAssertTrue([image waitForExistenceWithTimeout:timeout]);
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(XCUIElement *element, NSDictionary *bindings) {
        NSString *value = element.value;
        return value.length > 0 && ![value isEqualToString:previous];
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc] initWithPredicate:predicate object:image];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[expectation] timeout:timeout], XCTWaiterResultCompleted,
                   @"photo did not change from %@", previous);
    return image.value;
}

- (void)testAllPhotosSlideshow {
    XCUIApplication *app = [self launchWithArguments:@[@"-ISFUseAllPhotos", @"YES", @"-ISFInterval", @"2"]];
    [self allowPhotosIfAskedIn:app];
    NSString *first = [self waitForPhotoIn:app differentFrom:nil timeout:20];
    XCTAssertFalse(app.staticTexts[@"ISFSlideshowMessage"].exists && app.staticTexts[@"ISFSlideshowMessage"].isHittable);
    [self waitForPhotoIn:app differentFrom:first timeout:20];

    XCTAttachment *shot = [XCTAttachment attachmentWithScreenshot:[XCUIScreen mainScreen].screenshot];
    shot.name = @"photokit-slideshow";
    shot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:shot];
}

- (void)testAlbumPickerListsLibraryAlbums {
    XCUIApplication *app = [self launchWithArguments:@[@"-ISFInterval", @"2"]];
    XCTAssertTrue([app.cells[@"ISFAlbumsCell"] waitForExistenceWithTimeout:10]);
    [app.cells[@"ISFAlbumsCell"] tap];
    [self allowPhotosIfAskedIn:app];

    NSPredicate *albumCells = [NSPredicate predicateWithFormat:@"identifier BEGINSWITH 'ISFAlbum-'"];
    XCUIElement *firstAlbum = [app.cells matchingPredicate:albumCells].firstMatch;
    XCTAssertTrue([firstAlbum waitForExistenceWithTimeout:10]);

    XCTAttachment *shot = [XCTAttachment attachmentWithScreenshot:[XCUIScreen mainScreen].screenshot];
    shot.name = @"photokit-albums";
    shot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:shot];

    [firstAlbum tap];
    [app.navigationBars.buttons.firstMatch tap];
    [app.cells[@"ISFStartCell"] tap];
    [self waitForPhotoIn:app differentFrom:nil timeout:20];
}

@end
