#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Minimal Objective-C++ boundary around librime's versioned C API.
///
/// The keyboard and containing app compile this boundary separately because
/// they run in different processes. Rime data is shared through the App Group.
@interface VVRimeBridge : NSObject

- (nullable instancetype)initWithSharedDataDirectory:(NSString *)sharedDataDirectory
                                   userDataDirectory:(NSString *)userDataDirectory
                                  performMaintenance:(BOOL)performMaintenance
                                               error:(NSError * _Nullable * _Nullable)error
    NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/// Keys: preedit (NSString), candidates (NSArray<NSDictionary *>),
/// highlightedIndex (NSNumber).
- (NSDictionary<NSString *, id> *)snapshot;

/// Returns committed text when librime commits as a consequence of the key.
- (nullable NSString *)processKeyCode:(NSInteger)keyCode;
- (nullable NSString *)selectCandidateAtIndex:(NSInteger)index;
- (nullable NSString *)commitComposition;
- (void)clearComposition;

@end

NS_ASSUME_NONNULL_END
