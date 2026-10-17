#import <XCTest/XCTest.h>
#import "ISFPhotoSource.h"

static NSData *ISFBytes(NSArray<NSNumber *> *bytes) {
    NSMutableData *data = [NSMutableData dataWithCapacity:bytes.count];
    for (NSNumber *byte in bytes) {
        uint8_t value = byte.unsignedCharValue;
        [data appendBytes:&value length:1];
    }
    return data;
}

@interface ISFImageTests : XCTestCase
@end

@implementation ISFImageTests

- (void)testJFIFSegmentIsRemoved {
    NSData *data = ISFBytes(@[@0xFF, @0xD8,
                              @0xFF, @0xE0, @0x00, @0x07, @'J', @'F', @'I', @'F', @0x00,
                              @0xFF, @0xE1, @0x00, @0x04, @0x01, @0x02,
                              @0xFF, @0xDA, @0x00, @0x02, @0x33, @0xFF, @0xD9]);
    NSData *expected = ISFBytes(@[@0xFF, @0xD8,
                                  @0xFF, @0xE1, @0x00, @0x04, @0x01, @0x02,
                                  @0xFF, @0xDA, @0x00, @0x02, @0x33, @0xFF, @0xD9]);
    XCTAssertEqualObjects(ISFImageDataWithoutJFIF(data), expected);
}

- (void)testOtherDataIsKept {
    NSData *exifOnly = ISFBytes(@[@0xFF, @0xD8, @0xFF, @0xE1, @0x00, @0x04, @0x01, @0x02, @0xFF, @0xDA, @0x00, @0x02]);
    XCTAssertEqualObjects(ISFImageDataWithoutJFIF(exifOnly), exifOnly);
    NSData *png = ISFBytes(@[@0x89, @'P', @'N', @'G', @0x0D, @0x0A]);
    XCTAssertEqualObjects(ISFImageDataWithoutJFIF(png), png);
    NSData *truncated = ISFBytes(@[@0xFF, @0xD8, @0xFF, @0xE0, @0x00, @0x40, @'J', @'F']);
    XCTAssertEqualObjects(ISFImageDataWithoutJFIF(truncated), truncated);
    XCTAssertEqualObjects(ISFImageDataWithoutJFIF([NSData data]), [NSData data]);
}

- (void)testDecodedImageIsScaledDown {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(400, 200) format:format];
    NSData *jpeg = [renderer JPEGDataWithCompressionQuality:0.9 actions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor redColor] setFill];
        [context fillRect:CGRectMake(0, 0, 400, 200)];
    }];

    UIImage *image = ISFDecodedImage(jpeg, 100);
    XCTAssertNotNil(image);
    XCTAssertEqual(CGImageGetWidth(image.CGImage), 100u);
    XCTAssertEqual(CGImageGetHeight(image.CGImage), 50u);

    uint8_t pixel[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space, kCGImageAlphaNoneSkipLast);
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), image.CGImage);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    XCTAssertGreaterThan(pixel[0], 200);
    XCTAssertLessThan(pixel[1], 50);
}

- (void)testUndecodableDataGivesNil {
    XCTAssertNil(ISFDecodedImage([@"not an image" dataUsingEncoding:NSUTF8StringEncoding], 100));
}

@end
