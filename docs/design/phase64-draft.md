# Phase 64 · 裸机生成契约（`--freestanding` / 按需单元 / `--alloc` / const vtable）

**状态：在研（v0.63.0，`d=1`）**

| 项 | 值 |
| --- | --- |
| 状态 | **在研** |
| 依据 | [REQ-HW-010…013](../planning/hardware-readiness-requirements.md)；[battle hw-1 判决](../../battle/hw-1/verdict.md)（J-3 / J-4）；[裸机提案 §3](../proposals/ct-bare-metal-proposal.md) |
| 版本位 | `version-minor: 63`（PH-64，`d=1`，见 [AGENTS §0.3](../../AGENTS.md) 换算表） |
| 规范版本 | `1.15.0` |
| 只动 | `selfhost/ct-ast/**`、`test/ast/**`、`selfhost/check-ast.sh`、`docs/**` |

## 1. 目标

一句话：`ct build` 能为裸机目标产出**符号面受控**的 C —— 生成物不隐式拉 libc / 堆 / 构造函数，
分配器由用户映射，vtable 进只读段。

范围（做什么）：

- `--freestanding`：不隐式拉 std 单元、不带 libc / 堆、不发 constructor；默认允许集只用符号面判定；
- 按需单元：`Vec` / `Option` / `Result` / `Str` 只按实际使用与实例化拉取；
- `--alloc`：把 `malloc` / `free`（可选 `realloc` / `calloc`）映射到用户符号，注入所有生成单元；
- const vtable：定义、`__vptr`、`_iface.vt` 三处成套 `const`。

不做什么（本波不做）：

- `layout(plain)` 语法（REQ-HW-014 延后）；
- 按容器名字禁用（battle J-3 已否定）；
- 借用检查器 / 完整类型检查；
- 真实板卡 pilot（REQ-HW-020/021，不占 phase，需硬件与厂商工具链）。

## 2. 任务清单（开工前写死，与退出判据同受冻结）

| id | deliverable | verify | effort |
| --- | --- | --- | --- |
| PH-64-T1 | `backend/emit`：vtable 定义 `static const struct <T>_vtbl`、struct 的 `__<t>_vptr` 与 `_iface.vt` 为 `const … *` | `bash selfhost/check-ast.sh` 的 `p64_const_vtable` 段：产物三处均带 `const`、`sizeof` 不变、跨 TU 可链接运行 | M |
| PH-64-T2 | `Driver` / `Module`：`ct build` 只发射实际使用的 std 单元 | `p64_on_demand`：最小程序产物只有自身 `.c`；`Option<int>` 只拉 `Option.c` | M |
| PH-64-T3 | `Driver` / `Emitter`：`--alloc <sym>[,<sym>…]` 映射 `malloc/free[/realloc/calloc]`；无映射时 `own`/`delete` 走硬错 | `p64_alloc`：`--alloc pvPortMalloc,vPortFree` 产物不含 `malloc(`/`free(`；无 `--alloc` 的 `own` 在 `--freestanding` 下硬错 | M |
| PH-64-T4 | `Driver` / `Emitter`：`--freestanding` 开关：不做 constructor、不隐式带 libc / 堆 | `p64_freestanding`：`cc -ffreestanding -nostdlib -c` 每单元 `nm -u` ⊆ 允许集（默认空集） | M |
| PH-64-T5 | `Emitter`：`--freestanding` 下无初值的全局 trait 数组硬错并给位置 | `p64_no_init_array`：非零退出 + `文件:行:列: error: …` | S |

## 3. 退出判据（开工前写死）

