/* The C shim beside `lib.m.ct`: its declarations are invisible to a recipe,
   so shapes a recipe cannot spell (a global such as `errno`) live here. */
#include <errno.h>

static inline int ct_shim_errno(void)
{
    return errno;
}

int ct_shim_next(void);
