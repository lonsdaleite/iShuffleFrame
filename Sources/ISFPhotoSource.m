#import "ISFPhotoSource.h"

@implementation ISFAlbum
@end

UIImage *ISFPreparedImage(UIImage *image, CGSize maxSize) {
    CGSize size = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
    if (size.width <= 0 || size.height <= 0) return image;
    CGFloat factor = MIN(1, MIN(maxSize.width / size.width, maxSize.height / size.height));
    CGSize target = CGSizeMake(MAX(1, floor(size.width * factor)), MAX(1, floor(size.height * factor)));

    UIGraphicsBeginImageContextWithOptions(target, YES, 1);
    [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result ?: image;
}
