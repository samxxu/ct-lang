#ifndef LIB_SHIM_H
#define LIB_SHIM_H

#include <errno.h>

static inline int ct_shim_errno(void) { return errno; }
static inline void ct_shim_clear(void) { errno = 0; }

int ct_shim_next(void);

#endif
