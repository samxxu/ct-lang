#ifndef HOST_SHIM_H
#define HOST_SHIM_H

#include <string.h>

static inline int host_twice(int n) { return n * 2; }
static inline int host_plus(int n, int by) { return n + by; }
static inline int host_len(const char *s) { return (int)strlen(s); }
static inline double host_square(double x) { return x * x; }
static inline unsigned long host_twice_wide(unsigned long n) { return n * 2; }

#endif
