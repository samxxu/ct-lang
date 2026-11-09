/* The C beside `arr.m.ct`: a recipe is a single call, so the loop lives here
   and the consumer's `.c` includes this header by base name. */
static inline int ct_total(int *a, int n)
{
    int s = 0;
    int i;
    for (i = 0; i < n; i++) {
        s += a[i];
    }
    return s;
}
