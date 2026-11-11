# Change Log

## 0.6.0

- Phase 29 syntax, 12 new rules: `foreach (xs)` (`ct-foreach`), the built-in
  container protocol `Vec<T>` / `Map<K,V>` after `.` or `->`
  (`ct-container-method`: `push`, `get`, `set`, `pop`, `clear`, `retain`,
  `release`, `put`, `remove`, `entry`, `len`, `from`), the type-instantiation
  position `Vec<int> nums;` / `Map<char *, int> ages;` / `Box<Box<int>>`
  (`ct-generic-type`), the static path `Vec<char *>::from(…)`
  (`ct-generic-static-call`), `struct Stack<T> {` and `pub struct Pair<T, U> {`
  (`ct-generic-struct`), `impl<T> Stack<T> {` / `impl<T> Stack<T> use Show {`
  (`ct-generic-impl`), and `item.key` / `item.value` as the `Map` entry pair
  (`ct-foreach-entry`). `ct-generic-decl` now accepts a trait constraint
  (`T max2<T: Ord>(T a, T b)`).
- Phase 30 receiver blocks: `into` as a contextual keyword (`ct-into`, only when
  a `{` follows, so `int into = 1;` stays an identifier), the leading-dot body
  members `.field = v;` / `.method(args);` (`ct-into-field`, `ct-into-method`),
  and the inline spelling `into { .field = v; }`
  (`ct-into-inline-field`, `ct-into-inline-method`). Suffix chains
  (`}.add(2)`, `}->field`, `}[1]`) stay outside the block and are left to C.
- A line that starts with `.name` is scoped as a property/method, which is also
  the correct reading of a multi-line designated initializer; the grammar never
  takes a `{` on its own as the start of an `into` block, so
  `Person p = { .name = … }` is not treated as a receiver block.
- `$` keeps one scope, `variable.language.range-index.ct`: the range
  initializer and the `into` receiver are both `$`, and a line-oriented grammar
  cannot tell them apart. `item` / `i` are not coloured globally — only
  `item.key` / `item.value` are provable without block scope — so a user
  variable named `item` is never mis-highlighted.
- Snippets: `foreach`, `foreachmap`, `vec`, `mapvar`, `generic`,
  `genericbound`, `structg`, `implg`, `into`, `rangeinit`, `vecrange`.
- `test/check-grammar.py`: 168 assertions (167 without node), up from 109, with the Phase 29/30
  fixtures (`examples/21`, `22`, `23`, `24`, `26`, `29`, `test/ast/138`,
  `test/ast/147`) scanned by the gate.

This extension has its own version line; 0.6.0 does not affect the compiler's
`CTC_VERSION`.

## 0.5.1

- Go to definition now resolves a generic declaration `T id<T>(T x)` in
  K&R and Allman bodies, as an `impl` method and as a trait default body. The
  jump target is the declaration line only: `id<int>(42)` and `id<char *>(p)`
  both resolve to `id`, never to an instantiation.
- The indexer is now a plain CommonJS module (`indexer.js`) with executable
  assertions (`test/check-index.js`, 26 cases, run by `check-grammar.py` when
  `node` is present).

This extension has its own version line; 0.5.1 does not affect the compiler's
`CTC_VERSION`.

## 0.5.0

- Highlighting for the Phase 20–26 syntax, 17 rules in all: `type` / `pub type`
  aliases (`ct-type-alias`), generic declarations and calls
  (`ct-generic-decl`, `ct-generic-call`), `loop(n)` / `loop(a..b)`
  (`ct-loop`), the `a..b($)` range operator (`ct-range-dots`), the closure
  arrow `=>` (`ct-closure-arrow`), `_Static_assert` / `static_assert`
  (`ct-static-assert`), the C11 surfaces `_Alignas` (`ct-alignas`),
  `_Alignof T` / `_Alignof(T)` (`ct-alignof-type`, `ct-alignof`), `_Atomic`
  (`ct-atomic`), `_Generic` (`ct-generic-select`), `_Noreturn`
  (`ct-noreturn`), `_Thread_local` (`ct-thread-local`), `_Bool` / `_Complex` /
  `_Imaginary` (`ct-c11-builtin-types`), GNU `__attribute__((…))`
  (`ct-attribute`), and `map` recipes `name(args) -> callee(…)`
  (`ct-recipe`).
