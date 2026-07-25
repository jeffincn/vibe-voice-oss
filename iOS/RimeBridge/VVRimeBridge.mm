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
std::string gSharedDataDirectory;
std::string gUserDataDirectory;
RimeApi *gAPI = nullptr;

NSError *VVRimeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:VVRimeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

void InitializeStruct(void *value, size_t size) {
    memset(value, 0, size);
    *static_cast<int *>(value) = static_cast<int>(size - sizeof(int));
}

NSString *TakeCommit(RimeSessionId session) {
    if (!gAPI || !gAPI->get_commit || !gAPI->free_commit) {
        return nil;
    }
    RimeCommit commit;
    InitializeStruct(&commit, sizeof(commit));
    if (!gAPI->get_commit(session, &commit)) {
        return nil;
    }
    NSString *text = commit.text ? [NSString stringWithUTF8String:commit.text] : nil;
    gAPI->free_commit(&commit);
    return text.length > 0 ? text : nil;
}

}  // namespace

@interface VVRimeBridge ()
@property(nonatomic, assign) RimeSessionId session;
@end

@implementation VVRimeBridge

- (nullable instancetype)initWithSharedDataDirectory:(NSString *)sharedDataDirectory
                                   userDataDirectory:(NSString *)userDataDirectory
                                  performMaintenance:(BOOL)performMaintenance
                                               error:(NSError **)error {
    self = [super init];
    if (!self) {
        return nil;
    }

    {
        std::lock_guard<std::mutex> lock(gRuntimeMutex);
        if (!gRuntimeInitialized) {
            gAPI = rime_get_api();
            if (!gAPI || !gAPI->setup || !gAPI->initialize) {
                if (error) {
                    *error = VVRimeError(kVVRimeErrorUnavailable, @"librime API 不可用。");
                }
                return nil;
            }

            gSharedDataDirectory = sharedDataDirectory.UTF8String ?: "";
            gUserDataDirectory = userDataDirectory.UTF8String ?: "";
            RimeTraits traits;
            InitializeStruct(&traits, sizeof(traits));
            traits.shared_data_dir = gSharedDataDirectory.c_str();
            traits.user_data_dir = gUserDataDirectory.c_str();
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
    }

    if (performMaintenance && gAPI->start_maintenance) {
        if (!gAPI->start_maintenance(True)) {
            if (error) {
                *error = VVRimeError(kVVRimeErrorMaintenance, @"Rime 词库部署启动失败。");
            }
            return nil;
        }
        if (gAPI->join_maintenance_thread) {
            gAPI->join_maintenance_thread();
        }
    }

    self.session = gAPI->create_session ? gAPI->create_session() : 0;
    if (!self.session) {
        if (error) {
            *error = VVRimeError(kVVRimeErrorSession, @"Rime 会话创建失败。请先在主应用准备词库。");
        }
        return nil;
    }
    if (!gAPI->select_schema ||
        !gAPI->select_schema(self.session, "vibe_pinyin")) {
        gAPI->destroy_session(self.session);
        self.session = 0;
        if (error) {
            *error = VVRimeError(kVVRimeErrorSchema, @"Rime 拼音方案尚未部署。");
        }
        return nil;
    }
    return self;
}

- (void)dealloc {
    if (self.session && gAPI && gAPI->destroy_session) {
        gAPI->destroy_session(self.session);
    }
}

- (NSDictionary<NSString *, id> *)snapshot {
    if (!self.session || !gAPI || !gAPI->get_context || !gAPI->free_context) {
        return @{@"preedit": @"", @"candidates": @[], @"highlightedIndex": @0};
    }

    RimeContext context;
    InitializeStruct(&context, sizeof(context));
    if (!gAPI->get_context(self.session, &context)) {
        return @{@"preedit": @"", @"candidates": @[], @"highlightedIndex": @0};
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
    gAPI->free_context(&context);
    return @{
        @"preedit": preedit ?: @"",
        @"candidates": candidates,
        @"highlightedIndex": @(highlighted > 0 ? highlighted : 0),
    };
}

- (nullable NSString *)processKeyCode:(NSInteger)keyCode {
    if (!self.session || !gAPI || !gAPI->process_key) {
        return nil;
    }
    gAPI->process_key(self.session, static_cast<int>(keyCode), 0);
    return TakeCommit(self.session);
}

- (nullable NSString *)selectCandidateAtIndex:(NSInteger)index {
    if (!self.session || index < 0 || !gAPI || !gAPI->select_candidate) {
        return nil;
    }
    if (!gAPI->select_candidate(self.session, static_cast<size_t>(index))) {
        return nil;
    }
    return TakeCommit(self.session);
}

- (nullable NSString *)commitComposition {
    if (!self.session || !gAPI || !gAPI->commit_composition) {
        return nil;
    }
    if (!gAPI->commit_composition(self.session)) {
        return nil;
    }
    return TakeCommit(self.session);
}

- (void)clearComposition {
    if (self.session && gAPI && gAPI->clear_composition) {
        gAPI->clear_composition(self.session);
    }
}

@end
