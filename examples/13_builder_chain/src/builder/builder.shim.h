#ifndef BUILDER_SHIM_H
#define BUILDER_SHIM_H

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

static inline struct Builder builder_make(int n)
{
    struct Builder b;
    b.n = n;
    return b;
}

#endif
