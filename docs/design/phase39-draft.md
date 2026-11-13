# Phase 39 — C ABI 导出面与库制品

> **状态：已立项**（2026-11-13，用户批准三项决策 A；同日批准 battle 裁定：B39-1 走 C 路径（B1+B3）、B39-2 取默认 A；卡已冻结，冻结变更见 §9）。
> **基线**：PH-38 收口提交（`v0.38.0`）；S0 在该提交上重建并记录实际 sha 与门禁数字。
> **文档形态**：`phase39-draft.md`；design window 7/12，不触发归档。
> **前置**：[phase34-draft.md](phase34-draft.md)（`pub` 语义）、[phase36-draft.md](phase36-draft.md)（`Str` 的 ABI 边界）、[phase38-draft.md](phase38-draft.md)（收口基线）。
> **关联**：[modern-oo-gap.md](../modern-oo-gap.md) §3.8、[proposals/ct-pkg-agent-runtime.md](../proposals/ct-pkg-agent-runtime.md)、[D-001](../decisions/D-001.md)、[D-002](../decisions/D-002.md)。
> **规模**：编译器/驱动 220–500；夹具 100–180；文档 50–90；合计 **370–770**（±40%）。
> **纪律**：收口时 bump `v0.39.0`；tag/push 按 `AGENTS.md` 0.3 `phase-tag-requires-user-approval` 等用户批准。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | PH-39 |
| 目标 | 给 `ct build` 增加 `--lib`：产出 `lib<base>.a` + `<base>.abi.h`，**根单元**的 C 兼容 `pub` 函数即 C ABI 导出面 |
| 范围 | O1/O2/O3；不导出按值 struct / `pub` 全局 / `pub extern`；泛型模板跳过并诊断；不做 dylib、MSVC、版本协商 |
| 交付物 | `Driver.h.ct` / `Module.h.ct` / `Emitter.h.ct`；`selfhost/check-ast.sh` 的 p39 段；`test/modules/p39_lib/**`；`test/modules/errors/p39_*/**`；文档 |
| 任务清单 | §4.1（R1–R9） |
| 退出判据 | E39-1…E39-9（§5） |
| 依赖 | PH-38 收口 `v0.38.0`；P34 已收口；本机 `cc` / `ar` / `nm`；规范 1.9.0 |
| 规范版本 | 1.9.0 |
| version-minor | 39 |
| 已知风险 | R39-1…R39-6（§7） |

## 1 目标与边界

### 1.1 一句话

`ct build --lib` 把一次构建变成一个 C 静态库：**根 `.h.ct` 单元**里有定义、C 兼容的 `pub` 函数进入 `<base>.abi.h`，产物是 `lib<base>.a`，纯 C 工程 `#include` 头文件后可直接静态链接并运行。

### 1.2 三项

| 编号 | 内容 | 今天 |
| --- | --- | --- |
| O1 | `--lib` 产出 `lib<base>.a` + `<base>.abi.h` + 逐单元 `.o`；纯 C 消费者可链接运行 | 只有可执行文件与分单元 `.c`；无 `.a` / `.abi.h` |
| O2 | 导出面 = **根单元**中有定义、C 兼容的 `pub` 函数；泛型模板跳过并给 `file:line:col` 警告；非模板的不兼容签名报 L39-1 | 无导出面概念 |
| O3 | 导出定义带 `visibility("default")`，中间对象以 `-fvisibility=hidden` 编译；非 `pub` 函数/全局发射 `static` | impl 符号今天已是 `static`（实测 `nm`） |

> O3 的边界：**visibility 不改变静态归档的全局符号表**。v1 接受 `nm -g` 里出现 trait vtable 与内建 `Str_*`，并在 `<base>.abi.h` 与文档中明写「只有 `.abi.h` 的声明是 ABI」；不承诺 `nm` 只剩导出（这是 [D-002](../decisions/D-002.md) 的默认 A）。

### 1.3 非目标

