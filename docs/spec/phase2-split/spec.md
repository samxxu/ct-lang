# Spec — Phase 2 export item #2: split `selfhost/ctc.ct` into `selfhost/src/**`

Status: awaiting approval · Owner: user · Scope: `selfhost/**`, gate scripts, `AGENTS.md`, `docs/roadmap.md`
Approval gate: **do not write code until the user approves this spec.**

## 1. Goal

Partition the hand-written single-file L1 (`selfhost/ctc.ct`, 3685 lines, written in CT,
compiled by the frozen L0 `ctc.c`) into a multi-unit CT source tree under
`selfhost/src/**`, exercising L1's own `ctc build` module system (dogfooding).

- `selfhost/ctc.ct` **stays** as the hand-written L1 seed; it is **not** regenerated from
  `selfhost/src/**` and is **not** edited by this work.
- New gate: `L0 -> L1` as today; then **L1 builds `selfhost/src/**` -> L2**; **L2 must
  reproduce `test/cases/**` byte-for-byte** (the same oracle `check-goldens.sh` steps 4/5
  already use). L2 is the real deliverable: the split source only counts as done when the
  compiler it builds is byte-identical with L1 on the corpus.

## 2. Non-goals / hard constraints

- **No new language feature, CLI option, diagnostic, or naming change** on either side. L0
  (`ctc.c`) is frozen and is **not** touched. `selfhost/**` is written in the OO subset L0
  accepts (single file per unit, one statement per line, declarations before use, no
  interface arrays, no one-line bodies).
- Do **not** move `ctc.c` / `test/**` into `ctrait/` this round.
- Do **not** weaken any existing fixture (`test/modules/**`, `test/archive/**`, `test/cases/**`).
  No `*.expected.*` is regenerated: the generated output must not move.
- Generated `.c` stays self-contained per unit (includes its own `.h`), exactly as L1 already
  emits it.

## 3. Verified constraints (from code recon — these drive the design)

1. **The vtable and impl methods are emitted `static`** (`selfhost/ctc.ct` emits
   `static struct <T>_vtbl <S>_<T>_vtable = { ... }` and `static void <S>_<T>_<m>`, and the
   file-scope vptr writes are collected into `static void __ct_init(void)`).
   Consequence: a vtable **symbol cannot be referenced from another unit** — no unit may
   construct a shared object with the `.__<trait>_vptr = &..._vtable` designator, and no
   unit may emit a `__ct_init` write for a vtable owned by another unit.
   Conversely, **dispatching through a vptr already stored in an object is fine cross-unit**:
   the caller only dereferences a stored pointer and never names the vtable symbol.
2. The facilities layer (`die`, `word_at`, `skip_*`, `buf_*`, `xmalloc`, …) reads **loose
   file-scope statics** (`g_src`, `g_len`, `g_path`, `g_ns`, …) spread over the whole file.
   Exporting those functions to a second unit would both require exporting the statics
   (impossible: L1 has no `pub` globals) and spend the `MAX_FUNCS` budget. **Therefore all
   facilities and their statics stay in one unit.**
3. `MAX_FUNCS = 64` counts plain-C function signatures **accumulated across every unit in a
   build**, counting a prototype and its definition separately. The current single file has
   ~46 such records, so the split may add only a **small** number of cross-unit functions.
   Cross-unit surface must be minimised to ~2 accessors.
4. `import` resolution: importing file's own directory first, then each `-I <dir>` root in
   command-line order; a `foo.h.ct` unit emits `foo.c` + `foo.h`; the generated `.c` includes
   **its own `.h` first**, then one `#include` per import **in the order the imports appear**.
5. `pub` routing today: `pub trait` / `pub struct` / a `pub`-led prototype line go into the
   unit's `.h`; a `pub`-led raw line (no body) is stripped of `pub` and also routed to the
   `.h`. A bare top-level function definition without `pub` is emitted **non-static** (it is
   plain-C passthrough).

## 4. Design (route A — bundle state behind accessors; no new feature)

Three units under `selfhost/src/`:

### 4.1 `selfhost/src/types.h.ct` — the shared declaration unit (`*.h.ct` => `types.c` + `types.h`)

Header kinds only. Order matters (declaration before use):

