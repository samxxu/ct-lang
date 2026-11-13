# ct — C with Traits compiler

> English · [中文](README.md)

> This file is for human readers only. AI agents should use [README.md](README.md).
> Documentation other than this file is Chinese-only.

**ct** is a **source-to-source compiler** that translates `.ct` files (C plus trait syntax) into plain C.
The compilation path (`ct compile` / `ct build`) performs no type checking and no optimisation; the
optional `ct check` runs bounded semantic checks only (call-site arity, argument types, trait-method
ambiguity, impl signature drift). The output is **readable, ordinary C** with no runtime
library dependency, and the boilerplate (vtables, `_self` casts) is generated for you.
See [docs/roadmap.md](docs/roadmap.md) for what is done and what is next, and
[docs/glossary.md](docs/glossary.md) for the terminology.

### 1. Quick start

```bash
# 1a) install (downloads the source, bootstraps locally, installs to ~/.local/bin)
curl -fsSL https://raw.githubusercontent.com/samxxu/ct-lang/main/install.sh | sh

# 1b) or skip the install and use the L0 seed (single file, core grammar only; no ct, so use ./ctc)
gcc selfhost/l0/ctc.c -o ctc

# 2) compile a .ct to .c (a sibling .h is written only for a .h.ct input)
ct compile examples/01_greeter/greeter.ct -o /tmp/greeter.c      # after 1a
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c           # after 1b

# 3) build the output with the system C compiler
gcc /tmp/greeter.c -o /tmp/greeter && /tmp/greeter
```

New here? Start with the [tutorial](docs/tutorial.md); every command in it can be pasted as is.

### 2. Common commands

| Command | Result |
| --- | --- |
| `ct <in.ct>` / `ct compile <in.ct>` | single-file compile: a plain `.ct` writes `.c`, a `.h.ct` also writes its sibling `.h`; **single-file units only**, so `import` needs `ct build` (`-I` only applies to build too and is reported as ignored here) |
| `ct <in.ct> -o <out.c>` | write to the given path |
| `ct build <in.ct>… [-o <exe>]` | multi-file build: the generated `.c` goes into `.ctbuild/` (or `--outdir`), then the local C compiler produces an executable (`-o` names it, default `a.out`); `--emit-c` only emits the `.c` (plus `.h` for `.h.ct`), and then `-o` is the output directory; `--runtime-checks` guards a null vtable before iface dispatch (off by default; off keeps the output unchanged) |
| `ct check <in.ct>` | run the bounded semantic checks only, writing no `.c` (single-file units only; `import` is not accepted): call-site arity / argument types / trait-method ambiguity / impl signature drift (plus the existing leak / borrow findings) are all reported as `error:`, exit `1` on any finding and `0` when clean (`--diagnostics=json` tags each object with `"severity":"error"` and `"col"`) |
| `ct … --emit-map <file\|->` | also write the reverse-mapping JSON (trait / struct / function / impl → generated C symbols) |
| `ct get` / `ct update` / `ct install` / `ct verify` | package management: fetch into `vendor/`, write `ct.lock`; re-resolve or verify offline and print one build command (a bare name may resolve through `--index` / `CT_INDEX`; authors see [docs/package-guide.md](docs/package-guide.md)); the official packages live under [ct-pkg](https://github.com/ct-pkg): `hal` (contract), `hal-posix` (platform), `std` (standard library, including the C mappings) |
| `ct -v` / `ct -h` | version / usage |

Exit code `0` on success, `1` on syntax or I/O errors (on any `ct check` finding, or on an impl signature drift in `ct build`). Source diagnostics use `file:line:col: error: message`;
driver-level errors keep the `ctc:` prefix even when the binary is named `ct`, so logs and existing assertions
stay stable. The full flag list (`-I` / `--std` / `--line` / `--diagnostics` / `--ns-root`) is in the
[tutorial §11](docs/tutorial.md#11-cli-cheat-sheet).

### 3. Capabilities

- **traits**: `trait` / `impl` / `use`, dispatch, traits as types (interface values / arrays / fields / boxing), trait default methods
- **memory**: `Drop` / `delete`, `own` (AutoDrop), block-level `defer` (Phase 38), path-sensitive leak warnings, `borrow` + `Handback`
- **modules**: `namespace` / `import` / `pub` / multi-file `ct build` / directory = namespace
- **mapping**: `map trait T for instance …`, zero-cost `.m.ct` static mapping, companion C shims, `bindings/` for C libraries
- **passthrough**: `#ct-raw` / `#ct-endraw` raw blocks (macros and hand-written C land in the generated `.c` byte for byte)
- **diagnostics and tooling**: `#line` traceability, `--diagnostics=json|text`, multi-error recovery, incremental cache, `ct get` / `ct install`
- **generic functions**: `T name<T>(…)` + `name<int>(…)`, monomorphised at compile time (Phase 26); **bounded generics** `T name<T: Trait>(…)` (Phase 28)
- **generic structs and the built-in containers**: `struct Name<T, U>` + `impl<T> Name<Args>` with static dispatch (Phase 29); `Vec<T>` / `Map<K,V>` need no import, and `foreach` walks a `Map` in insertion order
- **not done by design**: inheritance, type checking on the default compile path (`ct check` runs bounded checks only), optimisation (the language is not final until `1.0.0`); parameterised traits are not implemented and not scheduled

The expansion rules live in [docs/language-spec.md](docs/language-spec.md); idioms in
[docs/patterns.md](docs/patterns.md); ownership conventions in [docs/memory-guide.md](docs/memory-guide.md).

### 4. Repository layout

`selfhost/` is the bootstrap chain: `l0/` (the C seed) → `l1/` (frozen) → `l2/` (regression oracle) → `ct-ast/`
(the mainline that provides the installed `ct`); `test/` holds tests and goldens; `docs/` holds documentation;
`bindings/` holds declarative C-library bindings; the standard library is the separate ct-pkg package `std`
(`ct get std`; it is no longer shipped with this repository); `issues/` is the review ledger; `AGENTS.md` is
the change contract.
Directory-level notes are in [selfhost/README.md](selfhost/README.md), [test/README.md](test/README.md) and
[docs/architecture.md](docs/architecture.md).

### 5. Docs and tests

- Documentation index: [docs/README.md](docs/README.md)
- Tests: `bash selfhost/check-all.sh` runs 11 hard gates; the layer map is in [test/README.md](test/README.md)
- Read [AGENTS.md](AGENTS.md) before changing code

### 6. License

GPL-3.0-or-later for the compiler itself (see [LICENSE](LICENSE)); the `.c` / `.h` it generates and your `.ct`
sources are **not covered by the GPL** ([LICENSE.EXCEPTION](LICENSE.EXCEPTION)); `examples/`, `test/` and
`editors/` are MIT.

### 7. Contact

Author: Sam X. Xu · samxxu@gmail.com · please open an [issue](https://github.com/samxxu/ct-lang/issues) first.
