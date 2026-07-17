#import "ObjCExceptionCatcher.h"

BOOL VVPerformThrowingBlock(void (^block)(void), NSError *_Nullable *_Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSString *message = exception.reason ?: exception.name ?: @"Audio engine exception";
            *error = [NSError errorWithDomain:@"app.vibevoice.oss.macos"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }
}
