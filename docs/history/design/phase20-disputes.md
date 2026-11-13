# Phase 20 争议清单（评审用）

> 中文 · [English](#english)
>
> **用途**：把 Phase 20 立项时的十项候选逐条摊开，供评审逐条裁决。本文不复述
> [phase20.md](phase20.md) 的任务设计，只记录**原始主张、核实结论、证据、处置、待裁决点**。
> **状态：已评审**（2026-11-07）。裁决以 [phase20.md](phase20.md) 的实际落地为准：
> A2 → P20-01、B6 → P20-02、B5 → P20-03、C8 → P20-04、C10 / N1 → P20-06 已落地；
> C9（原 P20-05）只移出 ct-pkg 侧的索引生成器（ct 侧 `pkg_index_lookup` 仍欠）、B7（原 P20-07）延后。§9 的勾选栏保留为评审时的登记表，不再单独维护。

裁决口径沿用 [phase20.md](phase20.md) §0：

> **包作者为了做对一件事，被迫改变设计——多一个文件、多一个编译开关、手工补 `-I`、
> 改方法名、避开 OO、接受静默错误——且这个改变与包本身的领域无关。**

「缺功能」不等于「掣肘」。只缺能力、但不改变包的设计的，不进本相。

---

## 1. 总览

| # | 主张摘要 | 判定 | 处置 |
| --- | --- | --- | --- |
| A1 | `.m.ct` 前导区禁 `#ct-raw`，std 被迫两文件 | 现象成立，定位需修正 | **争议项二**，暂不进 |
| A2 | 同一宿主同名方法直接歧义，两包无法共存 | **部分成立** | P0（P20-01） |
| A3 | `.h.ct` 不能出口 `pub fn` | **不成立** | 不进，改文档 |
| B4 | shim 的 `cc` 行缺 `-I <outdir>` | **不成立**（已修） | 不进，加回归探针 |
| B5 | 映射方法不校验实参个数（SH-56） | 成立 | P0（P20-03） |
| B6 | 声明后的 `import` 静默丢弃（SH-57） | 成立 | P0（P20-02） |
| B7 | `use` 结构体方法永远走 vtable | 成立（「永远」措辞需修正） | P2（P20-07） |
| C8 | `requires` 与 `dep` 两套语义，写错无提示 | **部分成立** | P0（P20-04）+ P2 文案 |
| C9 | 索引只收录最高 tag | 成立 | P1（P20-05） |
| C10 | 包根被迫等于命名空间根，std 多套一层 | **部分成立**（根源不是 `-I`） | P1（P20-06） |
| N1 | 跨 `-I` 根同名单元静默遮蔽（补漏） | 成立 | P1（并入 P20-06） |
| N3 | `v0.20.0` 必须含 `915c12c`，否则 std 装不上 | 事实约束 | 发布前置，见 §6 |

**必须单独裁决的三个分歧项**：§3（A3）、§4（A1）、§5（A2 的解法）。
**事实约束单列**：§6（N3）。

---

## 2. 逐条裁决

### A1 · `.m.ct` 前导区只允许 `#include` / `#define`

**原始主张**（保留原话）：

> `.m.ct` 前导区只允许 `#include` / `#define`，`#ct-raw` 硬报错。
> 后果是 std 的映射模块压不成单文件，必须拆成 `.m.ct` + `.shim.h` 两个文件。
> 这是「语法限制塑造了包的目录结构」，典型掣肘。

**判定**：现象成立；「前导区」这个定位需要修正——限制覆盖**整个 `.m.ct` 单元**，不只是前导区。

**证据**：

- [Parser.h.ct](../../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L789-L796) 的循环跑到 `T_EOF`，
  每遇到 `T_PP` 就检查 `unit_is_map`；白名单只有 `#include` / `#define`，其余直接
  `a .m.ct unit allows only #include and #define in its prologue`。因此 `.m.ct` 正文里写
  `#ct-raw` 同样被拒，报文说「prologue」但判定不限于前导区。
- 最小复现（v0.19.1）：`.m.ct` 里放 `#ct-raw static int helper(...) #ct-endraw`，构建即得到上述报文。
- 现状：`.m.ct` 的 C 实现只能放在同基名 `<Trait>.shim.h`（`static inline`），由 recipe 以裸 C 名调用。

**处置**：**暂不进**。只改错误文案，补一句「put the C implementation in `<base>.shim.h`」（P20-08）。
但是否维持这条限制，交由 §4 重新裁决，不引用 SH-58 的既有结论当理由。

**待裁决点**：见 §4 的选项 A / B / C。

---

### A2 · 同名方法在同一类型宿主上直接歧义

**原始主张**（保留原话）：

> 同名方法在同一个类型宿主上直接 `ambiguous type-host map`，且语言没有 re-export。
> 后果是**两个包无法在同一个宿主类型上共存**——A 包给 `char *` 加了 `len`，B 包就不能再加。
> 这直接封死了「包之间自由组合」这条路，我认为是 Phase 20 里最该优先的一条。

**判定**：**部分成立**。「两个包无法共存」说得过重：两个包可以同时构建、同时被导入；
报错发生在**调用点**，只在同名方法的调用无法唯一解析时触发。真正被封死的是
「同一个拼写在两个包里有不同实现」这件事，不是包的共存。

**证据**：

- 探针：`a/A.m.ct` 与 `b/B.m.ct` 各写 `map trait ... for type char * { len() -> ...; }`，
  两个包一起构建**不报错**；消费方写 `s.len()` 才得到
  `ambiguous type-host map for method 'len' on type 'char *': './a/A.m.ct' and './b/B.m.ct'`。
- [Emitter.h.ct](../../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2765-L2771)：歧义在方法调用解析时产生，
  报文已经带两个候选的路径。
- 全仓无 re-export 机制（0 处）。

**处置**：**进 P0**（P20-01）。解法与体验见 §5。

**待裁决点**：见 §5。

---

### A3 · `.h.ct` 不能出口 `pub fn`

**原始主张**（保留原话）：

> `.h.ct` 不能出口 `pub fn`（std 的既定政策）。这条是团队自己定的规矩不是编译器限制，
> 但要确认：是不是编译器逼的？如果是，就该修编译器而不是让包永远走 shim。

**判定**：**不成立**（作为编译器限制）。编译器允许 `.h.ct` 定义并导出函数。

**证据**：探针（v0.19.1）：

```ct
/* p/foo.h.ct */
namespace p;
pub int add(int a, int b) { return a + b; }
```

`ct build` 成功，生成的 `foo.h` 含 `int p_add(int, int);`，`foo.c` 含定义；
消费方 `import p::foo;` 后调用 `p::add(1, 2)`，运行退出码 0。

**处置**：**不进**。修正文档：`.h.ct` **可以**导出函数，std 不用它是风格选择。
但「std 的 shim 是否多余」另有原因，见 §3。

**待裁决点**：std 的形态选择要不要重估（见 §3 结论：不建议在本相重估）。

---

### B4 · shim 的 `cc` 行缺 `-I <outdir>`

**原始主张**（保留原话）：

> shim 的 include 路径：driver 的 `cc` 行缺 `-I <outdir>`（`Module.h.ct:1098` 与打印路径 `:1063` 都有）。
> 包一旦在 shim 里 include 生成的类型头就编不过，得让用户手工补 `-I`。
> 这是两行的事，但它决定了「shim 能不能用类型定义」。

**判定**：**不成立（已修）**。主张在提出时成立，但工作树里已经补上。

**证据**：

- [Module.h.ct](../../../selfhost/ct-ast/frontend/module/Module.h.ct#L1055-L1098) 的 `cc` 行现在包含
  `-I <outdir>`，注释写明它是 shim 包含生成类型头的根；打印给用户的命令也一致。
- 该修复来自提交 `915c12c`（尚未打 tag，见 §6）。

**处置**：**不进**。加一个回归探针：shim 里 `#include "<Type>.h"` 能在不改命令行的前提下编译。

**待裁决点**：无（事实已闭合）。

---

### B5 · 映射方法不校验实参个数（SH-56）

**原始主张**（保留原话）：

> 映射方法不校验实参个数（SH-56，`"abc".len(1)` 静默丢弃多余参数）。
> 包作者写错方法签名，编译器不报错，错误延迟到用户运行时才炸。

**判定**：成立。补充：用户举的 `"abc".len(1)` 需要字符串字面量接收者，这属于 `915c12c`；
在 `v0.19.1` 上的等价复现是 `char *s = "abc"; s.len(1);`。

**证据**：

- [Expr.h.ct](../../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1562-L1586)：arity 检查只在
  `!traits[t].is_static` 时执行；`.m.ct` 的静态 trait 被显式豁免。
- `issues/selfhost/sh56-map-method-arity-unchecked.md` 记录复现，状态「待修」。

**处置**：**进 P0**（P20-03）：静态映射按 trait 声明在调用点校验实参个数；多写、少写都产生 arity 诊断——`ct build` / `ct compile` 下按 `warning:` 打印、退出 0（多余实参被配方丢弃），`ct check` 下同一记录升为 `error:` 并退出 1。

**待裁决点**：无。

---

### B6 · 声明之后的 `import` 整条静默丢弃（SH-57）

**原始主张**（保留原话）：

> 声明之后的 `import` 整条静默丢弃（SH-57）。包内文件顺序一错就静默少依赖，产物丢命名空间前缀。

**判定**：成立。

**证据**：

- [Module.h.ct](../../../selfhost/ct-ast/frontend/module/Module.h.ct#L243-L266) 的 `scan_imports` 遇到首个
  非 `T_PP` / 非 `import` token 就 `break`；其后的 `import` 不会被记入依赖，于是依赖不加载、
  限定名无法解析。解析主循环虽然还会跳过 `import` 语句，但依赖已经缺了。
- `issues/selfhost/sh57-import-after-decl-silently-dropped.md` 记录两个最小复现，状态「待修」。

**处置**：**进 P0**（P20-02）：正文遇到 `import` 直接报错，文案给出「move the import to the top」。

**待裁决点**：无。唯一的选择是要不要兼容「import 混杂在文件中部」的既有代码——建议不兼容，
因为当前行为本来就是错的（静默丢依赖）。

---

### B7 · `use` 结构体的方法永远无法内联

**原始主张**（保留原话）：

> `use` 结构体的方法永远无法内联（std 实测：`-O2` 下直接调用可折叠为 0，走 vtable 固定约 1ns）。
> 包如果拿 OO 做热路径数据结构，性能白白损失。这条能不能靠「静态类型已知时去虚拟化」解决——
> 编译器自己的 emit 里已经有 `{vptr, self}` 的分支，值得评估。

**判定**：成立（现象）；「永远无法内联」措辞需修正——不是 CT 显式禁止内联，而是生成的调用
经过 vtable 字段，C 编译器无法在 `-O2` 下把它折叠掉。接收者静态类型是具体 struct 时，
CT 本可以直接发直接调用，但没有这样做。

**证据**：

- [Emitter.h.ct](../../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2789-L2806)：`use` 派发固定发
  `->__<trait>_vptr->method(...)` 或 `.__<trait>_vptr->method(&...)`，不区分接收者是不是具体 struct。
- std 的实测数据（直接调用 vs vtable）与用户观测一致。

**处置**：**进 P2**（P20-07）：接收者静态类型是具体 struct 且有对应 impl 时，发
`<Struct>_<Trait>_<method>(&recv, …)`；iface / trait 值仍走 vtable。

**待裁决点**：

- 去虚拟化会改变所有具体 struct 的 `use` 调用生成物，golden 大面积重生成是否接受（建议接受，单独提交）；
- 是否只做「具体 struct 接收者」这一档，不动跨单元/接口值（建议只做这一档）。

---

### C8 · `requires` 与 `dep` 两套语义

**原始主张**（保留原话）：

> `requires` 只比对编译器版本，包依赖要走 `dep`——两套语义容易混，包作者写错不会得到提示。

**判定**：**部分成立**。「写错不会得到提示」不准确：写坏的 `requires` 会报
`has an unsupported requires`；真正的缺口是**不满足只告警**。

**证据**：

- [Pkg.h.ct](../../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1561-L1583)：函数头注释写明
  「a mismatch is a warning, never a blocker」，不满足时只打印
  `ctc: package '%s' requires '%s', but this is v%s` 并 `return 0`。
- [package-guide.md](../../package-guide.md) 同样写明「不满足只告警，不拒绝安装」。
- `requires` 的语法只接受 `ct <比较符> <版本>`，不承载包依赖；包依赖是 `dep`。

**处置**：**进 P0**（P20-04）：不满足改为硬失败，新增 `--force` 降级为警告；
文案补一句「use dep = pkg@range for package dependencies」（P20-08）。

**待裁决点**：硬失败会让「装了但跑不起来」提前暴露，但也会挡住「先装后升级编译器」的用户；
`--force` 是否足够作为逃生门，请评审确认。

---

### C9 · 索引只收录最高 tag

**原始主张**（保留原话）：

> 索引只收录每个仓库最高 tag，旧编译器拿不到兼容旧版。

**判定**：成立。

**证据**：

- `ct-pkg/index/tools/refresh-index.sh` 用 `git ls-remote --tags ... | sort -V | tail -1`，
  每个仓库只写一行；`ct-pkg/index/index` 即此形态。

**处置**：**进 P1**（P20-05）：每个 `v*` tag 写一行（行尾追加 `requires` 字段）；
解析器在满足请求区间与 `requires` 的候选里取最高版本；旧格式仍可解析。

**待裁决点**：索引格式变更的兼容策略——建议新字段追加在行尾，旧 `ct` 按前五字段读取；
先发索引、再发编译器。请评审确认是否接受「同一个包里同时存在多个可装版本」。

---

### C10 · `ct install` 打印 `-I vendor/<pkg>`，命名空间根被迫等于包根

**原始主张**（保留原话）：

> `ct install` 按包打印 `-I vendor/<pkg>`，要求每个包的命名空间根恰好是包根；
> std 为此多套了一层 `std/std/`。这是「包的目录结构为了迁就工具」的又一例。

**判定**：**部分成立**。`-I vendor/<pkg>` 本身没有错；真正的成因是**导入路径按目录解析**——
想写 `import std::str::String`，就必须存在 `std/std/str/String.m.ct`。所以多套一层的是
导入约定，不是 `-I` 的打印。

**证据**：

- [Pkg.h.ct](../../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1290-L1291)：`printf(" -I vendor/%s", lname[i])`。
- 目录事实：`ct-pkg/std/std/...`、`zlib/zlib/...`、`sqlite/sqlite/...`、`clib/clib/...` 都是加倍层；
  `net-posix/net/net.m.ct` 的 `namespace` 是 `net`（与包名不同，绕开了）；
  `png/Png.m.ct` 放在包根（与其余包不一致）。
- 跨根同名单元：`Module.h.ct` 的解析是「按根顺序先命中先用」，只在同一根内把 `.h.ct` / `.m.ct`
  同名视为歧义（N1）。

**处置**：**进 P1**（P20-06）：

1. `ct.pkg` 新增可选 `namespace = <seg>`；
2. 解析 `import <seg>::x` 时先试 `<root>/x`，回退旧路径 `<root>/<seg>/x`；
3. 同一 `<seg>` 被两个包声明、或跨根同名单元命中两个包 → 报错，不做静默先到先得。

**待裁决点**：

- 键名与语义：`namespace =` 是「该包拥有导入路径第一段」，不是重命名文件名；默认无，保持兼容。
- 是否强制要求新包声明 `namespace`（建议不强制，只对无声明者走旧路径）。
- 既有包（std/zlib/sqlite/clib）何时收层，由包自己在下一个 major 决定，编译器只提供能力。

---

## 3. 分歧项一：A3 `.h.ct` 能否出口 `pub fn`

**双方立场**

- 用户：不能，std 因此走 shim；如果是编译器逼的，应该修编译器。
- 本文：能。探针编译运行通过（§2 A3）。

**裁决要看的不只是「谁对」**

如果 `.h.ct` 确实能导出函数，那 std 的「`.h.ct` 不出口函数」政策就不是编译器限制，
而是一条**风格约定**。需要回答的是：这条约定该不该改？std 的形态要不要重估？

**核实到的额外事实（关键）**：即使 `.h.ct` 能导出 `pub` 函数，它导出的符号是**命名空间改写后的
C 名**（探针里是 `p_add`），而 `.m.ct` 的 recipe 是**逐字发射的 C 调用**，只接受
「callee / 绑定参数 / C 类型词 / 全大写宏 / 成员名」，不接受命名空间限定调用。
因此 recipe 想调用一个 CT 层的 `pub` 函数，只能写它改写后的 C 名——把命名空间改写规则
耦合进配方文本；shim 的 `static inline` 裸 C 名反而是稳定接口。

**结论（建议）**

1. **A3 判定维持「不成立」**：编译器没有禁止 `.h.ct` 导出函数。
2. **std 的形态选择不在 Phase 20 重估**：shim 的成因不是「`.h.ct` 不能导出函数」，
   而是「recipe 只能调用裸 C 符号，且实现要按消费方内联复制」。
   把 std 改成 `.h.ct` 导出函数，不会消掉 shim，只会把 shim 换个文件名。
3. **文档要改**：package-guide 明确 `.h.ct` 可以导出函数；把「不能」改成「std 当前不用」。
4. **留给评审的选项**：如果评审认为「recipe 支持限定调用」值得做，那是另一项任务
   （影响 recipe 语法与发射），不是 A3 的修复，也不建议挤进本相。

**损失评估**：不做任何改动，损失为零；std 维持现状即可。若强行重估 std 形态，
收益不明确、回归面大。

---

## 4. 分歧项二：A1 `.m.ct` 禁 `#ct-raw`

**双方立场**

- 用户：「有意」不等于「合理」；放开后 std 的映射模块能从两文件压回一文件。
- 本文此前引 SH-58，判为有意边界。本节按要求**重新判一次**，不把 SH-58 当论据。

**放开能拿到什么**

- 每个映射模块从「`.m.ct` + `.shim.h`」变成单文件；当前仓内/`ct-pkg` 的 shim 共 9 个
  （std 5、net 1、png 1、sqlite 1、zlib 1），文件数减半，且实现与配方在同一屏内。

**放开必须定义的三件事（这些是成本，不是立场）**

1. **发射语义**：shim 现在是 `static inline`，按消费方各复制一份；`#ct-raw` 文本若进 `.m.ct`，
   是「每个消费方都发射一份」（必须 `static`，否则多消费方重复定义），还是「只发射一次」？
   后者需要新的「单一定义单元」概念，编译器目前没有。
2. **可见性边界**：recipe 只允许单次调用；`#ct-raw` 里的 helper 一旦可见，配方能调用的
   表面变大，`map` 的「静态、可审计」承诺需要重新表述。
3. **模块契约**：`.m.ct` 现在可以整份被当作「声明 + 配方」审阅；放开后同一文件既有声明
   又有实现，`-I` / 审计 / 文档三处的心智模型都要改。

**三个选项**

| 选项 | 内容 | 收益 | 成本 | 建议 |
| --- | --- | --- | --- | --- |
| A | 维持现状，只改文案 | 零风险 | 仍两文件 | **本相采用** |
| B | 允许 `#ct-raw`，但只作为「实现段」，按 `static` 每消费方发射 | 单文件 | 需定义发射语义 + 审计边界；隐式 `static` 规则易错 | 可延后评估 |
| C | 允许 `#ct-raw` 且只发射一次 | 单文件、无复制 | 需要「单一定义单元」，改动面最大 | 不建议 |

**结论（建议）**

- **本相不放开**，但理由从「有意边界」改为可复核的工程理由：**发射语义未定义**，
  不是「不许」。
- 若评审希望提升包作者体验，选 **B** 并将其列为独立 P2 任务（需要单独设计「实现段」的
  发射规则与 `static` 约定），不要顺手放开。
- 无论选哪个，P20-08 的文案改进都成立：错误报文要给出 `<base>.shim.h` 这条替代路径。

**待裁决点**：A / B / C 三选一。若选 B，需在 phase20.md 新增任务并定义验收。

---

## 5. 分歧项三：A2 的解法——限定调用是「绕开」还是「解决」

**先把体验如实描述**

- **没有冲突时**：行为不变，`s.len()` 照常解析到唯一候选。
- **有冲突时**：`s.len()` 报歧义，报文列出两个候选源文件；调用点必须写
  `a::ALen::len(s)` 或 `b::BLen::len(s)` 才能编译。
- **包之间的组合**：两个包可以同时被导入、同时构建；冲突只影响**同名方法的调用写法**，
  不影响类型、结构体、其他方法。也就是说，「共存」是成立的，「同名方法都想要默认拼写」
  是不成立的。
- **便利层**：不做 re-export，所以想给下游一个 `s.len()` 的默认体验，只能由其中一个包
  另外提供一个不同名的方法（或由应用层写包装）。这是**显式代价**，不是编译器偷偷选边。

**为什么选限定调用，而不是别的**

| 方案 | 结果 | 问题 |
| --- | --- | --- |
| map 优先级（后导入者赢/先导入者赢） | 调用点无需改 | **静默遮蔽**，同一份代码因导入顺序而语义不同 |
| re-export / `using` | 可恢复默认拼写 | 制造第二套可见性规则，冲突仍然要裁决，只是往后推 |
| 限定调用（本方案） | 冲突显式、可局部选择 | 每个冲突调用点都要写全限定名 |

**结论（建议）**

- 限定调用**解决了阻塞**（两个包都能用、都能被显式选中），但**没有解决组合体验**：
  它把「编译器替你选」变成「你必须选」。这是有意的取舍，因为另一条路是静默遮蔽。
- 因此对外表述要降调：**不要写成「两个包可以自由组合」**，应写成
  「两个包可以共存；同名方法必须限定调用」。
- 若评审认为体验不可接受，可另立「包级方法别名 / re-export」任务，但不建议与 P0 捆绑，
  否则 P0 会因为设计未定而拖延。

**待裁决点**：

1. 限定调用的语法用 `a::ALen::len(s)`（全路径）还是 `ALen::len(s)`（trait 名），
   还是两者都接受（建议两者都接受，全路径用于跨包同名 trait）。
2. 歧义报文的 hint 是否必须同时给出两条完整可复制的写法（建议是）。
3. 是否在 `ct check` 中对「可限定但未限定」给出提示（建议不做，噪音大）。

---

## 6. 发布前置：N3 `v0.20.0` 必须包含 `915c12c`

这条不是设计取舍，是事实约束，单列给发布负责人。

**事实链**

1. `ct-pkg/std/ct.pkg` 写明 `requires = ct >= 0.20.0`。
2. 理由是该包示例使用字符串字面量接收者（`"hi".len()`），该能力由提交 `915c12c` 引入。
3. `915c12c` 当前在**工作树**里，尚未被打成 tag；当前最新 tag 是 `v0.19.1`。
4. 如果 `v0.20.0` 从缺少 `915c12c` 的分支切出，std 的 `requires` 将无法满足；
   配合 P20-04 的硬失败，std 会**直接装不上**。

**处置**

- 发布检查表新增一项：`v0.20.0` 的 tag 必须包含 `915c12c`，并写入版本记录。
- 发布前用 `ct install std` 做一次端到端验证：在 `v0.19.1` 上应失败（符合 `requires`），
  在 `v0.20.0` 上应成功。
- 若评审决定 P20-04（硬失败）延后，N3 仍然成立，只是失败形态从「装不上」变成「装上后运行时报错」。

**待裁决点**：无。需要的是发布流程确认，不是设计选择。

---

## 7. 补漏项（不在用户清单内）

### N1 · 跨 `-I` 根的重名单元静默遮蔽

- **现象**：两个 `-I` 根各有一个 `Uart.h.ct`，导入时按根顺序先命中先用，无任何提示；
  只有**同一根内**的 `.h.ct` / `.m.ct` 同名才被判为歧义。
- **证据**：[Module.h.ct](../../../selfhost/ct-ast/frontend/module/Module.h.ct#L271-L276) 的两遍解析与注释。
- **处置**：并入 P20-06（跨根同名单元命中两个包 → 报错）。

### N2 · `requires` 不满足只告警

- 即 C8 的实质，不重复计为独立项。

---

## 8. 明确被排除的项

| 项 | 排除理由 | 不做会损失什么 |
| --- | --- | --- |
| 放开 `.m.ct` 的 `#ct-raw` | 见 §4：发射语义未定义，不是「不许」 | 每个映射模块仍是两文件；用文案与文档抵消 |
| `.h.ct` 支持 `pub fn` | 本就支持（探针） | 无 |
| 修 `-I <outdir>` | 已在 `915c12c` 修复 | 无；加回归探针 |
| 放宽 recipe 为任意 C 表达式 | 与 `#ct-raw` 同源：会把静态映射变成不可审计的 C 片段 | 转型 / 多语句仍放 shim；文档写清「单次调用」 |
| 跨包 re-export | 限定调用已能组合；re-export 会制造第二套可见性规则 | 冲突调用点要写全限定名 |
| `ct test` 子命令 | 包测试由各仓 CI 承担，不是编译器阻挡 | 无 |
| 泛型 / 容器重写 | 超出「包支持」主题 | 无 |

---

## 9. 裁决登记表

评审逐条填写；「同意」指同意本文判定与处置，「反对」请在备注写替代方案。

| 条目 | 同意 | 反对 | 备注 / 替代方案 |
| --- | --- | --- | --- |
| A1 判定（现象成立，暂不放开） | ☐ | ☐ | |
| A1 选项（A / B / C，见 §4） | ☐ A ☐ B ☐ C | | |
| A2 判定（部分成立） | ☐ | ☐ | |
| A2 解法（限定调用，不做 re-export） | ☐ | ☐ | |
| A2 语法（全路径 / trait 名 / 两者） | ☐ | ☐ | |
| A3 判定（不成立，改文档） | ☐ | ☐ | |
| A3 std 形态不重估 | ☐ | ☐ | |
| B4 判定（已修，加探针） | ☐ | ☐ | |
| B5 → P0 | ☐ | ☐ | |
| B6 → P0 | ☐ | ☐ | |
| B7 → P2 + golden 单独提交 | ☐ | ☐ | |
| C8 → P0 + `--force` | ☐ | ☐ | |
| C9 → P1（索引保留全版本） | ☐ | ☐ | |
| C10 → P1（`namespace =` + 双路径回退） | ☐ | ☐ | |
| N1 → P1（并入 P20-06） | ☐ | ☐ | |
| N3 发布前置（`v0.20.0` 含 `915c12c`） | ☐ | ☐ | |

---

## English

### Verdicts

| # | Claim | Verdict | Action |
| --- | --- | --- | --- |
| A1 | `.m.ct` rejects `#ct-raw` | true, but the check covers the whole unit, not just the prologue | dispute §4; keep for now |
| A2 | same-named type-host methods are ambiguous | **partly true** (packages coexist; only the call is ambiguous) | P0 |
| A3 | `.h.ct` cannot export `pub` functions | **false** (probe compiles and runs) | docs only |
| B4 | the `cc` line lacks `-I <outdir>` | **false** (fixed in `915c12c`) | regression probe |
| B5 | map-method arity unchecked | true (SH-56) | P0 |
| B6 | late `import` silently dropped | true (SH-57) | P0 |
| B7 | `use` calls always go through the vtable | true (wording "never inlined" is imprecise) | P2 |
| C8 | `requires` vs `dep` confusion | **partly true** (unsatisfied `requires` only warns) | P0 + docs |
| C9 | the index keeps only the highest tag | true | P1 |
| C10 | the namespace root is forced to be the package root | **partly true** (the cause is directory-based import resolution, not `-I`) | P1 |

### Three disputes

1. **A3**: the compiler does allow `.h.ct` to export functions. std's shims are not caused by that
   restriction: a recipe is emitted as a raw C call and can only name unmangled C symbols, while CT
   functions are namespace-mangled. Keeping std as is costs nothing.
2. **A1**: "deliberate" is not an argument. Lifting the ban would collapse two files into one, but it
   requires defining emission semantics (one copy per consumer vs one copy overall) and the audit
   boundary. Recommendation: keep it in this phase; if wanted, option B as a separate P2 item.
3. **A2**: qualified calls solve the blocker, not the ergonomics. Packages coexist; a colliding
   method must be called as `a::ALen::len(s)`. That is explicit by design; the alternative is silent
   shadowing.

**Release prerequisite (N3)**: `v0.20.0` must include `915c12c`, because `ct-pkg/std` already
declares `requires = ct >= 0.20.0` and its examples need string-literal receivers.
