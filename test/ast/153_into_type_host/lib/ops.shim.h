/* Macros expand at the recipe's call site, where the mapped struct is already
   complete -- the shape a by-pointer recipe can use without a .shim.c. */
#define ct_file_read(f, n)  ((f)->pos += (n))
#define ct_file_write(f, n) ((f)->wrote += (n))
#define ct_file_tell(f)     ((f)->pos + (f)->wrote)