- `ct-map` accepts a qualified instance host (`for instance hal::uart1`) and
  splits the `::` path from the host name.
- Contextual keywords stay contextual: `int loop = 5;`, `loop:`, `...`,
  `a >= b`, `p->x`, `dog_get()->hi();` and `return id<int>(42);` are all
  pinned by negative assertions.
- `test/check-grammar.py`: 108 assertions (40 before), with the Phase 20–26
  fixtures under `test/ast/` and `test/modules/map_ns/`; every new assertion
  was shown to fail by mutating its rule.
- `extension.js` is unchanged. The go-to-definition index still does not
  register generic function/method templates (`T id<T>(T x)`); the gap and its
  fix criteria are recorded as DOC-68 in `issues/docs/`.

## 0.4.0

- Highlighting for raw pass-through (Phase 17.3): `#ct-raw` / `#ct-endraw`
  form an embedded block (`meta.raw.ct`) whose body is left to the C grammar,
  so a macro or a hand-written function inside it is not read as a CT construct.
- `test/check-grammar.py`: 36 assertions, adding the raw marker pair and a
  "no CT keyword inside the block" check.

## 0.3.0

- Highlighting for `borrow` (`storage.modifier.borrow.ct`) in both of its
  contextual-keyword forms: a statement-initial declaration (`borrow struct
  Conn *c = …`) and a parameter annotation (`void render(borrow struct Conn *c)`).
- The built-in traits `Handback` and `Drop` highlight as trait types.
- `test/check-grammar.py`: 33 assertions, covering the two `borrow` forms.

## 0.2.0

- Highlighting for the batch-36 / batch-38 syntax: `map trait T for namespace
  A::B`, `map trait T for type char *` (the host C type is left to the C
  grammar), and trait default method bodies. `.m.ct` mapping units need no
  extra registration — the `.ct` suffix already covers them.
- Go-to-definition for the same features: trait default methods (an `impl`
  override wins, otherwise the body in the trait; `self->m()` inside a default
  body stays in that trait; `} use T;`-only structs resolve), zero-cost static
  mapping calls (`a.toInt()` on a `char *`/array receiver via the
  `for type` host, and `Host::Trait.method(…)` via the `for namespace` host),
  and `map` bindings keyed by the mapped instance.
- `test/check-grammar.py`: 31 assertions, covering the two new `map` hosts and
  the default-method fixtures.

## 0.1.0

- Go-to-definition (`Ctrl+Click` / `F12`) for `.ct` files via a single
  dependency-free `extension.js`: `impl` methods (narrowed by the receiver's
  declared struct), trait/struct declarations, trait method declarations,
  top-level functions, `Qual::name` calls, and `map` bindings.
- Highlighting fixes: `import … as Alias;`, headers whose tokens are split by
  comments or line breaks (`trait` / `impl` / `map`), and `pub` is no longer
  matched mid-line (so `int pub = 1;` stays plain).
- `test/check-grammar.py`: 27 assertions, including the import alias, the
  comment-split headers and the anchored `pub`.

## 0.0.1

Initial release.

- Syntax highlighting for the CT-specific constructs: `trait` definitions,
  `impl … for …` blocks, `use` clauses (including comma-separated lists) and
  the implicit `self` receiver. Everything else is delegated to VS Code's
  built-in C grammar via `include: source.c`.
- Strings and comments are tokenised before the CT rules, so the compiler's
  "never touch anything inside a string, char or comment" guarantee holds for
  the highlighter too.
- Language configuration: line/block comments, brackets, auto-closing and
  surrounding pairs, brace indentation, block-comment continuation on Enter.
- Snippets: `trait`, `structuse`, `impl`, `method`, `call`.
- `test/check-grammar.py`: a dependency-free smoke test (13 assertions at
  release) that replays the grammar's patterns over the demos and
  checks both directions — the CT rules fire on `trait` / `use` / `impl` /
  `self`, and stay silent inside comments, strings and look-alike identifiers
  (`use_it`, `selfish`).
