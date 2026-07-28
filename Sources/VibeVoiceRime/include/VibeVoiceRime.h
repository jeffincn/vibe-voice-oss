#ifndef VIBEVOICE_RIME_H
#define VIBEVOICE_RIME_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int vv_rime_available(void);
void *vv_rime_create(const char *shared_data_dir, const char *user_data_dir,
                     const char *staging_dir, const char *schema_id);
void vv_rime_destroy(void *session);
/* `modifiers` uses librime / IBus masks (kShiftMask, kReleaseMask, …). */
int vv_rime_process(void *session, int keycode, int modifiers,
                    char *commit, size_t commit_size);
/* Returns 1 when the named option is on (e.g. "ascii_mode"). */
int vv_rime_get_option(void *session, const char *name);
/* Copy the raw input buffer (uncommitted code) into `out`. */
int vv_rime_get_input(void *session, char *out, size_t out_size);
/* `candidates` is filled with one record per candidate, each holding the text
   and the comment separated by 0x1e, and each record terminated by 0x1f. */
int vv_rime_snapshot(void *session, char *preedit, size_t preedit_size,
                     char *candidates, size_t candidates_size, int *highlighted_index,
                     int *page_number, int *is_last_page);
/* Returns 1 when the candidate was accepted by librime. A non-empty `commit`
   buffer means the segment was flushed out of the composition; an empty buffer
   means the selection stayed inside the preedit (e.g. "真实nei rong") and the
   host must NOT insert the candidate text a second time. */
int vv_rime_select_candidate(void *session, size_t index, char *commit, size_t commit_size);
/* Flush the whole composition (confirmed segments + remaining code) into
   `commit`. Used when punctuation arrives mid-phrase. */
int vv_rime_commit_composition(void *session, char *commit, size_t commit_size);
void vv_rime_clear(void *session);

#ifdef __cplusplus
}
#endif

#endif
