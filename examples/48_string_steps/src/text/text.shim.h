#ifndef TEXT_SHIM_H
#define TEXT_SHIM_H

#include <string.h>

/* 前缀 text_ 避免与 lib/core 的 Str 接口（str_len 等）重名。 */
static inline char *text_split_once(const char *s, char sep)
{
    const char *p = strchr(s, sep);
    return p != 0 ? (char *)(p + 1) : (char *)s;
}

static inline int text_len(const char *s) { return (int)strlen(s); }

#endif
