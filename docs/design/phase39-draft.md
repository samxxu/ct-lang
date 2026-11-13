# Phase 39 — C ABI 导出面与库制品

> **状态：已立项**（2026-11-13，用户批准三项决策均取 A：导出面只收指针、禁用构造硬错、现在冻卡；卡已冻结）。
> **基线**：PH-38 收口提交（`v0.38.0`）；S0 在该提交上重建并记录实际 sha 与门禁数字。
> **文档形态**：`phase39-draft.md`；design window 7/12，不触发归档。
> **前置**：[phase34-draft.md](phase34-draft.md)（`pub` 语义；本相只导出非泛型 `pub`）、[phase36-draft.md](phase36-draft.md)（`Str` 的 ABI 边界）、[phase38-draft.md](phase38-draft.md)（收口基线）。
> **关联**：[modern-oo-gap.md](../modern-oo-gap.md) §3.8、[proposals/ct-pkg-agent-runtime.md](../proposals/ct-pkg-agent-runtime.md)。
> **规模**：编译器/驱动 220–500；夹具 100–180；文档 50–90；合计 **370–770**（±40%）。
> **纪律**：收口时 bump `v0.39.0`；tag/push 按 `AGENTS.md` 0.3 `phase-tag-requires-user-approval` 等用户批准。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | PH-39 |
| 目标 | 给 `ct build` 增加 `--lib`：产出 `lib<base>.a` + `<base>.abi.h`，`.h.ct` 的 `pub` 函数即为 C ABI 导出面 |
| 范围 | O1/O2/O3；不导出按值 struct / `pub` 全局 / 泛型 / `pub extern`；不做 dylib、MSVC、版本协商 |
| 交付物 | `Driver.h.ct` / `Module.h.ct` / `Emitter.h.ct`；`selfhost/check-ast.sh` 的 p39 段；`test/modules/p39_lib/**`；`test/modules/errors/p39_*/**`；文档 |
| 任务清单 | §4.1（R1–R9） |
| 退出判据 | E39-1…E39-9（§5） |
| 依赖 | PH-38 收口 `v0.38.0`；P34 已收口；本机 `cc` / `ar` / `nm`；规范 1.9.0 |
| 规范版本 | 1.9.0 |
| version-minor | 39 |
| 已知风险 | R39-1…R39-5（§7） |

## 1 目标与边界

### 1.1 一句话

`ct build --lib` 把一次构建变成一个 C 静态库：`.h.ct` 里所有有定义的 `pub` 函数进入 `<base>.abi.h`，产物是 `lib<base>.a`，纯 C 工程 `#include` 头文件后可直接静态链接并运行。

### 1.2 三项

| 编号 | 内容 | 今天 |
| --- | --- | --- |
| O1 | `--lib` 产出 `lib<base>.a` + `<base>.abi.h` + 逐单元 `.o`；纯 C 消费者可链接运行 | 只有可执行文件与分单元 `.c`；无 `.a` / `.abi.h` |
| O2 | 导出面 = 本次构建所有非内建 `.h.ct` 单元的有定义 `pub` 函数；签名不 C 兼容即 L39-1 | 无导出面概念 |
| O3 | 导出定义带 `visibility("default")`，中间对象以 `-fvisibility=hidden` 编译；非 `pub` 函数/全局发射 `static` | impl 符号今天已是 `static`（实测 `nm`） |

> O3 的边界：**visibility 不改变静态归档的全局符号表**。v1 只承诺「导出函数带 default 可见性、其余标 hidden」；`nm -g` 里仍会看到 trait vtable，它不属于 ABI 承诺（§3.3、E39-2）。

### 1.3 非目标

- 不导出按值 struct / union：`<base>.abi.h` 只放不透明前置声明，按值传参消费者无法编译（D39-6）。
- 不导出 `pub` 全局变量；不导出泛型函数与 `pub extern`（定义在库外的 C 符号）——三者都不写进 `.abi.h`。
- 不做 Windows/MSVC、`.dll` / `.dylib` / `.so`、ABI 版本协商运行时；v1 只覆盖 macOS/Linux 的 `cc` + `ar`。
- 不做 C++ 头、`extern "C"` 块（CT 无重载，导出名就是 C 符号名）。
- 不改既有 `ct build`（可执行）与模块 `.h` 的「只放类型」契约（D39-1）。
- 不承诺把内部符号从静态归档的符号表里藏掉（§1.2 O3 的边界）。

