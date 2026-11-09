# 包作者指南

> 中文 · [English](#english)
>
> 状态：v1（Phase 18.1，2026-11-02）。工具实现见
> [`selfhost/ct-ast/tool/pkg/`](../selfhost/ct-ast/tool/pkg/)；binding 写法见
> [bindings/README.md](../bindings/README.md)；首批官方包见
> [design/phase18.md](design/phase18.md) 的 18.3–18.5。

---

## 中文

### 1. 一个包长什么样

包仓库的**根目录就是包根**：`ct.pkg`、`LICENSE` 与源码单元并列，不嵌套子目录。

```
hello/
├── ct.pkg          # 清单（唯一由工具强制的文件）
├── LICENSE         # 许可证（发布约定必备；工具不校验，见 §5）
└── hello.h.ct      # 源码单元，可多个
```

源码单元遵守 [AGENTS.md](../AGENTS.md) §2 的「一单元一主类型」：

- `.h.ct`：`trait` / `struct` 声明、全局实例，以及 `pub fn` 函数——**`.h.ct` 可以导出函数**；
  std 把实现放在 `.ct` 只是风格选择。`pub` 才跨单元可见；
- `.ct`：普通实现单元（`pub` 函数），不发布接口；
- `.m.ct`：零成本静态映射，不产 `.c` / `.h`；
- binding 形式（`#include` 直通 + `map`）按 [bindings/README.md](../bindings/README.md)。

#### 单元目录 = 命名空间

单元声明了文件级命名空间，就必须坐在同名目录里：`namespace a::b;` 的单元位于 `<包根>/a/b/`。

```
acme/
├── ct.pkg
├── acme/
│   ├── Uart.h.ct        # namespace acme;
│   └── uart.m.ct        # namespace acme;
└── examples/
    └── main.ct          # import acme::Uart;  无 namespace，不受目录规则约束
```

- 这是编译器的既有语义（D13 方案 A：只校验、不推导）。传 `--ns-root <包根>` 时，`ct build` 对每个
  声明了命名空间的入参单元检查目录，不符即报
  `namespace 'a::b' does not match the directory '...'`。
- 不带 `--ns-root` 时**不做**这项校验；`--ns-root` 只检查落在该根下的单元（根外文件静默跳过），
  所以自检要传包根、并把包内单元都作为入参。
- 没有 `namespace` 声明的单元不受目录规则约束（C 映射单元与 `.m.ct` shim 多属此类），它们的位置
  只由 `import a::b::Unit` 的解析路径决定。向这类单元补命名空间会改变其导出符号，属于破坏性变更。
- 本仓库（ct-pkg）另提供 `tools/check-layout.sh`，遍历全部包的 `*.ct`、读出命名空间并与相对目录
  比对，可放进 CI：`tools/check-layout.sh`（或指定包根 `tools/check-layout.sh hal sqlite`）。

### 2. `ct.pkg` 的键

行式清单：`key = value`，`#` 起注释，`dep` 可重复，未知键**忽略**（向前兼容）。

| 键 | 必填 | 含义 |
| --- | --- | --- |
| `name` | 是 | 包名，见 §3 |
| `version` | 是 | `x.y.z`（工具只解析前三位数字；预发布 / 构建元数据不纳入） |
| `dep` | 否，可重复 | 依赖，`name` 或 `name@range`；格式与 Phase 8 一致 |
| `cflags` | 否 | 消费者编译该包时附加的编译选项，`ct install` 折进打印的命令 |
| `ldflags` | 否 | 链接选项（如 C 映射包的 `-lm`），同上 |
| `requires` | 否 | 对编译器版本的约束；**不满足时 `ct get` / `ct install` 失败**，`--force` 才降级为告警 |
| `licence` | 否 | 许可证标识（SPDX 风格，如 `MIT`）。**仅约定，工具不解析** |

约定而不是工具的强制项：工具只强制 `name` 与 `version` 非空；`name` / `version` 缺失或为空时
`ct get` 报 `cannot read '<dir>/ct.pkg'`。命名、tag、目录与 `licence` 由索引收录与 CI 审核。

`cflags` / `ldflags` / `requires` 由 `ct install` 读取；`install` 把每个包的 `cflags` / `ldflags`
拼进**一条** `ct build` 命令，遇到不满足的 `requires` 直接失败（`ct install --force` 才继续，
并把原因打到 stderr）。`requires` 也在 `ct get` 里检查，且**发生在写 `ct.lock` 之前**：不满足时本次
`get` 失败、既有 `ct.lock` 一个字节都不改（`ct get --force` 才继续并告警）。

### 3. 命名、版本与 tag

- 包名：`[a-z0-9][a-z0-9-]*`（小写字母、数字、连字符；不以连字符开头）。
- **仓库名 = 包名**：`github.com/ct-pkg/<name>`。
- tag：`v<version>`；索引行的 `tag` 字段记录实际 tag（可带或不带 `v`）。
- `dep` 的范围沿用 Phase 8 子集：`^x.y.z`、`~x.y.z`、`>=` / `>` / `<` / `<=` / `=`、裸版本（精确）
  或 `*`，多个条件用空格表示 AND。解析用 MVS（取满足范围的最低版本）。
- 破坏性变更必须换 `x.y.z` 的主版本号；本阶段不研究传递更新的策略。

### 4. 发布、索引与消费

1. **发布**：仓库根放 `ct.pkg` 与源码，打 tag `v<version>` 并推送。
2. **索引收录**：在 `ct-pkg/index` 的 `index` 文件追加一行，五字段、空白分隔：

   ```
   name version git-url tag sha256:<64 hex>
   ```

   摘要按 `ct.lock` 的同一算法计算（按路径排序后把每个文件的相对路径与内容汇入单流 SHA-256）。
   索引由 CI 生成并提交（18.2），本地可用 `CT_INDEX=<file>` 或 `--index <file>` 指向任意纯文本索引。
3. **消费**：

   ```sh
   ct get <name>@<range>        # 裸名经索引解析；本地目录用 ./path 或 file://
   ct verify                    # 离线：校验 vendor/ 与 ct.lock 的摘要
   ct install                   # 离线：校验摘要与依赖覆盖，打印一条可直接执行的 ct build 命令
   ct update                    # 离线：按 ct.pkg 重解并重写 ct.lock
   ```

   `ct verify` 只做摘要校验，**不读 `ct.pkg`**；清单里的 `dep` 是否被 `ct.lock` 覆盖由 `ct install` 判定
   （缺依赖时报 `dependency '<spec>' is not satisfied by ct.lock`）。
   `ct get` 一次只解析一个 spec，但会保留 `ct.lock` 中本次没有重解的其它行；重复 get 同一个包只替换
   该包的行，不会重复。这样再 get 一个新包不会把先前钉住的版本弄丢，随后的 `ct update` 仍按锁里的
   commit 解析。
   `ct get` 可用 git——它是**包管理路径**里唯一的子进程调用点；`ct update` / `ct verify` / `ct install`
   零网络、零子进程。编译器侧 `ct compile` / `ct build --emit-c` 零网络、零子进程，但 `ct build`
   的默认形态会经 `$CC` 派生子进程去链接（`--cc` > `$CC` > `cc`）。

### 5. 许可证

- 官方纯 `.ct` 包：**MIT**。
- C 库映射包：沿用上游许可证，并在 `ct.pkg` 的 `licence` 标注。
- 每个包必须有 `LICENSE` 文件；`licence` 键只是约定，工具不校验文件内容。

### 6. 常见失败

| 现象 | 原因 | 处置 |
| --- | --- | --- |
| `cannot read '<dir>/ct.pkg'` | 缺清单，或 `name` / `version` 为空 | 补键；值不能为空白 |
| `... does not satisfy '<range>'` | 版本不在范围内 | 改 `dep` 范围或发新版 |
| `no tag of '<name>' satisfies '<range>'` | git 源没有匹配 tag | 打 `v<version>` tag |
| `digest ... does not match ct.lock` | `vendor/` 被改动或锁过期 | 重新 `ct get` / `ct update` |
| `requires 'ct >= …'` 报错 | 编译器版本偏旧 | 升级编译器；确需继续时用 `ct get --force` / `ct install --force` |
| 索引读不到 | `--index` / `CT_INDEX` 路径错 | 检查路径；无索引时裸名无法解析 |

---

## English

### 1. What a package looks like

The repository root **is** the package root: `ct.pkg`, `LICENSE` and the source units sit side by side,
with no nested subdirectory.

```
hello/
├── ct.pkg          # the manifest (the only file the tool enforces)
├── LICENSE         # the licence (required by convention; the tool does not check it, see §5)
└── hello.h.ct      # a source unit; there may be several
```

Source units follow "one unit, one primary type" from [AGENTS.md](../AGENTS.md) §2:

- `.h.ct`: `trait` / `struct` declarations, global instances, and `pub fn` functions — a `.h.ct`
  **can** export functions; std keeping implementations in `.ct` is only a style choice. Only `pub`
  crosses a unit;
- `.ct`: an ordinary implementation unit (`pub` functions), publishing no interface;
- `.m.ct`: zero-cost static mappings, emitting no `.c` / `.h`;
- binding form (`#include` passthrough + `map`) per [bindings/README.md](../bindings/README.md).

#### Unit directory = namespace

A unit that declares a file-scoped namespace must live in the matching directory: a unit with
`namespace a::b;` sits in `<package-root>/a/b/`.

```
acme/
├── ct.pkg
├── acme/
│   ├── Uart.h.ct        # namespace acme;
│   └── uart.m.ct        # namespace acme;
└── examples/
    └── main.ct          # import acme::Uart;  no namespace, so no directory rule
```

- This is existing compiler semantics (D13 option A: validation, not derivation). With
  `--ns-root <package-root>`, `ct build` checks every input unit that declares a namespace and reports
  `namespace 'a::b' does not match the directory '...'` on a mismatch.
- Without `--ns-root` the check does not run. `--ns-root` only inspects units that fall under the root
  (files outside it are skipped silently), so a self-check must pass the package root and the package's
  units as inputs.
- Units without a `namespace` declaration are exempt (C mapping units and their `.m.ct` shims usually
  are); their location is decided only by `import a::b::Unit` resolution. Adding a namespace to such a
  unit would change its exported symbols, which is a breaking change.
- This repository (ct-pkg) also ships `tools/check-layout.sh`, which walks every package's `*.ct`,
  reads the namespace and compares it with the relative directory; it is CI-ready:
  `tools/check-layout.sh` (or name package roots: `tools/check-layout.sh hal sqlite`).

### 2. The keys of `ct.pkg`

A line-oriented manifest: `key = value`, `#` starts a comment, `dep` may repeat, and unknown keys are
**ignored** (forward compatibility).

| Key | Required | Meaning |
| --- | --- | --- |
| `name` | yes | the package name, see §3 |
| `version` | yes | `x.y.z` (the tool reads the first three numbers; pre-release / build metadata are out of scope) |
| `dep` | no, repeatable | a dependency, `name` or `name@range`; the Phase 8 format |
| `cflags` | no | extra compiler flags for consumers; `ct install` folds them into the printed command |
| `ldflags` | no | link flags (e.g. `-lm` for a C mapping package); same |
| `requires` | no | a compiler-version constraint; **a mismatch fails `ct get` and `ct install`**; `--force` downgrades it to a warning |
| `licence` | no | the licence identifier (SPDX style, e.g. `MIT`). **A convention only; the tool does not parse it** |

Conventions, not tool enforcement: the tool only requires a non-empty `name` and `version`; a missing or
empty one makes `ct get` report `cannot read '<dir>/ct.pkg'`. Naming, tags, layout and `licence` are
checked when the index accepts a package and by CI.

`cflags` / `ldflags` / `requires` are read by `ct install`, which folds every package's `cflags` /
`ldflags` into **one** `ct build` command; an unsatisfied `requires` fails the install, and only
`ct install --force` continues (printing the reason to stderr). `requires` is checked by `ct get` too,
**before `ct.lock` is written**: a mismatch fails that `get` and leaves an existing `ct.lock`
byte-identical (`ct get --force` continues with a warning).

### 3. Names, versions and tags

- Package name: `[a-z0-9][a-z0-9-]*` (lowercase letters, digits, hyphens; no leading hyphen).
- **Repository name = package name**: `github.com/ct-pkg/<name>`.
- Tag: `v<version>`; the index's `tag` field records the actual tag (with or without the `v`).
- `dep` ranges keep the Phase 8 subset: `^x.y.z`, `~x.y.z`, `>=` / `>` / `<` / `<=` / `=`, a bare
  version (exact) or `*`; several conditions separated by spaces mean AND. Resolution is MVS (the
  lowest satisfying version).
- A breaking change must move the major number; the transitive-update policy is out of scope here.

### 4. Publishing, the index and consuming

1. **Publish**: put `ct.pkg` and the sources at the repository root, tag `v<version>` and push.
2. **Indexing**: append one line to the `index` file of `ct-pkg/index`, five whitespace-separated
   fields:

   ```
   name version git-url tag sha256:<64 hex>
   ```

   The digest uses `ct.lock`'s algorithm (sorted relative paths, each path and its bytes folded into
   one SHA-256 stream). The index is generated and committed by CI (18.2); locally, `CT_INDEX=<file>`
   or `--index <file>` points at any plain-text index.