- 不导出按值 struct / union：`<base>.abi.h` 只放不透明前置声明（D39-6）。
- 不导出 `pub` 全局变量；不导出 `pub extern`（定义在库外的 C 符号）；两者都不写进 `.abi.h`，由 L39-6 汇总提示。
- 泛型模板不导出：跳过并给 L39-1w 警告，不再整库硬错（D39-10，B1）。
- 不做 Windows/MSVC、`.dll` / `.dylib` / `.so`、ABI 版本协商运行时；v1 只覆盖 macOS/Linux 的 `cc` + `ar`。
- 不做 C++ 头、`extern "C"` 块；不做链接期本地化/密封归档（[D-002](../decisions/D-002.md) 默认 A）。
- 不改既有 `ct build`（可执行）与模块 `.h` 的「只放类型」契约（D39-1）。

### 1.4 关键决策

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D39-1 | ABI 头是**独立产物** `<base>.abi.h`，模块 `.h` 仍只放类型 | 不违反 Phase 34 的 D34-2 硬边界 |
| D39-2 | 只导出**根单元**内有定义的 `pub` 函数；`pub extern` 与 import 单元的 `pub` 不进导出面 | 根单元是作者声明的公开头，文件级控制零新语法（D-001 的 C 路径） |
| D39-3 | 根单元必须是 `.h.ct`；`-o` 指定归档路径；默认 `<outdir>/lib<base>.a`；头固定 `<outdir>/<base>.abi.h` | 名字只依赖根单元，可预测 |
| D39-4 | 归档确定化：优先 `ar rcsD`；不支持时 `ZERO_AR_DATE=1 ar rcs`（实测 macOS 可用）；两者都失败即硬错 | Apple `ar` 无 `-D` 且默认 `ar rcs` 非确定（§2.2） |
| D39-5 | 导出定义注入 `visibility("default")`，中间对象加 `-fvisibility=hidden`；符号面 = 导出集合 + `expected.internal` 内部清单，二者并集逐行断言 | 静态归档无法藏符号；用可审计清单代替不可能的清空 |
| D39-6 | v1 只收标量 / 指针 / 函数指针 / 数组参数 / 指向具名 struct 的指针；按值 struct、trait 值、std 容器类型、`own` 一律 L39-1（泛型除外，见 D39-10） | 不透明前置声明与按值传参不可兼得 |
| D39-7 | `--lib` 下 `pub` 全局、`main`、带 shim 的 `.m.ct` 单元各自硬错（L39-3…L39-5） | 三者都会把不可控符号塞进归档 |
| D39-8 | `--lib` 下非 `pub` 顶层函数与全局一律发射 `static`；`pub` 函数保持 external | 非 `pub` 只在单元内可见（实测今天未 `static`，见 §2.2） |
| D39-9 | 导出名 = 发射后的 C 符号名（`cname`，含 `namespace` 前缀） | 头文件与归档必须同名，否则 C 链接不上 |
| D39-10 | 根单元内带定义的泛型模板：**跳过 + L39-1w 警告**（带 `file:line:col`），不中止构建 | 泛型实例无外部符号（实测 `t _id__ct1`），硬错会误杀正常库；B1 已由用户批准 |
| D39-11 | 非根单元的 `pub` 与 `pub extern`：不导出，但输出 L39-6 汇总警告；`.abi.h` 不含它们 | J-5「不静默」：不能既不导出又什么都不说 |
| D39-12 | `<base>.abi.h` 写 `<BASE>_ABI_VERSION 1` 与 `<BASE>_ABI_HASH`（导出名排序后的 FNV-1a 32 位） | 导出面变化必须可观测，不能只靠测试夹具 |

## 2 现状与基线

### 2.1 门禁基线

参考值（**历史量级参考**，v0.30.0）：`check-ast` 1155/0、`check-warnings` 389/0、`test/run` 145、`check-docs` 1030+ links、design window 12/12。S0 在 PH-38 收口提交上重建 `ct` 并实测替换本节。