### 1.4 关键决策

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D39-1 | ABI 头是**独立产物** `<base>.abi.h`，模块 `.h` 仍只放类型 | 不违反 Phase 34 的 D34-2 硬边界 |
| D39-2 | 只导出**有定义的** `pub` 函数；`pub extern` 跳过 | 外部 C 符号由消费者自己的链接解决，不算本库 ABI |
| D39-3 | 根单元必须是 `.h.ct`；`-o` 指定归档路径；默认 `<outdir>/lib<base>.a`；头固定 `<outdir>/<base>.abi.h` | 名字只依赖根单元，可预测；`-o` 不改变头的位置，避免两次构建写不同头 |
| D39-4 | 归档确定化：优先 `ar rcsD`；不支持时 `ZERO_AR_DATE=1 ar rcs`（实测 macOS 可用）；两者都失败即硬错 | Apple `ar` 无 `-D` 且默认 `ar rcs` 非确定（§2.2） |
| D39-5 | 导出定义注入 `visibility("default")`，中间对象加 `-fvisibility=hidden`；符号面用 `nm` 快照锁定 | 静态归档无法靠 visibility 藏符号，只能锁快照 |
| D39-6 | v1 只收标量 / 指针 / 函数指针 / 数组参数 / 指向具名 struct 的指针；按值 struct、trait 值、泛型、std 容器类型一律 L39-1 | 不透明前置声明与按值传参不可兼得 |
| D39-7 | `--lib` 下 `pub` 全局、`main`、带 shim 的 `.m.ct` 单元各自硬错（L39-3…L39-5） | 三者都会把不可控符号塞进归档，破坏导出面 |
| D39-8 | `--lib` 下非 `pub` 顶层函数与全局一律发射 `static`；`pub` 函数保持 external | 非 `pub` 只在单元内可见（实测今天未 `static`，见 §2.2），`static` 后才不会混进 `nm -g` |
| D39-9 | 导出名 = 发射后的 C 符号名（`cname`，含 `namespace` 前缀） | 头文件与归档必须同名，否则 C 链接不上 |

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

### 2.3 代码锚点

| 主题 | 位置 |
| --- | --- |
| `--lib` 解析与分派 | `tool/driver/Driver.h.ct` 的 `ct_driver_run`（`build` 分支） |
| build 主流程与输出默认值 | `frontend/module/Module.h.ct` 的 `build_main`（约 1025）与 cc 命令行拼装（约 1460–1540） |
| 只有 `.h.ct` 可被 import | `Module.h.ct` 的 `resolve_import`（约 393） |
| 模块 `.h` 只放类型 | `Module.h.ct` 的 `write_unit_header` |
| `pub` 标记与定义判定 | `frontend/sym/Symbols.h.ct` 的 `Func.is_pub` / `Func.body` |
| impl 符号 static | `backend/emit/Emitter.h.ct` 的 `emit_struct_impls` |
| 函数定义 / 原型发射 | `Emitter.h.ct` 的 `emit_proto`、`emit_unit_init`（`__ct_init` 已是 constructor） |

## 3 语义与落码

### 3.1 导出规则

一个函数进入导出面，当且仅当：

1. 声明在**非内建** `.h.ct` 单元，带 `pub`，且本构建内有定义（`Func.body >= 0`）；
2. 返回类型与参数类型都属于：内建标量、`void`、指针（含指向具名 struct 的指针、函数指针）、数组参数（decay 成指针）；
3. 签名里没有按值 struct/union、trait/接口值（`*_iface`）、泛型参数、`Vec`/`Map`/`Option`/`Result`/`Str` 等 std 类型、`own`。

违反 2/3 报 L39-1（位置在声明行），不写任何产物。`pub extern` 不进导出面（D39-2）。

### 3.2 产物与命名

```text
ct build --lib [-o <archive>] [--outdir <dir>] <root.h.ct>
```

| 产物 | 位置 | 说明 |
| --- | --- | --- |
| 归档 | `-o` 指定；缺省 `<outdir>/lib<base>.a` | `<base>` = 根 `.h.ct` 的文件名主干 |
| ABI 头 | `<outdir>/<base>.abi.h` | 始终随 `--outdir`，不随 `-o` |
| 中间对象 | `<outdir>/<unit>.o` | 只归档本构建生成的 `.o`，不混入用户手写对象 |

`<base>.abi.h` 内容固定为：banner；`#define <BASE>_ABI_VERSION 1`（`<BASE>` = base 大写、非 `[A-Za-z0-9]` 换 `_`）；每个导出签名用到的具名 struct 的 `struct <T>;` 前置声明；导出函数原型（C 符号名）。**不出现** `_iface` / `_vtbl` / `Vec_` / `Map_`。

`--lib` 与 `--emit-c` 互斥；出现在 `compile` / `check` 模式时报 usage 错误（非零退出），不写产物。

### 3.3 符号与可见性

