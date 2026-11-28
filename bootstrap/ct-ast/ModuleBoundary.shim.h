/*
 * ModuleBoundary.shim.h - the C-only surface of
 * selfhost/ct-ast/frontend/module/ModuleBoundary.h.ct.
 *
 * D-032 M2: the unit's system includes live in ModuleBoundary.h.ct now; the
 * package root `selfhost/ct-ast/ct.pkg` is allow. Only a declaration a `.ct`
 * cannot spell stays on this boundary. `ct build` copies the shim next to the
 * emitted `.c`/`.h`.
 */

/* POSIX/XSI `realpath`: glibc and musl hide its declaration under
   `-std=c99`, so the explicit prototype keeps every host warning-free. */
extern char *realpath(const char *path, char *resolved);
