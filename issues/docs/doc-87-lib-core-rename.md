# DOC-87 · `lib/std` 与外部 `std` 包同名（bugfix：`lib/core` + `CT_CORE_DIR` + `namespace core`）

| 项 | 值 |
| --- | --- |
| 模块 | docs / 工具链命名 |
| 定性 | **bug**（命名/身份混淆；不是新特性） |
| 严重度 | Medium |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | 所有者 2026-11-21 裁定“改名，作为 bug 去 fix”；[外部评审与惯用卡评估](../../docs/reviews/2026-11-21-v088-external-review-eval.md) §1；[同名核查](../../docs/review/builtin-layer-vs-std-package-name-check.md) |
| 状态 | deferred |
| 处置证据 | **延后（2026-11-22，REV）**：REQ 迁移卡已细化（目录/ENV/回退/引用清单/两条预写验收）；Stage 1 需一次改 9 个代码文件 + 21 个脚本 + 12 个活跃文档，属 DEV 单提交窗口，不在本批 DOC 路径内 |
| blocked-by | 执行触发：v1.0 收口窗口（README 大改尾部 + STD 配合清单就位）；负责人 DEV；Stage 2 另需 spec 命名空间条款后独立提交 |

## 现象

内置层目录叫 `lib/std`，与 ct-pkg 的外部包 `std` 同名；编译器的 `CT_STD_DIR`
也带同一个名字。仓库不得不在 `lib/std/README.md` 里解释“这不是整个 std 的新家”，
用户和外部包仍容易把两者混为一谈。

2026-11-15 的 [同名核查](../../docs/review/builtin-layer-vs-std-package-name-check.md)
结论是“符号表不冲突（内置根命名空间 vs `std::*`）”，但名称层面的混淆仍在；
所有者 2026-11-21 裁定按 **bug** 修复。

## 决策

| 项 | 决定 |
| --- | --- |
| 目录 | `lib/std` → **`lib/core`** |
| 环境变量 | `CT_STD_DIR` → **`CT_CORE_DIR`**（优先）；`CT_STD_DIR` 保留一个 MINOR 回退窗 |
| 命名空间 | **Stage 2：内置层迁到 `namespace core`**；根拼写 `Vec`/`Map`/`String` 等通过兼容别名/预导入保留一个 MINOR，随后切到 `core::*` |
| 外部 `std` 包 | 不动；`import std::str::String` 等继续有效 |
| 版本 | v1.0 前 bugfix；不占 phase，不 bump（随最近一次收口/补丁） |

## 改动面

| 位置 | 改动 |
| --- | --- |
| `lib/std/` | `git mv lib/std lib/core`；`lib/core/README.md` 改标题/说明 |
| `selfhost/ct-ast/frontend/module/Module.h.ct` | 查找顺序：`CT_CORE_DIR` → `CT_STD_DIR`（回退）→ `./lib/core` → `./lib/std`（回退） |
| `selfhost/ct-ast/tool/driver/Driver.h.ct` | 同上 |
| `selfhost/ct-ast/frontend/module/ModuleBoundary.h.ct` | 仓内路径白名单 `lib/std/` → 同时接受 `lib/core/` 与回退 |
| `selfhost/ct-ast/frontend/parse/{Stmt,Expr,Parser}.h.ct`、`backend/emit/Emitter.h.ct` | 路径字符串比较改为“`lib/core/` 或 `lib/std/`”；错误文案优先提示 `CT_CORE_DIR` |
| `selfhost/check-ast.sh`、`test/ast/*.sh`、`test/probes/*` | `CT_STD_DIR` → `CT_CORE_DIR`；保留一个回退测试 |
| `docs/**`、`README.md`、`README.en.md`、`examples/**` | 活跃引用改 `lib/core`；历史文档（`docs/history/**`、`battle/**`）不动 |
| `install.sh` / 分发脚本 | 内置层路径与 `CT_CORE_DIR` 同步 |

兼容窗：

- 新代码设置 `CT_CORE_DIR`；旧的 `CT_STD_DIR` 仍被读取；
- 目录查找先 `lib/core`，找不到再 `lib/std`；
- 一个 MINOR 后移除 `CT_STD_DIR` / `lib/std` 回退，另立清理 issue。

## Stage 1 REQ 迁移卡（2026-11-21 细化）

> 边界：只产出迁移步骤；**不碰代码**。DEV 执行等窗口：README 大改尾部 + STD 配合清单就位后
> 一次抖动；单提交、可整提交回滚。

### 1. 目录落点

