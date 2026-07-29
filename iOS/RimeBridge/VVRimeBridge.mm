#import "VVRimeBridge.h"

#include <rime_api.h>

#include <cstring>
#include <mutex>
#include <string>

namespace {

constexpr NSInteger kVVRimeErrorUnavailable = 1;
// 2 was a maintenance failure. librime cannot report one distinguishably, so
// the condition is no longer raised; see the deployment step below. The gap is
// deliberate, to keep these codes meaning the same thing in logs already taken.
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
                                          schemaID:(NSString *)schemaID
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
        // start_maintenance answers "did I schedule any work", not "did I
        // succeed". With full_check off librime runs detect_modifications
        // first and returns False when the build output is already newer than
        // every source file — the steady state after one successful deployment.
        // So there is only a maintenance thread to join when it returns True,
        // and a False is not something to report: it cannot be told apart from
        // an installation_update failure, and whether the workspace is usable
        // is settled below by opening a session and selecting the schema, which
        // is what the caller actually needs.
        if (api->start_maintenance(fullCheck ? True : False) &&
            api->join_maintenance_thread) {
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
    std::string selectedSchema = schemaID.UTF8String ?: "vibe_pinyin";
    if (!api->select_schema || !api->select_schema(self.session, selectedSchema.c_str())) {
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
    NSDictionary<NSString *, id> *empty = @{
        @"preedit": @"",
        @"candidates": @[],
        @"highlightedIndex": @0,
        @"pageNumber": @0,
        @"isLastPage": @YES,
    };
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
    NSInteger pageNumber = context.menu.page_no;
    BOOL isLastPage = context.menu.is_last_page != False;
    api->free_context(&context);
    return @{
        @"preedit": preedit ?: @"",
        @"candidates": candidates,
        @"highlightedIndex": @(highlighted > 0 ? highlighted : 0),
        @"pageNumber": @(pageNumber > 0 ? pageNumber : 0),
        @"isLastPage": @(isLastPage),
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

- (VVRimeKeyResult *)selectCandidateAtIndex:(NSInteger)index {
    RimeApi *api = CurrentAPI();
    if (!self.session || index < 0 || !api) {
        return [[VVRimeKeyResult alloc] initWithHandled:NO commit:nil];
    }
    // The snapshot exposes menu.candidates — the current page only. Absolute
    // select_candidate indexes a different list and rejects most page-local
    // taps (index 0 often works by coincidence on page 0; index 1+ fails).
    Bool ok = False;
    if (api->select_candidate_on_current_page) {
        ok = api->select_candidate_on_current_page(
            self.session, static_cast<size_t>(index));
    } else if (api->select_candidate) {
        ok = api->select_candidate(self.session, static_cast<size_t>(index));
    }
    if (!ok) {
        return [[VVRimeKeyResult alloc] initWithHandled:NO commit:nil];
    }
    // Commit may be nil when only part of the preedit was consumed — still a
    // successful selection; the caller must refresh the composition.
    return [[VVRimeKeyResult alloc] initWithHandled:YES
                                             commit:TakeCommit(api, self.session)];
}

- (VVRimeKeyResult *)selectAbsoluteCandidateAtIndex:(NSInteger)index {
    RimeApi *api = CurrentAPI();
    if (!self.session || index < 0 || !api || !api->select_candidate) {
        return [[VVRimeKeyResult alloc] initWithHandled:NO commit:nil];
    }
    if (!api->select_candidate(self.session, static_cast<size_t>(index))) {
        return [[VVRimeKeyResult alloc] initWithHandled:NO commit:nil];
    }
    return [[VVRimeKeyResult alloc] initWithHandled:YES
                                             commit:TakeCommit(api, self.session)];
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)allCandidates {
    RimeApi *api = CurrentAPI();
    if (!self.session || !api || !api->candidate_list_begin ||
        !api->candidate_list_next || !api->candidate_list_end) {
        return @[];
    }
    // Cap protects the keyboard extension: a long composition against a large
    // lexicon can theoretically yield thousands of entries, and the panel only
    // needs enough to scroll through.
    constexpr int kMaxCandidates = 120;
    RimeCandidateListIterator iterator;
    memset(&iterator, 0, sizeof(iterator));
    if (!api->candidate_list_begin(self.session, &iterator)) {
        return @[];
    }
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *candidates =
        [NSMutableArray arrayWithCapacity:32];
    do {
        NSString *text = iterator.candidate.text
            ? [NSString stringWithUTF8String:iterator.candidate.text]
            : @"";
        NSString *comment = iterator.candidate.comment
            ? [NSString stringWithUTF8String:iterator.candidate.comment]
            : @"";
        [candidates addObject:@{@"text": text ?: @"", @"comment": comment ?: @""}];
        if ((int)candidates.count >= kMaxCandidates) {
            break;
        }
    } while (api->candidate_list_next(&iterator));
    api->candidate_list_end(&iterator);
    return candidates;
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
