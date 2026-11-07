# Phase 20 计划（已完成）：包支持 —— 不让包作者做二等公民

> 中文 · [English](#english)
>
> **状态：完成**（2026-11-07；P20-01 / 02 / 03 / 04 / 06 / 08 落地，收口 `v0.20.0`；
> P20-05 只把 **ct-pkg 侧的索引生成器**移出本轮（ct 侧 `pkg_index_lookup` 仍是本仓欠账），
> P20-07 延后）。
> **版本口径：Phase 20 ↔ `v0.20.x`，已收口 bump 到 `v0.20.0`**（`CTC_VERSION` 五处一致）。
> 主题不是「补功能」，而是：**凡是「包本该能做好、却被编译器或工具链挡住」的地方，都归本相。**
> 关联：[package-guide](../package-guide.md)、[roadmap](../roadmap.md)、
> [争议清单（评审用）](phase20-disputes.md)、
> [SH-56](../../issues/selfhost/sh56-map-method-arity-unchecked.md)、
> [SH-57](../../issues/selfhost/sh57-import-after-decl-silently-dropped.md)、
> [SH-58](../../issues/selfhost/sh58-mct-prologue-raw-rejected.md)。
> Phase 21（闭包）不在本相，两者无依赖。

---

## 中文

### 0. 判据

「掣肘」的工程定义，本文统一按这一条判：

> **包作者为了做对一件事，被迫改变设计——多一个文件、多一个编译开关、手工补 `-I`、
> 改方法名、避开 OO、接受静默错误——且这个改变与包本身的领域无关。**

只缺功能、但不改变包的设计的，不算掣肘，不进本相。

---

### 1. 核对结论总表

核对方式：读源码 + 用 `ct v0.19.1` 做最小复现。**「有 issue 记录」不等于「已修」**；
只有提交、文档与门禁三样齐全才算完成。本相 **01–04、06、08 已完成**（收口 `v0.20.0`），
**05 只移出 ct-pkg 侧的索引生成器**（全版本索引由 ct-pkg 仓库另立阶段；**ct 侧
`pkg_index_lookup` 仍是本仓欠账**，不随本轮移交），**07 延后**（去虚拟化，P2 候选）。
下表的「判定」保留立项时的结论，不随本轮交付范围改写。

#### 1.1 用户清单的逐条核实

| # | 现象 | v0.19.1 实测 | 判定 |
| --- | --- | --- | --- |
| A1 | `.m.ct` 前导区只允许 `#include` / `#define`，`#ct-raw` 硬报错 | **成立**。复现得到 `a .m.ct unit allows only #include and #define in its prologue`；[SH-58](../../issues/selfhost/sh58-mct-prologue-raw-rejected.md) 已登记，结论是「保持（有意限制）」 | **不进**（改文案 + 文档） |
| A2 | 同名方法在同一类型宿主上 `ambiguous type-host map`，且无 re-export | **成立，且是硬阻塞**。两个包各给 `char *` 加 `len`，消费方调用报 `ambiguous type-host map for method 'len' on type 'char *': './a/A.m.ct' and './b/B.m.ct'`（`Emitter.h.ct:2767`）；全仓 0 处 re-export | **进 P0** |
| A3 | `.h.ct` 不能出口 `pub fn` | **不成立**。探针：`p/foo.h.ct` 里写普通函数定义，生成的 `foo.h` 有原型、`foo.c` 有定义，消费方编译运行通过 | **不进**（纯 std 约定；改文档） |
| B4 | `cc` 行缺 `-I <outdir>` | **已修**。`Module.h.ct:1069` 已发 `-I <outdir>`，注释说明它是 shim 包含生成类型头的根；来自提交 `915c12c` | **不进**（加回归探针） |
| B5 | 映射方法不校验实参个数（SH-56） | **成立**。[SH-56](../../issues/selfhost/sh56-map-method-arity-unchecked.md) 待修；`Expr.h.ct:1562-1586` 明确豁免了静态映射 | **进 P0** |
| B6 | 声明后的 `import` 静默丢弃（SH-57） | **成立**。[SH-57](../../issues/selfhost/sh57-import-after-decl-silently-dropped.md) 待修；`Module.h.ct:239-266` 遇到首个非预处理/非 import token 就停 | **进 P0** |
| B7 | `use` 结构体方法永远走 vtable | **成立**。`Emitter.h.ct:2789-2800`：具体 struct 接收者仍发 `->__<trait>_vptr->method(...)`，无静态类型快路径 | **延后**（原 P2，接受 golden 重生成） |
| C8 | `requires` 与 `dep` 两套语义易混 | **半成立**。写错 `requires` 会报 `has an unsupported requires`，不是全静默；但 `requires` 不满足**只告警**（`Pkg.h.ct:1562`，package-guide 也写明「不满足只告警」） | **进 P0**（改为硬失败）；文案并入 P2 |
| C9 | 索引只收录每个仓库最高 tag | **成立**。`ct-pkg/index/tools/refresh-index.sh` 用 `sort -V \| tail -1`，每包只写一行；`ct-pkg/index/index` 即此形态 | **ct-pkg 侧生成器移出本轮**（原 P1；ct 侧 `pkg_index_lookup` 仍欠） |
| C10 | `ct install` 按包打印 `-I vendor/<pkg>`，命名空间根被迫等于包根 | **成立，但根源不是 `-I`**。`Pkg.h.ct:1291` 打印 `-I vendor/<pkg>`；导入路径按目录解析，所以想写 `import std::str::String` 就必须有 `std/std/str/String.m.ct`。std、zlib、sqlite、clib 四包都已中招；net-posix 靠改用 `namespace net` 绕开；png 把 `Png.m.ct` 放在包根，与其余包不一致 | **进 P1**（包命名空间身份） |

#### 1.2 用户清单之外、实测发现的三条

| # | 现象 | 证据 | 判定 |
| --- | --- | --- | --- |
| N1 | **跨 `-I` 根的重名单元静默遮蔽** | `Module.h.ct:272-276` 的解析是「按根顺序先命中先用」，只在**同一根**内把 `.h.ct`/`.m.ct` 同名视为歧义；两个包都导出 `Uart` 时无任何提示 | **进 P1**（并入 P20-06） |
| N2 | **`requires` 不满足只告警** | `Pkg.h.ct:1562` 的注释与实现都是 warning，安装继续 | **进 P0** |
| N3 | **`v0.20.0` 已被 std 的清单预定** | `ct-pkg/std/ct.pkg`：`requires = ct >= 0.20.0`，注释写明理由是需要字符串字面量接收者（`"hi".len()`），该提交 `915c12c` 已在工作树、尚未打 tag | **发布前置**，不是独立任务 |

> N3 的含义：Phase 20 收口的 `v0.20.0` 必须把 `915c12c` 带上并写进文档，否则 std 0.2.0 的
> `requires` 无法满足，刚迁出的 std 立刻不可安装。

---

### 2. 进入 Phase 20 的任务

优先级：**P0 = 不做就会让包之间无法组合 / 静默出错；P1 = 包作者要改设计才能绕开；P2 = 有成本但可延后。**

**本轮交付**：P20-01 / 02 / 03 / 04 / 06 / 08 已落地；**P20-05 只移出 ct-pkg 侧的索引
生成器**（`ct` 侧 `pkg_index_lookup` 仍是本仓欠账）、**P20-07 延后**，
两项的需求与验收判据保留在下面，作为后续独立阶段的输入，不再作为本相完成判据。

#### P20-01（P0）类型宿主方法的冲突可解

- **目标**：两个包可以各自给 `char *` 增加同名方法；消费方显式选择，不再只有「歧义」一条路。
- **做法**：
  1. 新增 trait 限定调用 `Trait::method(recv, args)`，允许全路径 `a::ALen::len(s)`；复用 `::`，不引入新运算符。
  2. 歧义诊断保留，但 hint 必须打印**两个候选各自的限定写法**，让用户能直接改。
  3. 不做 re-export：组合用限定调用解决；包要提供便利 API，用自己的方法名另写一层。
- **交付**：parser/emitter 的限定调用；`Emitter.h.ct` 的歧义文案；language-spec 一节。
- **验收**：
  - 探针 `p20_two_pkg_same_method`：两个包都给 `char *` 加 `len`；`s.len()` 报歧义并给出两条限定写法；`a::ALen::len(s)` 编译并返回正确值；
  - `std` 与本包同时导入时，未限定调用仍报歧义，不静默选边；
  - 现有全部 `.m.ct` 的未限定调用行为不变。

#### P20-02（P0）`import` 只允许出现在前导区，且必须报错

- **目标**：声明之后的 `import` 不再静默消失。
- **做法**：`scan_imports` 之外，在正文解析遇到 `import` 时直接报错；文案给出「move the import to the top of the file」。
- **验收**：
  - SH-57 的两个最小复现都变成**指向 import 行**的错误；
  - 全仓语料与 `ct-pkg` 七个包零新增失败；
  - 负例进 `check-ast.sh`。

#### P20-03（P0）映射方法在调用点校验实参个数

- **目标**：`.m.ct` 静态映射与普通 trait 方法一样受 Phase 19 的 arity 检查。
- **做法**：`Expr.h.ct:1562` 的豁免面收窄到真正未知的情形（函数指针字段），静态配方按 `Trait` 声明比对；多写、少写都产生**调用点 arity 诊断**——`ct build` / `ct compile` 下按 `warning:` 打印、退出码仍为 0（多余实参被配方丢弃，编译期放行），`ct check` 下同一记录按 `error:` 打印并退出 1。
- **验收**：
  - `"abc".len(1)` 在 `ct check` 下报 `error:` 且指向调用点，在 `ct build` 下是 `warning:`、退出 0；`len()` 正常；
  - SH-56 的复现转为负例探针；
  - `std` / `clib` / `zlib` / `png` / `sqlite` / `net-posix` 全量构建零新增失败。

#### P20-04（P0）`requires` 不满足改为硬失败

- **目标**：不兼容的包不再「装上了，运行时才炸」。
- **做法**：`pkg_check_requires` 返回非零并使 `ct get` / `ct install` 退出；新增 `--force` 才降级为警告；文案同时给出当前版本与包要求。
- **验收**：
  - `requires = ct >= 99.0.0` 时 `ct install` 退出码非零，报文含 `requires 'ct >= 99.0.0', but this is vX.Y.Z`；
  - `--force` 打印 warning 后继续；
  - `std` 在 `v0.19.1` 上安装失败（符合其 `requires >= 0.20.0`），在 `v0.20.0` 上成功。

#### P20-05（P1，ct-pkg 侧生成器移出本轮）索引保留版本历史，按区间解析

- **目标**：旧编译器能拿到兼容旧版，而不是只能拿到最高 tag。
- **做法**：`refresh-index.sh` 为每个 `v*` tag 写一行（含 `requires` 字段）；`pkg_index_lookup` 在满足请求区间与包 `requires` 的候选里取最高版本；索引格式保持向后兼容（旧 `ct` 仍能解析第一行/五字段行）。
- **验收**：
  - 索引同时有 `std 0.1.x` 与 `0.2.0` 两行；
  - `v0.19.1` 上 `ct get std@^0.1` 选中 0.1.x 并成功安装；
  - `v0.20.0` 上 `ct get std@^0.2` 选中 0.2.0；
  - `ct.lock` 固定被选中的 tag 与摘要。
- **本轮状态**：只把 **ct-pkg 侧的索引生成器**（`refresh-index.sh` 为每个 tag 写一行）移出本轮，由 ct-pkg 仓库另立阶段；**ct 侧的 `pkg_index_lookup` 区间解析仍是本仓欠账**，不在本轮移交，也尚未实现。

#### P20-06（P1）包命名空间身份 + 跨根重名检测

- **目标**：消除「包名当顶层命名空间就必须多套一层目录」和「两个包的同名单元静默遮蔽」。
- **做法**：
  1. `ct.pkg` 新增可选 `namespace = <seg>`：声明该包拥有导入路径的第一段。
  2. 解析 `import <seg>::x` 时，若某个 `-I` 根对应的包声明了 `<seg>`，先试 `<root>/x`，再回退旧路径 `<root>/<seg>/x`（向后兼容）。
  3. 同一 `<seg>` 被两个包声明 → 错误；跨根同名单元落在两个 `-I` 根 → 错误并列出两个根（不做静默先到先得；仅豁免候选路径相同、根字符串相同、首个命中来自导入方自身目录三种）。
- **验收**：
  - 探针 `p20_pkg_namespace`：文件放在包根、`namespace = std`，`import std::str::String` 可解析；旧的 `std/std/...` 布局同样可解析；
  - 探针 `p20_dup_unit`：两个根都有 `Uart.h.ct` → 错误列出两个路径；
  - 探针 `p20_dup_plain`：两个普通 `-I` 根（都无 `ct.pkg`）同名单元 → 同样报错，不因缺包名而先到先得；
  - `std` 可在下一个 major 把 `std/std/*` 收成 `std/*`，不需改导入语句（迁移由包自己决定）。

#### P20-07（P2，已延后）`use` 在具体 struct 接收者上去虚拟化

- **目标**：OO 做热路径数据结构不再固定付一次 vtable 间接调用。
- **做法**：当接收者静态类型是**具体 struct** 且该 struct 有对应 impl 时，直接发 `<Struct>_<Trait>_<method>(&recv, …)`；接收者是 trait/iface 值时仍走 `->vt`。CT 无继承、vptr 由编译器管理，故该替换不改变语义。
- **验收**：
  - 探针 `p20_devirt`：反查生成的 C，具体接收者是直接调用；iface 接收者仍是 `vt->`；
  - `std::vec` 现有基准在 `-O2` 下与手写直接调用同量级；
  - **golden 预告**：所有具体 struct 的 `use` 调用生成物都会变化，必须单独一次提交重生成，不与其它段混在一起。
- **本轮状态**：**延后**（P2 候选）；不在 `v0.20.0` 交付，目标与 golden 重生成约束保留。

#### P20-08（P2）诊断与文档收口

- **A1 文案**：`.m.ct` 前导区错误补一句 `put the C implementation in <base>.shim.h`（与 SH-58 的建议一致），**不放开** `#ct-raw`。
- **C8 文案**：`requires` 报 `unsupported requires` 时补 `use dep = pkg@range for package dependencies`。
- **A3 文档**：package-guide 明确 `.h.ct` **可以**导出函数；std 不用它只是风格选择。
- **recipe 文档**：写明配方是「单次调用」，需要转型 / 多语句时放 shim；给出三个正例。
- **验收**：三条文案各有一个负例断言；package-guide 中「.h.ct 只能放类型」的表述被纠正（若有）。

---

### 3. 明确不进入 Phase 20 的项

| 项 | 为什么不做 | 损失 |
| --- | --- | --- |
| 放开 `.m.ct` 的 `#ct-raw` | SH-58 已判定为有意边界：映射单元保持声明式，C 实现集中在 shim，审计与 `-I` 语义都依赖这条分界。放开会让同一文件既声明配方又藏实现 | 每个映射模块仍是「`.m.ct` + `.shim.h`」两文件；用文案与文档抵消 |
| `.h.ct` 支持 `pub fn` | 不是限制，探针已通过 | 无 |
| 修 `-I <outdir>` | 已在 `915c12c` 修复 | 无；只加回归探针 |
| 放宽 recipe 为任意 C 表达式 | 与上一条同源：会把「零成本静态映射」变成不可审计的 C 片段 | 仍需 shim 承载转型/多语句；文档写清 |
| 跨包 re-export | 限定调用已能组合；re-export 会制造第二套可见性规则 | 用户要多写 `a::ALen::` 前缀 |
| `ct test` 子命令 | 包测试目前由各仓 CI 承担，不是编译器阻挡 | 无 |
| 泛型 / 容器重写 | 属 Phase 22+，且 std 已用具体类型落地 | 无 |

---

### 4. 优先级、依赖与并行

| 任务 | 优先级 | 依赖 | 可并行 |
| --- | --- | --- | --- |
| P20-01 限定调用 | P0 | 无 | 与 02/03/04 并行（都在前端/发射器） |
| P20-02 late import | P0 | 无 | 同上 |
| P20-03 映射 arity | P0 | 无 | 同上 |
| P20-04 requires 硬失败 | P0 | 无 | 同上 |
| P20-05 索引历史 | P1（仅 ct-pkg 侧生成器移出） | **P20-04**（失败语义先定） | 本轮不做生成器；ct 侧 `pkg_index_lookup` 仍欠 |
| P20-06 包命名空间 | P1 | 无（但是解析器改动，需单独窗口） | 与 01/03 不同文件可并行 |
| P20-07 去虚拟化 | P2（延后） | 无 | 本轮不做；重启时**单独重生成 golden** |
| P20-08 文案与文档 | P2 | 01/04 的文案定稿 | 最后统一 |

**关键串行点**：01/03/06 共用 parser / emitter 文件，需按提交次序合并；P20-04 → P20-05 与 P20-07 的 golden 重生成
随 05/07 移出本轮一并撤销，不再约束本轮收口。

---

### 5. 里程碑

| 里程碑 | 内容 | 判据 |
| --- | --- | --- |
| M20-A | P0 语义闭合 | 01–04 的探针全绿；全仓语料 + ct-pkg 七包零新增失败；除新增诊断外无生成物变化 |
| M20-B | 生态可用 | **06 完成**：新布局与旧布局都能解析；跨根重名报错（**05 只移出 ct-pkg 侧生成器、ct 侧 `pkg_index_lookup` 仍欠，不再作为判据**） |
| M20-C | 收口 | **08 文案与文档落地**；11 道硬门禁全绿（**07 已延后，去虚拟化与 golden 重生成不再作为判据**） |
| M20-D | 发布 | 11 道硬门禁 + CI + nightly 全绿；`CTC_VERSION` bump `0.20.0`；带上 `915c12c` 并写入版本记录 |

---

### 6. 风险

| # | 风险 | 处置 |
| --- | --- | --- |
| R1 | 限定调用引入新语法，可能与 `Trait::method` 的现有解析冲突 | 只在「`::` 链后跟 `(`，且第一段不是变量/类型」时识别；先做探针再落语法 |
| R2 | 包命名空间解析出现双路径回退，可能重新引入遮蔽 | 双命中一律报错；回退只用于兼容，不用于选择 |
| R3 | 索引格式变更破坏旧 `ct` | 新字段追加在行尾，旧解析器按五字段读取；先发索引再发编译器 |
| R4 | 去虚拟化改变生成物，大面积 golden diff | 单独提交、单独审查；只允许调用形态变化，运行结果不变 |
| R5 | `requires` 改硬失败让现有用户装不上包 | `--force` 逃生门 + 版本记录写明；先对 ct-pkg 七个包跑一遍 |
| R6 | 跨根重名检测误报 | 不做同包豁免（评审决议）：重复 `-I`（根字符串相同）与导入方目录优先仍豁免，其余两个 `-I` 根同时命中一律报错 |

---

### 7. 决策登记

| # | 问题 | 建议值 | 状态 |
| --- | --- | --- | --- |
| D20-1 | 冲突消解用限定调用还是 map 优先级 | **限定调用** `Trait::method(recv, …)`；优先级会造成静默遮蔽 | 已确认（P20-01 已落地） |
| D20-2 | 是否做 re-export | **不做** | 已确认 |
| D20-3 | `.m.ct` 是否放开 `#ct-raw` | **不放开**，只改文案 | 已确认 |
| D20-4 | `requires` 不满足 | **硬失败 + `--force`** | 已确认（P20-04 已落地） |
| D20-5 | 索引是否保留全版本 | **保留**，行尾追加 `requires` 字段 | 仅 ct-pkg 侧生成器移出；ct 侧 `pkg_index_lookup` 仍欠 |
| D20-6 | 包命名空间键名 | `namespace = <seg>`（可选，默认无） | 已确认（P20-06 已落地） |
| D20-7 | 跨根同名单元 | **报错**，不静默先到先得 | 已确认（P20-06 已落地） |
| D20-8 | 去虚拟化范围 | 仅具体 struct 接收者；iface 不动 | 延后，随 P20-07 |
| D20-9 | 去虚拟化的 golden churn | 接受，单独提交重生成 | 延后，随 P20-07 |
| D20-10 | 版本 | Phase 20 ↔ `v0.20.x`，收口 `v0.20.0`，必须含 `915c12c` | 已确认（`v0.20.0` 已收口） |

---

## English

### Summary

**Status: done** (2026-11-07). **Phase 20 ↔ `v0.20.x`, closed at `v0.20.0`.** P20-01 / 02 / 03 / 04 /
06 / 08 landed; for P20-05 only the **ct-pkg-side index generator** was moved out of this round (the
ct-side `pkg_index_lookup` is still owed in this repo), and P20-07 was deferred — so neither is an exit
criterion. The theme is package support: any place where a package author is forced into a second-class
design by the compiler or the toolchain. A restriction counts only when it forces the package's *design*
to change for reasons unrelated to its domain.

### Verified findings

- **Real and blocking**: type-host method collisions on a shared receiver type (`char *`) with no
  qualified-call escape hatch (`Emitter.h.ct:2767`, probe reproduces); late `import` silently dropped
  (SH-57); map-method arity unchecked (SH-56); `requires` mismatch only warns (`Pkg.h.ct:1562`); the
  package index records only the highest tag (`ct-pkg/index/tools/refresh-index.sh`).
- **Real but structural**: package-scoped imports are faked with a directory prefix, so `std`, `zlib`,
  `sqlite` and `clib` all carry a doubled path level; duplicate unit names across `-I` roots shadow
  silently (`Module.h.ct:272-276`).
- **Not real**: `.h.ct` can export functions (probe compiles and runs); `-I <outdir>` is already emitted
  (`915c12c`); `#ct-raw` in `.m.ct` is a deliberate boundary (SH-58), not an accident.

### Work items

| ID | Priority | Item | Round status |
| --- | --- | --- | --- |
| P20-01 | P0 | Trait-qualified call `Trait::method(recv, …)`; ambiguity hint prints both spellings | landed |
| P20-02 | P0 | Reject `import` outside the prologue | landed |
| P20-03 | P0 | Check map-method arity at the call site | landed |
| P20-04 | P0 | Make an unsatisfied `requires` a hard failure (`--force` overrides) | landed |
| P20-05 | P1 | Keep all tags in the index; resolve by range + `requires` | **ct-pkg-side generator moved out** (ct-side `pkg_index_lookup` still owed) |
| P20-06 | P1 | Optional `namespace =` in `ct.pkg`; reject duplicate unit names across roots | landed |
| P20-07 | P2 | Devirtualize `use` calls on concrete struct receivers (golden regeneration expected) | **deferred** |
| P20-08 | P2 | Diagnostics and docs: shim path in the `.m.ct` error, `dep` hint, `.h.ct` clarification | landed |

Out of scope: lifting the `.m.ct` raw-C restriction, re-export, a `ct test` command, generics, and any
Phase 21 closure work.

**Release prerequisite:** `v0.20.0` must ship `915c12c` (string-literal receivers); `ct-pkg/std` already
declares `requires = ct >= 0.20.0` because of it.

**Exit:** 11 hard gates plus the new probes green; all seven ct-pkg packages build with zero new failures;
old layouts still resolve (the new `namespace =` layout coexists); `CTC_VERSION` bumped to `0.20.0`.
The ct-pkg-side P20-05 index generator and P20-07 are explicitly not part of this exit; the ct-side
`pkg_index_lookup` range resolution remains owed in this repo.
