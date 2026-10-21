# Change Log

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
