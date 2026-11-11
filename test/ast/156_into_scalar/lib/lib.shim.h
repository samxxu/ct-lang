#include <string.h>

/* A recipe names a C symbol; the shim beside the mapping unit declares it for
   the consumer. */
static inline int ct_twice(int n)
{
    return n * 2;
}

static inline int ct_plus(int a, int b)
{
    return a + b;
}

static inline int ct_text_size(char *s)
{
    return (int)strlen(s);
}
