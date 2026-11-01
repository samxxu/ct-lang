# Change Log

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
