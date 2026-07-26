#import "VVRimeBridge.h"

#include <rime_api.h>

#include <cstring>
#include <mutex>
#include <string>

namespace {

constexpr NSInteger kVVRimeErrorUnavailable = 1;
constexpr NSInteger kVVRimeErrorMaintenance = 2;
constexpr NSInteger kVVRimeErrorSession = 3;
constexpr NSInteger kVVRimeErrorSchema = 4;

NSString *const VVRimeErrorDomain = @"app.vibevoice.oss.rime";

std::mutex gRuntimeMutex;
bool gRuntimeInitialized = false;
RimeApi *gAPI = nullptr;

/// The runtime is process global and initialised once. Every read goes through
/// the same mutex that guards the assignment.
RimeApi *CurrentAPI() {
    std::lock_guard<std::mutex> lock(gRuntimeMutex);
    return gAPI;
}

NSError *VVRimeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:VVRimeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

void InitializeStruct(void *value, size_t size) {
    memset(value, 0, size);
    *static_cast<int *>(value) = static_cast<int>(size - sizeof(int));
}

NSString *TakeCommit(RimeApi *api, RimeSessionId session) {
    if (!api || !api->get_commit || !api->free_commit) {
        return nil;
    }
    RimeCommit commit;
    InitializeStruct(&commit, sizeof(commit));
    if (!api->get_commit(session, &commit)) {
        return nil;
    }
    NSString *text = commit.text ? [NSString stringWithUTF8String:commit.text] : nil;
    api->free_commit(&commit);
    return text.length > 0 ? text : nil;
}

}  // namespace

@implementation VVRimeKeyResult

- (instancetype)initWithHandled:(BOOL)handled commit:(nullable NSString *)commit {
    self = [super init];
    if (self) {
        _handled = handled;
        _commit = [commit copy];
    }
    return self;
}

@end

@interface VVRimeBridge ()
@property(nonatomic, assign) RimeSessionId session;
@end

@implementation VVRimeBridge

- (nullable instancetype)initWithSharedDataDirectory:(NSString *)sharedDataDirectory
                                   userDataDirectory:(NSString *)userDataDirectory
                                    stagingDirectory:(nullable NSString *)stagingDirectory
                                  performMaintenance:(BOOL)performMaintenance
                                           fullCheck:(BOOL)fullCheck
                                               error:(NSError **)error {
    self = [super init];
    if (!self) {
        return nil;
    }

    RimeApi *api = nullptr;
    {
        std::lock_guard<std::mutex> lock(gRuntimeMutex);
        if (!gRuntimeInitialized) {
            gAPI = rime_get_api();
            if (!gAPI || !gAPI->setup || !gAPI->initialize) {
                gAPI = nullptr;
                if (error) {
                    *error = VVRimeError(kVVRimeErrorUnavailable, @"librime API 不可用。");
                }
                return nil;
            }

            // RimeSetup copies these into the deployer, but keeping the storage
            // alive for the duration of the call costs nothing and documents it.
            std::string shared = sharedDataDirectory.UTF8String ?: "";
            std::string user = userDataDirectory.UTF8String ?: "";
            std::string staging = stagingDirectory.UTF8String ?: "";
            RimeTraits traits;
            InitializeStruct(&traits, sizeof(traits));
            traits.shared_data_dir = shared.c_str();
            traits.user_data_dir = user.c_str();
            if (!staging.empty()) {
                traits.staging_dir = staging.c_str();
            }
            traits.distribution_name = "Vibe Voice";
            traits.distribution_code_name = "vibe_voice_ios";
            traits.distribution_version = "0.7.0";
            traits.app_name = "rime.vibevoice.ios";
            traits.min_log_level = 2;
            traits.log_dir = "";
            gAPI->setup(&traits);
            gAPI->initialize(&traits);
            gRuntimeInitialized = true;
        }
        api = gAPI;
    }

    if (performMaintenance && api->start_maintenance) {
        if (!api->start_maintenance(fullCheck ? True : False)) {
            if (error) {
                *error = VVRimeError(kVVRimeErrorMaintenance, @"Rime 词库部署启动失败。");
            }
            return nil;
        }
        if (api->join_maintenance_thread) {
            api->join_maintenance_thread();
        }
    }

    self.session = api->create_session ? api->create_session() : 0;
    if (!self.session) {
        if (error) {
            *error = VVRimeError(kVVRimeErrorSession, @"Rime 会话创建失败。请先在主应用准备词库。");
        }
        return nil;
    }
    if (!api->select_schema || !api->select_schema(self.session, "vibe_pinyin")) {
        api->destroy_session(self.session);
        self.session = 0;
        if (error) {
            *error = VVRimeError(kVVRimeErrorSchema, @"Rime 拼音方案尚未部署。");
        }
        return nil;
    }
    return self;
}