### 2.2 红证探针（2026-11-13 实测，本机 Apple clang + Apple ar，`ct v0.37.0`）

| 探针 | 命令 | 基线输出 |
| --- | --- | --- |
| `--lib` 缺失 | `ct build --lib x.h.ct` | `unknown option '--lib'`，exit 1 |
| `ar -D` 不可用 | `ar rcsD liba.a a.o` | `illegal option -- D`，exit 1 |
| 默认 `ar` 非确定 | 间隔 1s 两次 `ar rcs` 后 `cmp` | 字节不同（内嵌 mtime/uid） |
| `ZERO_AR_DATE` 确定 | 间隔 1s 两次 `ZERO_AR_DATE=1 ar rcs` 后 `sha256` | 两文件 sha256 相同 |
| visibility 不藏符号 | `cc -fvisibility=hidden -c` + `nm -g` | hidden 函数仍是 `T`（Mach-O 仍列出） |
| 非 `pub` 函数未 static | `ct build --emit-c` 后读生成的 `.c` | `int helper(void)` 无 `static`，会进 `nm -g` |
| 泛型 `pub` 无外部符号 | `p34_pub_generic` 的 `--emit-c` + `nm` | `id` 是 local `t`，`from_lib` 是唯一 `T`；纯 C 消费者今天可链接运行 |
| 消费者可链内部符号 | 手抄布局 + `extern Dog_Speak_vtable` | 链接成功并运行（D-002 默认 A 的依据） |

### 2.3 代码锚点

| 主题 | 位置 |
| --- | --- |
| `--lib` 解析与分派 | `tool/driver/Driver.h.ct` 的 `ct_driver_run`（`build` 分支） |
| build 主流程与输出默认值 | `frontend/module/Module.h.ct` 的 `build_main`（约 1025）与 cc 命令行拼装（约 1460–1540） |
| 根单元 `pub` 扫描范围 | `Module.h.ct` 的 `fn_start` / `fn_end`（只界定本单元自身解析范围） |
| 只有 `.h.ct` 可被 import | `Module.h.ct` 的 `resolve_import`（约 393） |
| 模块 `.h` 只放类型 | `Module.h.ct` 的 `write_unit_header` |
| `pub` 标记与定义判定 | `frontend/sym/Symbols.h.ct` 的 `Func.is_pub` / `Func.body` |
| impl 符号 static | `backend/emit/Emitter.h.ct` 的 `emit_struct_impls` |
| 函数定义 / 原型发射 | `Emitter.h.ct` 的 `emit_proto`、`emit_unit_init`（`__ct_init` 已是 constructor） |

## 3 语义与落码

### 3.1 导出规则

一个函数进入导出面，当且仅当：

1. 声明在 `--lib` 的**根 `.h.ct` 单元**，带 `pub`，且本构建内有定义（`Func.body >= 0`）；
2. 返回类型与参数类型都属于：内建标量、`void`、指针（含指向具名 struct 的指针、函数指针）、数组参数（decay 成指针）；
3. 非模板签名里没有按值 struct/union、trait/接口值（`*_iface`）、`Vec`/`Map`/`Option`/`Result`/`Str` 等 std 类型、`own`。

处置分级：

| 情形 | 处置 |
| --- | --- |
| 根单元内带定义的泛型模板 | **跳过**，`file:line:col: warning: '<name>' not exported: generic template has no external symbol`（L39-1w） |
| 根单元内非模板、签名违反规则 3 | **硬错** L39-1，不写任何产物 |
| 根单元内 `pub extern`、被 import 单元的 `pub` | 不导出，输出 L39-6 汇总警告 |
| 根单元只有泛型模板（全部被跳过） | exit 0；`.abi.h` 只含 banner、版本宏与哈希 + 警告（L39-2 不触发） |

`pub extern` 不写进 `.abi.h`（D39-2）。列号来源：在 `Module.h.ct` 内回读声明行定位函数名（1-based，须剥掉 `<...>` 类干扰），不新增 `Symbols.h.ct` 字段（`Fn` 只存 `line`）。