- `--lib` 下非 `pub` 顶层函数与全局发射 `static`（D39-8）；`pub` 定义保持 external，并在定义前写 `__attribute__((visibility("default")))`。
- cc 编译中间对象时追加 `-fvisibility=hidden`；导出函数因此是唯一 default 可见的符号。
- trait vtable 仍 external（跨单元装箱要用），不加 attribute → hidden；它**不是** ABI，由 `expected.nm` 快照锁定。
- `nm -g --defined-only` 归一化（去前导 `_`）后的集合必须逐行等于 `test/modules/p39_lib/expected.nm`。
- 任何 L39-* 错误：不写 `.a` / `.abi.h`，并删除同名旧产物（避免陈旧库被误用）。

### 3.4 诊断

| 编号 | 触发 | 文案要点 |
| --- | --- | --- |
| L39-1 | 导出签名含按值 struct / trait 值 / 泛型 / std 类型 / `own` | `'<name>' cannot be exported: <reason>` |
| L39-2 | 根不是 `.h.ct`，或没有可导出函数 | `no exported functions in '<unit>'` |
| L39-3 | `--lib` 构建包含 `main` | `a --lib build cannot contain 'main'` |
| L39-4 | `--lib` 构建含 `pub` 全局变量 | `'<name>' cannot be exported: pub globals are not supported` |
| L39-5 | `--lib` 构建含带 shim 的 `.m.ct` 单元 | `a --lib build cannot include the C shim of '<unit>'` |

五条都是硬错，`ct build` 内报出，位置指向声明行（L39-2 指向根单元）。

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
| R2 | 导出扫描 + C 兼容判定 + L39-1…L39-5（`Module.h.ct`） | `bash selfhost/check-ast.sh` 的 `p39/errors` 8 条全绿 | M | revert |
| R3 | `<base>.abi.h` 生成（`Emitter.h.ct`） | `p39/abi-header`：与 `expected.abi.h` 逐字节相同 | M | revert |
| R4 | `static` 化非导出 + visibility 注入 + cc 选项（`Emitter.h.ct` / `Module.h.ct`） | `p39/visibility`：每个导出定义前恰 1 个 attribute，cc 行含 `-fvisibility=hidden` | M | revert |
| R5 | 逐单元 `.o` + `ar` 归档 + 符号面（`Module.h.ct`） | `p39/symbols`：`nm` 快照 diff 为空 | M | revert |
| R6 | 两单元库 + 纯 C 消费者夹具（`test/modules/p39_lib/**` + `check-ast.sh`） | `p39/lib-consumer`：链接、运行、输出逐字节等于 `expected.out` | M | revert |
| R7 | 确定性归档（`ar rcsD` / `ZERO_AR_DATE` 回退） | `p39/determinism`：两次构建 `.a` sha256 相同 | S | revert |
| R8 | 零回归证据：`baseline.sha` + `check-ast.sh` 的 `p39/regression` 段 | `p39/regression`：`test/modules/{split,p34_pub_generic,ns_dir}` 的 `--emit-c` 产物 sha256 与 `baseline.sha` 逐行相同 | M | revert |
| R9 | 文档：ABI 指南、language-spec 导出规则、gap、README（`docs/**`） | `python3 test/docs/check-docs.py` exit 0；`p39/docs` 示例可跑 | S | revert |

映射：R1/R2→E39-3；R3→E39-6；R4→E39-7；R5→E39-2；R6→E39-1；R7→E39-5；R8→E39-4；R9→E39-9。**每项至多覆盖 1 条退出判据**（6.6 T-5）。

## 5 退出判据（E39-n）

所有 p39 断言挂在既有 `selfhost/check-ast.sh` 内，由 `check-all.sh` 统一执行；不新增门禁编号。

| ID | 断言 | 命令与阈值 | 夹具 |
| --- | --- | --- | --- |
| E39-1 | `--lib` 产出 `.a` + `.abi.h`；纯 C 消费者 `#include` 后链接运行，输出正确；不产可执行 | `check-ast.sh` 输出 `ok p39/lib-consumer`，1/1；stdout 与 `expected.out` 逐字节相同；无 `a.out` | `test/modules/p39_lib` |
| E39-2 | 归档全局符号面 = 导出函数 + 夹具快照（含 vtable），无 impl 方法 | `ok p39/symbols`；`nm -g --defined-only` 去前导 `_` 排序后与 `expected.nm` diff 为空 | 同上 |
| E39-3 | 8 个负例各自 rc≠0、恰一条 `文件:行:列: error:`、不写 `.a`/`.abi.h` | `ok p39/errors`，8/8 | `test/modules/errors/p39_*` |
| E39-4 | 既有 `ct build` / `--emit-c` 行为与产物零变化 | `bash selfhost/check-all.sh` 退出 0（11/11）+ `ok p39/regression` 摘要全等 | 全量 |
| E39-5 | 两次 `--lib` 构建（间隔 ≥1s）字节级确定 | `ok p39/determinism`；两次 `.a` sha256 相同，`nm` 排序相同 | `test/modules/p39_lib` |
| E39-6 | `.abi.h` 契约：版本宏、不透明前置、原型集合 = 导出集合、无禁用符号 | `ok p39/abi-header`；与 `expected.abi.h` 逐字节相同；`_iface` / `_vtbl` / `Vec_` / `Map_` 命中 0 | 同上 |
| E39-7 | 导出定义恰带 1 个 visibility attribute；cc 行含 `-fvisibility=hidden`；非导出函数无 attribute | `ok p39/visibility`；计数等于导出数 | 同上 |
| E39-8 | **任务清单每项可独立验收（6.6 T-6）** | 逐项跑 §4.1 的验收命令，9/9 exit 0；收口对照表逐行贴原始输出 | §4.1 |
| E39-9 | 文档可执行：`package-guide` 的 `--lib` 示例原样可跑 | `python3 test/docs/check-docs.py` exit 0；`ok p39/docs` | `docs/**` |