- `git mv lib/std lib/core`；文件名不变（`Vec.h.ct` / `Option.h.ct` / `Result.h.ct` /
  `Str.h.ct` / `Box.h.ct` / `README.md`）。
- **不保留 `lib/std` 实体目录**：回退靠 loader 查找旧路径，不靠双目录并存（避免双源漂移）。
- `lib/core/README.md` 标题改「lib/core — 内置层」；加一句“曾用名 `lib/std`（迁移见 DOC-87）”。
  这是活跃文档里**唯一**允许保留旧名的位置。

### 2. `CT_CORE_DIR` 语义

| 优先级 | 来源 | 行为 |
| --- | --- | --- |
| 1 | `CT_CORE_DIR` 已设且目录存在 | 使用；不再看其他来源 |
| 2 | `CT_CORE_DIR` 已设但目录不存在 | **硬错**：`CT_CORE_DIR points to a missing directory: <dir>`；不静默回退 |
| 3 | `CT_CORE_DIR` 未设，`CT_STD_DIR` 已设 | 使用（兼容窗），每次进程打一条 `warning: CT_STD_DIR is deprecated; use CT_CORE_DIR` |
| 4 | 两者都设且不同 | `CT_CORE_DIR` 胜出 + 同上 warning |
| 5 | 都未设 | `./lib/core` → 输入的 sibling `../lib/core` → 旧 `./lib/std` / sibling（旧路径命中时打 warning） |

- 变量值指向**包含 `Vec.h.ct` 的目录**；兼容窗内 `CT_STD_DIR=<repo>/lib/core` 仍有效。
- 找不到时错误文案同时点名两者：`built-in layer not found; set CT_CORE_DIR (legacy CT_STD_DIR)
  or run from the repo root`。
- `--freestanding` 不加载内置层，不受影响。
- 变量只影响**查找根**，不影响文件名、`namespace` 或生成物。

### 3. 一个 MINOR 的回退预案

- **窗口**：随最近 MINOR（v1.0.0 或补丁收口）引入 `lib/core` + `CT_CORE_DIR`；
  `lib/std` 与 `CT_STD_DIR` 在窗口内仍可解析，活跃文档标 deprecated。
- **移除**：v1.1 删除旧路径/旧变量，硬错并提示迁移；另立清理 issue（不并入本卡）。
- **回滚**：Stage 1 是单提交——目录 `git mv`、loader 查找、脚本、活跃文档同进同退；
  回滚 = revert 该提交，`lib/std` 与旧查找恢复，`CT_CORE_DIR` 随之消失（不做双写/半回退）。
- 回滚不依赖 tag、不重写历史；外部消费者在窗口内不需要改。

### 4. 引用替换清单（仓内版）

#### 4.1 自托管代码（9 个文件）

| 文件 | 现行点 |
| --- | --- |
| `selfhost/ct-ast/frontend/module/Module.h.ct` | `lib/std` 查找候选（713/733/739）、注释 217 |
| `selfhost/ct-ast/tool/driver/Driver.h.ct` | 查找候选 330/336、`CT_STD_DIR` |
| `selfhost/ct-ast/frontend/module/ModuleBoundary.h.ct` | 仓内白名单 `core[4]`（118）、注释 126 |
| `selfhost/ct-ast/frontend/parse/Parser.h.ct` | `lib/std/` 路径判断 2742 |
| `selfhost/ct-ast/frontend/parse/Expr.h.ct` | `Str.h.ct` / `Vec.h.ct` 判断 5569 / 7513、`CT_STD_DIR` |
| `selfhost/ct-ast/frontend/parse/Stmt.h.ct` | `Str.h.ct` 判断 4677 |
| `selfhost/ct-ast/frontend/lex/Lexer.h.ct` | 注释 35 |
| `selfhost/ct-ast/backend/emit/Emitter.h.ct` | 注释 2403 / 3552 / 3573 |
| `selfhost/check-ast.sh` | 注释 1219、`CT_STD_DIR` 7658 / 7689 |

#### 4.2 测试脚本（21 个，全部 `CT_STD_DIR`）

`test/ast/` 下：`p47_map`、`p48_drop`、`p49_own`、`p50_has`、`p51_dot`、`p52_subscript`、
`p53_optional`、`p64_freestanding`、`p66_io_empty`、`p72_stdmissing`、`p80_cstr`、
`p80_layout`、`p80_literal`、`p80_methods`、`p80_migrate`、`p80_retain`、`p81_box`、
`p82_allow`、`p82_config`、`p82_cycle`、`p82_errors`。

