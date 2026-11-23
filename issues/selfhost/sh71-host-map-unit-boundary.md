# SH-71 · 类型宿主映射的单元限制：`.h.ct` 不许放 `map`、`.m.ct` 看不见接口

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 单元模型 / 静态映射） |
| 严重度 | Info（有意的语言边界，规约已载；不改编译器） |
| 锚点 | `v0.44.1`（`13db6cad`，2026-11-15 复核） |
| 文件 | [MapBuild.h.ct:638](../../selfhost/ct-ast/frontend/parse/MapBuild.h.ct#L638)、[Module.h.ct:412](../../selfhost/ct-ast/frontend/module/Module.h.ct#L412)、[Module.h.ct:557-559](../../selfhost/ct-ast/frontend/module/Module.h.ct#L557-L559) |
| 状态 | verified |
| 处置证据 | **已解决**（A-1 于 `fb55985c` 落地：允许 `.m.ct` import `.h.ct`）；A-2 **拒绝**（维持原判） |

## 现象

ct-http 想让 `"https://…".method("GET")` 这一跳作为整条链的起手，于是需要同时满足：

1. `map trait Entry for type char *`（类型宿主）——只能写在 `.m.ct`；
2. `Entry.method` 的返回类型是 `.h.ct` 发布的接口值 `HttpRequest`。

两条约束没有交集：

```c
/* 写进 .h.ct */
map trait Entry for type char * { method(s, verb) -> http_entry_new(s, verb); }
```

```text
src/http/http.h.ct:35:21: error: a type host is only allowed in a .m.ct unit
$ echo $?
1
```

```c
/* 写进 .m.ct，并 import 接口单元 */
#include "entry.shim.h"
import http::http;
namespace api;
pub trait Entry { HttpRequest method(char *verb); }
map trait Entry for type char * { method(s, verb) -> http_entry_new(s, verb); }
```

```text
$ ct build src/main.ct -o out
ctc: cannot resolve import 'http/http'
$ echo $?
1
$ ct build src/main.ct -o out -I src
src/api/api.m.ct:2:1: error: a .m.ct unit can only import another .m.ct unit
$ echo $?
1
```

不写 import、只保留 `HttpRequest` 拼写时，映射单元能过，消费单元在调用点失败：

```text
src/main.ct:6:66: error: cannot box this expression
$ echo $?
1
```

排除「是否存在同时满足的位置」：

```text
$ ct build src/main.ct -o out          # 接口 trait 写进 .m.ct 并在消费单元作类型
src/main.ct:5:5: error: a static trait has no interface value
$ echo $?
1

$ ct build src/main.ct -o out          # 接口写进普通 .ct 并 import
ctc: only a .h.ct unit can be imported: rename 'plain/plain.ct' to 'plain/plain.h.ct'
$ echo $?
1
```

## 定性：有意的语言边界

规约逐条对得上，不是实现遗漏：

- `.m.ct` 只允许 `namespace` / `import` / prologue / `pub trait` / `pub type` / `map` / `_Static_assert`，
  且「映射单元只能 import 另一个映射单元」
  （[language-spec.md:525-530](../../docs/language-spec.md#410-mapphase-11-新增--sh-20-扩展仅-ct-ast)、[:538](../../docs/language-spec.md#410-mapphase-11-新增--sh-20-扩展仅-ct-ast)）。
- `.m.ct` 的 `pub trait` 自动是静态 trait：「不能 `impl`、不能进 `use`、不能作类型、不能装箱」
  （[:548-549](../../docs/language-spec.md#410-mapphase-11-新增--sh-20-扩展仅-ct-ast)）。
- `map trait … for type …` 只能出现在 `.m.ct`（[:662](../../docs/language-spec.md#410-mapphase-11-新增--sh-20-扩展仅-ct-ast)）；shim 只为 `.m.ct`
  探测，`.h.ct` 旁的 `*.shim.h` 被忽略（[:600](../../docs/language-spec.md#410-mapphase-11-新增--sh-20-扩展仅-ct-ast)）。
- §4.10.1 已把三段逐段标成「第 1 段成立 / 第 2 段不成立」
  （[:643-646](../../docs/language-spec.md#4101-链式构建器范式权威定义与两档路径)）。

**文档失真一处**：规约 §4.10.1 引用的 `.m.ct` 导入报错是
`a .m.ct unit can only import another .m.ct unit`，但只有在给了 `-I` 使 `.h.ct` 能被解析到时才会走到
这条诊断；否则先报 `cannot resolve import`。原因是 `.m.ct` 的传递导入不继承入口目录，只按自身目录与
`-I` 搜索。文档把「解析失败」与「单元种类不符」混成了同一条。

## 影响面与绕法

- 影响的是「字符串起手 → 接口对象」这一形态；**不影响**字符串起手本身。
- 可用形态 A（规约已推荐）：静态宿主链，例如
  [examples/47_chain_factory](../../examples/47_chain_factory/src/main.ct)——字符串起手、可一行链、
  无 vtable / 无装箱；代价是对象在映射单元里是 struct，不是 trait 定义的接口类型。
- 可用形态 B：`.h.ct` 自由函数工厂 `HttpRequest http_entry(char *, char *)`，保留接口类型；
  代价是起手不再是字符串。
- 两条形态都不需要改编译器。

## 候选解的代价

| 候选 | 做法 | 代价 |
| --- | --- | --- |
| A-1 | 允许 `.m.ct` import `.h.ct` | 跨单元解析接口类型与 `impl` / `use` 可见性；构建图、缓存键、`.m.ct` 加载顺序、依赖遍历都要改；现有「映射单元之间」诊断需重定义；单元矩阵与文档同步改写。**数百行，高风险** |
| A-2 | 允许 `.h.ct` 承载类型宿主 | `.h.ct` 目前没有 recipe 展开路径；头/实现分离、shim 的 `-I`、`--emit-map` 宿主条目、消费单元生成顺序都要扩；会破坏 `.h.ct` 的「只发布接口」定位。**明确拒绝** |
| A-3 | 换一个同时满足两约束的位置 | 不存在：`.m.ct` 的 trait 是静态 trait，普通 `.ct` 不可导入，`.h.ct` 不许放映射。**维持结论** |

## 建议

- 0.1.0 **不改编译器**；ct-http 按形态 A（[examples/47](../../examples/47_chain_factory/src/main.ct)）或
  形态 B 落地，并在 API 文档写清「字符串起手」与「接口对象」二选一。
- A-2 拒绝：与 `.h.ct` 的单元职责冲突，收益小于维护成本。
- A-1 **已实施**（见下节），原「延后」结论作废；A-2 维持拒绝。
- 修文档：把 §4.10.1 的两条报错拆开写（无 `-I` → `cannot resolve import`；有 `-I` → 单元种类错误）。

## A-1 实施结果（`fb55985c`）

**放开的边**：`.m.ct` import `.h.ct`。被 import 的 header 单元的 `pub` struct / typedef /
enum / union、`pub` trait（裸名）、`pub` 全局与类型别名，和任何依赖一样进入映射单元的名字表；
映射单元的 trait 签名因此可以命名 header 发布的接口类型。

**仍禁止的边**：

- 普通 `.ct` 不能被 import：`resolve_import` 只认 `.h.ct` / `.m.ct`，报
  `only a .h.ct unit can be imported`（判据未动）。
- `.h.ct` import `.m.ct` 在 A-1 之前就合法，本轮保持不变（`test/modules/map_unit_cross` 依赖它）。
- 闭环 `m -> h -> m` 走既有 `circular import` 诊断，退出码 1，不崩。

**产出**：`.h.ct` 仍只发布接口与 `pub` 函数，仍产出 `.c`/`.h`；`.m.ct` 仍不产出 C，因此
新增的边不改变构建产物顺序。缓存键本来就按依赖折叠（`unit_key` 里 header 依赖记 `.h`），
新边自然进入 `main.c.key`：实测两次构建键稳定，`touch` 被 import 的 `.h.ct` 后消费方键改变。

**验收夹具**：`test/modules/sh71_map_import_hdr`（入口目录可直接解析，无需 `-I`）。
起手 `HttpRequest r = "https://example.com/users".method("GET");` 成立，
`HttpRequest r2 = r.header("Accept", "application/json");` 也成立，输出 `200 201`。

**下一条阻断（未修，advisory）**：把同一形态搬进 `namespace api;` 后，消费方用裸名
`api::HttpRequest r = …` 不被支持（`qualified type names are not supported`），
而裸名 `HttpRequest r = …` 的声明能过、下一跳 `r.header(…)` 报
`cannot resolve the method trait (unknown receiver type)`：跨单元发布的 trait 只登记了
裸名别名，声明处没有换成 `struct api_HttpRequest_iface`。这是命名空间 + 跨单元类型
解析的独立缺口，不属于 A-1 的单元矩阵；另案处理。

## 关联

- [examples/47_chain_factory](../../examples/47_chain_factory/src/main.ct) / [examples/48_string_steps](../../examples/48_string_steps/src/main.ct)
- [docs/language-spec.md §4.10 / §4.10.1](../../docs/language-spec.md#410-mapphase-11-新增--sh-20-扩展仅-ct-ast)
- 外部来源：`ct-http/docs/review/ct-http-0.1.0-blockers.md` §2（2026-11-15 独立复核）
