/*
 * Pkg.shim.h - the C surface of selfhost/ct-ast/tool/pkg/Pkg.h.ct (v1-PH-2 S9).
 *
 * A strict `.h.ct` may only include its own shim. The unit's system
 * includes moved here; `ct build` copies this file next to the emitted
 * `.c`/`.h`, so the product tree and the frozen seed find it by base
 * name. Add a header here before adding it to the unit.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <dirent.h>
#include <unistd.h>
#include <stdarg.h>

/* A function-like macro cannot sit in a `.ct` / `.m.ct`; the SHA-256
   rotate helper lives on the boundary. */
#define CT_ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
