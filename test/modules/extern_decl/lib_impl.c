/* The C library's own translation unit: it owns the symbols the CT declarations
   name. The gate compiles it next to the generated units. */
int lib_flag = 7;

int lib_fn(int x) { return x * 3; }
