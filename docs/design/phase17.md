# Phase 17 计划（已确认，待实施）：工程质量与新能力

> 中文 · [English](#english)
>
> **状态：计划已确认（2026-11-02），待实施。** 本文件把 2026-11-02 第三方评估中「属新能力或治理决策、
> 当时未立项」的六项——**std / CI 矩阵与 ASAN / raw 透传 / 文档分层 / 包管理 / `ct build` 一步到位**——
> 转为下一阶段的实施计划，供编码 agent 按切片落地。**D17-1…D17-9 已按建议值经用户确认**（含 README
> ≤ 10K 字符、标准库目录名 `std`、`ct build` 默认产出可执行文件）。
> 实施前仍须按既有流程补写各切片的 `spec` / `tasks` / `checklist`；本文件不是逐行实现依据。
> 本文件只记录计划，不描述现状；现状见 [README](../../README.md) 与 [language-spec](../language-spec.md)。
>
> 前置约束（见 [AGENTS.md](../../AGENTS.md) §2）：`selfhost/l0/ctc.c`、`selfhost/l1/ctc.ct`、
> `selfhost/l2/**` 一律不动；新能力只落 **`selfhost/ct-ast/**`**（std / CI / 文档属新增顶层面，
> 需同步修订 AGENTS 的文件所有权表）；不引入第三方库、构建系统或代码生成脚本；
> **零网络**契约不变，**零子进程**契约按 D17-9 收窄为「`ct compile` 与 `ct build --emit-c` 零子进程，
> `ct build` 默认调用 C 编译器」；`install.sh` 的行为变更需用户显式确认。

---

## 中文

### 1. 目标与出口

| 项 | 内容 |
| --- | --- |
| 目标 | 把六项「新能力 / 治理决策」落成可验证的工程能力：**CI 矩阵 + 消毒器 + 确定性 fuzz**、**官方 std**、**raw 透传**、**文档分层与链接门禁**、**包管理补全（update / verify / index / 比较器范围 / 构建元数据）**、**`ct build` 一步到位产出可执行文件** |
| 出口 | 新增 / 扩展的门禁在 `bash selfhost/check-all.sh` 与 CI 上全绿；六项各有独立测试层；`ct` 的产物形态、banner、`ctc:` 前缀与**零网络**契约不变；**零子进程**按 D17-9 收窄为 `ct compile` / `ct build --emit-c` |
| 版本 | **Phase 17 ↔ `v0.17.0`**（D17-1）——`v0.13.0`–`v0.16.3` 已被「Phase 12 之后的能力 / 修复补丁」占用，故不沿用 Phase 13 编号；收口时一次性 bump，阶段内仅在需要重生成 golden 的修复上用 patch 位 |
| 回退 | 各切片独立：CI / 文档 / 包管理回退不动编译器核；std 与 raw 透传为**叠加**能力（不改变既有语法与产物），回退即移除新增文件与入口；`ct build` 一步到位可用 `--emit-c` 退回既有行为 |

### 2. 非目标

- 不做类型检查、不做泛型、不做优化——语言仍未定稿（`1.0.0` 才定稿）。
- 不改 L0 / L1 / L2 的任何行为；不为新用例改 oracle。
- 不引入 HTTP 服务、托管 registry、CI 之外的网络依赖；**零网络不变**。`ct build` 默认调用本地 C 编译器（受控子进程，D17-9），`ct compile` 与 `ct build --emit-c` 仍零子进程；`ct build` **不解析** `cc` 的诊断、不做增量链接、不内置任何构建系统。
- 不把 raw 透传做成「注释保留」或通用预处理器；不做 L0 / L1 / L2 支持。
- 不做完整的 SemVer（预发布 / 构建元数据 / `!=` 暂不纳入）；不做依赖锁的传递更新策略研究。
- 不重写 README 的技术内容为营销文案；文档分层只做**结构与链接**治理。

### 3. 现状与缺口（2026-11-02 仓库实测）

| 面 | 现状 | 缺口 |
| --- | --- | --- |
| CI | 仓库**无 `.github/`**；`Makefile` 仅 `check: bash selfhost/check-all.sh`；`check-all.sh` 九道硬门禁，支持 GCC wrapper（`-Wno-format-truncation` / `-Wno-implicit-fallthrough`） | 无平台矩阵、无 clang、无消毒器、无 fuzz；BSD-only 探针在 Linux 上 skip 后无人复核 |
| std | **不存在 `std/`**；每个示例自带 `#include` 与手写工具函数 | 无可复用标准库；无命名空间 / 生命周期约定 |
| raw 透传 | 词法器在 token 化前**丢弃** `//` 与 `/* */`（[Lexer.h.ct](../../selfhost/ct-ast/frontend/lex/Lexer.h.ct) 第 72–84 行）；`#` 行首已捕获为 `T_PP`（第 90–100 行） | 无法把未识别的 C 片段原样带进产物；`N_RAW = 31` 已被「原始初始化式」占用 |
| 文档 | `README.md` 约 89K 字节（`wc -c`）；`docs/` 与 `reports/` 边界模糊；无导航页、无链接门禁 | 无 `docs/README.md`；无死链 / 版本 token / 门禁计数检查 |
| 包管理 | `Pkg.h.ct` 已有 manifest、MVS、git tag 选择、本地目录源、SHA-256、`sha256:` lock、vendor、`ct get` / `ct install` | **无 `ct update` / `ct verify` / index**；`range_match` 仅 `^` / `~` / 精确 / `*`，无比较器范围；**`ct.pkg` 无 `cflags` / `ldflags` / `requires`**，平台包与需要 `-l` 的库包无法一步交付 |
| `ct build` CLI | 必须 `-o <dir>`，只写 `.c` / `.h` 并打印一条 `cc` 行（[Module.h.ct](../../selfhost/ct-ast/frontend/module/Module.h.ct) 第 683–825 行）；无 `--cc` / `-D` / `-l` 入口；仓库内 **9 个脚本共 94 处** `build … -o <dir>` | 用户必须手工再跑一次 `cc`（每个示例与测试都自写 `build.sh`）；嵌入式所需的 `--cc` / `-mcpu` / `-l` 无处传递（SH-43 待决项） |
| std 生命周期 | 内建 `Drop` / `Handback` 的发射函数是 `static`（[Emitter.h.ct](../../selfhost/ct-ast/backend/emit/Emitter.h.ct) 第 1445 行） | 跨单元无法 `delete` / `own`；std 必须暴露显式 `*_free` / `*_reset` |
| 模块解析 | `resolve_import` 先找 importer 目录，再按 `-I` 顺序；**无默认 include 根**（[Module.h.ct](../../selfhost/ct-ast/frontend/module/Module.h.ct) 第 248–304 行） | std 需要显式 `-I`，否则用户无从发现 |
| 字符串池 | `calloc(262144, 1)`，`str_put` 到 262144 上限（[Arena.h.ct](../../selfhost/ct-ast/runtime/arena/Arena.h.ct) 第 76、117 行） | raw 块需块级上限与诊断，避免静默耗尽 |

### 4. 切片

| 切片 | 内容 | 主要改动面 | 出口 |
| --- | --- | --- | --- |
| **17.1** | **CI 矩阵 + 消毒器 + 确定性 fuzz** | 新增 `.github/workflows/{ci,nightly}.yml`、`selfhost/check-sanitizers.sh`、`test/fuzz/run.sh` | 三个 CI job 全绿；ASAN/UBSAN 本地与 nightly 可跑；fuzz 固定 seed 可复现且零崩溃 |
| **17.2** | **`std` 官方标准库** | 新增顶层 `std/{str,vec,arena,fs,utf8,test,map}.h.ct`；新增 `test/std/run.sh`；`install.sh` 安装路径（D17-2） | 七模块 `gcc` 端到端可跑；`test/std/run.sh` 成为第 10 道硬门禁 |
| **17.3** | **raw 透传** | `Lexer.h.ct`（`#ct-raw` 特判）+ `Arena.h.ct`（新节点 `N_RAW_TEXT`）+ `Parser.h.ct`（块解析与未闭合诊断）+ `Emitter.h.ct`（原样输出） | 正例 / 负例全绿；ct-ast 源码禁用 raw 的护栏生效；spec / README / tutorial / editor grammar 同步 |
| **17.4** | **文档分层 + 链接门禁** | 新增 `docs/README.md`、`test/docs/check-docs.py`；迁移 `reports/` → `docs/history/reports/`、已完成阶段的 `docs/design/*.md` → `docs/history/design/`；README 瘦身（D17-5） | 门禁零死链；README 体量达标；`issues/` 与 `AGENTS.md` 保留原位 |
| **17.5** | **包管理补全** | `Pkg.h.ct`（比较器范围、`update`、`verify`、`cflags` / `ldflags` / `requires`）+ `Driver.h.ct`（命令分发）+ `test/pkg/run.sh` 扩展 + 索引格式文档 | `ct update` / `ct verify` 可用；比较器范围有正负例；`ct install` 能拼出**一条**含 `-I` / `-D` / `-l` 的命令；编译路径仍零网络 |
| **17.6** | **`ct build` 一步到位** | `Module.h.ct`（`build_main` 的默认路径）+ `Driver.h.ct`（两套 CLI 解析器，见 SH-24）+ 9 个脚本的 94 处调用点 + `test/run.sh` 的 CLI 层 | 默认直接产出可执行文件；`--emit-c` 与既有行为逐字节等价；`--cc` 失败时退出码非零；11 道门禁不变 |

#### 17.1 CI 矩阵 / ASAN / fuzz

- **矩阵**（`ci.yml`，push / PR 触发）：
  - `ubuntu-latest` × gcc：全量 `bash selfhost/check-all.sh`（唯一「全量」权威）；
  - `macos-latest` × clang：全量同上（覆盖 Darwin 探针路径）；
  - `ubuntu-latest` × clang：smoke——`./test/run.sh` + `bash selfhost/check-ast.sh` + `check-warnings.sh`（控制时长）。
- **消毒器**（`selfhost/check-sanitizers.sh`，nightly + 手动）：以 `CC` + `-fsanitize=address,undefined
  -fno-omit-frame-pointer` 构建 ct-ast，跑 `test/run.sh` 与 `test/ast/**`；`ASAN_OPTIONS=detect_leaks=0`
  （编译器进程内长期存活的 arena 不适用泄漏检测；泄漏语义由 `check-warnings.sh` 的编译期分析负责）。
  断言：任何 sanitizer 报告即失败。
- **fuzz**（`test/fuzz/run.sh`，nightly + 手动）：固定 seed、确定性；种子来自 `test/ast/**` 的**随机截断**
  与 token 乱序，断言「不崩溃、不退化成无界输出、诊断有界」。不改 `check-all.sh`（本地时长不变）。
- 出口：CI 全绿；nightly 绿；脚本可在本机单独执行。

#### 17.2 `std`

- 目录与命名：`std/<mod>.h.ct`，namespace `std::<mod>`；只放**接口与实现都自包含**的单元。
- 七个模块的 v1 范围：
  - `str`：切片 / 查找 / 前后缀 / 大小写 / 拼接（定长缓冲）；
  - `vec`：单态化 `VecInt` / `VecStr`（无泛型），`push` / `pop` / `at` / `len`；
  - `arena`：块式 bump 分配 + `*_reset`；
  - `fs`：存在性 / 读文件 / 写文件 / 遍历（薄封装 `stdio` / `dirent`）；
  - `utf8`：码点解码 / 编码 / 长度；
  - `test`：断言宏 / 计数器（供 `test/std/run.sh` 与用户自测）；
  - `map`：见下节。
- **容器模块 `map`（D17-7，来源：2026-11-02 容器支持建议，经本仓库实测复核后调整）**：
  - 实现形态：**固定容量 + 开放寻址**的有界实现；满载即返回失败，不自动 rehash、不隐式 `malloc` 扩容。
  - 类型形态：**单态具体类型为主**——v1 为 `MapStrInt` / `MapIntPtr`（与 `VecInt` / `VecStr` 同一取向）；
    可选的 `trait Map`（`void *` 键值 + 键长 + `hash` / `eq` 函数指针）作为**擦除接口**，
    文档写明「可替换但无编译期类型安全」的取舍，两者不互相替代。
  - 所有权契约：`*_clear` 一次性释放全部 value；释放方式二选一——值自带显式 `*_free`，
    或构造时传入 `free_fn` 函数指针；**不写 `delete`**（跨单元 `Drop` 为 `static`，库单元无法销毁调用方单元的值类型）。
  - 明确不做：第三方库 binding（uthash / klib 属「需要完整预处理器」+ 逐类型 shim，且与
    binding 规约「不 vendored、不下载、编译路径零网络」冲突）；官方方言展开器（仅文档记录为用户模式）。
- 生命周期约定：因 `Drop` / `Handback` 为 `static`（跨单元不可用），每个持有资源的类型必须提供显式
  `*_free` / `*_close` / `*_reset`，文档写清「不依赖 `delete`」。
- 发现方式（D17-2）：用户显式 `ct ... -I <std>`；`install.sh` 安装到
  `$(dirname "$prefix")/share/ct/std` 并打印建议的 `-I` 行。**不新增编译器默认搜索路径**
  （那是行为变更，且会与用户的 `-I` 顺序产生歧义）。
- 新门禁：`test/std/run.sh`（`check-all.sh` 第 10 道），每模块至少 1 正例 + 1 边界 / 负例，走
  ct-ast → `.c` → `gcc` → 运行断言。
- 出口：七模块全覆盖；`test/std/run.sh` 绿；`install.sh` 安装路径经用户确认后落地。

#### 17.3 raw 透传

- **标记语法**（D17-3）：行首 `#ct-raw` 与 `#ct-endraw`（沿用现有 `T_PP` 捕获路径，无需改注释跳过逻辑）；
  不采用 `//@ct-raw`（会迫使词法器保留注释原文，牵动全部注释处理）。
- **节点**：新增 `N_RAW_TEXT`（`N_RAW = 31` 已被「原始初始化式」占用，不复用）；节点携带原文偏移与长度。
- **解析**：块内不做 token 化；未闭合 `#ct-endraw` 在**起始行**报错；
  `#ct-raw` 必须在行首且独占一行（尾随非空白即报错）。
- **发射**：原样写入生成 `.c`（不缩进、不改写、不参与宏展开），并保持 `#line` 语义：块后恢复行号。
- **容量**：块级上限（建议 32 KiB / 块），并与字符串池剩余量比较，超出报
  `raw block exceeds N bytes`；不使用静默截断。
- **护栏**：ct-ast 由 L2 编译，L2 不认识 raw 块——`check-ast.sh` 增加断言「`selfhost/ct-ast/**`
  不含 `#ct-raw`」，防止自举被自己写坏。
- **同步面**（AGENTS §9）：`language-spec.md`、`README.md`（中英）、`docs/tutorial.md`（若有该节）、
  `docs/roadmap.md`、本文件、编辑器语法（新增 `ct-raw` scope + 断言）。
- 出口：`test/ast/**` 正例（C 片段 / 未识别宏 / 块后行号）与负例（未闭合 / 超限 / 非行首 /
  ct-ast 源码含 raw）全绿。

#### 17.4 文档分层 / doc lint

- `docs/README.md`：导航（「是什么 / 语言规范 / 设计与计划 / 历史 / issue 台账 / 贡献」），每条给目标与适用范围。
- `test/docs/check-docs.py`（标准库 Python，不引第三方）：
  1. `docs/**` 与 `README.md` 的相对链接可解析（0 死链）；
  2. 文档中的版本 token 与 `ctc.c` 的 `CTC_VERSION` 一致；
  3. `check-all.sh` 的门禁条数与文档描述一致（9 / 10 / 11 随切片更新）；
  4. `docs/design/phase*.md` 的状态行与 roadmap 的阶段表一致。
- 迁移（D17-5）：
  - `reports/` → `docs/history/reports/`（历史报告，保留原文件名与日期）；
  - 已完成阶段的 `docs/design/*.md` → `docs/history/design/`（`phase5` / `phase6` / `phase8` / `phase9` /
    `phase10` / `phase12` 等；**Phase 17 本文件留在 `docs/design/`**）；
  - **保留原位**：`issues/**`（活台账）、`AGENTS.md`（入口规约）、`bindings/README.md`（binding 规约）。
- README 瘦身：目标「简介 + 5 分钟上手 + 能力表 + 导航」；语法细节、测试说明、目录说明、已知限制
  迁入 `docs/` 对应页。初始目标 **≤ 10K 字符**（以现有中文 + 英文两版合计计）；具体阈值由 D17-5 确认。
- 出口：`check-docs.py` 成为 `check-all.sh` 第 11 道门禁；迁移后全量链接与版本 token 绿；README 达标。

#### 17.5 包管理

- **比较器范围**：`range_match` 扩展为 `>=` / `>` / `<` / `<=`，空格分隔表示 AND（如 `>=1.2.0 <2.0.0`）；
  `^` / `~` / 精确 / `*` 语义不变；不接受 `||`（留待后续，避免一次扩大语义面）。
- **`ct update`**：按 `ct.pkg` 重新解析（尊重现有 `ct.lock` 的 pin），写回 `ct.lock`，**不**隐式改
  `ct.pkg`；默认离线可用（本地目录源 / 已缓存 git 源），远程拉取仍只在 `ct get` 发生。
- **`ct verify`**：离线校验 `vendor/**` 内容与 `ct.lock` 的 `sha256:<64 hex>` 一致；复用 `dir_digest`，
  只新增命令入口与错误消息。
- **索引**（D17-4）：git 托管的**纯文本** `index`（每行 `name version git-url tag sha256`）；
  通过 `CT_INDEX` 环境变量或 `--index <path>` 显式指定，**不内置 URL、不做 HTTP 客户端**；
  `ct get <name>[@range]` 在无 spec 前缀时查该索引，有 spec 时行为不变。
- **构建元数据**（与 17.6 合流）：`ct.pkg` 增加可选的 `cflags` / `ldflags` / `requires`（`ct >= x.y.z`）；
  `ct install` 读取 `vendor/**/ct.pkg`，把每包的 `cflags` / `ldflags` 与 `-I vendor/<pkg>` 一起拼进
  **一条**可直接执行的命令；`requires` 与本机 `CTC_VERSION` 不符时告警（不阻断）。不引入 `provides` /
  `conflicts`——平台包的互斥由索引与 CI 校验，见 Phase 18。
- 出口：`test/pkg/run.sh` 增加比较器、update、verify、index、元数据五组断言；`ct compile` / `ct build --emit-c` 仍零网络、零子进程。

#### 17.6 `ct build` 一步到位

- **默认形态**（D17-9）：`ct build <entry.ct>... [-o <exe>]` —— 先按现规则发射 `.c` / `.h`，再调用
  C 编译器，**直接产出可执行文件**。省略 `-o` 时写 `a.out`。
- **只发 C**：`--emit-c` 跳过调用、只写 `.c` / `.h`，此时 `-o` 沿用旧的「输出目录」语义。仓库内
  **9 个脚本的 94 处**调用点全部改为 `ct build --emit-c … -o <dir>`，因此既有 golden、`cc` 行断言与
  `check-warnings.sh` 的 awk 提取**逐字节不变**。
- **中间产物目录**：默认 `.ctbuild/`，可用 `--outdir <dir>` 覆盖（目录不存在时自动创建）；该目录加入
  `.gitignore`。`-o` 在默认形态下只表示可执行文件路径，不再兼作目录。
- **透传参数**：`--cc <path>`（默认 `$CC`，否则 `cc`）、`--cflags <s>`、`--ldflags <s>`（可重复，也可
  空格分隔）；三者只拼进命令行，**不解析、不校验**。与 17.5 的 `ct.pkg` 元数据合流后，`ct install`
  打印的命令可直接交给 shell。
- **子进程约定**：整条命令经 `system()` 执行，每个路径与参数按 `PkgOps::sh_quote` 的单引号规则转义
  （该函数需上移到共享单元，两处共用一份）；`cc` 退出码原样作为 `ct` 的退出码；`cc` 不存在或不可执行
  时报 `ctc: cannot run '<cc>'`。`ct build` **不翻译** `cc` 的诊断——`#line` 已把 gcc 的报错映回 `.ct` 行。
- **库构建**：没有 `main` 的单元集合（只产 `.h` 的库、包内的 `.h.ct`）必须用 `--emit-c`；默认形态要求
  输入里存在 `main`，否则由 `cc` 报链接错误（`ct` 不预判，避免与「不解析 `cc` 诊断」自相矛盾）。
- **两套 CLI 解析器**：`Driver.h.ct`（compile 模式）与 `Module.h.ct`（build 模式）各有一份参数循环
  （SH-24），新开关必须同时接入，且 `--help` 两处输出保持一致。
- **测试**：扩展 `test/run.sh` 的 CLI 层——(a) 默认形态产出可执行文件并运行，输出与 `expected.out` 一致；
  (b) `--emit-c` 下 `CC` 指向一个「被调用即失败」的假脚本，断言它**未被调用**；(c) `--cc` 指向不存在的
  路径时退出码非零且 stderr 含 `cannot run`；(d) `--ldflags -lm` 透传后 `sqrt` 可用。
- 出口：上述四类断言全绿；94 处调用点迁移后 11 道硬门禁与既有 golden 不变；`ct compile` 仍零子进程。

### 5. 依赖与顺序

| 顺序 | 切片 | 理由 |
| --- | --- | --- |
| 1 | 17.1 CI | 先建护栏：后续每个切片的绿/红都能被矩阵与 nightly 持续验证，避免「本地绿、别的平台红」 |
| 2 | 17.4 文档分层 | 先立导航与 doc lint，再让 17.2 / 17.3 的新文档有确定落点；迁移与链接修复一次做完 |
| 3 | 17.6 `ct build` 一步到位 | 先把 94 处调用点一次性迁到 `--emit-c`，后续新脚本（`test/std/run.sh`）只写一次；也让 17.5 的 `ct install` 能打印「一条命令」 |
| 4 | 17.2 std | 依赖 17.4 的文档位置与 17.1 的多平台验证（std 要跨 gcc / clang 一致） |
| 5 | 17.3 raw 透传 | 动词法器 / AST / 发射器，风险最高；在 CI 与文档门禁就位后单独收口 |
| 6 | 17.5 包管理 | 独立 leaf（`Pkg.h.ct` 不触 AST），但**必须在 17.6 之后**——构建元数据要拼进 17.6 的命令行 |

切片之间**可并行**：17.2 与 17.5 无交集；17.3 只碰 `selfhost/ct-ast/**` 的 frontend / backend。
但 17.4 的迁移会移动文件路径，必须在 17.2 / 17.3 新增文档**之前**完成，否则新链接会二次搬迁。
17.6 会改 `build_main` 与两套 CLI 解析器，与 17.3 的 frontend 改动不相交，但两者都要跑全量门禁，
建议串行收口。

### 6. 版本与发布

- 阶段编号：**Phase 17 ↔ `v0.17.0`**。`v0.13.0`–`v0.16.3` 已在版本记录中标为「Phase 12 之后的能力 /
  修复补丁」，故下一个 phase 不取 13；在 roadmap 中补一句「13–16 由补丁占用」的说明（D17-1）。
- 收口 bump 到 `v0.17.0`：`CTC_VERSION` 五处同步（`ctc.c` / L1 / `l2/{core,driver}.ct` / `ast/main.ct`），
  全量 golden 仅版本 token 变化。
- 阶段内 patch bump 仅在「需要重生成 golden 的修复」时使用；17.1 / 17.4 / 17.5 / 17.6 不产生 golden 变化
  （17.6 的 `--emit-c` 必须与旧行为逐字节一致）。
- tag：收口时打 `v0.17.0`；中间里程碑用非版本 tag（如 `phase17-std`、`phase17-raw`），避免 tag 与
  `CTC_VERSION` 不一致。

### 7. 全局 DoD

1. `bash selfhost/check-all.sh` 全绿（门禁从 9 道增至 **11 道**：新增 `test/std/run.sh`、`test/docs/check-docs.py`）。
2. CI 三个 job + nightly 全绿；sanitizer 与 fuzz 零报告。
3. 所有新增 / 修改语料由**真实二进制**输出生成期望值，不手写 golden。
4. 文档中英双语；`language-spec` / `README` / tutorial / roadmap / glossary / editor grammar 同步（AGENTS §9）。
5. 不改 L0 / L1 / L2；不引入第三方库与构建系统；**零网络**不变；`ct compile` 与 `ct build --emit-c` 零子进程，`ct build` 默认只调用本地 C 编译器（不解析其诊断、不做增量链接）。
6. `install.sh` 的任何行为变更（std 安装路径）须先获用户确认。
7. `ct build` 默认一步产出可执行文件；`--emit-c` 下 94 处既有调用点的产物、stdout 与 `cc` 行逐字节不变。

### 8. 已确认决策

| 编号 | 议题 | 建议 | 状态 |
| --- | --- | --- | --- |
| **D17-1** | 阶段编号与版本 | 新开 **Phase 17 ↔ `v0.17.0`**；在 roadmap 说明 13–16 已被补丁占用 | ✅ 用户确认 |
| **D17-2** | std 发现方式 | 显式 `-I`；`install.sh` 安装到 `$(dirname "$prefix")/share/ct/std` 并打印 `-I` 行；**不改**编译器默认搜索路径 | ✅ 用户确认 |
| **D17-3** | raw 标记语法 | 行首 `#ct-raw` / `#ct-endraw`（走 `T_PP` 路径）；仅 ct-ast；`N_RAW_TEXT`；32 KiB/块上限；ct-ast 源码禁用 raw | ✅ 用户确认 |
| **D17-4** | registry 形态 | git 托管的纯文本 index（`CT_INDEX` / `--index` 显式指定）；无 HTTP、无托管；新增 `ct update` / `ct verify`；范围只加比较器与空格 AND | ✅ 用户确认 |
| **D17-5** | 文档分层目标 | `docs/README.md` + `test/docs/check-docs.py` 先行；`reports/` 与已完成阶段的 `design/` 移入 `docs/history/`；README 目标 **≤ 10K 字符**；`issues/` 与 `AGENTS.md` 留在原位 | ✅ 用户确认 |
| **D17-6** | 消毒器 / fuzz 的门禁地位 | 不进 `check-all.sh`（保持本地时长），只做 CI nightly + 手动脚本；fuzz 固定 seed、确定性 | ✅ 用户确认 |
| **D17-7** | 容器落位与形态 | 并入 17.2，新增 `std/map.h.ct`；单态类型为主（`MapStrInt` / `MapIntPtr`）+ 可选 `void *` 擦除接口；有界开放寻址；`*_clear` / `free_fn`，不用 `delete`；不做第三方 binding 与官方方言展开器 | ✅ 用户确认 |
| **D17-8** | 标准库命名 | 顶层目录 **`std/`**、namespace `std::<mod>`、安装到 `$(dirname "$prefix")/share/ct/std`；`stdlib` 一词不再使用（用户：太啰嗦） | ✅ 用户确认（2026-11-02） |
| **D17-9** | `ct build` 默认形态 | **默认一步到位**：发射 C（默认 `.ctbuild/`，`--outdir` 可改）后调用 C 编译器（`$CC` / `--cc`，默认 `cc`）产出可执行文件；`--emit-c` 只发射；`--cflags` / `--ldflags` 透传；仓库内 94 处调用点全部改用 `--emit-c`；零子进程契约收窄为 `ct compile` / `ct build --emit-c` | ✅ 用户确认（2026-11-02） |

### 9. 风险

| 风险 | 说明 | 缓解 |
| --- | --- | --- |
| 自举被 raw 写坏 | ct-ast 由 L2 编译，L2 不认识 raw 块 | `check-ast.sh` 断言 `selfhost/ct-ast/**` 无 `#ct-raw`；raw 只用于用户代码与测试语料 |
| std 跨单元生命周期 | `Drop` / `Handback` 为 `static`，跨单元不可用；容器无法用 `delete` 销毁调用方单元的值类型 | 全部资源类型提供显式 `*_free` / `*_reset`；容器用 `*_clear` + `free_fn`；文档与测试同时钉住 |
| std 发现路径不一致 | 无默认 include 根，用户可能找不到库 | 安装后打印 `-I` 行；`test/std/run.sh` 用显式 `-I` 固化调用形态 |
| 字符串池耗尽 | 池仅 262144 字节，raw 块易撞顶 | 块级上限 + 显式诊断；不静默截断 |
| 文档迁移破坏外链 | `reports/` 与 `docs/design/` 的既有引用会失效 | 迁移前先跑 `check-docs.py` 记录基线；迁移同时改全仓库引用；保留一份 `docs/history/README.md` 索引 |
| CI 时长与成本 | 三个 job 全量 + nightly 可能过长 | 只保留一个「全量权威」（ubuntu-gcc）；clang 走 smoke；nightly 独立触发 |
| 包管理语义扩张 | 比较器与 index 会扩大 `Pkg.h.ct` 的语法面 | 一次只加一组断言；`ct get` 既有 spec 形态行为不变；无 spec 且无 index 时明确报错 |
| 阶段编号争议 | 「Phase 13」被补丁占用可能引发误读 | roadmap 记录编号说明；所有阶段 tag 与 `CTC_VERSION` 一致 |
| `ct build` 调 `cc` 的命令注入 | 默认会拼一条外部命令，路径与 `--cflags` 都来自用户 | 每个 token 走 `PkgOps::sh_quote` 的单引号化；`--cc` 只接受单个可执行路径；不把 `--cflags` 当 shell 片段直接拼接 |
| 94 处调用点漏改 | 漏改会让脚本进入「链接」形态，产物目录里没有 `.c` | 一次性 sed 后逐脚本跑既有断言；17.1 的 CI 全量门禁作为兜底 |
| `--emit-c` 行为漂移 | 一旦 stdout 或 `cc` 行变一个字节，`check-warnings.sh` 的 awk 提取与 golden 全红 | 迁移前记录一次基线快照；先实现 `--emit-c` 分支，最后才切默认值 |

---

## English

### 1. Goal and exit

Phase 17 turns six items from the 2026-11-02 third-party review — **std / CI matrix & sanitizers /
raw passthrough / documentation layering / package management / one-step `ct build`** — into an
executable plan with independent, verifiable slices. **D17-1…D17-9 are confirmed as proposed** (incl.
README ≤ 10K characters, the `std/` directory name, and `ct build` producing an executable by default).
Each slice still needs its own `spec` / `tasks` / `checklist` before implementation; this file is not a
line-by-line implementation contract. Per D17-9 the **subprocess-free** contract narrows to
`ct compile` and `ct build --emit-c`; the **network-free** contract is unchanged.

| Item | Content |
| --- | --- |
| Goal | Land the six governance / capability items as verifiable engineering capabilities |
| Exit | New and extended gates green under `bash selfhost/check-all.sh` and in CI; each item has its own test layer; the binary shape, banner, `ctc:` prefix and the **network-free** contract stay unchanged; **subprocess-free** narrows to `ct compile` / `ct build --emit-c` (D17-9) |
| Version | **Phase 17 ↔ `v0.17.0`** (D17-1) — `v0.13.0`–`v0.16.3` are already recorded as post-Phase-12 capability / fix patches, so the next phase does not reuse 13; one bump at close, patch bumps only for fixes that regenerate goldens |
| Rollback | Every slice is additive: CI / docs / package management do not touch the compiler core; std and raw passthrough add files and entry points only; the one-step `ct build` falls back to the old behaviour via `--emit-c` |

### 2. Non-goals

- No type checking, no generics, no optimisation — the language is not final (`1.0.0`).
- No behaviour change in L0 / L1 / L2; no oracle edits for new cases.
- No HTTP service, no hosted registry, no network beyond CI; **the network-free contract is unchanged**. `ct build` invokes a local C compiler by default (a controlled subprocess, D17-9), while `ct compile` and `ct build --emit-c` stay subprocess-free; `ct build` does **not** parse `cc` diagnostics, does no incremental linking and ships no build system.
- No comment-preserving preprocessor: raw passthrough is a block marker, not a general preprocessor, and ct-ast only.
- No full SemVer (pre-release / build metadata / `!=` excluded); no transitive lock-update policy research.
- No marketing rewrite of README: documentation layering is about structure and links.

### 3. Current state and gaps (measured 2026-11-02)

| Area | Today | Gap |
| --- | --- | --- |
| CI | No `.github/`; `Makefile` only runs `check-all.sh`; nine hard gates with a GCC wrapper | No platform matrix, clang, sanitizers or fuzz; BSD-only probes are skipped on Linux with nobody re-checking |
| std | No `std/` at all | No reusable library, no namespace or lifetime convention |
| raw passthrough | The lexer drops `//` and `/* */` before tokenising (`Lexer.h.ct` lines 72–84); `#` at line start already becomes `T_PP` | No way to carry an unrecognised C fragment into the output; `N_RAW = 31` is taken |
| Docs | `README.md` ≈ 89K bytes (`wc -c`); `docs/` and `reports/` overlap; no index page and no link gate | No `docs/README.md`, no dead-link / version-token / gate-count check |
| Package manager | `Pkg.h.ct` has manifests, MVS, git tags, directory sources, SHA-256, `sha256:` locks, vendor, `ct get` / `ct install` | No `ct update` / `ct verify` / index; `range_match` only `^` / `~` / exact / `*`; **`ct.pkg` has no `cflags` / `ldflags` / `requires`**, so platform packages and anything needing `-l` cannot ship in one step |
| `ct build` CLI | Requires `-o <dir>`, writes only `.c` / `.h` and prints a `cc` line (`Module.h.ct` lines 683–825); no `--cc` / `-D` / `-l` entry point; **94 call sites across 9 scripts** in this repo | Users must run `cc` by hand again (every example and test writes its own `build.sh`); embedded `--cc` / `-mcpu` / `-l` have nowhere to go (the open SH-43 item) |
| Lifecycle | Built-in `Drop` / `Handback` emitters are `static` (`Emitter.h.ct` line 1445) | No cross-unit `delete` / `own`; std must expose explicit `*_free` / `*_reset` |
| Import roots | `resolve_import` searches the importer's directory then `-I` roots; no default root (`Module.h.ct` lines 248–304) | std needs an explicit `-I` or users cannot discover it |
| String pool | `calloc(262144, 1)` (`Arena.h.ct` lines 76, 117) | Raw blocks need a per-block cap and a hard diagnostic |

### 4. Slices

| Slice | Content | Surface | Exit |
| --- | --- | --- | --- |
| **17.1** | **CI matrix + sanitizers + deterministic fuzz** | `.github/workflows/{ci,nightly}.yml`, `selfhost/check-sanitizers.sh`, `test/fuzz/run.sh` | three CI jobs green; ASAN/UBSAN green locally and nightly; fuzz reproducible with a fixed seed and no crash |
| **17.2** | **`std`** | `std/{str,vec,arena,fs,utf8,test,map}.h.ct`, `test/std/run.sh`, install path (D17-2) | seven modules end-to-end under `gcc`; `test/std/run.sh` becomes the 10th hard gate |
| **17.3** | **raw passthrough** | `Lexer.h.ct`, `Arena.h.ct` (`N_RAW_TEXT`), `Parser.h.ct`, `Emitter.h.ct` | positive / negative cases green; the ct-ast self-hosting guard holds; spec / README / tutorial / editor grammar in sync |
| **17.4** | **docs layering + link gate** | `docs/README.md`, `test/docs/check-docs.py`, moves into `docs/history/`, README slimming (D17-5) | zero dead links; README within target; `issues/` and `AGENTS.md` stay in place |
| **17.5** | **package management** | `Pkg.h.ct` (comparator ranges, `update`, `verify`, `cflags` / `ldflags` / `requires`), `Driver.h.ct`, `test/pkg/run.sh` | `ct update` / `ct verify` work; comparator ranges covered; `ct install` prints **one** command with `-I` / `-D` / `-l`; compile path still network-free |
| **17.6** | **one-step `ct build`** | `Module.h.ct` (`build_main`'s default path), `Driver.h.ct` (both CLI parsers, SH-24), 94 call sites in 9 scripts, the CLI layer of `test/run.sh` | an executable by default; `--emit-c` byte-identical to today; a failing `--cc` yields a non-zero exit; the 11 gates stay unchanged |

Slice details mirror the Chinese section: 17.1 keeps a single full-matrix authority (ubuntu-gcc), clang
runs smoke on Linux and full on macOS, sanitizers and fuzz live in nightly; 17.2 uses explicit `-I`
plus an install path under `$(dirname "$prefix")/share/ct/std` and never relies on cross-unit
`Drop`, and adds `std::map` as a bounded open-addressing container with monomorphic `MapStrInt` /
`MapIntPtr` plus an optional `void *` erased interface, cleared via `*_clear` + `free_fn` (never
`delete`); 17.3 uses `#ct-raw` / `#ct-endraw` at line start, a new `N_RAW_TEXT` node, a 32 KiB block cap
and a `check-ast.sh` assertion that ct-ast sources contain no raw block; 17.4 adds navigation and a
Python-standard-library-only link / version / gate-count checker before moving history; 17.5 adds comparator
ranges with space-separated AND, `ct update`, `ct verify`, a git-hosted plain-text index selected
via `CT_INDEX` or `--index`, and the optional `cflags` / `ldflags` / `requires` manifest keys that
`ct install` folds into one runnable command; 17.6 makes the executable the default output of
`ct build` (C emitted into `.ctbuild/` unless `--outdir` says otherwise, then `$CC` / `--cc` is
invoked, with `--cflags` / `--ldflags` passed through), keeps `--emit-c` byte-identical for the 94
existing call sites, quotes every token with the `PkgOps::sh_quote` rule, propagates the compiler's
exit code, leaves `cc` diagnostics untranslated (`#line` already maps them back to `.ct`), and requires
`--emit-c` for library-only builds that have no `main`.

### 5. Order and dependencies

1. **17.1 CI** — build the safety net first so every later slice is validated on all platforms.
2. **17.4 docs** — navigation and doc lint must exist before 17.2 / 17.3 add new docs, and the move
   must happen in one pass to avoid double relocation.
3. **17.6 one-step build** — migrate all 94 call sites to `--emit-c` once, so later scripts are written
   against the new CLI, and 17.5 can print a single command.
4. **17.2 std** — needs the doc locations from 17.4 and the cross-platform checks from 17.1.
5. **17.3 raw** — touches lexer, AST and emitter; highest risk, closed on its own after CI and docs are in place.
6. **17.5 package management** — an independent leaf (`Pkg.h.ct` never touches the AST), but it must
   follow 17.6 because the build metadata lands in the 17.6 command line.

17.2 and 17.5 are disjoint and may run in parallel; 17.3 only touches `selfhost/ct-ast/**` frontend / backend.
17.6 changes `build_main` and both CLI parsers — disjoint from 17.3's frontend work, but both need the
full gate run, so close them one after the other.

### 6. Version and release

- **Phase 17 ↔ `v0.17.0`**; the roadmap records that `v0.13.0`–`v0.16.3` were consumed by post-Phase-12 patches.
- Close with one bump: `CTC_VERSION` in five places (`ctc.c` / L1 / `l2/{core,driver}.ct` / `ast/main.ct`),
  every golden regenerated for the version token only.
- In-phase patch bumps only when a fix regenerates goldens; 17.1 / 17.4 / 17.5 / 17.6 do not
  (17.6's `--emit-c` must stay byte-identical to today).
- Tag `v0.17.0` at close; intermediate milestones use non-version tags (`phase17-std`, `phase17-raw`).

### 7. Global definition of done

1. `bash selfhost/check-all.sh` green with **11 hard gates** (adding `test/std/run.sh` and `test/docs/check-docs.py`).
2. Three CI jobs plus nightly green; sanitizer and fuzz report nothing.
3. Every new or changed case gets its expected output from a real binary; no hand-written goldens.
4. Documentation is bilingual; `language-spec` / `README` / tutorial / roadmap / glossary / editor grammar move together (AGENTS §9).
5. L0 / L1 / L2 untouched; no third-party libraries or build systems; **network-free** unchanged; `ct compile` and `ct build --emit-c` are subprocess-free, and `ct build` only invokes a local C compiler (no diagnostic parsing, no incremental linking).
6. Any `install.sh` behaviour change (the std install path) is confirmed by the user first.
7. `ct build` produces an executable in one step by default; under `--emit-c` the artefacts, stdout and `cc` line of the 94 existing call sites stay byte-identical.

### 8. Confirmed decisions

| Id | Topic | Proposal | Status |
| --- | --- | --- | --- |
| **D17-1** | Phase number and version | **Phase 17 ↔ `v0.17.0`**; document that 13–16 were consumed by patches | ✅ confirmed |
| **D17-2** | std discovery | Explicit `-I`; `install.sh` installs to `$(dirname "$prefix")/share/ct/std` and prints the `-I` line; **no** default search path | ✅ confirmed |
| **D17-3** | raw marker syntax | Line-start `#ct-raw` / `#ct-endraw` (existing `T_PP` path); ct-ast only; `N_RAW_TEXT`; 32 KiB per block; ct-ast sources must not use raw | ✅ confirmed |
| **D17-4** | registry shape | Git-hosted plain-text index via `CT_INDEX` / `--index`; no HTTP or hosting; `ct update` / `ct verify`; comparator ranges with space-separated AND | ✅ confirmed |
| **D17-5** | docs layering target | `docs/README.md` + `test/docs/check-docs.py` first; move `reports/` and closed-phase `design/` into `docs/history/`; README ≤ 10K characters; `issues/` and `AGENTS.md` stay | ✅ confirmed |
| **D17-6** | sanitizer / fuzz gate status | Not in `check-all.sh` (keeps local runtime); CI nightly plus manual scripts; deterministic fixed seed | ✅ confirmed |
| **D17-7** | container placement and shape | Fold into 17.2 as `std/map.h.ct`; monomorphic types first (`MapStrInt` / `MapIntPtr`) plus an optional `void *` erased interface; bounded open addressing; `*_clear` / `free_fn`, never `delete`; no third-party binding and no official dialect expander | ✅ confirmed |
| **D17-8** | standard-library naming | Top-level directory **`std/`**, namespace `std::<mod>`, installed at `$(dirname "$prefix")/share/ct/std`; the word `stdlib` is retired (user: too verbose) | ✅ confirmed (2026-11-02) |
| **D17-9** | default `ct build` shape | **One step by default**: emit C (default `.ctbuild/`, `--outdir` to change) then invoke the C compiler (`$CC` / `--cc`, default `cc`) to produce an executable; `--emit-c` emits only; `--cflags` / `--ldflags` pass through; all 94 in-repo call sites switch to `--emit-c`; subprocess-free narrows to `ct compile` / `ct build --emit-c` | ✅ confirmed (2026-11-02) |

### 9. Risks

| Risk | Mitigation |
| --- | --- |
| Raw blocks break self-hosting | ct-ast is compiled by L2, which does not know raw; `check-ast.sh` asserts no `#ct-raw` under `selfhost/ct-ast/**` |
| std lifetime across units | `Drop` / `Handback` are `static`; a container cannot `delete` a value type from the caller's unit | Every resource type exposes `*_free` / `*_reset`; containers use `*_clear` + `free_fn`; pinned by docs and tests |
| Undiscoverable std | install prints the `-I` line; `test/std/run.sh` fixes the invocation shape |
| String-pool exhaustion | per-block cap plus a hard diagnostic; never truncate silently |
| Docs move breaks inbound links | run `check-docs.py` for a baseline before moving, rewrite every reference in the same slice, keep a `docs/history/README.md` index |
| CI cost | one full-matrix authority (ubuntu-gcc); clang smoke on Linux, full on macOS; nightly is separately triggered |
| Package-manager scope creep | one assertion group per addition; existing `ct get` spec forms unchanged; a clear error when neither a spec nor an index is available |
| Phase-number ambiguity | roadmap records the numbering note; every phase tag matches `CTC_VERSION` |
| Command injection in the `cc` invocation | every token goes through the `PkgOps::sh_quote` rule; `--cc` accepts a single executable path only; `--cflags` is never spliced as a shell fragment |
| A missed call site among the 94 | mechanical migration, then each script's existing assertions; 17.1's CI full run is the backstop |
| `--emit-c` behaviour drift | snapshot a baseline before migrating; implement the `--emit-c` branch first and flip the default last |
