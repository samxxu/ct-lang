/*
 * Result.shim.h - the C surface of lib/core/Result.h.ct (v1-PH-2 S9).
 *
 * `lib/core` is the built-in layer: it allocates, copies and prints
 * through libc, so these declarations are its C boundary. A strict
 * `.h.ct` may only include its own shim; compile mode expands this
 * shim into the single translation unit it emits.
 */
#include <stdio.h>
#include <stdlib.h>