- (void)dealloc {
    RimeApi *api = CurrentAPI();
    if (self.session && api && api->destroy_session) {
        api->destroy_session(self.session);
    }
}

- (NSDictionary<NSString *, id> *)snapshot {
    NSDictionary<NSString *, id> *empty =
        @{@"preedit": @"", @"candidates": @[], @"highlightedIndex": @0};
    RimeApi *api = CurrentAPI();
    if (!self.session || !api || !api->get_context || !api->free_context) {
        return empty;
    }

    RimeContext context;
    InitializeStruct(&context, sizeof(context));
    if (!api->get_context(self.session, &context)) {
        return empty;
    }

    NSString *preedit = context.composition.preedit
        ? [NSString stringWithUTF8String:context.composition.preedit]
        : @"";
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *candidates =
        [NSMutableArray arrayWithCapacity:context.menu.num_candidates > 0
                                              ? context.menu.num_candidates
                                              : 0];
    for (int index = 0; index < context.menu.num_candidates; index++) {
        RimeCandidate candidate = context.menu.candidates[index];
        NSString *text = candidate.text
            ? [NSString stringWithUTF8String:candidate.text]
            : @"";
        NSString *comment = candidate.comment
            ? [NSString stringWithUTF8String:candidate.comment]
            : @"";
        [candidates addObject:@{@"text": text ?: @"", @"comment": comment ?: @""}];
    }
    NSInteger highlighted = context.menu.highlighted_candidate_index;
    api->free_context(&context);
    return @{
        @"preedit": preedit ?: @"",
        @"candidates": candidates,
        @"highlightedIndex": @(highlighted > 0 ? highlighted : 0),
    };
}

- (VVRimeKeyResult *)processKeyCode:(NSInteger)keyCode {
    RimeApi *api = CurrentAPI();
    if (!self.session || !api || !api->process_key) {
        return [[VVRimeKeyResult alloc] initWithHandled:NO commit:nil];
    }
    BOOL handled = api->process_key(self.session, static_cast<int>(keyCode), 0) != False;
    return [[VVRimeKeyResult alloc] initWithHandled:handled
                                             commit:TakeCommit(api, self.session)];
}

- (nullable NSString *)selectCandidateAtIndex:(NSInteger)index {
    RimeApi *api = CurrentAPI();
    if (!self.session || index < 0 || !api || !api->select_candidate) {
        return nil;
    }
    if (!api->select_candidate(self.session, static_cast<size_t>(index))) {
        return nil;
    }
    return TakeCommit(api, self.session);
}

- (nullable NSString *)commitComposition {
    RimeApi *api = CurrentAPI();
    if (!self.session || !api || !api->commit_composition) {
        return nil;
    }
    if (!api->commit_composition(self.session)) {
        return nil;
    }
    return TakeCommit(api, self.session);
}

- (void)clearComposition {
    RimeApi *api = CurrentAPI();
    if (self.session && api && api->clear_composition) {
        api->clear_composition(self.session);
    }
}

@end