承诺映射：O1→E39-1 / E39-2 / E39-5；O2→E39-3 / E39-6；O3→E39-7。E39-4 / E39-9 守边界与文档。

## 6 负例台账（L39-n）

| 编号 | 触发 | 夹具（`test/modules/errors/`） | 文案要点 |
| --- | --- | --- | --- |
| L39-1 | 按值 struct 导出 | `p39_export_byvalue/` | `cannot be exported: by-value struct` |
| L39-1 | trait / 接口值导出 | `p39_export_trait/` | `cannot be exported: trait value` |
| L39-1 | 泛型参数导出 | `p39_export_generic/` | `cannot be exported: generic parameter` |
| L39-1 | std 容器导出 | `p39_export_vec/` | `cannot be exported: std type` |
| L39-2 | 根不是 `.h.ct` / 无可导出函数 | `p39_no_exports/` | `no exported functions in` |
| L39-3 | `--lib` 含 `main` | `p39_main/` | `cannot contain 'main'` |
| L39-4 | `--lib` 含 `pub` 全局 | `p39_pub_global/` | `pub globals are not supported` |
| L39-5 | `--lib` 含 shim | `p39_shim/` | `cannot include the C shim of` |

8 条各断言一次；`pub extern` 不是负例（D39-2 跳过），由 R3 的 `expected.abi.h` 正例锁住：`p39_lib` 头单元含一条 `pub extern` 声明，`expected.abi.h` 不出现它。

## 7 风险与开放项

| 编号 | 风险 | 触发信号 / 处置 |
| --- | --- | --- |
| R39-1 | `pub extern` 被误算进导出面 | E39-3 的 8 条不含它；R2 在正例里断言 `.abi.h` 无外部 C 函数 |
| R39-2 | 内建 std 单元符号混入归档 | 导出扫描跳过内建单元；E39-2 快照会抓出多出的行 |
| R39-3 | trait vtable 留在 `nm -g`，被误读为 ABI | §3.3 写进文档；`expected.nm` 显式列出并注明「非 ABI」 |
| R39-4 | `ar` 平台差异导致归档不确定 | R7 双路径；S0 实测 `ar -D`；两条都失败即硬错 |
| R39-5 | 用户要求导出按值 struct 或数据 | 转 T39-1 另立卡；v1 不放开 L39-1 |

开放项：

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T39-1 | 按值 struct / `pub` 全局的数据导出 | 有包明确需要，且 `.abi.h` 能携带布局 |
| T39-2 | 泛型函数导出（显式实例化清单） | P34 `pub` 泛型有导出需求 |
| T39-3 | Windows/MSVC、`.dll`/`.lib` | 有目标平台需求 |
| T39-4 | dylib/`.so` 与动态导出面（visibility 真正生效处） | 静态库稳定后另立卡 |

## 8 估算与收口

- 编译器/驱动 220–500 = R1 40–80 + R2 60–120 + R3 60–120 + R4 40–80 + R5 20–100；夹具 100–180；文档 50–90。
- 开工前 S0：PH-38 收口提交上重建 `ct`（`ct -v` = v0.38.0）、复跑 §2.2、写 §2.1 与 `baseline.sha`；不占任务行。
- 收口动作：11 道门禁绿、`p39/*` 全绿、`version-minor=39`、五处 `CTC_VERSION` 与全部版本落点同步到 `v0.39.0`、phase-log 与对照表落盘；tag/push 按 0.3 `phase-tag-requires-user-approval` 等用户批准。
- 每个实现任务 ≤3 个源码文件（夹具/文档任务按目录计）；每个实现提交的父提交是它的 `test(abi): <task-id> 红`；仓库任何时刻可构建。
