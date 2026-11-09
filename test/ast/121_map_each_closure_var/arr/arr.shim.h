/* The synchronous consumer the recipe calls (D25-6): the environment is a
   stack compound literal, so it must not outlive this frame. */
static inline int ct_each_int(int *a, int n, int (*fn)(void *env, int x), void *env)
{
    int k, sum = 0;
    for (k = 0; k < n; k++) sum += fn(env, a[k]);
    return sum;
}
