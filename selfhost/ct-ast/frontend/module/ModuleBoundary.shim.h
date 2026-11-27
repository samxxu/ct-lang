/*
 * ModuleBoundary.shim.h - the C surface of selfhost/ct-ast/frontend/module/ModuleBoundary.h.ct (v1-PH-2 S9).
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
#include <unistd.h>

/* POSIX/XSI `realpath`: glibc and musl hide its declaration under
   `-std=c99`, so the explicit prototype keeps every host warning-free. */
extern char *realpath(const char *path, char *resolved);
