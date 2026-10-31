/* The C shim beside `lib.m.ct`: its declarations are invisible to a recipe,
   so shapes a recipe cannot spell (a global such as `errno`) live here. */
#include <errno.h>

static inline int ct_shim_errno(void)
{
    return errno;
}

/* `errno` is not guaranteed 0 at `main` entry, so the fixture clears it first:
   the same accessor then proves the read of the global, not the C runtime. */
static inline void ct_shim_clear(void)
{
    errno = 0;
}

int ct_shim_next(void);
