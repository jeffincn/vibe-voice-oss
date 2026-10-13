#include "VibeVoiceRime.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if __has_include(<rime_api.h>)
#include <rime_api.h>
#define VV_HAS_RIME 1
#else
#define VV_HAS_RIME 0
#endif

#if VV_HAS_RIME
extern void vv_rime_require_default(void) __asm__("__ZN4rime27rime_require_module_defaultEv");
extern void vv_rime_require_plugins(void) __asm__("__Z27rime_require_module_pluginsv");
extern void vv_rime_require_core(void) __asm__("__Z24rime_require_module_corev");
extern void vv_rime_require_dict(void) __asm__("__Z24rime_require_module_dictv");
extern void vv_rime_require_gears(void) __asm__("__Z25rime_require_module_gearsv");
extern void vv_rime_require_levers(void) __asm__("__Z26rime_require_module_leversv");
typedef struct {
    RimeApi *api;
    RimeSessionId session;
} VVSession;
static int vv_active_sessions = 0;
static int vv_runtime_initialized = 0;
static pthread_mutex_t vv_runtime_lock = PTHREAD_MUTEX_INITIALIZER;

static void clear_buffer(char *buffer, size_t size) {
    if (buffer && size) buffer[0] = '\0';
}

static int copy_text(char *destination, size_t capacity, const char *source) {
    if (!destination || capacity == 0) return 0;
    if (!source) source = "";
    size_t length = strlen(source);
    if (length >= capacity) length = capacity - 1;
    memcpy(destination, source, length);
    destination[length] = '\0';
    return (int)length;
}

static int copy_commit(VVSession *value, char *commit, size_t commit_size) {
    clear_buffer(commit, commit_size);
    RimeCommit result;
    RIME_STRUCT_INIT(RimeCommit, result);
    if (!value->api->get_commit(value->session, &result)) return 0;
    int length = copy_text(commit, commit_size, result.text);
    value->api->free_commit(&result);
    return length;
}

int vv_rime_available(void) { return 1; }

void *vv_rime_create(const char *shared_data_dir, const char *user_data_dir,
                     const char *staging_dir, const char *schema_id) {
    RimeApi *api = rime_get_api();
    if (!api) return NULL;
    pthread_mutex_lock(&vv_runtime_lock);
    const char *modules[] = {"default", "core", "dict", "gears", "levers", "plugins", NULL};
    RimeTraits traits;
    RIME_STRUCT_INIT(RimeTraits, traits);
    traits.shared_data_dir = shared_data_dir;
    traits.user_data_dir = user_data_dir;
    traits.distribution_name = "Vibe Voice";
    traits.distribution_code_name = "vibe_voice";
    traits.distribution_version = "0.8.0";
    traits.app_name = "rime.vibevoice";
    traits.modules = modules;
    traits.staging_dir = staging_dir;
    if (!vv_runtime_initialized) {
        api->setup(&traits);
        vv_rime_require_default();
        vv_rime_require_plugins();
        vv_rime_require_core();
        vv_rime_require_dict();
        vv_rime_require_gears();
        vv_rime_require_levers();
        api->initialize(&traits);
        /* Incremental maintenance trusts user.yaml's last_build_time. If the
           staging dir was wiped (config upgrade) but user.yaml remains, a
           non-full run skips schema rebuild and leaves an empty Build — every
           key then falls through as ASCII. Force a full deploy when the
           compiled default.yaml is missing. */
        int full_check = 1;
        if (staging_dir && *staging_dir) {
            char compiled_default[4096];
            snprintf(compiled_default, sizeof compiled_default, "%s/default.yaml", staging_dir);
            full_check = access(compiled_default, R_OK) != 0 ? 1 : 0;
        }
        if (api->start_maintenance && api->start_maintenance(full_check)
            && api->join_maintenance_thread) {
            api->join_maintenance_thread();
        }
        vv_runtime_initialized = 1;
    }
    RimeSessionId session = api->create_session();
    if (!session) {
        pthread_mutex_unlock(&vv_runtime_lock);
        return NULL;
    }
    if (schema_id && *schema_id && !api->select_schema(session, schema_id)) {
        api->destroy_session(session);
        pthread_mutex_unlock(&vv_runtime_lock);
        return NULL;
    }
    VVSession *value = calloc(1, sizeof(VVSession));
    value->api = api;
    value->session = session;
    vv_active_sessions += 1;
    pthread_mutex_unlock(&vv_runtime_lock);
    return value;
}

void vv_rime_destroy(void *session) {
    VVSession *value = (VVSession *)session;
    if (!value) return;
    pthread_mutex_lock(&vv_runtime_lock);
    value->api->destroy_session(value->session);
    vv_active_sessions -= 1;
    if (vv_active_sessions == 0 && vv_runtime_initialized && value->api->finalize) {
        value->api->finalize();
        vv_runtime_initialized = 0;
    }
    pthread_mutex_unlock(&vv_runtime_lock);
    free(value);
}

