#ifndef BUILDER_SHIM_H
#define BUILDER_SHIM_H

#include <stdlib.h>

/* A plain C value type. The map unit sees it only as the spelling
   `struct Builder`; the recipe turns each method into one C call. */
struct Builder {
    int n;
};

static inline struct Builder builder_add(struct Builder b, int by)
{
    b.n = b.n + by;
    return b;
}

static inline int builder_value(struct Builder b)
{
    return b.n;
}

/* 工厂：字符串在这里变成宿主，调用点看不到字段初始化。 */
static inline struct Builder builder_from(const char *s)
{
    struct Builder b;
    b.n = atoi(s);
    return b;
}

#endif
