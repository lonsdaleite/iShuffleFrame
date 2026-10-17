#import "ISFPhotoSource.h"
#import <ImageIO/ImageIO.h>

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

NSData *ISFImageDataWithoutJFIF(NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    if (length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return data;
    NSUInteger i = 2;
    // Walk the header segments up to the image data (start of scan).
    while (i + 4 <= length && bytes[i] == 0xFF && bytes[i + 1] != 0xDA) {
        NSUInteger segment = 2 + (((NSUInteger)bytes[i + 2] << 8) | bytes[i + 3]);
        if (segment < 4 || i + segment > length) return data;
        BOOL jfif = bytes[i + 1] == 0xE0 && segment >= 9 &&
                    bytes[i + 4] == 'J' && bytes[i + 5] == 'F' && bytes[i + 6] == 'I' && bytes[i + 7] == 'F' && bytes[i + 8] == 0;
        if (jfif) {
            NSMutableData *result = [NSMutableData dataWithCapacity:length - segment];
            [result appendBytes:bytes length:i];
            [result appendBytes:bytes + i + segment length:length - i - segment];
            return result;
        }
        i += segment;
    }
    return data;
}

UIImage *ISFDecodedImage(NSData *data, CGFloat maxPixelSize) {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)ISFImageDataWithoutJFIF(data), NULL);
    if (!source) return nil;
    NSDictionary *options = @{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                              (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
                              (id)kCGImageSourceThumbnailMaxPixelSize: @(MAX(1, maxPixelSize))};
    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!thumbnail) return nil;
    UIImage *image = [UIImage imageWithCGImage:thumbnail];
    CGImageRelease(thumbnail);
    return ISFPreparedImage(image, CGSizeMake(maxPixelSize, maxPixelSize));
}