1. `pub #include <stddef.h>` / `<stdio.h>` — a header unit needs `size_t` / `FILE` available
   at the point `types.h` is parsed (see risk R1; fallback F1 if `pub #include` is unsupported).
2. `pub #define` for every `MAX_*` and `CTC_VERSION` (single source of truth; every importing
   unit gets them from this header instead of duplicating them).
3. `pub struct Buf`, `pub struct Method`, `pub struct Trait`, `pub struct Struct`,
   `pub struct Var`, `pub struct FuncSig`, `pub struct ImplMethod` — moved verbatim from
   `ctc.ct` lines 110-179.
4. `pub trait SymTabOps { ... }` then `pub struct SymTab { ... } use SymTabOps;` (moved from
   `ctc.ct` 430-453). The `SymTab` body already includes the vptr field via `use`.
5. `pub trait PipeOps { ... }`, `pub trait RewriteOps { ... }`, then
   `pub struct Pipe { FILE *out; FILE *hout; <import fields>; } use PipeOps, RewriteOps;`
   (moved from `ctc.ct` 698-775). The import list `g_imp_h` / `g_nimp_h` becomes **fields of
   `Pipe`** (`char imp_h[MAX_IMPORTS][MAX_NAME]; int nimp_h;`) so no `pub` global is needed and
   the driver can fill it through the returned pointer.
6. The two accessor **prototypes** (defined in `core.ct`, declared here so the driver imports
   only this unit):
   `pub struct SymTab *ct_sym(void);` and `pub struct Pipe *ct_pipe(void);`

### 4.2 `selfhost/src/core.ct` — facilities + data + impls + the two singletons

- `import types;` first, then `#include <ctype.h> <stdarg.h> <stdio.h> <stdlib.h> <string.h>`.
- Facilities `ctc.ct` 237-329 (`xmalloc`, `xstrndup`, `is_ident_char`, `die`, `trim`,
  `trim_right_len`, `to_lower`, `buf_init/putn/puts/putc`) — verbatim.
- Loose statics `ctc.ct` 181-235 **except** `g_imp_h` / `g_nimp_h` (now `Pipe` fields) and
  **except** `g_incdir` / `g_nincdirs` (moved to the driver).
- Source-level helpers `ctc.ct` 331-425; the signature-parsing helpers `ctc.ct` 593-687 with
  their 3 forward prototypes (`line_literal_end` / `line_match_paren` / `line_assign_eq`).
- `static int struct_uses(...)`, `find_field_ex`, `needs_nested_init`, `find_iface_field`
  (`ctc.ct` 533-591); `impl SymTabOps for SymTab { ... }` + `static SymTab g_sym = ...`
  (`ctc.ct` 455-531).
- `impl PipeOps for Pipe { ... }` (`ctc.ct` 782-2128), the raw line-rewriting helpers
  (`ctc.pt` 3341-3386), `impl RewriteOps for Pipe { ... }` (`ctc.ct` 2135-3340),
  `static Pipe g_pipe = { };` (`ctc.ct` 3339).
- Inside `compile_file` / the construct parsers, every reference to `g_imp_h` / `g_nimp_h`
  becomes `self->imp_h` / `self->nimp_h` (mechanical rename; same semantics).
- The two accessor **definitions**: `struct SymTab *ct_sym(void) { return &g_sym; }`,
  `struct Pipe *ct_pipe(void) { return &g_pipe; }`.

### 4.3 `selfhost/src/driver.ct` — unit tables, CLI, `main`

- `import types;` first (for `MAX_*`, `Buf`, `struct Pipe`/`SymTab` and the accessor
  prototypes), then `#include <stdio.h> <stdlib.h> <string.h>`.
- `g_incdir` / `g_nincdirs` move here (only the driver reads them: `resolve_import`,
  the `-I` parsing in `build_main` / `compile_main`).
- `build_output`, `file_exists`, `collect_imports`, `resolve_import` (`ctc.ct` 3391-3498);
  the unit tables and `unit_find` / `unit_visit` (`ctc.ct` 3502-3554); `build_main`,
  `compile_main`, `main` (`ctc.ct` 3559-3685).