### 3.2 产物与命名

```text
ct build --lib [-o <archive>] [--outdir <dir>] <root.h.ct>
```

| 产物 | 位置 | 说明 |
| --- | --- | --- |
| 归档 | `-o` 指定；缺省 `<outdir>/lib<base>.a` | `<base>` = 根 `.h.ct` 的文件名主干 |
| ABI 头 | `<outdir>/<base>.abi.h` | 始终随 `--outdir`，不随 `-o` |
| 中间对象 | `<outdir>/<unit>.o` | 逐单元保留；归档只收本构建生成的 `.o` |

`<base>.abi.h` 内容固定为：banner（含「只有本文件的声明是 ABI；归档 `nm` 面可能更大」）；`#define <BASE>_ABI_VERSION 1`；`#define <BASE>_ABI_HASH 0x<8 位十六进制>`；每个导出签名用到的具名 struct 的 `struct <T>;` 前置声明；导出函数原型（C 符号名）。**不出现** `_iface` / `_vtbl` / `Vec_` / `Map_` / `Str_`。

`--lib` 与 `--emit-c` 互斥；出现在 `compile` / `check` 模式时报 usage 错误（非零退出），不写产物。

### 3.3 符号与可见性

- `--lib` 下非 `pub` 顶层函数与全局发射 `static`（D39-8）；`pub` 定义保持 external，并在定义前写 `__attribute__((visibility("default")))`。
- cc 编译中间对象时追加 `-fvisibility=hidden`；导出函数因此是 default 可见的符号，其余标 hidden。
- trait vtable 与内建 `Str_*` 仍 external；它们**不是** ABI，只出现在 `expected.internal` 的「内部清单」。
- `nm -g --defined-only`（归一化：去前导 `_`、去成员头、排序）的集合必须 **等于「导出集合 ∪ `expected.internal` 内部清单」**；任一漂移即红。
- `<base>.abi.h` 与文档必须明写「`nm -g` 面 ⊋ 导出面；只有 `.abi.h` 的声明是 ABI」。
- 任何 L39-* 错误：不写 `.a` / `.abi.h`，并删除同名旧产物。

### 3.4 诊断

| 编号 | 触发 | 文案要点 |
| --- | --- | --- |
| L39-1 | 根单元非模板签名含按值 struct / trait 值 / std 类型 / `own` | `'<name>' cannot be exported: <reason>` |
| L39-1w | 根单元泛型模板被跳过（warning） | `'<name>' not exported: generic template has no external symbol` |
| L39-2 | 根不是 `.h.ct`，或没有候选（没有 `pub` 函数，或只有 `pub extern`） | `no exported functions in '<unit>'` |
| L39-3 | `--lib` 构建包含 `main` | `a --lib build cannot contain 'main'` |
| L39-4 | `--lib` 构建含 `pub` 全局变量 | `'<name>' cannot be exported: pub globals are not supported` |
| L39-5 | `--lib` 构建含带 shim 的 `.m.ct` 单元 | `a --lib build cannot include the C shim of '<unit>'` |
| L39-6 | 非根 `pub` / `pub extern` 不进导出面（warning） | `<n> pub function(s) are not part of the ABI surface (imported or extern)` |

L39-1/2/3/4/5 是硬错并带 `file:line:col`；L39-1w 与 L39-6 是 warning，不中止构建，但必须出现在 stderr。

### 3.5 与既有构建的关系

- `ct build`（可执行）与 `ct build --emit-c` 的行为、产物逐字节不变；`--lib` 只新增分支。
- 模块 `.h` 仍是类型-only；ABI 头独立（D39-1）。
- `__ct_init` 已是 `__attribute__((constructor))`，静态库被链接时自动运行，无需 `main`。

## 4 任务清单

