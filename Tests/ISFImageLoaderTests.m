#import <XCTest/XCTest.h>
#import "ISFImageLoader.h"

/// Records requests; the test finishes them by hand.
@interface ISFFakeSource : NSObject <ISFPhotoSource>
@property (nonatomic, strong) NSMutableArray<NSString *> *requested;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *cancelled;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, void (^)(UIImage *)> *pending;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *requestIDs;
- (void)finishItem:(NSString *)item withImage:(UIImage *)image;
@end

@implementation ISFFakeSource {
    NSInteger _lastID;
}
@synthesize changeHandler;

- (instancetype)init {
    if ((self = [super init])) {
        _requested = [NSMutableArray array];
        _cancelled = [NSMutableArray array];
        _pending = [NSMutableDictionary dictionary];
        _requestIDs = [NSMutableDictionary dictionary];
    }
    return self;
}

- (ISFAuthorization)authorization { return ISFAuthorizationAuthorized; }
- (void)requestAuthorization:(void (^)(ISFAuthorization))completion { completion(ISFAuthorizationAuthorized); }
- (NSArray<ISFAlbum *> *)albums { return @[]; }
- (NSArray<NSString *> *)itemIDsForAllPhotos:(BOOL)allPhotos albumIDs:(NSArray<NSString *> *)albumIDs { return @[]; }

- (NSInteger)requestImageForItem:(NSString *)item targetSize:(CGSize)targetSize completion:(void (^)(UIImage *))completion {
    NSInteger requestID = ++_lastID;
    [_requested addObject:item];
    _pending[@(requestID)] = completion;
    _requestIDs[item] = @(requestID);
    return requestID;
}

- (void)cancelImageRequest:(NSInteger)requestID {
    [_cancelled addObject:@(requestID)];
}

- (void)finishItem:(NSString *)item withImage:(UIImage *)image {
    NSNumber *requestID = _requestIDs[item];
    void (^completion)(UIImage *) = _pending[requestID];
    [_pending removeObjectForKey:requestID];
    if (completion) completion(image);
}

@end

@interface ISFImageLoaderTests : XCTestCase
@end

@implementation ISFImageLoaderTests {
    ISFFakeSource *_source;
    ISFImageLoader *_loader;
    UIImage *_image;
}

- (void)setUp {
    _source = [ISFFakeSource new];
    _loader = [[ISFImageLoader alloc] initWithSource:_source targetSize:CGSizeMake(100, 100) capacity:3];
    _image = [UIImage new];
}

- (void)testWaitersShareOneRequestAndTheImageIsCached {
    __block NSUInteger calls = 0;
    [_loader loadItem:@"a" completion:^(UIImage *image) { calls++; }];
    [_loader loadItem:@"a" completion:^(UIImage *image) { calls++; }];
    XCTAssertEqualObjects(_source.requested, @[@"a"]);
    [_source finishItem:@"a" withImage:_image];
    XCTAssertEqual(calls, 2u);
    XCTAssertEqual([_loader cachedImageForItem:@"a"], _image);
}

- (void)testPrefetchedImageIsUsedByALaterLoad {
    [_loader prefetchItems:@[@"a", @"b"]];
    XCTAssertEqualObjects(_source.requested, (@[@"a", @"b"]));
    __block UIImage *loaded;
    [_loader loadItem:@"b" completion:^(UIImage *image) { loaded = image; }];
    XCTAssertEqual(_source.requested.count, 2u); // joins the running prefetch
    [_source finishItem:@"b" withImage:_image];
    XCTAssertEqual(loaded, _image);
}

- (void)testPrefetchCancelsLoadsNobodyNeeds {
    [_loader prefetchItems:@[@"a", @"b"]];
    [_loader loadItem:@"b" completion:^(UIImage *image) {}];
    [_loader prefetchItems:@[@"c"]];
    // a is not wanted any more; b is waited for.
    XCTAssertEqualObjects(_source.cancelled, (@[_source.requestIDs[@"a"]]));
    [_loader stopWaitingForItem:@"b"];
    [_loader prefetchItems:@[@"c"]];
    XCTAssertTrue([_source.cancelled containsObject:_source.requestIDs[@"b"]]);
}

- (void)testCacheKeepsTheMostRecentlyUsed {
    for (NSString *item in @[@"a", @"b", @"c"]) {
        [_loader prefetchItems:@[item]];
        [_source finishItem:item withImage:[UIImage new]];
    }
    [_loader cachedImageForItem:@"a"]; // used: b is now the oldest
    [_loader prefetchItems:@[@"d"]];
    [_source finishItem:@"d" withImage:[UIImage new]];
    XCTAssertNotNil([_loader cachedImageForItem:@"a"]);
    XCTAssertNil([_loader cachedImageForItem:@"b"]);
    XCTAssertNotNil([_loader cachedImageForItem:@"c"]);
    XCTAssertNotNil([_loader cachedImageForItem:@"d"]);
}

- (void)testDroppedLoadFailsItsWaitersAndIsRequestedAgain {
    __block BOOL failed = NO;
    [_loader loadItem:@"a" completion:^(UIImage *image) { failed = image == nil; }];
    [_loader dropItem:@"a"];
    XCTAssertTrue(failed);
    [_source finishItem:@"a" withImage:_image]; // a late answer of the dropped request is ignored
    XCTAssertNil([_loader cachedImageForItem:@"a"]);
    [_loader loadItem:@"a" completion:^(UIImage *image) {}];
    XCTAssertEqualObjects(_source.requested, (@[@"a", @"a"]));
}

- (void)testFailedLoadIsNotCached {
    __block BOOL called = NO;
    [_loader loadItem:@"a" completion:^(UIImage *image) { called = image == nil; }];
    [_source finishItem:@"a" withImage:nil];
    XCTAssertTrue(called);
    XCTAssertNil([_loader cachedImageForItem:@"a"]);
}

- (void)testCachedLoadCompletesAsynchronously {
    [_loader prefetchItems:@[@"a"]];
    [_source finishItem:@"a" withImage:_image];
    __block UIImage *loaded;
    XCTestExpectation *done = [self expectationWithDescription:@"loaded"];
    [_loader loadItem:@"a" completion:^(UIImage *image) { loaded = image; [done fulfill]; }];
    XCTAssertNil(loaded);
    [self waitForExpectations:@[done] timeout:1];
    XCTAssertEqual(loaded, _image);
}

- (void)testResetCancelsEverything {
    [_loader prefetchItems:@[@"a"]];
    [_source finishItem:@"a" withImage:_image];
    [_loader prefetchItems:@[@"b"]];
    [_loader reset];
    XCTAssertTrue([_source.cancelled containsObject:_source.requestIDs[@"b"]]);
    XCTAssertNil([_loader cachedImageForItem:@"a"]);
}

@end
