#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ISFAlbumKind) {
    ISFAlbumKindShared = 0,
    ISFAlbumKindRegular,
    ISFAlbumKindSmart,
    ISFAlbumKindOther,
};

typedef NS_ENUM(NSInteger, ISFAuthorization) {
    ISFAuthorizationNotDetermined = 0,
    ISFAuthorizationDenied,
    ISFAuthorizationAuthorized,
};

@interface ISFAlbum : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) ISFAlbumKind kind;
/// Number of photos (videos are not counted).
@property (nonatomic) NSUInteger count;
@end

/// Where the slideshow takes photos from. Methods are called and callbacks arrive on the main thread, except
/// `itemIDsForAllPhotos:albumIDs:`, which may be called from a background queue.
@protocol ISFPhotoSource <NSObject>

- (ISFAuthorization)authorization;
- (void)requestAuthorization:(void (^)(ISFAuthorization status))completion;

/// Albums the user can pick from.
- (NSArray<ISFAlbum *> *)albums;

/// Photo identifiers in source order (oldest first). Videos are skipped. Thread-safe; may be slow on big libraries.
- (NSArray<NSString *> *)itemIDsForAllPhotos:(BOOL)allPhotos albumIDs:(NSArray<NSString *> *)albumIDs;

/// Loads a photo that fits into `targetSize` pixels and is ready to draw. The completion gets nil on failure.
/// Returns an identifier for `cancelImageRequest:`.
- (NSInteger)requestImageForItem:(NSString *)item
                      targetSize:(CGSize)targetSize
                      completion:(void (^)(UIImage *_Nullable image))completion;
/// Stops a request; its completion may still be called, with nil.
- (void)cancelImageRequest:(NSInteger)requestID;

/// Called after the library changes.
@property (nonatomic, copy, nullable) void (^changeHandler)(void);

@end

/// Redraws `image` into an opaque bitmap that fits into `maxSize` pixels, so that showing it does not decode
/// it on the main thread. Safe to call off the main thread.
UIImage *ISFPreparedImage(UIImage *image, CGSize maxSize);

/// Returns JPEG data without its JFIF (APP0) segment; other data is returned as is. Some JPEGs carry both JFIF
/// and Exif headers (photos of iCloud shared albums do), and the iOS 15 decoder on A8X turns them into black images.
NSData *ISFImageDataWithoutJFIF(NSData *data);

/// Decodes image file data into an opaque bitmap no larger than `maxPixelSize` on the longer side, with the Exif
/// orientation applied. Safe to call off the main thread.
UIImage *_Nullable ISFDecodedImage(NSData *data, CGFloat maxPixelSize);

NS_ASSUME_NONNULL_END
