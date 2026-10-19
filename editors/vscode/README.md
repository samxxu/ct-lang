# CT — C with Traits for VS Code

Syntax highlighting, snippets and language configuration for **CT**, the
trait-flavoured C compiled by [`ct`](https://github.com/samxxu/ct-lang) (`ctc`
remains a compatibility alias).

```c
trait Greeter {
    void greet();
}

struct Person {
    char *name;
} use Greeter;

impl Greeter for Person {
    void greet() {
        printf("Hello, %s\n", self->name);
    }
}
```

## What it gives you

| Construct | Highlighted as |
| --- | --- |
| `trait Greeter {` | `storage.type` + `entity.name.type` |
| `} use Greeter, Counter;` | `keyword` + one `entity.name.type` per trait |
| `impl Greeter for Person {` | `storage.type`, `keyword`, two `entity.name.type` |
| `self->name` | `variable.language` (like C++ `this`) |

Everything else — strings, comments, preprocessor lines, types, function
bodies — is **VS Code's own C grammar**, pulled in with `include: source.c`.
No duplicated C grammar to maintain and nothing to drift.

Strings, chars and comments are tokenised *before* the CT rules, so the
compiler's core guarantee ("never touch anything inside a string, char or
comment") holds for the highlighter too: `printf("use self here")` stays a
plain string.

Also included: comment and bracket configuration, auto-closing and surrounding
pairs, brace-based indentation, block-comment continuation on Enter, and the
snippets `trait`, `structuse`, `impl`, `method`, `call`.

The extension is **declarative JSON — no build step, no dependencies**. The
`.ct` sources are not compiled by this extension; use `ct` (or the `ctc` alias)
for that.

## Install

From a local checkout (development):

```bash
cd editors/vscode
code --extensionDevelopmentPath="$PWD"   # open VS Code with the extension loaded
```

Or symlink it into your extensions folder and reload VS Code:

```bash
ln -s "$PWD" ~/.vscode/extensions/ct-vscode
```

To get an F5 workflow, add a launch configuration at the repository root as
`.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Run Extension",
      "type": "extensionHost",
      "request": "launch",
      "args": ["--extensionDevelopmentPath=${workspaceFolder}/editors/vscode"]
    }
  ]
}
```

## Checks

```bash
python3 test/check-grammar.py    # 21 assertions; exit code 0 means it passed
```

The script replays the grammar's patterns with Python's `re` over the demos in
`examples/` and the cases in `test/cases/`, asserting both directions: the CT
rules fire on `trait` / `use` / `impl` / `self`, and they stay silent inside
comments, strings and look-alike identifiers (`use_it`, `selfish`).

It is a smoke test, not a substitute for a human pass: Python's `re` is not
Oniguruma, and the real engine also runs VS Code's built-in `source.c` grammar,
which the script deliberately does not emulate. Open a `.ct` file in VS Code
once before publishing.

## Package and publish

```bash
cd editors/vscode
npx @vscode/vsce package        # produces ct-vscode-0.0.1.vsix
npx @vscode/vsce publish        # needs a Marketplace publisher + PAT
```

Two things are needed before publishing:

- **`publisher`** in `package.json` must match your
  [Marketplace publisher id](https://marketplace.visualstudio.com/manage)
  (currently set to `samxxu`, which does not exist yet).
- **`icon.png`** — a 128×128 PNG referenced as `"icon": "icon.png"`.
  It is intentionally absent from the repo; add your own before publishing
  (`vsce` still packages without it, but the listing looks bare).

## License

MIT — see [LICENSE](LICENSE). The compiler itself is GPL-3.0-or-later with an
output exception; see the [repository](https://github.com/samxxu/ct-lang) for
details.

---

## 中文说明

给 **CT（C with Traits）** 用的 VS Code 扩展：语法高亮 + 代码片段 + 编辑器配置。

- **CT 独有构造**（`trait` 定义、`use` 子句含逗号列表、`impl … for …`、隐式 `self`）由本扩展高亮；
  **其余全部交给 VS Code 内置的 C 语法**，不需要维护一份 C 语法副本。
- 字符串、字符、注释**先于** CT 规则被整体吃掉，因此编译器"字符串/注释内绝不改写"的保证在高亮层面同样成立。
- 纯 JSON，**无构建、无依赖**，可直接 `npx @vscode/vsce package` 打包。
- 发布前需要补两样：`package.json` 里的 `publisher` 改成你真实的 Marketplace 发布者 ID，以及自备一张 128×128 的 `icon.png`。