- Cross-unit calls become explicit on the accessors, e.g.
  `ct_pipe()->read_file(path, &len)`, `ct_pipe()->compile_file(ct_sym(), path, out, 1)`,
  `ct_pipe()->usage(prog)`, `ct_pipe()->default_output(...)`; the import list is filled as
  `ct_pipe()->nimp_h = u's count;` + `strcpy(ct_pipe()->imp_h[k], name);` (plain C field
  access — no vtable symbol crosses).

### 4.4 Cross-unit contract (the whole surface)

| Consumer | Needs | Mechanism |
| --- | --- | --- |
| driver | the pipeline entry points, `usage`, `default_output`, `read_file` | `ct_pipe()` -> `struct Pipe *` (type in `types.h`), vptr dispatch |
| driver | the symbol table for `compile_file` | `ct_sym()` -> `struct SymTab *` |
| driver | the import list | writes `struct Pipe` fields through the pointer |
| anything | `MAX_*`, `CTC_VERSION`, the data structs | `import types;` |

No plain-C function is exported except the two accessors, so `MAX_FUNCS` grows by at most 4
records.

## 5. Risks and pre-decided fallbacks

- **R1 — `pub` on a raw preprocessor line (issue #1).** If `pub #define` / `pub #include` are
  not routed into the `.h` (or `#define` must precede its use in the header), `types.h` cannot
  carry the macros/`size_t`. **Fallback F1:** collapse to **two units** — all data types,
  traits and `MAX_*` stay inside `core.ct` (non-`pub`, so they land in `core.c`); the driver
  imports `core` and uses only the two accessors (`struct` pointer arithmetic needs no macro).
  The driver then defines its own `MAX_*` copies (values must match, as already settled).
- **R2 — `MAX_FUNCS` overflow in a 3-unit build.** If the accumulated signature count hits 64,
  **fallback F2:** drop the `types.h.ct` unit (F1) to keep the plain-C count unchanged.
- **R3 — header-first include ordering.** `core.c` includes `core.h` before `types.h`; `core.h`
  must therefore contain **only** the two accessor prototypes (no macro- or type-dependent
  content). Verified by the build step; if violated, move the offending declaration into
  `types.h.ct`.

The probe (T0) settles R1/R2 before any partitioning begins.

## 6. Verification / Definition of Done (all must pass, output pasted)

1. `gcc -Wall -Wextra -std=c99 ctc.c -o ctc` — zero warnings (L0 untouched).
2. `./ctc selfhost/ctc.ct -o /tmp/ctc-l1.c` then build L1 warning-free — unchanged gate.
3. **New:** `L1 build selfhost/src/** -o <dir>` builds `types`/`core`/`driver` and the emitted
   `.c`s compile warning-free with `cc` — i.e. **L2 exists**.
4. **The split's exit criterion:** `L2` reproduces `test/cases/**` **byte-for-byte**
   (`*.expected.c` + `*.expected.h`), identical to L1's own output — 25/25, 0 regression.
5. `bash selfhost/check-goldens.sh` — step 5 (L1' vs goldens) still green; new L2 step green.
6. `bash selfhost/check-archive.sh` — 7 groups, **0 regression** (`19_namespace`,
   `20_namespace_nested`, 4 namespace negatives, `hdr`/`inc`/`inc_missing`/`precedence`;
   22_drop + drop negatives + 4 multi-unit remain PENDING as before).
7. `bash selfhost/check-m2a.sh` and `./test/run.sh` green; `python3 editors/vscode/test/check-grammar.py` green.
8. Manual three-step check (`AGENTS.md` §6) run by hand and pasted.
9. `selfhost/ctc.ct` is **byte-identical** to before (`git diff --stat selfhost/ctc.ct` empty).

## 7. Docs

- `AGENTS.md` §2: `selfhost/**` row — `single file selfhost/ctc.ct` -> multi-unit
  `selfhost/src/**` (L1 seed `selfhost/ctc.ct` retained), and the L1 bullet gains the
  "L1 builds `selfhost/src/**` into L2, which must match L1 byte-for-byte" exit.
- `docs/roadmap.md`: Phase 2 progress — record the split landing, the verified static-vtable
  constraint, and the L2 gate.

## 8. Approval request

Approve this spec (3-unit design, F1/F2 fallbacks, the new L2 gate) to begin execution:
T0 probe -> partition -> gates -> regression -> docs.
