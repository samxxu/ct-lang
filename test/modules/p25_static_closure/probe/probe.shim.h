/* The C side beside `probe.m.ct`. A recipe is a single call, and the callback
   is consumed synchronously before the call returns (D25-6): the environment
   is a stack compound literal and must not outlive this frame. */
static inline int ct_probe_walk(const char *s, int (*fn)(void *env, int x), void *env)
{
    int k, sum = 0;
    for (k = 0; s[k]; k++) sum += fn(env, (unsigned char)s[k]);
    return sum;
}

static inline int ct_probe_apply(int n, int (*fn)(void *env, int x), void *env)
{
    int k, sum = 0;
    for (k = 0; k < n; k++) sum += fn(env, k);
    return sum;
}
