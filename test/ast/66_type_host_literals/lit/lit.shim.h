/* The C beside `lit.m.ct`: a recipe cannot spell a helper, so `ct_tag` lives
   here and the consumer's `.c` includes this header by base name. */
static inline int ct_tag(int host)
{
    return host;
}
