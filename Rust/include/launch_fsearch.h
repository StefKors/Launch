#ifndef LAUNCH_FSEARCH_H
#define LAUNCH_FSEARCH_H

#include <stdint.h>

#pragma clang assume_nonnull begin

/// An fsearch engine running inside this process.
typedef struct lf_engine lf_engine;

/// Starts indexing in the background and returns at once. `dir` is where the
/// index lives. Returns NULL on failure and, if `error_out` is not NULL, sets
/// it to a message to free with `lf_free_string`.
lf_engine *_Nullable lf_start(const char *home, const char *dir, char *_Nullable *_Nullable error_out);

/// Name search. `query` uses fsearch's query language ("main ext:swift").
/// Returns JSON to free with `lf_free_string`:
///   {"ok":true,"took_us":N,"hits":[{"path","kind","size","mtime","score"}]}
///   {"ok":false,"indexing":bool,"error":"...","hits":[]}
/// `kind` is "file", "dir", "link" or "other". NULL only if out of memory.
char *_Nullable lf_search(lf_engine *engine, const char *query, uint32_t limit);

/// JSON: {"ready","progress","full_disk_access","owner","entries","index_bytes",...}.
char *_Nullable lf_status(lf_engine *engine);

/// Keeps the CPU cores clocked up for `milliseconds`, so the next keystroke's
/// search starts fast.
void lf_keep_warm(lf_engine *engine, uint32_t milliseconds);

/// Schedules the name index to be written to disk.
void lf_save(lf_engine *engine);

void lf_free_string(char *_Nullable s);

/// Saves the index and releases the handle. Background threads end with the
/// process.
void lf_stop(lf_engine *_Nullable engine);

#pragma clang assume_nonnull end

#endif
