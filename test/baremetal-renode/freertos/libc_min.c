/* Minimal freestanding memory/string routines: the firmware links -nostdlib,
   so FreeRTOS references to memset/memcpy must resolve here. */
#include <stddef.h>
void *memset(void *d, int c, size_t n) { unsigned char *p = d; while (n--) *p++ = (unsigned char)c; return d; }
void *memcpy(void *d, const void *s, size_t n) { unsigned char *p = d; const unsigned char *q = s; while (n--) *p++ = *q++; return d; }
void *memmove(void *d, const void *s, size_t n) { unsigned char *p = d; const unsigned char *q = s; if (p < q) { while (n--) *p++ = *q++; } else { p += n; q += n; while (n--) *--p = *--q; } return d; }
size_t strlen(const char *s) { size_t n = 0; while (*s++) n++; return n; }
int memcmp(const void *a, const void *b, size_t n) { const unsigned char *p = a, *q = b; while (n--) { if (*p != *q) return *p - *q; p++; q++; } return 0; }
