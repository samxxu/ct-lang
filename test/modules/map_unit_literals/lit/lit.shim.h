/* The same shape as std::num's `Num.shim.h` / std::str's `String.shim.h`: four
   static 32-byte slots handed out round-robin, so two calls in one expression
   stay distinct and only a fifth live result reuses the first slot. */
#include <stdio.h>
#include <string.h>

static inline char *ct_lit_int(int v)
{
    static char ring[4][32];
    static int slot = 0;
    char *out = ring[slot];

    slot = (slot + 1) & 3;
    snprintf(out, sizeof ring[0], "%d", v);
    return out;
}

static inline char *ct_lit_str(char *s)
{
    static char ring[4][32];
    static int slot = 0;
    char *out = ring[slot];

    slot = (slot + 1) & 3;
    snprintf(out, sizeof ring[0], "%s", s);
    return out;
}

static inline int ct_lit_len(char *s)
{
    return (int)strlen(s);
}
