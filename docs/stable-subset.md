# Ct 稳定子集与改动授权

> 中文
>
> **状态**：定稿（2026-11-21 REQ 起草）；**v1.0.0 起生效**，v0.88→v1.0 为过渡期。
>
> **用途**：回答三个问题——哪些能力已经冻结、哪些还能改、改动要谁批。语言语义以
> [language-spec](language-spec.md) 为准；本文件只定“能不能改、怎么批、什么时候截止”，不重复语法。
>
> **机判断言**：`check-docs` 校验下面的「分档清单」：每行五列、档位合法、授权与版本列非空、
> 三档各至少一条。`已冻结` 条目的改动还必须在提交里引用一份存在的 ADR（评审级检查）。

## 1. 三档定义

| 档位 | 含义 | 典型对象 |
| --- | --- | --- |
| **已冻结** | v1.0.0 起只允许兼容性修复；语义、拼写、生成物形状不再变 | C 核心透传、trait 语义、ABI、lock 格式、诊断格式 |
| **冻结中** | v1.0 前可改；改动必须走 ADR 或 battle，破坏性改动给迁移窗 | String/Str、切片、`ref/out`、ADT、`Box`、容量、`lib/core` |
| **1.0 前可改** | 编译器内部、文档结构、测试基建；REQ 开 issue 即可，不碰语义的不需 ADR | L0/L1/L2 去留、A 默认值、spec 拆分、tutorial 结构 |

**过渡期规则**：`已冻结` 条目在 v0.88→v1.0 期间**即按冻结对待**；唯一例外必须在「版本/截止」
列显式登记（当前是 LANG-24 与 DOC-87）。没有登记的一律视为已冻结。

## 2. 分档清单

