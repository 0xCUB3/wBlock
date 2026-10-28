/*
 * C ABI of the wbe filter engine (crates/wbe/src/ffi.rs), used by
 * wBlockCoreService through module.modulemap.
 *
 * Ownership: every pointer returned by a function named *_new, *_build,
 * *_open or *_lookup, or by wbe_classify_line, is owned by the caller and
 * released with the matching free function. Accessors such as
 * wbe_compile_webkit_json return borrowed pointers that stay valid until
 * the owning WbeCompileResult is freed.
 *
 * Failure: functions return NULL or false. wbe_last_error returns the
 * message for the last call on the calling thread; it is valid until that
 * thread's next wbe call and must not be freed.
 *
 * Threading: a WbeEngine must not be used from two threads at once.
 */
#ifndef WBE_H
#define WBE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct WbeCompileResult WbeCompileResult;
typedef struct WbeEngine WbeEngine;

const char *wbe_last_error(void);

/* Changes whenever the engine's outputs change for the same input. */
uint32_t wbe_output_version(void);

/* lists: UTF-8 list texts. trusted: one flag per list (may be NULL when count is 0). */
WbeCompileResult *wbe_compile(const char *const *lists, const bool *trusted, size_t count,
                              uint16_t safari_major, uint16_t safari_minor);
/* Safari content-blocker JSON array. */
const char *wbe_compile_webkit_json(const WbeCompileResult *result);
/* uBO rule lines for wbe_engine_build, joined with newlines. */
const char *wbe_compile_runtime_text(const WbeCompileResult *result);
/* {"lines":..,"rules":..,"native_rules":..,"runtime_rules":..,"dropped":{..}} */
const char *wbe_compile_stats_json(const WbeCompileResult *result);
void wbe_compile_free(WbeCompileResult *result);

/* On success *out holds *out_len bytes; free with wbe_bytes_free. */
bool wbe_engine_build(const char *runtime_text, uint8_t **out, size_t *out_len);
void wbe_bytes_free(uint8_t *bytes, size_t len);

WbeEngine *wbe_engine_open(const uint8_t *bytes, size_t len);
/* PagePayload JSON: {"hide":[..],"procedural":[..],"scriptlets":[[name,args..],..],"generichide":bool}. */
char *wbe_engine_lookup(const WbeEngine *engine, const char *url);
void wbe_engine_free(WbeEngine *engine);

/* Registrable domain (eTLD+1) of host, or NULL for a public suffix; free with wbe_string_free. */
char *wbe_registrable_domain(const char *host);

/* Byte offset and length of the leftmost cosmetic marker in line; false if none. */
bool wbe_cosmetic_marker(const char *line, size_t *start, size_t *len);

/* ParsedLine JSON for one filter line, for the rule editor. */
char *wbe_classify_line(const char *line);
void wbe_string_free(char *s);

#ifdef __cplusplus
}
#endif

#endif /* WBE_H */
