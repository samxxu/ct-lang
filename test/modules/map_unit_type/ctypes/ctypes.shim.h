/* The C shim beside `ctypes.m.ct`: a recipe may only be a single call, and a
   `void` method cannot map straight to `strlen` -- glibc marks the string
   functions `pure`, so a statement that discards the result is
   -Wunused-value. This is the void shape the trait promises. */
static inline void ct_probe_void(const char *s) { (void)s; }
