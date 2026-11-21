# DOC-87 · `lib/std` 与外部 `std` 包同名（bugfix：`lib/core` + `CT_CORE_DIR` + `namespace core`）

| 项 | 值 |
| --- | --- |
| 模块 | docs / 工具链命名 |
| 定性 | **bug**（命名/身份混淆；不是新特性） |
| 严重度 | Medium |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | 所有者 2026-11-21 裁定“改名，作为 bug 去 fix”；[外部评审与惯用卡评估](../../docs/reviews/2026-11-21-v088-external-review-eval.md) §1；[同名核查](../../docs/review/builtin-layer-vs-std-package-name-check.md) |
| 状态 | **accepted（bugfix；v1.0 前，不占 phase）；REQ 待细化（排 DOC-90 之后）** |

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
