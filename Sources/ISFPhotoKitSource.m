#import "ISFPhotoKitSource.h"
#import <Photos/Photos.h>

/// Library changes come in bursts while iCloud syncs: report them after a 2 s pause, but at least every 10 s.
static const NSTimeInterval ISFChangeDelay = 2;
static const NSTimeInterval ISFChangeMaxDelay = 10;

@interface ISFPhotoKitSource () <PHPhotoLibraryChangeObserver>
@end

@implementation ISFPhotoKitSource {
    BOOL _observing;
    NSDate *_firstPendingChange;
}

@synthesize changeHandler = _changeHandler;

- (void)dealloc {
    if (_observing) [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}

#pragma mark - Authorization

static ISFAuthorization ISFAuthorizationFromStatus(PHAuthorizationStatus status) {
    switch (status) {
        case PHAuthorizationStatusNotDetermined: return ISFAuthorizationNotDetermined;
        case PHAuthorizationStatusRestricted:
        case PHAuthorizationStatusDenied: return ISFAuthorizationDenied;
        default: return ISFAuthorizationAuthorized; // authorized, or limited on iOS 14+
    }
}

- (ISFAuthorization)authorization {
    ISFAuthorization status = ISFAuthorizationFromStatus([PHPhotoLibrary authorizationStatus]);
    if (status == ISFAuthorizationAuthorized) [self startObserving];
    return status;
}

- (void)requestAuthorization:(void (^)(ISFAuthorization))completion {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ISFAuthorization result = ISFAuthorizationFromStatus(status);
            if (result == ISFAuthorizationAuthorized) [self startObserving];
            completion(result);
        });
    }];
}

#pragma mark - Albums

static PHFetchOptions *ISFImageOptions(BOOL sorted) {
    PHFetchOptions *options = [PHFetchOptions new];
    options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %ld", (long)PHAssetMediaTypeImage];
    if (sorted) options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES]];
    return options;
}

static ISFAlbumKind ISFKindForCollection(PHAssetCollection *collection) {
    if (collection.assetCollectionType == PHAssetCollectionTypeSmartAlbum) return ISFAlbumKindSmart;
    switch (collection.assetCollectionSubtype) {
        case PHAssetCollectionSubtypeAlbumCloudShared: return ISFAlbumKindShared;
        case PHAssetCollectionSubtypeAlbumRegular: return ISFAlbumKindRegular;
        default: return ISFAlbumKindOther;
    }
}

- (NSArray<ISFAlbum *> *)albums {
    if ([self authorization] != ISFAuthorizationAuthorized) return @[];

    NSMutableArray<ISFAlbum *> *albums = [NSMutableArray array];
    PHFetchOptions *imageOptions = ISFImageOptions(NO);
    void (^collect)(PHAssetCollectionType) = ^(PHAssetCollectionType type) {
        PHFetchResult<PHAssetCollection *> *collections =
            [PHAssetCollection fetchAssetCollectionsWithType:type subtype:PHAssetCollectionSubtypeAny options:nil];
        for (PHAssetCollection *collection in collections) {
            NSUInteger count = [PHAsset fetchAssetsInAssetCollection:collection options:imageOptions].count;
            ISFAlbumKind kind = ISFKindForCollection(collection);
            // Smart albums are many and mostly empty (Videos, Slo-mo, ...); show only those with photos.
            if (kind == ISFAlbumKindSmart && count == 0) continue;
            ISFAlbum *album = [ISFAlbum new];
            album.identifier = collection.localIdentifier;
            album.title = collection.localizedTitle.length ? collection.localizedTitle : @"Untitled";
            album.kind = kind;
            album.count = count;
            [albums addObject:album];
        }
    };
    collect(PHAssetCollectionTypeAlbum);
    collect(PHAssetCollectionTypeSmartAlbum);
    return albums;
}

#pragma mark - Items

- (NSArray<NSString *> *)itemIDsForAllPhotos:(BOOL)allPhotos albumIDs:(NSArray<NSString *> *)albumIDs {
    // May run off the main thread: check the status directly instead of -authorization, which registers
    // the change observer.
    if (ISFAuthorizationFromStatus([PHPhotoLibrary authorizationStatus]) != ISFAuthorizationAuthorized) return @[];

    PHFetchOptions *options = ISFImageOptions(YES);
    if (allPhotos) {
        PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsWithOptions:options];
        NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:assets.count];
        for (PHAsset *asset in assets) [ids addObject:asset.localIdentifier];
        return ids;
    }

    if (albumIDs.count == 0) return @[];
    NSMutableDictionary<NSString *, PHAsset *> *byID = [NSMutableDictionary dictionary];
    PHFetchResult<PHAssetCollection *> *collections =
        [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:albumIDs options:nil];
    for (PHAssetCollection *collection in collections) {
        for (PHAsset *asset in [PHAsset fetchAssetsInAssetCollection:collection options:options]) {
            byID[asset.localIdentifier] = asset;
        }
    }
    NSArray<PHAsset *> *assets = [byID.allValues sortedArrayUsingComparator:^NSComparisonResult(PHAsset *a, PHAsset *b) {
        NSDate *da = a.creationDate ?: [NSDate distantPast];
        NSDate *db = b.creationDate ?: [NSDate distantPast];
        NSComparisonResult result = [da compare:db];
        return result != NSOrderedSame ? result : [a.localIdentifier compare:b.localIdentifier];
    }];
    return [assets valueForKey:@"localIdentifier"];
}

- (NSInteger)requestImageForItem:(NSString *)item
                      targetSize:(CGSize)targetSize
                      completion:(void (^)(UIImage *))completion {
    PHAsset *asset = [PHAsset fetchAssetsWithLocalIdentifiers:@[item] options:nil].firstObject;
    if (!asset) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return PHInvalidImageRequestID;
    }
    PHImageRequestOptions *options = [PHImageRequestOptions new];
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    options.resizeMode = PHImageRequestOptionsResizeModeFast;
    options.networkAccessAllowed = YES;
    return [[PHImageManager defaultManager] requestImageForAsset:asset
                                               targetSize:targetSize
                                              contentMode:PHImageContentModeAspectFit
                                                  options:options
                                            resultHandler:^(UIImage *image, NSDictionary *info) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            UIImage *prepared = image ? ISFPreparedImage(image, targetSize) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(prepared); });
        });
    }];
}

- (void)cancelImageRequest:(NSInteger)requestID {
    if (requestID != PHInvalidImageRequestID) [[PHImageManager defaultManager] cancelImageRequest:(PHImageRequestID)requestID];
}

#pragma mark - Changes

- (void)startObserving {
    if (_observing) return;
    _observing = YES;
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
}

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_firstPendingChange) self->_firstPendingChange = [NSDate date];
        NSTimeInterval waited = -[self->_firstPendingChange timeIntervalSinceNow];
        NSTimeInterval delay = MAX(0, MIN(ISFChangeDelay, ISFChangeMaxDelay - waited));
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(notifyChange) object:nil];
        [self performSelector:@selector(notifyChange) withObject:nil afterDelay:delay];
    });
}

- (void)notifyChange {
    _firstPendingChange = nil;
    if (self.changeHandler) self.changeHandler();
}

@end