开工前先做 **S0（不占任务行，不产提交）**：在 PH-38 收口提交上重建 `ct`、复跑 §2.2、把 §2.1 的门禁数字与 `test/modules/p39_lib/baseline.sha` 写进夹具目录，作为 R8 的比较基线。

R1–R7 每项先提 `test(abi): <task-id> 红`（只含夹具与断言），实现提交随后转绿；R8 为 `no-test:`（只做等价性证据，无行为改动，3.9 test-fix），R9 为纯文档 `no-test:`（6.6 T-7 例外），二者均须评审签字。收口不是任务：按 §8 的收口动作执行，不占任务行。

### 4.1 冻结任务表

| 任务 | 交付物（路径） | 验收命令 | effort | 回滚 |
| --- | --- | --- | --- | --- |
| R1 | `--lib` 解析、模式骨架与默认输出（`Driver.h.ct` / `Module.h.ct`） | `ct build --lib x.ct` 报 L39-2 且不产可执行；`ct compile --lib` 与 `--lib --emit-c` 均非零退出 | M | revert |
| R2 | 根单元导出扫描 + 分级处置 + L39-1/1w/2…6（`Module.h.ct`） | `bash selfhost/check-ast.sh` 的 `p39/errors` 9 条全绿（7 负例 + 2 诊断正例） | M | revert |
| R3 | `<base>.abi.h` 生成（版本宏 + 哈希 + 不透明前置 + 原型，`Emitter.h.ct`） | `p39/abi-header`：与 `expected.abi.h` 逐字节相同 | M | revert |
| R4 | `static` 化非导出 + visibility 注入 + cc 选项（`Emitter.h.ct` / `Module.h.ct`） | `p39/visibility`：每个导出定义前恰 1 个 attribute，cc 行含 `-fvisibility=hidden` | M | revert |
| R5 | 逐单元 `.o` + `ar` 归档 + 符号面（`Module.h.ct`） | `p39/symbols`：`nm` == 导出 ∪ `expected.internal`，diff 为空 | M | revert |
| R6 | 根单元 + 被 import 单元 + 纯 C 消费者夹具（`test/modules/p39_lib/**` + `check-ast.sh`） | `p39/lib-consumer`：链接、运行、输出逐字节等于 `expected.out`；imported 单元的 `pub` 不在 `.abi.h` | M | revert |
| R7 | 确定性归档（`ar rcsD` / `ZERO_AR_DATE` 回退） | `p39/determinism`：两次构建 `.a` sha256 相同 | S | revert |
| R8 | 零回归证据：`baseline.sha` + `check-ast.sh` 的 `p39/regression` 段 | `p39/regression`：`test/modules/{split,p34_pub_generic,ns_dir}` 的 `--emit-c` 产物 sha256 与 `baseline.sha` 逐行相同 | M | revert |
| R9 | 文档：ABI 指南、language-spec 导出规则、gap、README（`docs/**`） | `python3 test/docs/check-docs.py` exit 0；`p39/docs` 示例可跑 | S | revert |

映射：R1/R2→E39-3；R3→E39-6；R4→E39-7；R5→E39-2；R6→E39-1；R7→E39-5；R8→E39-4；R9→E39-9。**每项至多覆盖 1 条退出判据**（6.6 T-5）。

## 5 退出判据（E39-n）

所有 p39 断言挂在既有 `selfhost/check-ast.sh` 内，由 `check-all.sh` 统一执行；不新增门禁编号。

