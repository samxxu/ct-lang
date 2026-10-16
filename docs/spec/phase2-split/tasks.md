# Tasks — Phase 2 split of `selfhost/ctc.ct` into `selfhost/src/**`

Ordered. Each task is done only when its verification passes. `selfhost/ctc.ct` is never edited.

- [x] **T0** — Feasibility probe (settles R1/R2/R3 before any partitioning)

Fixture under `/tmp` only (do not touch `test/**`):
`/tmp/probe/{types.h.ct, core.ct, driver.ct}` + a tiny consumer, exercising exactly what the
design needs:

- `types.h.ct`: `pub #include <stddef.h>`; `pub #define MAX_N 8`; a `pub struct Buf` using
  `MAX_N` in a field; a `pub trait Ops { void go(); }` + `pub struct Impl { ... } use Ops;`
  + `pub struct Impl *ct_impl(void);` prototype.
- `core.ct`: `import types;`, the `impl Ops for Impl` and `static Impl g_impl = { };`,
  `struct Impl *ct_impl(void) { return &g_impl; }`, a `pub`-declared function.
- `driver.ct`: `import types;` then `ct_impl()->go();`.

Verify (paste raw output):
1. `L0 selfhost/ctc.ct -o /tmp/ctc-l1.c` builds -> `/tmp/ctc-l1` (L1) warning-free. (reuse existing gate)
2. `L1 build /tmp/probe/*.ct -o /tmp/probe/out` emits one `.c`/`.h` pair per unit; inspect
   whether `MAX_N` / `<stddef.h>` landed in `types.h` (**R1**).
3. `cc /tmp/probe/out/*.c -o /tmp/probe/a.out` links (vtable dispatch through the accessor
   works cross-unit) and `./a.out` runs (**R3**).
4. Report the `MAX_FUNCS` headroom: count plain-C signature records L1 registers when building
   the real files (add a temporary counter locally in a scratch copy, **not** in `ctc.c`) —
   only if needed; otherwise infer from the build succeeding (**R2**).

Decision: if R1 holds and R2 has headroom -> 3-unit design; else **F1/F2** (2 units, no
`types.h.ct`). Record the decision in this file at the end.

- [~] **T1 — `selfhost/src/types.h.ct` — SKIPPED by F1 (see T0 decision below)**

Create the declaration unit (§4.1): `pub #include`s, `pub #define` `MAX_*`/`CTC_VERSION`,
`pub` data structs, `pub trait SymTabOps` + `pub struct SymTab ... use SymTabOps;`,
`pub trait PipeOps` + `pub trait RewriteOps` + `pub struct Pipe { out, hout, imp_h, nimp_h }
use PipeOps, RewriteOps;`, and the two accessor prototypes. One statement per line.
Verify: `L0 selfhost/src/types.h.ct -o /tmp/t.c` produces the expected `types.h` (types + the
2 prototypes, guard `TYPES_H`).

- [x] **T2 — `selfhost/src/core.ct`**

Create the core unit (§4.2) as a faithful, order-preserving partition of `ctc.ct`: facilities,
statics, source-level helpers, signature parsing, `impl SymTabOps`, `g_sym`, `impl PipeOps`,
raw line rewriters, `impl RewriteOps`, `g_pipe`, the two accessor definitions. Rename
`g_imp_h`/`g_nimp_h` -> `self->imp_h`/`self->nimp_h` inside the pipeline.
Verify: `L0 selfhost/src/core.ct -o /tmp/core.c` succeeds; `types` import resolved.

- [x] **T3 — `selfhost/src/driver.ct`**

Create the driver unit (§4.3): `import types;`, includes, `g_incdir`/`g_nincdirs`,
`build_output`/`file_exists`/`collect_imports`/`resolve_import`, the unit tables,
`unit_find`/`unit_visit`, `build_main`/`compile_main`/`main`. Route every pipeline call through
`ct_pipe()` / `ct_sym()`; fill the import list via the returned pointer.
Verify: `L0 selfhost/src/driver.ct -o /tmp/driver.c` succeeds.

- [x] **T4 — Build L2 and diff against L1 (the exit criterion)**

- `L1 build selfhost/src/driver.ct -o /tmp/l2src` (imports pull in core + types in dependency
  order) -> the emitted `.c`s; compile them warning-free -> `L2`.