- 统一改 `CT_CORE_DIR="$root/lib/core"`；
- **`p72_stdmissing.sh` 是回退测试**：改为断言 `CT_CORE_DIR` 文案 + 新增
  「`CT_STD_DIR=<repo>/lib/core` 兼容窗可用且打 warning」与「`CT_CORE_DIR` 指向不存在目录硬错」
  两条；保留 `env -u CT_CORE_DIR` 的缺省路径测试。

#### 4.3 活跃文档（12 个 + `lib/core/README.md`）

`README.md`、`README.en.md`、`docs/README.md`、`docs/llm-guide.md`、`docs/glossary.md`、
`docs/std-catalog.md`、`docs/guide-for-c-programmers.md`、`docs/tutorial.md`、
`docs/bindings-and-patterns.md`、`docs/ct-pkg.md`、`docs/stable-subset.md`、
`docs/language-spec.md`（操作行；§1.2 的迁移行保留旧名并带“迁移”字样）。

- 另：`examples/48_string_steps/src/text/text.shim.h` 的注释 1 行；
  移动后的 `lib/core/README.md` 自身。
- 历史性描述（如 `docs/README.md` 的 Phase 29 索引行）改写为“当时目录（现 `lib/core`）”，
  避免留下裸旧路径。

#### 4.4 明确不动（历史/记录）

`docs/history/**`、`docs/reviews/**`、`docs/review/**`、`docs/proposals/**`、
`docs/decisions/**`、`docs/design/**`、`docs/planning/j6-evidence/**`、`issues/**`、`battle/**`。
需要指路的，在 `docs/history/README.md` 加一行“2026-11-21 起内置层目录为 `lib/core`”，
不批量替换旧文。

### 5. 验收（预写两条 + 既有项）

**A. 活跃面零业务命中**

```sh
# .ct / .md：排除历史与记录目录；迁移/曾用名说明行不计
grep -rn 'lib/std' --include='*.ct' --include='*.md' . \
  | grep -vE '^\./(docs/history|docs/reviews|docs/review|docs/proposals|docs/decisions|docs/design|docs/planning/j6-evidence|issues|battle)/' \
  | grep -vE '迁移|曾用名'

# .sh / .py：业务脚本零命中；仅允许回退测试显式使用旧变量
grep -rn 'lib/std\|CT_STD_DIR' --include='*.sh' --include='*.py' . \
  | grep -vE '^\./(docs/|issues/|battle)/' \
  | grep -v 'test/ast/p72_stdmissing.sh'
```

两条命令都必须输出为空。迁移说明行必须带“迁移”或“曾用名”，否则按业务命中处理。

**B. 全量门禁绿**

- `bash selfhost/check-all.sh` → `check-all: OK (11 hard gates green)`；
- L0→L1→L2→ct-ast 自举不变；≤501 函数程序生成 C 逐字节不变。

**既有验收保留**：`CT_CORE_DIR=<repo>/lib/core` 下 `ct build` / `ct check` 正常；
`CT_STD_DIR=<repo>/lib/core` 在窗口内可用；外部 `std` 包 `import std::str::CharStr` 与内置
`String`/`Str` 共存；Stage 1 单提交回滚。

### 6. 执行前置与顺序

1. README 大改尾部（DOC-86）与 STD 配合清单就位；
2. 同一个提交：`git mv` + 9 个代码文件 + 21 个脚本 + 12 个活跃文档 + 示例注释；
3. 提交后立即跑 A/B 两条验收，再更新 `docs/history/README.md` 的一行指路；
4. **合入后唤醒（外部）**：Stage 1 合入即触发 STD 项目组配合清单（`lib/std` 路径替换）；
   外部配合不随 DEV 批次自动发生，由 REQ 在合入后 48 小时内启动。

## Stage 2：`namespace core`（同一 issue，独立切片）

Stage 1 只解决目录/环境变量同名；所有者 2026-11-21 要求把内置层的**命名空间**也改掉，
不能只做一半。Stage 2 是**语言/生成物可见变更**，必须单独提交、单独回滚：

- 内置层五个单元（`Vec`/`Option`/`Result`/`Str`/`Box`）声明 `namespace core`；
  编译器内置名解析改为 `core::Vec` / `core::String` / `core::box` 等；
- **兼容窗**：在根命名空间提供 `Vec`/`Map`/`Option`/`Result`/`String`/`Str`/`box`
  的别名或预导入（一个 MINOR），保证存量用户代码仍能编译；