| 能力面 | 档位 | 授权 | 版本/截止 | 依据 |
| --- | --- | --- | --- | --- |
| C 表达式 / 语句 / 类型核心的透传与语义 | 已冻结 | REQ + ADR + REVIEW 签收；破坏性改动需 MAJOR 或 ADR 批准的迁移窗 | v1.0.0 起 | spec §1、§4 |
| `trait` / `impl` / `use` 语义（含默认方法、接口值装箱与派发） | 已冻结 | 同上 | v1.0.0 起 | spec §4.8–§4.12 |
| 生成 C 命名契约（`<Type>_<Trait>_<method>`、`_Drop_drop`、实例符号） | 已冻结 | 同上；改名前必须在 v1.0 前完成或提供别名 | v1.0.0 起；LANG-24 的 `Box_*` 改名须在 v1.0 前完成 | spec §3；[LANG-24](../issues/lang/lang-24-box-pascalcase-rename.md) |
| C ABI 静态库（`.h.ct` / `.abi.h` / `lib<base>.a`） | 已冻结 | 同上 | v1.0.0 起 | spec §4.57 |
| `ct.lock` v2 格式与包 store 布局 | 已冻结 | 同上；只允许追加字段 | v1.0.0 起 | [package-guide](package-guide.md) §8 |
| 诊断人读前缀 `file:line:col: error/warning:` 与 `--diagnostics=json` 必填字段、退出码 0/1 | 已冻结 | 同上；JSON 只允许追加字段 | v1.0.0 起 | spec §9；[LANG-10](../issues/lang/lang-10-machine-readable-diagnostics.md) |
| `ct` CLI 子命令与主要选项名（`compile` / `build` / `check` / `get` / `index verify`） | 已冻结 | 同上；新增选项属兼容改动 | v1.0.0 起 | [tutorial §11](tutorial.md)、README §2 |
| 内建容器与结果类型 API（`Vec` / `Map` / `Option` / `Result` 的公开方法名与语义） | 已冻结 | 同上 | v1.0.0 起 | spec §4.13–§4.30、§4.31 |
| `foreach` 语义（数组/Vec 绑定只读 `i`；`Map` 只给 `item.key` / `item.value`） | 已冻结 | 同上 | v1.0.0 起 | spec §4.49、§4.70 |
| 命名契约 §5.1（类型 PascalCase、函数 snake_case；保留名清单封闭） | 已冻结 | 同上；保留名清单只能经 ADR 追加 | v1.0.0 起 | spec §5.1 |
| `String` / `Str` 的布局、存放位置与释放分层 | 已冻结 | REQ + ADR 或 battle；破坏性改动 MINOR + 一个 MINOR 回退 | v1.1.0 起 | spec §4.70；[LANG-22](../issues/lang/lang-22-nonimmortal-view-store-lint.md) |
| 切片 `T[]` 的拼写、位置白名单与边界行为 | 已冻结 | 同上 | v1.1.0 起 | spec §4.69；[SH-108](../issues/selfhost/sh108-p87-dogfood-t-a-fp.md) |
| `ref` / `out` 参数语义与 `out` 定值分析 | 已冻结 | 同上；逃逸契约已写入 spec §4.68（J-4b） | v1.1.0 起 | spec §4.68；D-011 J-4b |
| ADT 与 `match` 的形态（无泛型 ADT、无 or 模式）；ADT/变体/负载计数按需增长到形式上限 65536，不再有 64/16/8 语义上限（S1a-0 C3） | 已冻结 | 同上 | v1.1.0 起 | spec §4.73 |
| `Box<T>` / `new` 的语义与规范拼写 | 已冻结 | REQ + ADR；`box<T>` 别名已于 v1.1.0 删除（硬错） | v1.1.0 起 | [D-016](decisions/D-016.md)；LANG-24 |
| `MAX_FUNCS` 动态增长（初始 512、翻倍、65536 安全阀） | 冻结中 | REQ + ADR；只允许扩大安全阀，不收紧 | **当前 pre 窗口（v1.1 前；2026-11-23 提前）** | [提案](proposals/ct-max-funcs-growth.md)；[SH-109](../issues/selfhost/sh109-max-funcs-capacity.md) |
| `lib/core` 目录与 `namespace core` 布局 | 冻结中 | REQ + ADR；根拼写兼容一个 MINOR | **v1.0 前（当前 pre 窗口；Stage 1+2）** | [DOC-87](../issues/docs/doc-87-lib-core-rename.md) |
| 泄漏策略 `leaks = warn 或 error` 与 `c-boundary = allow 或 strict` 的键名 | 冻结中 | REQ + ADR | v1.1 冻结 | D-012；spec §4.70 |
| `std` 包导入名与单元命名（`std::str::CharStr` 等） | 冻结中 | 包维护者 + 索引记录；std 0.20.0 起无旧名别名（[D-025](decisions/D-025.md)） | 已随 PKG-22 发布 | [PKG-22](../issues/packages/pkg-22-std-str-charstr-rename.md) |
| 内建 trait（`Drop` / `Handback`）的可见声明显性化 | 冻结中 | REQ + ADR；不得引入 vtable/vptr | **v1.0 前（当前 pre 窗口；依赖 `lib/core` Stage 1）** | [LANG-23](../issues/lang/lang-23-builtin-trait-declarations.md) |
| 非 immortal `Str` 视图存入容器的 lint（warn 级） | 冻结中 | REQ + ADR；先 warn，不升硬错；**v1.1 已实现**（compile/build warning，`ct check` error） | v1.1 | [LANG-22](../issues/lang/lang-22-nonimmortal-view-store-lint.md) |
| 编译器内部分层（L0 / L1 / L2 去留、seed cutover） | 1.0 前可改 | REQ 开 issue；语义不变的不需 ADR | `v1-PH-0` 前 | [v1 路线](planning/v1-release-plan.md) §2 |
| A 检查的默认值（`--check-level` 默认 off/warn/error） | 1.0 前可改 | REQ + ADR（产品契约） | **SH-115 起默认 `warn`；v1-PH-1 S3 起默认 `error`**（FP=0 证据 [SH-118](../issues/selfhost/sh118-full-corpus-fp-zero.md)；`off` 保留逃生，单提交可回退） | [SH-115](../issues/selfhost/sh115-b-plus-strengthening.md)、[v1 路线](planning/v1-release-plan.md) §2.4 |
| spec 结构（是否拆分、目录与锚点） | 1.0 前可改 | REQ 开 issue；结构不动语义 | v1.1 | [DOC-88](../issues/docs/doc-88-spec-split-decision.md) |
| README / tutorial 的结构与示例 | 1.0 前可改 | REQ 开 issue；事实修正不需 ADR | 持续 | [DOC-86](../issues/docs/doc-86-readme-v088-rewrite.md)、[DOC-90](../issues/docs/doc-90-tutorial-string-slice-chapters.md) |
| phase-ID 迁移（旧编号 → `v1-PH-*`） | 1.0 前可改 | REQ 开 issue；历史记录不改写 | v1.0 发布前 | [DOC-83](../issues/docs/doc-83-phase-id-migration-decision.md) |
| J-6 证据台账与 goldens 静态化 | 1.0 前可改 | REQ 定验收，DEV 实施；不改语言语义 | `v1-PH-0` 前 | [SH-104](../issues/selfhost/sh104-j6-evidence-ledger.md)、[SH-105](../issues/selfhost/sh105-goldens-static-freeze.md) |
| 文档门禁增强（锚点校验等） | 1.0 前可改 | REQ 开 issue；并入第 11 道门禁，不新增条数 | v1.1 起 | [DOC-89](../issues/docs/doc-89-anchor-validation.md) |