- `L2` over `test/cases/*.ct` compared byte-for-byte with `*.expected.c` / `*.expected.h`
  -> expect 25/25 identical, and identical to L1's own output.
Verify: paste the diff result and L2's per-case verdict.

- [x] **T5 — New fixture pinning the capability the split relies on**

Add `test/modules/split/` as a designed fixture: a `pub trait` + `pub struct` in a header
unit, its `impl` in another unit, and a third unit dispatching through an accessor-returned
pointer; `build.args` + `*.expected.c` / `*.expected.h` + `expected.out`. Promote it in
`check-archive.sh`'s `baseline_designed`. Baselines are generated with the compiler, never
hand-written.

- [x] **T6 — Extend the gate scripts**

Add the "L1 builds `selfhost/src/**` -> L2 -> corpus byte-diff" step to:
`selfhost/check-goldens.sh` (after step 5), `selfhost/check-archive.sh` (after step 3),
`selfhost/check-m2a.sh` (after step 6), and `selfhost/ct-tour.sh` (a display step). Keep every
existing `selfhost/ctc.ct` invocation intact.
Verify: each script exits 0; paste the new step's output.

- [x] **T7 — Full regression**

`check-goldens.sh`, `check-archive.sh` (7 groups, 0 regression), `check-m2a.sh`,
`./test/run.sh`, `check-grammar.py`, L0/L1 warning-free builds, and the manual three-step
check. Paste all results. Confirm `git diff --stat selfhost/ctc.ct` is empty.

- [x] **T8 — Docs**

`AGENTS.md` §2 (`selfhost/**` -> multi-unit `selfhost/src/**` with the L1 seed retained) and the
L1 exit bullet; `docs/roadmap.md` Phase 2 progress (split landed, static-vtable constraint, L2
gate). Update this file's T0 decision line.

---
T0 decision: **F1 — two units, no `types.h.ct`.**

Probe result: **R1 FAILS.** A `pub`-prefixed preprocessor line (`pub #include <stddef.h>`,
`pub #define MAX_N 8`) is written verbatim into the unit's `.c` and never reaches the generated `.h`
(verified with `/tmp/probe/{types.h.ct,core.ct,driver.ct}`: `types.h` came out with only the
`pub trait`/`pub struct`/prototype content, macros and includes stayed in `types.c`). Line 1593 of
`selfhost/ctc.ct` short-circuits any line starting with `#` before the `pub` routing runs, so a header
unit cannot carry `MAX_*`, `size_t` or `FILE`.

**R2** has headroom: only **non-`static` top-level signatures** accumulate (cross-unit), and a
`pub` prototype plus a non-`static` definition counts once. The split exports only the accessor
wrappers, well under `MAX_FUNCS=64` (a scratch probe of 70 such pairs died at the 65th registration,
confirming the rule and the headroom).

**R3** holds trivially under F1 (`core.c` includes only `core.h`, which carries the accessor
prototypes only).

Consequence: `selfhost/src/` = **`core.ct` + `driver.ct`**. All data types, traits, `MAX_*` and the
singleton stay inside `core.ct` (non-`pub`, so they land in `core.c`); `driver.ct` `import core;` and
reaches shared state only through 10 scalar `pub` wrappers (`ct_read_file`, `ct_is_ident_char`,
`ct_usage`, `ct_default_output`, `ct_begin_imports`, `ct_add_import`, `ct_compile_file`,
`ct_cc_reset`, `ct_cc_add`, `ct_cc_finish`); it defines its own matching `MAX_*` copies. See `core.ct`'s
header comment for why this unit cannot be cut further (facilities read file-scope statics, L1 has no
`pub` globals, headers cannot carry macros/includes, and `struct Pipe` holds `FILE*`/`size_t`).

Exit criterion met: **T4 PASS — L2 reproduces 25/25 `test/cases/**` byte-for-byte.**

---

Close-out decision (2026-10-16, user-approved option A): **Phase 2 ends here without a version
bump.** `CTC_VERSION` stays `v0.0.1` (changing it is a frozen-period "not allowed" item), so the
phase is marked with the non-version tag `phase2-multifile-split`. The `v0.1.0` / `v0.2.0` bumps
land together with the single-entry `ct`, regenerating every golden once at that point.

