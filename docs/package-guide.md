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
├── ct.pkg          # 清单（唯一必填文件）
├── LICENSE         # 许可证（必填，见 §5）
└── hello.h.ct      # 源码单元，可多个
```

源码单元遵守 [AGENTS.md](../AGENTS.md) §2 的「一单元一主类型」：

- `.h.ct`：`trait` / `struct` 声明与全局实例，`pub` 才跨单元可见；
- `.c.ct`：普通实现（`pub` 函数）；
- `.m.ct`：零成本静态映射，不产 `.c` / `.h`；
- binding 形式（`#include` 直通 + `map`）按 [bindings/README.md](../bindings/README.md)。

### 2. `ct.pkg` 的键

行式清单：`key = value`，`#` 起注释，`dep` 可重复，未知键**忽略**（向前兼容）。

| 键 | 必填 | 含义 |
| --- | --- | --- |
| `name` | 是 | 包名，见 §3 |
| `version` | 是 | `x.y.z`（工具只解析前三位数字；预发布 / 构建元数据不纳入） |
| `dep` | 否，可重复 | 依赖，`name` 或 `name@range`；格式与 Phase 8 一致 |
| `cflags` | 否 | 消费者编译该包时附加的编译选项，`ct install` 折进打印的命令 |
| `ldflags` | 否 | 链接选项（如 C 映射包的 `-lm`），同上 |
| `requires` | 否 | 对编译器版本的约束；**不满足只告警**，不拒绝安装 |
| `licence` | 否 | 许可证标识（SPDX 风格，如 `MIT`）。**仅约定，工具不解析** |

约定而不是工具的强制项：工具只强制 `name` 与 `version` 非空；`name` / `version` 缺失或为空时
`ct get` 报 `cannot read '<dir>/ct.pkg'`。命名、tag、目录与 `licence` 由索引收录与 CI 审核。

`cflags` / `ldflags` / `requires` 由 `ct install` 读取；`install` 把每个包的 `cflags` / `ldflags`
拼进**一条** `ct build` 命令，并把不满足的 `requires` 打到 stderr。

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
   ct verify                    # 离线：校验 vendor/ 与 ct.lock 的摘要与依赖覆盖
   ct install                   # 离线：打印一条可直接执行的 ct build 命令
   ct update                    # 离线：按 ct.pkg 重解并重写 ct.lock
   ```

   `ct get` 可用 git（唯一的子进程调用点）；`ct update` / `ct verify` / `ct install` 零网络、
   零子进程。编译器本身（`ct compile` / `ct build --emit-c`）零网络。

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
| `requires 'ct >= …'` 告警 | 编译器版本偏旧 | 升级编译器；**不阻塞安装** |
| 索引读不到 | `--index` / `CT_INDEX` 路径错 | 检查路径；无索引时裸名无法解析 |

---

## English

### 1. What a package looks like

The repository root **is** the package root: `ct.pkg`, `LICENSE` and the source units sit side by side,
with no nested subdirectory.

```
hello/
├── ct.pkg          # the manifest (the only required file)
├── LICENSE         # the licence (required, see §5)
└── hello.h.ct      # a source unit; there may be several
```

Source units follow "one unit, one primary type" from [AGENTS.md](../AGENTS.md) §2:

- `.h.ct`: `trait` / `struct` declarations and global instances; only `pub` crosses a unit;
- `.c.ct`: ordinary implementations (`pub` functions);
- `.m.ct`: zero-cost static mappings, emitting no `.c` / `.h`;
- binding form (`#include` passthrough + `map`) per [bindings/README.md](../bindings/README.md).

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
| `requires` | no | a compiler-version constraint; **a mismatch is a warning**, never a refusal |
| `licence` | no | the licence identifier (SPDX style, e.g. `MIT`). **A convention only; the tool does not parse it** |

Conventions, not tool enforcement: the tool only requires a non-empty `name` and `version`; a missing or
empty one makes `ct get` report `cannot read '<dir>/ct.pkg'`. Naming, tags, layout and `licence` are
checked when the index accepts a package and by CI.

`cflags` / `ldflags` / `requires` are read by `ct install`, which folds every package's `cflags` /
`ldflags` into **one** `ct build` command and prints unsatisfied `requires` to stderr.

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
   ct verify                    # offline: check vendor/ against ct.lock digests and coverage
   ct install                   # offline: print one ct build command you can run as is
   ct update                    # offline: re-resolve ct.pkg and rewrite ct.lock
   ```

   `ct get` may use git (the only subprocess call site); `ct update` / `ct verify` / `ct install` are
   network-free and subprocess-free. The compiler itself (`ct compile` / `ct build --emit-c`) is
   network-free.

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
| a `requires 'ct >= …'` warning | the compiler is older than the package wants | upgrade; **installation is not blocked** |
| the index cannot be read | a wrong `--index` / `CT_INDEX` path | fix the path; without an index a bare name cannot resolve |