| ID | 断言 | 命令与阈值 | 夹具 |
| --- | --- | --- | --- |
| E39-1 | `--lib` 产出 `.a` + `.abi.h`；纯 C 消费者链接运行，输出正确；不产可执行 | `ok p39/lib-consumer`，1/1；stdout 与 `expected.out` 逐字节相同；无 `a.out` | `test/modules/p39_lib` |
| E39-2 | 符号面 = 导出集合 ∪ `expected.internal`；无 impl 方法符号 | `ok p39/symbols`；`nm -g --defined-only` 归一化排序后 diff 为空 | 同上 |
| E39-3 | 7 个负例各 rc≠0、恰一条 `文件:行:列: error:`、不写产物；2 个诊断正例 exit 0 且带 L39-1w/L39-6 | `ok p39/errors`，9/9 | `test/modules/errors/p39_*` |
| E39-4 | 既有 `ct build` / `--emit-c` 行为与产物零变化 | `bash selfhost/check-all.sh` 退出 0（11/11）+ `ok p39/regression` 摘要全等 | 全量 |
| E39-5 | 两次 `--lib` 构建（间隔 ≥1s）字节级确定 | `ok p39/determinism`；两次 `.a` sha256 相同，`nm` 排序相同 | `test/modules/p39_lib` |
| E39-6 | `.abi.h` 契约：版本宏 + `ABI_HASH` = 导出名 FNV-1a；原型集合 = 导出集合；无禁用符号 | `ok p39/abi-header`；与 `expected.abi.h` 逐字节相同；`_iface` / `_vtbl` / `Vec_` / `Map_` / `Str_` 命中 0 | 同上 |
| E39-7 | 导出定义恰带 1 个 visibility attribute；cc 行含 `-fvisibility=hidden`；非导出函数无 attribute | `ok p39/visibility`；计数等于导出数 | 同上 |
| E39-8 | **任务清单每项可独立验收（6.6 T-6）** | 逐项跑 §4.1 的验收命令，9/9 exit 0；收口对照表逐行贴原始输出 | §4.1 |
| E39-9 | 文档可执行：`package-guide` 的 `--lib` 示例原样可跑，且写明 `nm` 面 ⊋ 导出面 | `python3 test/docs/check-docs.py` exit 0；`ok p39/docs` | `docs/**` |

承诺映射：O1→E39-1 / E39-2 / E39-5；O2→E39-3 / E39-6；O3→E39-7。E39-4 / E39-9 守边界与文档。

## 6 负例台账（L39-n）

| 编号 | 触发 | 夹具（`test/modules/errors/`） | 文案要点 |
| --- | --- | --- | --- |
| L39-1 | 根单元按值 struct 导出 | `p39_export_byvalue/` | `cannot be exported: by-value struct` |
| L39-1 | 根单元 trait / 接口值导出 | `p39_export_trait/` | `cannot be exported: trait value` |
| L39-1 | 根单元 std 容器导出 | `p39_export_vec/` | `cannot be exported: std type` |
| L39-2 | 根不是 `.h.ct` / 没有候选 | `p39_no_exports/` | `no exported functions in` |
| L39-3 | `--lib` 含 `main` | `p39_main/` | `cannot contain 'main'` |
| L39-4 | `--lib` 含 `pub` 全局 | `p39_pub_global/` | `pub globals are not supported` |
| L39-5 | `--lib` 含 shim | `p39_shim/` | `cannot include the C shim of` |
| L39-1w（正例） | 根单元只有泛型模板 + C 包装器 | `p39_generic_skip/` | exit 0；`.abi.h` 不含泛型；stderr 带 `file:line:col: warning` |
| L39-6（正例） | 根单元 import 一个含 C 兼容 `pub` helper 的单元 | `p39_imported_units/` | helper 不在 `.abi.h`；stderr 有汇总行 |

7 负例 + 2 诊断正例 = 9 条，各断言一次；`pub extern` 由 `p39_imported_units/` 连带覆盖（不进 `.abi.h`，出现在 L39-6 汇总里）。

## 7 风险与开放项

