#import "ISFDemoSource.h"

@implementation ISFDemoSource

@synthesize changeHandler = _changeHandler;

static NSArray<NSString *> *ISFDemoItems(NSString *prefix, NSUInteger count) {
    NSMutableArray<NSString *> *items = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [items addObject:[NSString stringWithFormat:@"%@-%lu", prefix, (unsigned long)i]];
    return items;
}

static NSDictionary<NSString *, NSArray<NSString *> *> *ISFDemoAlbums(void) {
    return @{@"demo-a": ISFDemoItems(@"A", 10), @"demo-b": ISFDemoItems(@"B", 5)};
}

- (ISFAuthorization)authorization { return ISFAuthorizationAuthorized; }

- (void)requestAuthorization:(void (^)(ISFAuthorization))completion {
    dispatch_async(dispatch_get_main_queue(), ^{ completion(ISFAuthorizationAuthorized); });
}

- (NSArray<ISFAlbum *> *)albums {
    NSMutableArray<ISFAlbum *> *albums = [NSMutableArray array];
    NSDictionary *content = ISFDemoAlbums();
    for (NSString *identifier in @[@"demo-a", @"demo-b"]) {
        ISFAlbum *album = [ISFAlbum new];
        album.identifier = identifier;
        album.title = [identifier isEqualToString:@"demo-a"] ? @"Demo A" : @"Demo B";
        album.kind = [identifier isEqualToString:@"demo-a"] ? ISFAlbumKindShared : ISFAlbumKindRegular;
        album.count = [content[identifier] count];
        [albums addObject:album];
    }
    return albums;
}

- (NSArray<NSString *> *)itemIDsForAllPhotos:(BOOL)allPhotos albumIDs:(NSArray<NSString *> *)albumIDs {
    NSDictionary<NSString *, NSArray<NSString *> *> *content = ISFDemoAlbums();
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (NSString *identifier in @[@"demo-a", @"demo-b"]) {
        if (allPhotos || [albumIDs containsObject:identifier]) [items addObjectsFromArray:content[identifier]];
    }
    return items;
}

- (void)cancelImageRequest:(NSInteger)requestID {}

- (NSInteger)requestImageForItem:(NSString *)item targetSize:(CGSize)targetSize completion:(void (^)(UIImage *))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // A 4:3 landscape "photo" for A-items, a 3:4 portrait one for B-items.
        BOOL portrait = [item hasPrefix:@"B"];
        CGSize size = portrait ? CGSizeMake(600, 800) : CGSizeMake(800, 600);
        CGFloat hue = (CGFloat)(item.hash % 360) / 360.0;

        UIGraphicsBeginImageContextWithOptions(size, YES, 1);
        [[UIColor colorWithHue:hue saturation:0.5 brightness:0.8 alpha:1] setFill];
        UIRectFill(CGRectMake(0, 0, size.width, size.height));
        NSDictionary *attributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:120],
                                     NSForegroundColorAttributeName: [UIColor whiteColor]};
        CGSize textSize = [item sizeWithAttributes:attributes];
        [item drawAtPoint:CGPointMake((size.width - textSize.width) / 2, (size.height - textSize.height) / 2)
           withAttributes:attributes];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        UIImage *prepared = ISFPreparedImage(image, targetSize);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(prepared); });
    });
    return 0;
}

@end
