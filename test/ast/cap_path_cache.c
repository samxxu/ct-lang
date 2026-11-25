/*
 * cap_path_cache.c - S1a-0 C2l white-box probe: the cache's directory and
 * key-file paths grow past the old 1024-byte MAX_PATH stack buffers.
 *
 * The old `Cache.paths` filled two `char[MAX_PATH]` caller buffers and
 * returned -1 on overflow, which made `hit`/`store` silently skip the cache
 * for a long output path. The new one returns two owned blocks. The probe
 * passes a 1400-byte logical output path (no filesystem access: `paths` only
 * composes) and checks both blocks are whole.
 */
#include <stdio.h>
#include <string.h>

#include "Cache.h"

static int fail(const char *what)
{
    fprintf(stderr, "FAIL cache: %s\n", what);
    return 1;
}

int main(void)
{
    static char outc[1401 + 6];
    struct tool_cache_Cache *c;
    char *dir = 0;
    char *kf = 0;
    size_t dl;
    int rc;

    c = tool_cache_cache_get();
    if (!c) return fail("cache_get returned null");
    /* 1400 'd' + "/out.c": the slash makes the cache directory the 1400 bytes. */
    memset(outc, 'd', 1400);
    memcpy(outc + 1400, "/out.c", 7);
    rc = c->__tool_cache_cacheops_vptr->paths(c, outc, &dir, &kf);
    if (rc != 0) return fail("paths rejected a 1406-byte output path");
    if (!dir || !kf) return fail("paths returned a null block");
    dl = strlen(dir);
    if (dl != 1400 + 9) return fail("the cache directory was cut or padded");
    if (memcmp(dir, outc, 1400) != 0) return fail("the directory lost its prefix");
    if (strcmp(dir + 1400, "/.ctcache") != 0) return fail("the directory suffix is wrong");
    if (strlen(kf) != dl + 1 + 5 + 4) return fail("the key path was cut or padded");
    if (strncmp(kf, dir, dl) != 0) return fail("the key path does not sit under the cache dir");
    if (strcmp(kf + dl, "/out.c.key") != 0) return fail("the key-name suffix is wrong");
    free(dir);
    free(kf);

    /* A short path still composes exactly as before (no growth on every call). */
    rc = c->__tool_cache_cacheops_vptr->paths(c, "a/b.c", &dir, &kf);
    if (rc != 0) return fail("paths rejected a short output path");
    if (!dir || strcmp(dir, "a/.ctcache") != 0) return fail("the short directory is wrong");
    if (!kf || strcmp(kf, "a/.ctcache/b.c.key") != 0) return fail("the short key path is wrong");
    free(dir);
    free(kf);
    printf("ok   cache paths (%d-byte dir, %d-byte key)\n",
           1400 + 9, 1400 + 9 + 1 + 5 + 4);
    return 0;
}