- 生成 C 的符号名会变（`Vec` → `core_Vec` 一类）；golden/ABI/`--emit-model` 需同步，
  并给出“旧→新”映射；
- 外部 `std` 包仍占 `std::*`，与 `core::*` 不再有名称重叠；
- 需先补 spec §4.51/§4.70/§4.71 的命名空间与兼容窗条款，再动代码。

Stage 2 验收：

1. `core::Vec` / `core::String` / `core::box` 可用；根拼写在兼容窗内仍可用；
2. 外部 `import std::str::String` 与 `core::String` 可共存；
3. 生成 C 的旧→新符号映射完整；golden/ABI 更新有清单；
4. 存量语料在兼容窗内逐字节或按映射一致；
5. Stage 2 单提交回滚，不影响 Stage 1。

## 验收

1. `CT_CORE_DIR=<repo>/lib/core` 下 `ct build` / `ct check` 正常；
2. `CT_STD_DIR=<repo>/lib/core` 在兼容窗内仍可用；
3. `grep -rn 'lib/std'` 在活跃代码/脚本/文档中清零（`docs/history/**`、`battle/**` 历史除外）；
4. 外部 `std` 包仍可 `import std::str::String`，与内置 `String`/`Str` 共存；
5. `check-all` 11 门绿；L0→L1→L2→ct-ast 自举不变；
6. ≤501 函数程序生成 C 逐字节不变；
7. 单提交回滚（目录 + 路径查找 + 脚本一起退）。

## 非目标

- Stage 1 不混入 `namespace core` 变更；Stage 2 不混入目录/ENV 回退；
- 不改外部 `std` 包/`std::*`；
- 不改语言语义、`ct.lock`/索引；
- 不批量改 `battle/**` 与 `docs/history/**` 的历史记录。

## 风险

| 风险 | 缓解 |
| --- | --- |
| 755 处引用（含历史） | 只改活跃路径；历史文档加“当时叫 lib/std”的说明，不批量替换 |
| 外部消费者写死 `CT_STD_DIR` | 保留一个 MINOR 回退窗；错误文案提示 `CT_CORE_DIR` |
| 路径字符串比较漏改 | `grep 'lib/std/'` + `test/ast/p72_stdmissing` 回退测试 |
| Stage 2 生成物/ABI 变化 | 旧→新符号映射 + golden/ABI 清单；独立提交回滚 |
| 与 v1.0 收口抢窗口 | Stage 1 单提交；Stage 2 至少一个 MINOR 兼容窗，不阻塞 v1.0 |

## 关联

- [外部评审与惯用卡评估](../../docs/reviews/2026-11-21-v088-external-review-eval.md)
- [同名核查](../../docs/review/builtin-layer-vs-std-package-name-check.md)
- [D-014](../../docs/decisions/D-014.md)、[v1 路线](../../docs/planning/v1-release-plan.md)

## 复核与延后（2026-11-22，REV）

**结论：`deferred`。这是 bug 的修复窗口问题，不是文档措辞问题；本轮不动代码与 21 个脚本。**

已就绪：REQ 迁移卡（本 issue §Stage 1）把目录落点、`CT_CORE_DIR` 五级语义、一个 MINOR
回退窗、9 个代码文件 / 21 个脚本 / 12 个活跃文档的替换清单、两条预写 grep 验收和单提交
回滚都写死了。执行面尚未开始：

```console
$ ls -d lib/std lib/core 2>&1
ls: lib/core: No such file or directory
lib/std

$ grep -rn 'CT_CORE_DIR' --include='*.ct' --include='*.sh' selfhost test | wc -l
0

$ grep -rn 'CT_STD_DIR' selfhost --include='*.ct' --include='*.sh' | wc -l
7

$ grep -rl 'lib/std' README.md README.en.md docs/*.md | wc -l
13
```

文档侧已有前瞻表述（README 第 14 行、spec §1.2 迁移行、stable-subset 的 Stage 1/2 条目），
但它们描述的是**待执行**契约，不能替代 `git mv lib/std lib/core` 与 loader/脚本迁移。

**触发/负责人**：v1.0 收口窗口（README 大改尾部 + STD 配合清单就位）由 DEV 一次单提交执行
Stage 1；合入后 48 小时内由 REQ 唤醒外部 STD 项目组。Stage 2（`namespace core`）需先在
spec §4.51/§4.70/§4.71 补命名空间与兼容窗条款，再独立提交、独立回滚。两条都完成后本条才
转 `verified`；本轮不改源码，故不以文档修订代偿。
