#import "ISFImageLoader.h"

@interface ISFImageLoad : NSObject
@property (nonatomic) NSInteger requestID;
@property (nonatomic, strong) NSMutableArray<void (^)(UIImage *)> *waiters;
@end

@implementation ISFImageLoad
@end

@implementation ISFImageLoader {
    id<ISFPhotoSource> _source;
    CGSize _targetSize;
    NSUInteger _capacity;
    NSMutableDictionary<NSString *, UIImage *> *_cache;
    NSMutableArray<NSString *> *_recent; // cached items, least recently used first
    NSMutableDictionary<NSString *, ISFImageLoad *> *_loads;
}

- (instancetype)initWithSource:(id<ISFPhotoSource>)source targetSize:(CGSize)targetSize capacity:(NSUInteger)capacity {
    if ((self = [super init])) {
        _source = source;
        _targetSize = targetSize;
        _capacity = MAX(capacity, (NSUInteger)1);
        _cache = [NSMutableDictionary dictionary];
        _recent = [NSMutableArray array];
        _loads = [NSMutableDictionary dictionary];
    }
    return self;
}

- (UIImage *)cachedImageForItem:(NSString *)item {
    UIImage *image = _cache[item];
    if (image) {
        [_recent removeObject:item];
        [_recent addObject:item];
    }
    return image;
}

- (void)loadItem:(NSString *)item completion:(void (^)(UIImage *))completion {
    UIImage *cached = [self cachedImageForItem:item];
    if (cached) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(cached); });
        return;
    }
    [[self startLoadOfItem:item].waiters addObject:[completion copy]];
}

- (void)stopWaitingForItem:(NSString *)item {
    [_loads[item].waiters removeAllObjects];
}

- (void)prefetchItems:(NSArray<NSString *> *)items {
    NSSet<NSString *> *wanted = [NSSet setWithArray:items];
    for (NSString *item in _loads.allKeys) {
        if (![wanted containsObject:item] && _loads[item].waiters.count == 0) [self cancelLoadOfItem:item];
    }
    for (NSString *item in items) {
        if (!_cache[item]) [self startLoadOfItem:item];
    }
}

- (void)dropItem:(NSString *)item {
    ISFImageLoad *load = _loads[item];
    if (!load) return;
    [self cancelLoadOfItem:item];
    for (void (^waiter)(UIImage *) in load.waiters) waiter(nil);
}

- (void)trimExceptItem:(NSString *)item {
    UIImage *kept = item ? _cache[item] : nil;
    [_cache removeAllObjects];
    [_recent removeAllObjects];
    if (kept) [self storeImage:kept forItem:item];
}

- (void)reset {
    for (NSString *item in _loads.allKeys) [self cancelLoadOfItem:item];
    [_cache removeAllObjects];
    [_recent removeAllObjects];
}

#pragma mark - Private

- (ISFImageLoad *)startLoadOfItem:(NSString *)item {
    ISFImageLoad *load = _loads[item];
    if (load) return load;
    load = [ISFImageLoad new];
    load.waiters = [NSMutableArray array];
    _loads[item] = load;
    __weak typeof(self) weakSelf = self;
    load.requestID = [_source requestImageForItem:item targetSize:_targetSize completion:^(UIImage *image) {
        [weakSelf load:load ofItem:item finishedWithImage:image];
    }];
    return load;
}

- (void)load:(ISFImageLoad *)load ofItem:(NSString *)item finishedWithImage:(UIImage *)image {
    if (_loads[item] != load) return; // cancelled or replaced
    [_loads removeObjectForKey:item];
    if (image) [self storeImage:image forItem:item];
    for (void (^waiter)(UIImage *) in load.waiters) waiter(image);
}

- (void)cancelLoadOfItem:(NSString *)item {
    ISFImageLoad *load = _loads[item];
    if (!load) return;
    [_loads removeObjectForKey:item];
    [_source cancelImageRequest:load.requestID];
}

- (void)storeImage:(UIImage *)image forItem:(NSString *)item {
    _cache[item] = image;
    [_recent removeObject:item];
    [_recent addObject:item];
    while (_recent.count > _capacity) {
        [_cache removeObjectForKey:_recent.firstObject];
        [_recent removeObjectAtIndex:0];
    }
}

@end
