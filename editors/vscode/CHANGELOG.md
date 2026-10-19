# Change Log

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
  release; 20 today) that replays the grammar's patterns over the demos and
  checks both directions — the CT rules fire on `trait` / `use` / `impl` /
  `self`, and stay silent inside comments, strings and look-alike identifiers
  (`use_it`, `selfish`).
