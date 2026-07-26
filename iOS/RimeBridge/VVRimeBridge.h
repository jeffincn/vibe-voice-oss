#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Outcome of feeding a single key to librime.
@interface VVRimeKeyResult : NSObject

/// NO when librime did not consume the key, in which case the host is
/// responsible for it. Dropping unhandled keys silently loses input.
@property(nonatomic, readonly) BOOL handled;

/// Text librime committed as a direct consequence of this key. librime has
/// already removed it from the composition, so the host must insert it now.
@property(nonatomic, readonly, nullable, copy) NSString *commit;

@end

/// Minimal Objective-C++ boundary around librime's versioned C API.
///
/// The keyboard and containing app compile this boundary separately because
/// they run in different processes. Rime data is shared through the App Group.
@interface VVRimeBridge : NSObject

/// @param userDataDirectory Where this process keeps its own user dictionary.
///   librime stores it in a LevelDB, which allows one writer, so the app and
///   the keyboard must not be pointed at the same directory.
/// @param stagingDirectory Where to read schemas compiled by another process.
///   Pass nil to use librime's default of `userDataDirectory/build`.
- (nullable instancetype)initWithSharedDataDirectory:(NSString *)sharedDataDirectory
                                   userDataDirectory:(NSString *)userDataDirectory
                                    stagingDirectory:(nullable NSString *)stagingDirectory
                                          schemaID:(NSString *)schemaID
                                  performMaintenance:(BOOL)performMaintenance
                                           fullCheck:(BOOL)fullCheck
                                               error:(NSError * _Nullable * _Nullable)error
    NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/// Keys: preedit (NSString), candidates (NSArray<NSDictionary *>),
/// highlightedIndex (NSNumber).
- (NSDictionary<NSString *, id> *)snapshot;

- (VVRimeKeyResult *)processKeyCode:(NSInteger)keyCode;
- (nullable NSString *)selectCandidateAtIndex:(NSInteger)index;
- (nullable NSString *)commitComposition;
- (void)clearComposition;

@end

NS_ASSUME_NONNULL_END
