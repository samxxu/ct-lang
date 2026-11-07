/* The C side of the mapping unit. The type names the mapping uses (`Text`,
   `Count`) are CT aliases, so this header carries no typedef for them. */
#include <string.h>

static inline int ct_text_size(const char *s) { return (int)strlen(s); }
static inline int ct_text_same(const char *a, const char *b) { return strcmp(a, b); }
static inline int ct_twice(int n) { return n * 2; }
static inline int ct_plus(int n, int other) { return n + other; }
