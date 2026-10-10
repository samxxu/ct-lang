# AGENTS.md — 项目规约（面向 AI 编码代理）

> 中文 · [English](#english)

本文件是 `ctc` 仓库的**唯一行为规约**。任何 AI 编码代理在本仓库动手之前，必须先读完本文件；
它与代码冲突时以代码为准，但**修改代码前必须先跟用户确认**。

---

## 中文

### 1. 项目画像

| 项 | 值 |
| --- | --- |
| 是什么 | ct —— CT（*C with Traits*）到纯 C 的 source-to-source 编译器 |
| 命名 | 项目/语言 `ct`（源文件后缀 `.ct`）；当前命令 `ctc`；GitHub 仓库 `ct-lang`（仅是仓库名）。差异是刻意的（同 `tinycc` 发布 `tcc`），**不要"统一"**。命令的最终形态已定为单入口 `ct`（`ctc` 保留为兼容别名），**尚未落地**，见 roadmap |
| 实现语言 | C（C99），**单文件** `ctc.c` |
| 依赖 | 无。只用 libc（`stdio` / `stdlib` / `string` / `ctype` / `stdarg`） |
| 构建 | `gcc ctc.c -o ctc`（必须 `-Wall -Wextra -std=c99` 零警告） |
| 当前版本 | v0.0.1（`CTC_VERSION`，见 `ctc.c` 顶部；会写进生成物注释） |
| 许可 | 编译器 GPL-3.0-or-later（`LICENSE`）；`.ct` 源码与生成物**不受 GPL 约束**（`LICENSE.EXCEPTION`）；`examples/`、`test/` 与 `editors/` 为 MIT |
| 当前阶段 | Phase 0：只做结构转换，不做类型检查、不做优化、不做错误恢复 |
| 规模目标 | 保持单文件、可一次读完；不要把 `ctc.c` 拆成多文件 |

### 2. 文件职责与改动边界

| 文件 | 性质 | 可否修改 |
| --- | --- | --- |
| `ctc.c` | 源码，全部实现 | ✅ 唯一需要改的实现文件 |
| `examples/**` | 源码：可运行示例（`<name>.ct` + `<name>.expected.out`） | ✅ 新增语法时同步扩充；生成物不入库 |
| `test/**` | 测试：用例、golden 基线、runner | ✅ 可改；`*.expected.*` 只能用 `./ctc` 重新生成 |
| `editors/**` | 编辑器插件：`editors/vscode/`（VS Code，纯 JSON） | ✅ 可改；见下方硬性边界 |
| `LICENSE`、`LICENSE.EXCEPTION` | 许可全文与输出例外 | ❌ 仅限用户明确要求时修改 |
| `README.md`、`AGENTS.md`、`docs/*` | 文档 | ✅ |
| `ctc`、生成的 `.c`/`.h`、`.o` | 编译产物 | ❌ 不入库 |

硬性边界：

- 生成的 `.c` 必须**自包含**（不 `#include` 生成的 `.h`），保证生成物可单独编译。
- 生成的头文件只放类型（trait vtable、struct 定义），不放 `static` 函数/变量。
- 不引入任何第三方库、构建系统、代码生成脚本。
- `editors/**` 必须保持**纯声明式 JSON**：无构建步骤、无 npm 依赖、无需打包器，改完可直接
  `npx @vscode/vsce package`。插件只负责高亮与编辑体验，不做语法校验、不调用 `ctc`。
- 不改变已发布产物的命名规则（`<Trait>_vtbl`、`__<trait>_vptr`、`<Struct>_<Trait>_<method>`、`<Struct>_<Trait>_vtable`），除非用户明确要求。

### 3. 代码风格

- 缩进 4 空格，K&R 花括号；**函数定义**的左花括号另起一行。
- 所有内部函数一律 `static`；不使用非 `static` 的全局函数。
- 命名：
  - 全局变量 `g_` 前缀 + `snake_case`（`g_src`、`g_ntraits`）
  - 函数 `snake_case`（`parse_impl`、`transform_calls`）；「动作」动词开头（`parse_` / `emit_` / `try_` / `find_` / `skip_`）
  - 宏与上限常量 `UPPER_SNAKE`（`MAX_TRAITS`、`MAX_VARS`）
  - 类型 `typedef struct { … } Name;`，**不加** `_t` 后缀（`Trait`、`Struct`、`Method`）
- 注释：**英文**，`/* … */` 风格；只解释「为什么」，不复述代码。
- 内存：一律走 `xmalloc` / `xstrndup`（失败即 `exit(1)`）；拼接字符串用 `Buf`（`buf_puts` / `buf_putc` / `buf_putn`），不要写 `strcat`。
- 上限：所有固定容量常量集中在文件头部，越界一律 `die()` 报错，不允许静默截断。
- 逐个函数按「工具 → 源扫描 → 符号表 → 签名解析 → 生成器 → 解析器 → 行重写 → main」的顺序摆放，新增函数放进对应分区，不要乱序插入。

### 4. 错误处理约定

- 唯一入口是 `die(pos, fmt, ...)`：`pos` 是 `g_src` 中的字节偏移，由它换算出 `行:列`。
- 报错格式固定为 `文件:行:列: error: 描述`，描述小写、不加句号、标识符用单引号包裹。
- 遇到无法解析的 trait / struct / impl 语法，或引用未定义的 trait / struct，**必须 `die` 并 `exit(1)`**，不允许「跳过继续」。
- 不允许生成明知编译不过的 C 代码来「糊过去」——能静态判定的错误就要在 `ctc` 阶段报出来。
- 不做错误恢复（Phase 0）：一个错误即终止。

### 5. 修改流程

1. **先读后改**：改任何函数前，先读 `ctc.c` 中相关分区，确认数据流与副作用。
2. **先确认后动手**：涉及行为变更（新增语法、改变命名、改变 CLI）必须先向用户说明方案并获得确认。
3. **最小改动**：只改与任务直接相关的代码，不顺手重构、不调整无关格式、不重命名既有符号。
4. **同步文档**：改动语法或产物命名时，必须同步更新 `docs/language-spec.md`，以及 `README.md` 中的语法表。
5. **重新生成基线**：生成器有任何变化，都要重跑 `./test/run.sh`（其中的 examples 层会端到端校验 `examples/**` 的展开与运行结果），并确认 `test/cases/**` 的 golden 差异符合预期。
6. **改版本号**：`CTC_VERSION` 会进入生成物注释，改它必须重新生成 `test/cases/**` 的全部 golden、同步 `README.md` 与 `docs/roadmap.md` 的版本记录，并跑完整套验证。

### 6. 验证（Definition of Done）

任何改动完成后，必须完整跑通下面三条，并把结果贴给用户：

```bash
# 1) 编译器本身：零警告
gcc -Wall -Wextra -std=c99 ctc.c -o ctc

# 2) 代码生成：应无输出（无报错）。产物写临时目录，避免污染仓库
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c

# 3) 产物：必须编译并输出两行
gcc -Wall -Wextra /tmp/greeter.c -o /tmp/greeter && /tmp/greeter
# Hello, I'm Tom, age 36
# Hello Jerry, I'm Tom
```

补充要求：

- **自动化测试**：`./test/run.sh` 必须全绿（退出码 0）。五层覆盖：ctc 自身零警告构建、
  `test/unit` 白盒单测、`test/cases` golden 快照（生成 → 比对 → 编译 → 运行）、
  `examples/**` 端到端（生成 → 构建 → 运行 → 与 `.expected.out` 比对）、
  `test/errors` 负例诊断（必须非 0 退出，且带 `文件:行:列: error:` 前缀）。`CC=gcc ./test/run.sh` 可换编译器。
- **手工三件套不可省**：套件内部的路径与你手工敲的不完全相同，改完必须按上面三条命令亲自跑一次并贴结果。
- **新增/修改语法必须补用例**：见第 9 节检查清单。
- **编辑器侧**：语法有变必须同步 `editors/vscode/syntaxes/ct.tmLanguage.json`，并跑
  `python3 editors/vscode/test/check-grammar.py`（13 项断言，必须全绿）。它校验插件而不是编译器，
  因此**不进** `./test/run.sh`；反过来它也不能替代手工三件套。
- **诚实报告**：验证失败就如实说失败并贴原始输出，不允许把「没跑」说成「通过」；
  更不允许靠改 golden 基线或 `.expected.out` 来「修」失败——只有在确认编译器行为变更是有意为之之后，才重新生成它们。

### 7. 禁止事项

- 禁止在 `ctc.c` 中引入类型检查、语义分析、优化（Phase 0 范围外）。
- 禁止新增 namespace、泛型、继承、多文件编译支持，除非用户明确把对应阶段指派给你。
- 禁止把 `examples/**` 下生成的 `.c` / `.h` 入库或手工编辑（生成物一律不入库）。
- 禁止为了让示例通过而修改 `examples/**/*.ct` 的语义（可以扩充，不可以削弱）。
- 禁止吞掉错误、禁止静默截断、禁止 `TODO` 空实现留在主路径上。
- 禁止把项目名 `ct`、当前命令 `ctc` 或后缀 `.ct` 改成 `ct-lang` / `ctlang` / `.ctlang`（`ct-lang` 只是仓库名）。唯一被认可的演进是 roadmap 里已定的「单入口 `ct` + `ctc` 兼容别名」，不得自行发明其它名字。
- 禁止删除或改写生成物 banner 里的许可声明行，也禁止移除 `ctc.c` 顶部的 SPDX / 版权 / 例外说明——输出例外必须**随产物走**（见 `LICENSE.EXCEPTION`）。
- 禁止给 `editors/**` 引入构建步骤、npm 依赖或打包器（见第 2 节硬性边界）。
- 禁止提交二进制文件、`.o`、临时文件。

### 8. 提交规范

```
<type>(<scope>): <subject>      # 英文祈使句，≤ 50 字符
```

- `type`：`feat` | `fix` | `docs` | `refactor` | `test` | `chore`
- `scope`：`parser` | `codegen` | `rewrite` | `cli` | `docs` | `example`
- 正文用中文说明「为什么这么改」以及验证方式；一次提交只做一件事。

### 9. 新增语法特性检查清单

开发新特性（如 Phase 1 的 namespace）时逐条确认：

- [ ] 词法识别不会与既有构造冲突（用 `word_at()` 做词边界判断，而不是 `strncmp`）
- [ ] 解析器能对不完整/错误输入给出带位置的报错
- [ ] 生成物的命名规则已写入 `docs/language-spec.md`
- [ ] 未破坏「字符串 / 字符 / 注释内不重写」的既有保证
- [ ] `examples/**` 增加或更新示例，生成物重新展开并人工核对，`.expected.out` 同步更新
- [ ] `test/cases` 增加 golden 用例（基线用 `./ctc <case>.ct -o <case>.expected.c` 重新生成并人工核对，禁止手写），负例补进 `test/errors`
- [ ] 三件套验证通过，且 `./test/run.sh` 全绿
- [ ] `editors/vscode/syntaxes/ct.tmLanguage.json` 覆盖了新构造，`python3 editors/vscode/test/check-grammar.py` 全绿
- [ ] `README.md` / `docs/language-spec.md` 已同步

---

## English

This file is the single behavioural contract for the `ctc` repository. Any coding agent must read it
before touching the code. When this document and the code disagree, the code wins — but **ask the
user before changing code**.

### 1. Project profile

| Item | Value |
| --- | --- |
| What | ct — a source-to-source compiler from CT (*C with Traits*) to plain C |
| Naming | project/language `ct` (files end in `.ct`); current command `ctc`; GitHub repository `ct-lang` (repository name only). The differences are deliberate (cf. the `tinycc` repo shipping `tcc`) — **do not unify them**. The final command shape is decided: a single-entry `ct` with `ctc` kept as a compatibility alias — **not implemented yet**, see the roadmap |
| Language | C (C99), **single file** `ctc.c` |
| Dependencies | None. libc only (`stdio`, `stdlib`, `string`, `ctype`, `stdarg`) |
| Build | `gcc ctc.c -o ctc`, must be warning-free under `-Wall -Wextra -std=c99` |
| Version | v0.0.1 (`CTC_VERSION` at the top of `ctc.c`; it is embedded in generated comments) |
| License | compiler: GPL-3.0-or-later (`LICENSE`); `.ct` sources and generated output are **not covered by the GPL** (`LICENSE.EXCEPTION`); `examples/`, `test/` and `editors/` are MIT |
| Stage | Phase 0 — structure rewriting only: no type checking, no optimisation, no error recovery |
| Size target | Keep it one readable file; do not split `ctc.c` |

### 2. File ownership

| File | Kind | Editable |
| --- | --- | --- |
| `ctc.c` | Source, the whole implementation | ✅ the only implementation file to change |
| `examples/**` | Source: runnable demos (`<name>.ct` + `<name>.expected.out`) | ✅ extend when adding syntax; generated files are not committed |
| `test/**` | Tests: cases, golden baselines, runner | ✅ editable; `*.expected.*` may only be regenerated |
| `editors/**` | Editor extensions: `editors/vscode/` (VS Code, declarative JSON) | ✅ editable; see the hard boundaries below |
| `LICENSE`, `LICENSE.EXCEPTION` | License text and the output exception | ❌ only when the user explicitly asks |
| `README.md`, `AGENTS.md`, `docs/*` | Documentation | ✅ |
| `ctc`, generated `.c`/`.h`, `.o` | Build products | ❌ never commit |

Hard boundaries:

- The generated `.c` must stay self-contained (it must not `#include` the generated `.h`) so that it
  compiles on its own.
- The generated header carries types only (trait vtables, struct definitions) — no `static` code.
- No third-party libraries, build systems, or code-generation scripts.
- `editors/**` must stay **declarative JSON only**: no build step, no npm dependencies, no bundler —
  `npx @vscode/vsce package` must work as-is. Extensions cover highlighting and editing comfort
  only; they do not validate syntax and do not invoke `ctc`.
- Do not change published naming rules (`<Trait>_vtbl`, `__<trait>_vptr`, `<Struct>_<Trait>_<method>`,
  `<Struct>_<Trait>_vtable`) unless the user explicitly asks.

### 3. Code style

- 4-space indent, K&R braces; the opening brace of a **function definition** goes on its own line.
- Every internal function is `static`.
- Naming: globals `g_snake_case`, functions `snake_case` with a verb prefix
  (`parse_`, `emit_`, `try_`, `find_`, `skip_`), constants `UPPER_SNAKE`, types
  `typedef struct { … } Name;` (no `_t` suffix).
- Comments in **English**, `/* … */` style, explaining *why*, not *what*.
- Memory goes through `xmalloc` / `xstrndup` (fail fast), string building through `Buf`.
- All fixed capacities live as `MAX_*` constants at the top of the file; overflow must `die()`, never
  silently truncate.
- Keep functions grouped in the existing order: utilities → source scanning → symbol tables →
  signature parsing → emitters → construct parsers → line rewriting → `main`.

### 4. Error handling

- The only reporting entry point is `die(pos, fmt, ...)`, where `pos` is a byte offset used to derive
  `line:column`.
- Format: `file:line:col: error: message`; lowercase message, no trailing period, identifiers in
  single quotes.
- Unparsable trait/struct/impl syntax, or references to undefined traits/structs, **must** `die` and
  `exit(1)` — never skip and continue.
- Never emit C that is known not to compile. If it can be detected statically, report it in `ctc`.
- Phase 0 has no error recovery: the first error terminates.

### 5. Change workflow

1. **Read before writing.** Inspect the relevant section of `ctc.c` and confirm the data flow.
2. **Confirm before implementing.** Behaviour changes (new syntax, naming, CLI) require user sign-off.
3. **Minimal diff.** No opportunistic refactors, reformatting, or renames.
4. **Update the docs.** Any syntax or naming change must be mirrored in `docs/language-spec.md` and
   the syntax table in `README.md`.
5. **Regenerate the baseline.** After any generator change, re-run `./test/run.sh` (its examples
   layer re-checks `examples/**` end to end) and review any golden diffs under `test/cases/**`.
6. **Version bumps.** `CTC_VERSION` is embedded in the generated comments, so bumping it means
   regenerating every golden under `test/cases/**`, updating the version records in `README.md` and
   `docs/roadmap.md`, and re-running the full suite.

### 6. Definition of done

```bash
gcc -Wall -Wextra -std=c99 ctc.c -o ctc                        # zero warnings
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c         # silent (no errors)
gcc -Wall -Wextra /tmp/greeter.c -o /tmp/greeter && /tmp/greeter   # prints two lines
```

Also required:

- **Automated tests**: `./test/run.sh` must be green (exit 0). Five layers: a warning-free build of
  `ctc`, white-box unit tests in `test/unit`, golden snapshots in `test/cases`
  (generate → diff → compile → run), end-to-end examples in `examples/**`
  (generate → build → run → compare with `.expected.out`), and negative diagnostics in `test/errors`
  (must exit non-zero with a `file:line:col: error:` prefix). `CC=gcc ./test/run.sh` selects a compiler.
- **The manual three-step check stays required** — the suite's internal paths differ from the commands
  you type, so run the three commands above yourself and paste the output.
- **New or changed syntax needs new cases** — see the checklist in §9.
- **Editor side**: a syntax change must be mirrored in `editors/vscode/syntaxes/ct.tmLanguage.json`,
  and `python3 editors/vscode/test/check-grammar.py` (13 assertions) must be green. It checks the
  extension, not the compiler, so it stays **out** of `./test/run.sh` — and it never replaces the
  manual three-step check.
- **Report honestly**: never claim an unrun check passed, and never "fix" a failure by editing a
  golden baseline or an `.expected.out`. Regenerate them only after confirming the behaviour change
  was intended.

### 7. Prohibited

- No type checking, semantic analysis, or optimisation in `ctc.c` (outside Phase 0 scope).
- No namespaces, generics, inheritance, or multi-file support unless assigned.
- No committing or hand-editing the `.c` / `.h` generated under `examples/**` (generated files are
  never committed).
- No weakening of `examples/**/*.ct` to make output pass (extending them is fine).
- No swallowed errors, silent truncation, or `TODO` stubs on the main path.
- Never rename the project `ct`, the current `ctc` command or the `.ct` extension to `ct-lang` /
  `ctlang` / `.ctlang` (`ct-lang` is only the repository name). The one sanctioned evolution is the
  decided "single-entry `ct` with `ctc` as a compatibility alias" recorded in the roadmap — do not
  invent other names.
- Never delete or reword the license line in the generated banner, and never strip the SPDX /
  copyright / exception notice at the top of `ctc.c` — the output exception must **travel with the
  output** (see `LICENSE.EXCEPTION`).
- No build step, npm dependencies, or bundler under `editors/**` (see the hard boundaries in §2).
- No committing binaries, object files, or temporary files.

### 8. Commits

`<type>(<scope>): <subject>` with an English imperative subject ≤ 50 chars; `type` ∈
`feat|fix|docs|refactor|test|chore`; `scope` ∈ `parser|codegen|rewrite|cli|docs|example`. Explain the
*why* and the verification steps in the body (Chinese is fine). One concern per commit.

### 9. Checklist for new syntax features

- [ ] Lexing uses `word_at()` word-boundary checks, not bare `strncmp`
- [ ] Incomplete/invalid input produces a positional error
- [ ] New naming rules documented in `docs/language-spec.md`
- [ ] The "never rewrite inside strings/chars/comments" guarantee still holds
- [ ] `examples/**` extended or updated, regenerated and reviewed, `.expected.out` refreshed
- [ ] `test/cases` extended with golden cases (regenerate baselines with `./ctc <case>.ct -o <case>.expected.c` and review them — never hand-write them); negative cases go to `test/errors`
- [ ] The three-step verification passes **and** `./test/run.sh` is green
- [ ] `editors/vscode/syntaxes/ct.tmLanguage.json` covers the new construct and
      `python3 editors/vscode/test/check-grammar.py` is green
- [ ] `README.md` and `docs/language-spec.md` updated