3. **Consuming**:

   ```sh
   ct get <name>@<range>        # a bare name resolves through the index; a local dir is ./path or file://
   ct verify                    # offline: check vendor/ against the ct.lock digests
   ct install                   # offline: check digests and dependency coverage, print one ct build command
   ct update                    # offline: re-resolve ct.pkg and rewrite ct.lock
   ```

   `ct verify` checks digests only and **does not read `ct.pkg`**; whether every `dep` in the manifest
   is covered by `ct.lock` is decided by `ct install` (a missing one reports
   `dependency '<spec>' is not satisfied by ct.lock`).
   `ct get` resolves one spec per run, but it keeps the `ct.lock` rows it did not resolve again;
   re-getting the same package replaces its row instead of duplicating it. Getting a new package
   therefore cannot unpin an older one, and a later `ct update` still resolves from the locked commit.
   `ct get` may use git — it is the only subprocess call site on the **package-management path**;
   `ct update` / `ct verify` / `ct install` are network-free and subprocess-free. On the compiler side
   `ct compile` / `ct build --emit-c` are network-free and subprocess-free, but the default form of
   `ct build` spawns `$CC` to link (`--cc` > `$CC` > `cc`).

### 5. Licensing

- Official pure-.ct packages: **MIT**.
- C-library mapping packages: inherit the upstream licence and state it in `ct.pkg`'s `licence`.
- Every package must carry a `LICENSE` file; the `licence` key is a convention and the tool does not
  verify the file.

### 6. Common failures

| Symptom | Cause | Fix |
| --- | --- | --- |
| `cannot read '<dir>/ct.pkg'` | missing manifest, or an empty `name` / `version` | add the key; values may not be blank |
| `... does not satisfy '<range>'` | the version is outside the range | widen the `dep` range or release a new version |
| `no tag of '<name>' satisfies '<range>'` | no matching tag on the git source | tag `v<version>` |
| `digest ... does not match ct.lock` | `vendor/` was edited or the lock is stale | re-run `ct get` / `ct update` |
| a `requires 'ct >= …'` error | the compiler is older than the package wants | upgrade; use `ct get --force` / `ct install --force` if you must continue |
| the index cannot be read | a wrong `--index` / `CT_INDEX` path | fix the path; without an index a bare name cannot resolve |
