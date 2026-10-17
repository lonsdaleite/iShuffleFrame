#import "ISFCycleStore.h"

@implementation ISFCycleStore

+ (dispatch_queue_t)queue {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("ishuffleframe.cycle-store", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

+ (NSURL *)fileURL {
    NSURL *directory = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                              inDomains:NSUserDomainMask].firstObject;
    // Outside the sandbox (jailbreak build in /Applications) Application Support is shared, hence the subfolder.
    NSString *folder = [NSBundle mainBundle].bundleIdentifier ?: @"com.lonsdaleite.ishuffleframe";
    return [[directory URLByAppendingPathComponent:folder] URLByAppendingPathComponent:@"cycle.plist"];
}

+ (NSDictionary *)loadState {
    __block NSDictionary *state;
    dispatch_sync([self queue], ^{ state = [NSDictionary dictionaryWithContentsOfURL:[self fileURL]]; });
    return state;
}

+ (void)save:(NSDictionary *)state {
    dispatch_async([self queue], ^{ [self write:state]; });
}

+ (void)saveNow:(NSDictionary *)state {
    dispatch_sync([self queue], ^{ [self write:state]; });
}

/// Runs on the store queue.
+ (void)write:(NSDictionary *)state {
    {
        NSURL *url = [self fileURL];
        [[NSFileManager defaultManager] createDirectoryAtURL:url.URLByDeletingLastPathComponent
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:NULL];
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:state
                                                                  format:NSPropertyListBinaryFormat_v1_0
                                                                 options:0
                                                                   error:NULL];
        [data writeToURL:url atomically:YES];
    }
}

+ (void)clear {
    dispatch_sync([self queue], ^{ [[NSFileManager defaultManager] removeItemAtURL:[self fileURL] error:NULL]; });
}

@end
