#import "ISFSettings.h"

static NSString *const ISFUseAllPhotosKey = @"ISFUseAllPhotos";
static NSString *const ISFAlbumIDsKey = @"ISFAlbumIDs";
static NSString *const ISFOrderKey = @"ISFOrder";
static NSString *const ISFIntervalKey = @"ISFInterval";
static NSString *const ISFTransitionKey = @"ISFTransition";
static NSString *const ISFAutostartKey = @"ISFAutostart";

@implementation ISFSettings {
    NSUserDefaults *_defaults;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) {
        _defaults = defaults;
        [_defaults registerDefaults:@{
            ISFUseAllPhotosKey: @NO,
            ISFAlbumIDsKey: @[],
            ISFOrderKey: @(ISFOrderShuffle),
            ISFIntervalKey: @20,
            ISFTransitionKey: @(ISFTransitionNone),
            ISFAutostartKey: @YES,
        }];
    }
    return self;
}

- (BOOL)useAllPhotos { return [_defaults boolForKey:ISFUseAllPhotosKey]; }
- (void)setUseAllPhotos:(BOOL)value { [_defaults setBool:value forKey:ISFUseAllPhotosKey]; }

- (NSArray<NSString *> *)albumIDs {
    NSArray *ids = [_defaults arrayForKey:ISFAlbumIDsKey];
    NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:ids.count];
    for (id item in ids) {
        if ([item isKindOfClass:[NSString class]]) [result addObject:item];
    }
    return result;
}
- (void)setAlbumIDs:(NSArray<NSString *> *)value { [_defaults setObject:[value copy] forKey:ISFAlbumIDsKey]; }

- (ISFOrder)order {
    return [_defaults integerForKey:ISFOrderKey] == ISFOrderSequential ? ISFOrderSequential : ISFOrderShuffle;
}
- (void)setOrder:(ISFOrder)value { [_defaults setInteger:value forKey:ISFOrderKey]; }

- (NSTimeInterval)interval { return MAX(1, [_defaults doubleForKey:ISFIntervalKey]); }
- (void)setInterval:(NSTimeInterval)value { [_defaults setDouble:MAX(1, value) forKey:ISFIntervalKey]; }

- (ISFTransition)transition {
    return [_defaults integerForKey:ISFTransitionKey] == ISFTransitionFade ? ISFTransitionFade : ISFTransitionNone;
}
- (void)setTransition:(ISFTransition)value { [_defaults setInteger:value forKey:ISFTransitionKey]; }

- (BOOL)autostart { return [_defaults boolForKey:ISFAutostartKey]; }
- (void)setAutostart:(BOOL)value { [_defaults setBool:value forKey:ISFAutostartKey]; }

- (BOOL)hasSource { return self.useAllPhotos || self.albumIDs.count > 0; }

@end