| 编号 | 风险 | 触发信号 / 处置 |
| --- | --- | --- |
| R39-1 | `pub extern` 被误算进导出面 | R3 的 `expected.abi.h` 断言无外部 C 函数；L39-6 必须出现 |
| R39-2 | 内建 std 单元符号混入归档 | 导出扫描只看根单元；`expected.internal` 显式列出 `Str_*`，E39-2 抓漂移 |
| R39-3 | trait vtable 留在 `nm -g`，被误读为 ABI | §3.3 + `.abi.h` banner + 文档三处明写「非 ABI」；`expected.internal` 注明 |
| R39-4 | `ar` 平台差异导致归档不确定 | R7 双路径；S0 实测 `ar -D`；两条都失败即硬错 |
| R39-5 | 用户要求导出按值 struct 或数据 | 转 T39-1 另立卡；v1 不放开 L39-1 |
| R39-6 | C 路径残留：同根 C 兼容 helper 仍全导出、不能逐函数选 | 作者用「根单元 / 内部单元」文件组织控制；若需要函数级控制，回到 [D-001](../decisions/D-001.md) 的 B 案（需 1 次语法批准） |

开放项：

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T39-1 | 按值 struct / `pub` 全局的数据导出 | 有包明确需要，且 `.abi.h` 能携带布局 |
| T39-2 | 泛型函数导出（显式实例化清单） | P34 `pub` 泛型有导出需求 |
| T39-3 | Windows/MSVC、`.dll`/`.lib` | 有目标平台需求 |
| T39-4 | 链接期密封归档 / dylib 动态导出面 | Linux 实测 + D39-5 visibility + constructor 语义齐备（见 D-002 重开条件） |
| T39-5 | 函数级导出控制（`pub export` / `--export` 清单） | 用户批准一次语法/CLI 变更；见 D-001 的 B 案 |

## 8 估算与收口

- 编译器/驱动 220–500 = R1 40–80 + R2 70–130 + R3 60–120 + R4 40–80 + R5 20–100；夹具 100–180；文档 50–90。
- 开工前 S0：PH-38 收口提交上重建 `ct`（`ct -v` = v0.38.0）、复跑 §2.2、写 §2.1 与 `baseline.sha`；不占任务行。
- 收口动作：11 道门禁绿、`p39/*` 全绿、`version-minor=39`、五处 `CTC_VERSION` 与全部版本落点同步到 `v0.39.0`、phase-log 与对照表落盘；tag/push 按 0.3 `phase-tag-requires-user-approval` 等用户批准。
- 每个实现任务 ≤3 个源码文件（夹具/文档任务按目录计）；每个实现提交的父提交是它的 `test(abi): <task-id> 红`；仓库任何时刻可构建。

## 9 battle 裁定与冻结变更（2026-11-13，用户已批准）

两处争议按主规范 §7 立案、三轮收口；记录见 [`battle/p39-1/`](../../battle/p39-1/)、[`battle/p39-2/`](../../battle/p39-2/)，ADR 见 [D-001](../decisions/D-001.md)、[D-002](../decisions/D-002.md)。

| 争议 | 判决 | 用户裁定 | 本卡落地 |
| --- | --- | --- | --- |
| B39-1 导出面选择机制 | A `rejected`；C `rejected`；B 未过庭 | **走 C 路径**：批 B1（泛型改「跳过 + L39-1w」）+ B3（冻结卡变更签字） | §1.1 / O2 / D39-2 / D39-6 / D39-10 / D39-11 / §3.1 / L39-1w / L39-6 / R2 / R3 / E39-3 / §6 |
| B39-2 归档内部符号 | A `rejected`；B 部分成立；C `rejected` | **取默认 A**：逐单元 `.o` + `.abi.h` 明写 `nm` 面 ⊋ 导出面 | O1 / §3.3 / D39-5 / D39-12 / E39-2 / E39-6 / R5 / 风险 R39-2/R39-3 |

冻结变更记录：本次是一次显式冻结变更（6.2 / 6.6 T-6 / G8 `g8-phase-freeze`），变更范围仅上表两行所列为 O2/O1、D39-2/5/6/10/11/12、§3.1/§3.3、R2/R3/R5、E39-2/E39-3/E39-6 与 §6；R1/R4/R7/R8/R9 与 version-minor 不变。阻断已解除：PH-38 收口后 R2/R3/R5 可开工；T39-4/T39-5 为后续开放项。
