# CT — C with Traits for VS Code

Syntax highlighting, snippets, go-to-definition and language configuration for
**CT**, the trait-flavoured C compiled by
[`ct`](https://github.com/samxxu/ct-lang) (`ctc` remains a compatibility alias).

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
| `import a::b as C;` | `keyword` + namespace path + alias |
| `map trait T for instance x {` | `storage.type` + trait/instance names |
| `map trait T for namespace A::B {` | `storage.type` + trait/host names |
| `map trait T for type char * {` | `storage.type` + trait name, host type by the C grammar |
| `trait T { m() { … } }` | `trait`, then the default body as C |
| `own`, `delete`, `pub`, `namespace` | modifiers/keywords at line start |

`.m.ct` mapping units are plain `.ct` files to the editor (the suffix still
ends in `.ct`), so they get the same highlighting; `#include` / `#define`
prologues are handled by the C grammar.

Everything else — strings, comments, preprocessor lines, types, function
bodies — is **VS Code's own C grammar**, pulled in with `include: source.c`.
No duplicated C grammar to maintain and nothing to drift.

## Go to definition

`Ctrl+Click` / `F12` works inside `.ct` files without any C/C++ extension:

- `p.greet()` → the matching `impl Greeter for Person` method. The receiver's
  struct is taken from `Person p`, `Person *p`, parameters, or `self` inside
  an `impl` block; if it cannot be inferred, every same-name method is offered
  in the peek list.
- `Controller::send` → the function/type in `namespace Controller` (or the
  namespace that owns the type).
- Plain names → trait/struct declarations, `impl` methods, trait method
  declarations (abstract and default bodies), top-level functions (`pub` and
  Allman-style bodies included).
- `c.send()` against a `map`-ed instance → the `map` binding when the receiver
  is the mapped global.
- Trait default methods (batch 36): `c.write_all()` → the impl override when
  one exists, otherwise the default body in the trait; `self->m()` inside a
  default body resolves within that trait; a struct that only wrote
  `} use T;` still resolves.
- Zero-cost static mapping (batch 38): `a.toInt()` on a `char *` receiver
  (arrays decay) → the trait method of the `map trait T for type char *`
  binding, and `libc::Env.get(…)` → the trait method of the
  `map trait T for namespace libc` binding.

The index is built by scanning workspace `.ct` files (`.m.ct` included) on
first use and is invalidated on edits/saves. It is a line-oriented
approximation of the compiler's rules, not a full semantic analyzer: same-name
methods across structs may show multiple candidates, fields are not indexed,
and call sites inside strings/comments still resolve as words.

Strings, chars and comments are tokenised *before* the CT rules, so the
compiler's core guarantee ("never touch anything inside a string, char or
comment") holds for the highlighter too: `printf("use self here")` stays a
plain string.

Also included: comment and bracket configuration, auto-closing and surrounding
pairs, brace-based indentation, block-comment continuation on Enter, and the
snippets `trait`, `structuse`, `impl`, `method`, `call`.

The grammar, snippets and language configuration are **declarative JSON — no
build step**. Navigation lives in a single `extension.js` that uses only the
`vscode` API and Node's `fs`, so there are still **no third-party
dependencies**. The `.ct` sources are not compiled by this extension; use `ct`
(or the `ctc` alias) for that.

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
python3 test/check-grammar.py    # 36 assertions; exit code 0 means it passed
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
npx @vscode/vsce package        # produces ct-vscode-0.2.0.vsix
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

给 **CT（C with Traits）** 用的 VS Code 扩展：语法高亮 + 代码片段 + 跳转定义 + 编辑器配置。

- **CT 独有构造**（`trait` 定义、`use` 子句含逗号列表、`impl … for …`、隐式 `self`）由本扩展高亮；
  **其余全部交给 VS Code 内置的 C 语法**，不需要维护一份 C 语法副本。
- `import a::b as C;`、`map trait T for instance x {`、跨行或被注释分隔的 `trait` / `impl` / `map` 头部均已覆盖。
- **最新特性**：第三十六批的 trait 默认方法（方法体直接写在 trait 里），以及第三十八批的
  `.m.ct` 零成本静态映射（`map trait T for namespace A::B {`、`map trait T for type char * {`，
  `for type` 之后的 C 类型交给 C 语法）。`.m.ct` 映射单元与 `.ct` 用同一套高亮（文件名仍以 `.ct` 结尾）。
- 字符串、字符、注释**先于** CT 规则被整体吃掉，因此编译器"字符串/注释内绝不改写"的保证在高亮层面同样成立。
- **跳转定义**：`Ctrl+Click` / `F12` 可跳到 `impl` 方法、trait/struct 声明、顶层函数与 `map` 绑定；
  `p.greet()` 会按 `p` 的声明类型收窄到对应 `impl`，`self` 取当前 `impl`（默认方法体内则取当前 trait）。
  新特性同样可跳：trait 默认方法（impl 覆盖优先）、静态映射的 `a.toInt()`（按接收者 C 类型 +
  `for type` 宿主匹配）与命名空间调用 `libc::Env.get(…)`。
  它是按行扫描的近似索引，不做完整类型推导：同名方法可能给出多个候选，字段不建索引，字符串/注释里的词也会被当作名字解析。
- 语法与片段仍是纯声明式 JSON，跳转逻辑集中在单个 `extension.js`，只用 `vscode` API 与 Node 内置 `fs`，
  **无构建、无第三方依赖**，可直接 `npx @vscode/vsce package` 打包。
- 发布前需要补两样：`package.json` 里的 `publisher` 改成你真实的 Marketplace 发布者 ID，以及自备一张 128×128 的 `icon.png`。