int vv_rime_process(void *session, int keycode, int modifiers,
                    char *commit, size_t commit_size) {
    VVSession *value = (VVSession *)session;
    clear_buffer(commit, commit_size);
    if (!value) return 0;
    int handled = value->api->process_key(value->session, keycode, modifiers);
    copy_commit(value, commit, commit_size);
    return handled ? 1 : 0;
}

int vv_rime_get_option(void *session, const char *name) {
    VVSession *value = (VVSession *)session;
    if (!value || !name || !value->api->get_option) return 0;
    return value->api->get_option(value->session, name) ? 1 : 0;
}

int vv_rime_get_input(void *session, char *out, size_t out_size) {
    VVSession *value = (VVSession *)session;
    clear_buffer(out, out_size);
    if (!value || !value->api->get_input) return 0;
    const char *input = value->api->get_input(value->session);
    return copy_text(out, out_size, input) > 0 ? 1 : 0;
}

int vv_rime_snapshot(void *session, char *preedit, size_t preedit_size,
                     char *candidates, size_t candidates_size, int *highlighted_index,
                     int *page_number, int *is_last_page) {
    VVSession *value = (VVSession *)session;
    clear_buffer(preedit, preedit_size);
    clear_buffer(candidates, candidates_size);
    if (highlighted_index) *highlighted_index = 0;
    if (page_number) *page_number = 0;
    if (is_last_page) *is_last_page = 1;
    if (!value) return 0;
    RimeContext context;
    RIME_STRUCT_INIT(RimeContext, context);
    if (!value->api->get_context(value->session, &context)) return 0;
    copy_text(preedit, preedit_size, context.composition.preedit);
    if (highlighted_index) *highlighted_index = context.menu.highlighted_candidate_index;
    if (page_number) *page_number = context.menu.page_no;
    if (is_last_page) *is_last_page = context.menu.is_last_page ? 1 : 0;
    size_t offset = 0;
    for (int i = 0; i < context.menu.num_candidates; i++) {
        const char *text = context.menu.candidates[i].text ?: "";
        const char *comment = context.menu.candidates[i].comment ?: "";
        size_t text_length = strlen(text);
        size_t comment_length = strlen(comment);
        /* text + 0x1e + comment + 0x1f + terminator */
        if (offset + text_length + comment_length + 3 > candidates_size) break;
        memcpy(candidates + offset, text, text_length);
        offset += text_length;
        candidates[offset++] = '\x1e';
        memcpy(candidates + offset, comment, comment_length);
        offset += comment_length;
        candidates[offset++] = '\x1f';
        candidates[offset] = '\0';
    }
    value->api->free_context(&context);
    return 1;
}

int vv_rime_select_candidate(void *session, size_t index, char *commit, size_t commit_size) {
    VVSession *value = (VVSession *)session;
    clear_buffer(commit, commit_size);
    if (!value || !value->api->select_candidate_on_current_page(value->session, index)) return 0;
    /* Selection can succeed without flushing a commit: librime keeps the
       confirmed segment inside composition.preedit until the whole phrase is
       done. Returning success with an empty commit is intentional. */
    copy_commit(value, commit, commit_size);
    return 1;
}

int vv_rime_commit_composition(void *session, char *commit, size_t commit_size) {
    VVSession *value = (VVSession *)session;
    clear_buffer(commit, commit_size);
    if (!value || !value->api->commit_composition(value->session)) return 0;
    return copy_commit(value, commit, commit_size) > 0 ? 1 : 0;
}

void vv_rime_clear(void *session) {
    VVSession *value = (VVSession *)session;
    if (value) value->api->clear_composition(value->session);
}
#else
int vv_rime_available(void) { return 0; }
void *vv_rime_create(const char *a, const char *b, const char *c, const char *d) { return NULL; }
void vv_rime_destroy(void *session) { (void)session; }
int vv_rime_process(void *session, int keycode, int modifiers, char *commit, size_t commit_size) {
    (void)session; (void)keycode; (void)modifiers;
    if (commit && commit_size) commit[0] = '\0';
    return 0;
}
int vv_rime_get_option(void *session, const char *name) { (void)session; (void)name; return 0; }
int vv_rime_get_input(void *session, char *out, size_t out_size) {
    (void)session;
    if (out && out_size) out[0] = '\0';
    return 0;
}
int vv_rime_snapshot(void *session, char *preedit, size_t preedit_size, char *candidates, size_t candidates_size, int *highlighted_index, int *page_number, int *is_last_page) { (void)session; if (preedit && preedit_size) preedit[0] = '\0'; if (candidates && candidates_size) candidates[0] = '\0'; if (highlighted_index) *highlighted_index = 0; if (page_number) *page_number = 0; if (is_last_page) *is_last_page = 1; return 0; }
int vv_rime_select_candidate(void *session, size_t index, char *commit, size_t commit_size) { (void)session; (void)index; if (commit && commit_size) commit[0] = '\0'; return 0; }
int vv_rime_commit_composition(void *session, char *commit, size_t commit_size) { (void)session; if (commit && commit_size) commit[0] = '\0'; return 0; }
void vv_rime_clear(void *session) { (void)session; }
#endif
