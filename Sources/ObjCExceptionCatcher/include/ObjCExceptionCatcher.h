#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` inside `@try/@catch` so AVFAudio NSExceptions become NSError
/// instead of aborting the process (SIGABRT).
BOOL VVPerformThrowingBlock(void (^block)(void), NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
