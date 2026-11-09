/* The synchronous consumer the recipe calls: `fn` receives the environment
   first, so the generated call needs no adapter. */
static inline int ct_each_int(int *a, int n, int (*fn)(void *env, int x), void *env)
{
    int k, sum = 0;

    for (k = 0; k < n; k++) {
        sum += fn(env, a[k]);
    }
    return sum;
}