## 3. 授权矩阵

| 档位 | 谁批 | 要不要 ADR / battle | 版本后果 |
| --- | --- | --- | --- |
| 已冻结 | REQ + REVIEW 签收 | 必须 ADR；破坏性改动还要显式迁移窗 | 兼容修复 MINOR；破坏 MAJOR（或永不做） |
| 冻结中 | REQ | ADR 或 battle 二选一；涉及所有权/ABI 必须 ADR | 破坏性 MINOR + 一个 MINOR 回退；迁移说明入库 |
| 1.0 前可改 | REQ | 不碰语义的不需；碰语义按“冻结中” | 文档/内部改动不 bump；语义改动按冻结中 |

**判定优先级**：一条改动同时命中多档时，取**更严**的档位。不确定时默认按 `已冻结` 处理，
再由 REQ 裁定是否降档。

**C 互操作逐项**（指针、`const`/`volatile`、数组衰减、struct 布局、enum、bit-field、
函数指针、变参、`setjmp`/`longjmp`、`restrict`、宏、attribute/中断、内联汇编、C++）的
“透传 / strict 禁区 / shim”判定见 [C Interop Semantics Matrix](c-interop-semantics-matrix.md)。
该附录只索引权威节与证据，**不改本表的档位**；C shim 的作者义务见
[C Shim 契约](c-shim-contract.md)。

## 4. 当前待决与过渡登记

| 事项 | 为什么必须在 v1.0 前定 | 跟踪 |
| --- | --- | --- |
| `box` → `Box` 规范拼写、`box_*` → `Box_*` 生成符号 | 生成 C 命名契约 v1.0 起冻结；之后再改只能加别名 | [LANG-24](../issues/lang/lang-24-box-pascalcase-rename.md) |
| `lib/std` → `lib/core` 目录（Stage 1，迁移已落地）+ `namespace core` / `core::*`（Stage 2，已落地；C 符号兼容窗内保持根拼写） | 目录与加载键属于构建契约；命名空间是生成物可见变更 | [DOC-87](../issues/docs/doc-87-lib-core-rename.md) |
| v1.0 冻结时点 | 所有 `冻结中` 条目必须在此之前收敛或转入 `已冻结` | [v1 路线](planning/v1-release-plan.md) §1.5 |

## 5. 变更本清单

1. 移动条目 = 改档位：按“授权矩阵”走；`已冻结` 降档视同破坏性改动。
2. 新增条目：先写档位、授权、版本/截止、依据四列；依据必须是 spec 节号、ADR、issue 或实测。
3. 删条目：不允许静默删除；删除必须在提交说明里写理由，并在 `issues/` 留一条记录。
4. `check-docs` 只校验结构（五列、档位合法、三档齐全）；“冻结项改动必须带 ADR”由评审执行，
   机器只校验被引用的 ADR 文件存在。
