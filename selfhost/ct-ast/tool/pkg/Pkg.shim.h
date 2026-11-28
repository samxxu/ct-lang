/*
 * Pkg.shim.h - the C-only surface of selfhost/ct-ast/tool/pkg/Pkg.h.ct.
 *
 * D-032 M2: the unit's system includes live in Pkg.h.ct now; the package root
 * `selfhost/ct-ast/ct.pkg` is allow. Macros do not cross a unit boundary and a
 * function-like macro cannot sit in a `.ct` / `.m.ct`, so the SHA-256 rotate
 * helper stays on this boundary. `ct build` copies the shim next to the
 * emitted `.c`/`.h`.
 */
#define CT_ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