| # | 判据 | 命令 / 锚点 |
| --- | --- | --- |
| E1 | 最小 `--freestanding` 程序的每个生成单元 `nm -u` ⊆ 允许集（默认空集） | `p64_freestanding` 段：`cc -ffreestanding -nostdlib -c` + `nm -u` 逐单元比对 |
| E2 | `--freestanding` 下无初值的全局 trait 数组硬错并给位置 | `p64_no_init_array` 段：非零退出 + `文件:行:列: error:` |
| E3 | `Option<int>` 只拉 `Option` 单元；最小程序只有自身 `.c` | `p64_on_demand` 段 |
| E4 | `--alloc pvPortMalloc,vPortFree` 后产物无 `malloc` / `free` 引用 | `p64_alloc` 段 |
| E5 | vtable 与 `__vptr` / `vt` 为 `const`，`sizeof` 不变，跨 TU 链接运行通过 | `p64_const_vtable` 段 |
| E6 | `bash selfhost/check-all.sh` 11/11 绿 | 收口对照表贴原始输出 |
| E7 | 任务清单每项可独立验收（6.6 T-6） | 收口对照表逐条对应 T1–T5 的 `verify` |

## 4. 依赖与风险

- 依赖：SH-86（P0，v0.62.1）已收口——数组与 `const` 的 vptr 现在由初值本身写入，否则本 phase 的
  const vtable 无从验证；
- 风险：`nm -u` 的符号名受 `-O2` / FORTIFY 影响（battle §4 已记录）——允许集按本机 clang 归一化，
  不按平台硬编码；`__*_chk` / `bzero` 一类由 libc 版本决定，门禁只断言「默认集里没有 libc」；
- 风险：按需单元会改变现有 `--emit-c` 产物集合，`test/pkg` 的 build 断言与 `check-ast` 的模块段
  需要同步；两者都以「产物必须能链接运行」为准，不锁文件清单。

## 5. 进度与阻塞（未收口）

**已交付：PH-64-T1**（`49bc9549`，vtable 与 `__vptr` / `vt` 成套 const）。

| 验收 | 结果 |
| --- | --- |
| `bash test/ast/p64_const_vtable.sh` | `OK p64cv`（红证见 `b5000b1c`） |
| `bash selfhost/check-ast.sh` | rc=0（1458/0） |
| p39 r8 `--emit-c` 字节基线 | 随 const 文本重写（3 组 6 行摘要） |

**未交付：T2 / T3 / T4 / T5**，阻塞点逐条记录如下（不许以「差不多」收口，6.3 A-2）：

- **T2（按需单元）是 T4 的前置**：`ct build --emit-c` 今天把 `Vec` / `Option` / `Result` / `Str`
  四个内置单元无条件解析并各发一份 `.c/.h`（实测最小程序产物 = 四单元 + 自身）。
  要让「最小程序只有自身 `.c`」，需要把「单元是否被使用」记录到符号表：
  `StructDef.owner` 只在非实例行有值（`frontend/sym/Symbols.h.ct:283` 的注释），实例行是 `-1`，
  所以 `add_struct_inst`（`:927`）处拿不到模板所属单元。可走的两条路：
  ① 在 `add_struct_inst` 前由解析器传入模板 owner，实例行记 `owner`，发射时按 owner 过滤；
  ② 给单元表加 `used` 位，在解析到 `Vec` / `Option` / `Result` / `Str` 的实例或非模板符号引用时置位。
  两者都要动 `frontend/sym` 与 `frontend/parse`，属于跨单元改动，需要单独立项评审。
- **T3（`--alloc`）依赖 T4 的硬错语义**：`own` / `delete` 无映射时在 `--freestanding` 下硬错，
  需要先有开关；映射本身（`Emitter` 把 `malloc(` / `free(` 换成用户符号）可独立做，
  但 E4 的验收要在 T4 之后才有意义。
- **T4 / T5 未开工**：卡面的 `--freestanding` 开关与符号面门禁尚未实现；
  在 T2 落地前，最小程序的 `nm -u` 一定含 libc 符号（`Vec.c` 带 `fprintf` / `abort`），E1 不可能绿。

**结论：PH-64 保持「在研」，不 bump MINOR、不打 tag。** 下一步是 T2 的立项（跨 `frontend/sym` +
`frontend/parse` 的改动面），完成后 T3→T4→T5 才能按依赖顺序收口。
