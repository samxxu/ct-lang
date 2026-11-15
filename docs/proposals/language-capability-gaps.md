# CT 语言能力缺口清单（供 CT 语言组评估）

> **已退役为「背景册」（2026-11-15 重排）**：本文基线是 `v0.44.1`，26 条按能力域归并；此后
> PH-46–53 已改掉多批前提。不得把本文当需求单逐条执行；需要某条时先按当前 HEAD 复跑，再单独立项。
> 其中 DF-1 仍成立，已转入 [LANG-17](../../issues/lang/lang-17-preprocessor-line-truncation.md)。
> 现行安排见 [post-58-plan.md](../planning/post-58-plan.md)。

> **评估对象**：CT **v0.44.1**（release tag `13db6cad`，二进制 `~/.local/bin/ct`）。
> **仓库现状**：`b5797cbf`（本文写作时的 HEAD；比 tag 多 4 个修复提交，见 §9.2）。
> **谁该读**：CT 语言与编译器的维护者——用来判断哪些能力值得补、哪些不值得。
> **谁不该把它当需求单**：本文按**能力域**归并，不按包归并；不替任何一个包主张自己的 API 形态。
> **纪律**：只新增本文；不改实现、不改规约、不改夹具、不 bump、不打 tag。所有探针在 `/tmp/ctgap`，不在仓库内。

---

## 0 读法

### 0.1 基线与环境

| 项 | 值 |
| --- | --- |
| 编译器 | `ct v0.44.1`（`ct -v` 输出 `ct v0.44.1`；`git describe --tags 13db6cad` → `v0.44.1`） |
| 平台 | macOS arm64，Apple clang（`cc -std=c99`） |
| 单文件探针 | `ct <file>.ct -o <file>.c` → `cc -std=c99 <file>.c -o <file>.bin` → 运行 |
| 多单元探针 | `ct build src/main.ct -o out`（在探针目录内执行） |
| 标准库发现 | 把 `ct` 复制出安装布局后必须设 `CT_STD_DIR=<repo>/lib/std`；**否则单文件模式会把泛型声明误解析**（见 §9.3）。本文全部多单元探针都在设了该变量的环境下执行 |

**三个单元**（后文反复用到）：`.ct` 普通单元（不可 import）、`.h.ct` 接口单元（只有它能被 import）、
`.m.ct` 映射单元（只有它能写 `map … for type`，其中的 `trait` 是静态 trait）。

### 0.2 两个标签的精确定义

本文每条只给**一个**标签，判据是「谁该动」：

| 标签 | 含义 | CT 组要动的东西 |
| --- | --- | --- |
| **规范缺口** | 规约**没有**给出语义（未定义），或规约**明文排除**该形态 | 规约条款 + 判据 + （可能）实现 |
| **实现缺陷** | 规约已有要求、或可由既有条款推出，实现没做到（含静默产出错误 C） | 只改实现 + 负例 |

「明文排除」也算规范缺口，因为处理方式是**改设计**（要先说服自己这条边值得放开），不是修 bug。
遇到两者都沾的（例如诊断文案错但语义已定义），按「实现缺陷」记，并在依据里说明。

### 0.3 优先级口径

不按感觉给 P0–P3，按两个维度打分：

| 维度 | 取值 |
| --- | --- |
| 撞上的广度 | **多数包**（对象集合、字符串、错误面、多单元布局）/ **少数包**（只在特定建模方式下出现）/ **单个包** |
| 绕法代价 | **无**（只能不做）/ **改交付形态**（换 API 形状或放弃能力）/ **便宜**（多写几行、换个写法） |

| 优先级 | 判据 |
| --- | --- |
| **P0** | 多数包会撞 **且** 无绕法，或静默 UB（读错值/漏清理且无诊断） |
| **P1** | 多数包会撞 **且** 绕法要改交付形态；或少数包撞但完全无绕法 |
| **P2** | 有便宜绕法，但默认/自然写法会撞 |
| **P3** | 只影响少数写法，或绕法比缺失本身更省事 |

**「已修待发版」**：条目定位在 `v0.44.1` 的行为，但在 HEAD 上已有修复提交。这类条目优先级仍按
0.44.1 的用户影响给，处置建议统一是「发版」，不是「再做一次」。

### 0.4 事实与推断

- 标 **实测** 的段落：本文作者在本机跑过，命令、退出码、原始输出在 §11。
- 标 **来源：X** 的段落：没有在本机重跑（多是 HEAD 已修的东西——工作区 `selfhost/` 由另一会话占用，
  不能构建），依据是提交、夹具或规约原文，坐标一并给出。
- 标 **推断** 的段落：作者的判断，写清需要什么证据才能确认。

---

## 1 总览

### 1.1 计数

| 项 | 数量 |
| --- | --- |
| 条目总数 | **26** |
| 规范缺口 | **16** |
| 实现缺陷 | **10** |
| 其中 P0 | 5（B-3、B-4、**C-4**、G-4、**G-8**） |
| 其中 P1 | 7（A-1、B-1、E-2、E-4、G-2、G-3、**G-7**） |
| 其中 P2 | 9（A-3、B-2、C-2、C-3、D-1、E-3、F-1、G-1、**G-5**） |
| 其中 P3 | 5（A-2、C-1、E-1、F-2、**G-6**） |
| **真卡住（无绕法、且绕法必然牺牲核心能力）** | **3**：E-2、B-3、B-4；后两条 HEAD 已修 |

G-5–G-8 是 RILL 的 CT 实现撞到的四条 `ct build` 前端限制（2026-11 补录，探针
`/tmp/ctgap3`）。其中 G-8 是唯一「`ct` 通过、生成文本与源码不一致且无诊断」的缺陷（G-4 是生成
逻辑错，不是文本截断）；具体修复单见 [ct-build-frontend-defects.md](ct-build-frontend-defects.md)。

另外，输入材料里有 **8 条**旧结论在 v0.44.1 上**复现不出来或只在特定条件下成立**（6 条完全不成立、
2 条部分不成立，见 §9.1）。这 6 条不是"已修"，是当时就判错了或已在更早版本落地——这部分对评估
同样重要：**照抄旧清单会把已经不成立的缺口当成待办。**

### 1.2 最该先看的五条

| # | 条目 | 理由（一句话） |
| --- | --- | --- |
| 1 | **G-8** 超过 159 字节的预处理行被静默截断 | 唯一「`ct` rc=0、无诊断、生成 C 与源码不一致」的缺陷；任何用长宏的包都会撞，截断点合法时编译通过但语义被改（实测 6→3），无声、最难查；修法明确（切片存储或至少越界报错） |
| 2 | **C-4** `Map<char *, 用户 struct>` 在 `ct build` 下生成不可编译的头 | 覆盖所有「记录/对象用 `Map` 按值装」的包，且**单文件模式通过、build 模式失败**——包方在单文件探针上验不出来，装进工程才炸；根因（`MapEntry` 按值进共享头）与 `Vec` 的既有做法不一致，改法明确 |
| 3 | **G-4** 指针字段的自动 Drop 胶水把 `T**` 当 `T*` | 唯一一条「静默读错值 + 无诊断 + 任何父子指针结构都会撞」的实现缺陷；生成物里一行就能看出，修复面小，但拖着会让所有 `own` 树型包在运行时读到垃圾 |
| 4 | **E-2 + E-4** `Map` 键只收 int/long/char\*，且键不复制 | 数据保真类包（JSON/序列化）真正的硬阻塞：含 `\0` 的键写不出来，键的生命周期又没人定义；它同时是规范决策（要不要给容器加键协议）而不是修 bug |
| 5 | **G-2** 跨单元 `delete` 不执行 Drop 体 | 多单元资源包的**默认写法**就在泄漏：消费者编译出空桩并调用它，定义单元的真实体是 `static`，链接不上也不报错。它不是"少数包"的问题，而是多单元布局的通用陷阱 |

**第 4 件事（不是条目）**：把 HEAD 上已经修好的 4 项（A-1、B-1、B-3、B-4）发出去。
在 `v0.44.1` 上，「函数返回接口值」这条路径**整体不安全**——B-3 与 B-4 都是静默 UB。留着不发，
等于这半边能力对包方不可用。

---

## 2 A 单元模型

### A-1 `.m.ct` 不能 import `.h.ct`：字符串起手接不到接口对象

| 项 | 值 |
| --- | --- |
| 定性 | 规范缺口（规约明文把这条列为「第 2 段不成立」） |
| 优先级 | **P1**（多数包会撞；绕法要改交付形态） |
| 卡住的项目 | ct-http 0.1.0 的「一行链」；ct-pkg DSL 的字符串入口 |
| 有无绕法 | 有，但都要放弃「字符串起手 + 接口对象」二选一 |
| 版本状态 | v0.44.1 失败；HEAD `fb55985c` 已放开（来源：提交 + 夹具 `test/modules/sh71_map_import_hdr`，未在本机重跑） |

**需求场景**（ct-http 相关材料里的产品形态，改写成真实会写的代码）：

```c
/* http/http.h.ct —— 接口只能发布在 .h.ct */
pub trait HttpRequest {
    HttpRequest header(char *k, char *v);
    HttpResponse send();
}

/* api/api.m.ct —— 字符串起手只能写在 .m.ct */
import http::http;
pub trait Entry { HttpRequest method(char *verb); }
map trait Entry for type char * {
    method(s, verb) -> http_entry_new(s, verb);
}

/* main.ct */
HttpRequest r = "https://api.example.com/users".method("GET");
```

**当前行为**（实测，探针 `/tmp/ctgap/m/m1`）：

```text
$ ct build src/main.ct -o out
ctc: cannot resolve import 'http/http'
$ ct build src/main.ct -o out -I src
src/api/api.m.ct:1:1: error: a .m.ct unit can only import another .m.ct unit
ctc: 1 error(s) generated
$ echo $?
1
```

**期望能力**：映射单元的 `import` 能解析 `.h.ct`，并把 header 发布的 `pub trait` / `pub struct` /
`pub enum` / `pub` 全局放进映射单元的名字表；recipe 里能命名该接口类型。满足「映射单元能看见接口，
且映射仍只在 `.m.ct`」就算解决。

**这是规范缺口还是实现缺陷**：**规范缺口**。规约把三处位置逐一排除过，且写明 `.m.ct` 只能 import
另一个 `.m.ct`（[language-spec.md:525-530](../language-spec.md#L525-L530)、[:538](../language-spec.md#L538)、
[:643-651](../language-spec.md#L643-L651)）。实现与规约一致，所以不是 bug，是规约画的边。

**替代盘**：

| 方案 | 包方现在怎么写 | 代价 |
| --- | --- | --- |
| 静态宿主链 | [examples/47_chain_factory](../../examples/47_chain_factory/src/main.ct) | 对象在映射单元内部是 struct：没有接口类型、没有响应侧多实现。轻量档（纯字符串步骤）仍可交付 |
| `.h.ct` 自由函数工厂 | `HttpRequest r = http::http_entry("url", "GET"); r.header(...);` | 起手不是字符串；每跳落变量；且返回值在 0.44.1 上命中 B-4（悬垂） |
| C shim | `.m.ct` 同目录 `*.shim.c` 承担工厂 | 与上一条同代价，再叠一层 C 维护面 |

**影响面**：ct-http 的「一行链」产品形态、ct-pkg 的 DSL 入口。卡的性质是**只能做得难看**——轻量
静态链能跑，只是写不出「接口对象 + 字符串起手」。

**放开的风险**：`.m.ct` 的传递导入不继承入口目录（实测：不给 `-I` 时先报 `cannot resolve import`），
所以放开后要同时定义搜索根；circular import、缓存键、单元加载顺序都要重验。HEAD 的 A-1 已给出
「只放开 `.m.ct → .h.ct` 这一条边、`m → h → m` 走既有 circular 诊断」的收窄做法，可作为参考。

---

### A-2 类型宿主只能写在 `.m.ct`，不能写在发布接口的单元里

| 项 | 值 |
| --- | --- |
| 定性 | 规范缺口（§4.10.1 第 2 段的另一半） |
| 优先级 | **P3**（A-1 修后组合已可用；本条单独做收益小） |
| 卡住的项目 | 与 A-1 同一组 |
| 有无绕法 | 有（同 A-1） |

**需求场景**：同一份 `http.h.ct` 里先定义接口，紧接着写宿主映射，希望「谁发布接口谁发布映射」。

```c
pub trait Entry { int method(char *verb); }

map trait Entry for type char * {
    method(s, verb) -> entry_new(s, verb);
}
```

**当前行为**（实测，探针 `/tmp/ctgap/m/a5`）：

```text
$ ct build src/main.ct -o out
src/cfg/cfg.h.ct:5:21: error: a type host is only allowed in a .m.ct unit
$ echo $?
1
```

**期望能力**：`.h.ct` 能承载 `map … for type`，且其 recipe 展开路径与 `.m.ct` 一致。

**这是规范缺口还是实现缺陷**：**规范缺口**。规约明文：`map trait … for type …` 只能出现在 `.m.ct`
（[language-spec.md:662](../language-spec.md#L662)），shim 也只探测 `.m.ct`（[:600](../language-spec.md#L600)）。

**替代盘**：同 A-1。若 A-1 落地，「映射写哪儿」就不再是阻塞——`.m.ct` 能看见接口，组合已经成立。

**影响面**：只影响包布局的美观度（接口与映射分居两文件）。**不卡交付**。

**放开的风险**：`.h.ct` 没有 recipe 展开路径；头/实现分离、shim 的 `-I`、`--emit-map` 的宿主条目、
生成顺序都要扩。A-2 在 SH-71 里已被**明确拒绝**，本文不主张翻案。

---

### A-3 类型位置不接受命名空间限定名

| 项 | 值 |
| --- | --- |
| 定性 | 规范缺口（规约写明「类型的限定写法仍不支持」） |
| 优先级 | **P2**（多单元工程常见，但别名 import 便宜） |
| 卡住的项目 | 多命名空间的包；ct-http 把形态搬进 `namespace api;` 后（SH-71 文末） |
| 有无绕法 | 有（alias import） |

**需求场景**：

```c
import cfg::cfg;
namespace app;

int run(void) {
    cfg::Api r = cfg::make(7);   /* 想按命名空间指名类型 */
    return r.ping();
}
```

**当前行为**（实测，探针 `/tmp/ctgap/m/a4b`）：

```text
$ ct build src/main.ct -o out
src/main.ct:6:14: error: no variable of that name in that namespace (qualified type names are not supported; use the bare name or an alias import)
$ echo $?
1
```

`struct cfg::Api *p;` 形态报 `expected a variable name`（来源：`issues/selfhost/ct-ast-qualified-type-name-rejected.md`，
SH-18，状态「部分修复」）。另一处不对称：`pub struct` 的**裸名**跨单元可用，`pub trait` 的裸名不可用
（同来源）。enum 成员在**显式 `namespace`** 下可用限定名 `cfg::Str`，无 `namespace` 时同一写法报
`no variable of that name`（实测 `/tmp/ctgap/m/d2c` 通过、`/tmp/ctgap/m/d2` 失败）——诊断把类型
引用报成变量查找，排查成本高。

**期望能力**：类型位置（声明、参数、返回、字段）接受 `ns::Type`，等价于别名 import。

**这是规范缺口还是实现缺陷**：**规范缺口**。规约已把「裸名 + 别名 import」写成规定做法，并明说
限定写法不支持（[language-spec.md:700](../language-spec.md#L700)）。所以不是实现偏离，是规范没定义语法。

**替代盘**：

| 方案 | 写法 | 代价 |
| --- | --- | --- |
| 别名 import | `import a::b::T as T;` 后写 `T` | 每个外部类型一行；漏写时错误是「未声明变量」，看起来像笔误 |
| 裸名 | `T v;`（仅 struct 可用） | trait 不行，行为不一致 |

**影响面**：多单元 + 命名空间的工程（第三方 nc/Stream 场景）。卡的是**只能做得难看**。

**放开的风险**：要在类型文法里解析 `::` 链并映射到 `<ns>_<Type>`，同时处理 `struct` 前缀、别名、
重名三种形态（SH-18 已给最小方案：裸名唯一候选时直接可用）。诊断文案要一起改，否则用户仍会被
「未声明变量」误导。

---

## 3 B 动态派发与链式

### B-1 接口方法返回接口值，调用点无法消费

| 项 | 值 |
| --- | --- |
| 定性 | **实现缺陷** |
| 优先级 | **P1**（0.44.1 上无安全绕法；HEAD 已修待发版） |
| 卡住的项目 | ct-http（拿响应对象）；任何「收口返回新接口」的 API |
| 有无绕法 | 0.44.1 上**没有安全的**绕法（见下） |
| 版本状态 | v0.44.1 失败；HEAD `5ff69ac3` 已修（来源：提交 + 夹具 `test/ast/238_iface_ret_value`，未在本机重跑） |

**需求场景**：

```c
HttpRequest req = ...;
HttpResponse res = req.send();     /* 想拿响应 */
int code = res.status();
```

**当前行为**（实测，探针 `/tmp/ctgap/p/b1_iface_ret.ct`）：

```text
$ ct b1_iface_ret.ct -o b1_iface_ret.c
b1_iface_ret.ct:37:24: error: cannot infer the type to box
$ echo $?
1
```

同一份代码把该行改成丢弃返回值 `q.send();`，`ct` / `cc` / 运行全部 rc=0。

**期望能力**：声明行已给出目标接口类型时，方法返回值直接就是该接口值，不需要「装箱推断」；
`Resp res = q.send();` 可编译、可调用 `res.status()`。

**这是规范缺口还是实现缺陷**：**实现缺陷**。规约把「只有变量或 `&变量`、以及返回同款接口的函数
调用能装箱」写成规则（[language-spec.md:356](../language-spec.md#L356)），但这里两侧是同一接口、
目标类型来自声明，vtable 槽 `struct Resp_iface (*send)(void *)` 本身是合法的（§4.10.1 自述）。
SH-72 已定位到 `expr_type` 对动态派发 `N_MCALL` 直接返回 -1，`maybe_box` 随即报「无法推断」——
类型其实可推。

**替代盘**：

| 方案 | 写法 | 代价 |
| --- | --- | --- |
| 丢弃返回值 | `req.send();` | 拿不到响应，`.status()` 无处可调 |
| 自由函数返回接口 | `HttpResponse res = http::send(req);` | 丢掉 `.send()` 这一跳；**且在 0.44.1 上命中 B-4**（返回局部接口值悬垂） |
| 返回 struct 指针 | `struct Res *r = req.send();` | 使用者接触具体类型，响应侧失去多实现 |

**影响面**：ct-http 的「收口拿响应」、任何 `-> Response` 的接口方法。卡的性质在 0.44.1 上是
**不能做**（三条绕法分别丢掉响应、丢掉方法形态、或踩 UB）。

**放开的风险**：SH-72 的修法只动 `expr_type`（+19 行），不改变既有生成 C；但必须与 B-4 同批，
否则先把「返回局部值」这条悬垂路径放开。

---

### B-2 方法结果不能作下一跳接收者

| 项 | 值 |
| --- | --- |
| 定性 | 规范缺口（规约明文拒绝，理由是求值顺序） |
| 优先级 | **P2**（有规约推荐的便宜绕法：逐跳落变量） |
| 卡住的项目 | ct-http 的「一行链」；任何 fluent API |
| 有无绕法 | 有（多行；或改静态宿主） |

**需求场景**：

```c
return h.tap(1)->status();          /* 方法结果直接作接收者 */
return h.tap(1)->tap(2)->status();  /* 连两跳 */
```

**当前行为**（实测，探针 `/tmp/ctgap/p/b2_tmp_receiver.ct`）：

```text
$ ct b2_tmp_receiver.ct -o b2_tmp_receiver.c
b2_tmp_receiver.ct:22:1: error: method receiver must be a variable, an element, a call or a field chain
$ echo $?
1
```

连跳与固有方法版本另有两条文案（来源：SH-73）：
`error: a method call on a temporary is only allowed at the start of a statement or of an assignment`。

**期望能力**：接收者本身是方法调用时，先物化为临时量（求值一次、顺序不变），再派发；
`a.m().n()` 与 `a.m().n().o()` 都可写。

**这是规范缺口还是实现缺陷**：**规范缺口**。规约把「接收者是一次方法调用（`N_MCALL`）的形态当前
一律拒绝」写成刻意选择，理由是「不会静默产出坏 C」（[language-spec.md:251-258](../language-spec.md#L251-L258)）；
临时量的提升位置也被限死在「语句行首」与「赋值/声明初始化式右值行首」（[:259-267](../language-spec.md#L259-L267)）。
同一条规约也承认这是两条 lowering 的差异、不是设计意图（[:1886-1890](../language-spec.md#L1886-L1890)）。

**替代盘**：逐跳落变量（规约推荐）；或走类型宿主链（[examples/47](../../examples/47_chain_factory/src/main.ct)），
代价是失去接口对象与响应侧多实现。

**影响面**：只影响「接口值上的一行链」。静态宿主链不受影响（实测：`b5`/`b5b`/`b5c` 的字段链接收者可用）。

**放开的风险**：SH-73 估 100–300 行，且会改「已被接受形态」的生成物——golden 与 `--emit-c` 跨编译器
一致性门禁都要重跑；临时值生命周期、装箱目标推断、求值顺序三件事必须同时给判据。**不建议为单个包
单独放开。**

---

### B-3 impl 内 `return self` 发射 `&_self`：指向已返回的栈帧

| 项 | 值 |
| --- | --- |
| 定性 | **实现缺陷**（静默 UB） |
| 优先级 | **P0**（0.44.1 上无安全绕法；HEAD 已修待发版） |
| 卡住的项目 | ct-http（`header()` / `timeout()` / `send()` 都是这个形状） |
| 有无绕法 | 0.44.1 上无（只能不返回 `self`） |
| 版本状态 | v0.44.1 命中；HEAD `d6e82e25` 已修（来源：提交 + 夹具 `test/ast/237_iface_ret_self`） |

**需求场景**：

```c
impl HttpRequest for Req {
    HttpRequest header(char *k, char *v) { (void)k; (void)v; return self; }
}
```

**当前行为**（实测，探针 `/tmp/ctgap/p/b3_self_ret.ct`，`ct` rc=0）：

```c
/* 生成 C：b3_self_ret.c:38 */
return (struct HttpRequest_iface){ (void *)&_self, &Req_HttpRequest_vtable };
```

`_self` 是函数内的局部指针变量，`&_self` 指向返回后失效的栈帧，并且把 `self` 多套了一层间接。
0.44.1 的 `ct` / `cc` / 运行全部 rc=0（丢弃返回值时看不出来）；一旦消费，解引用读到的是该指针的
低 32 位（来源：SH-74 的可触发路径，实测复现输出 `deref as int = 1861411328 (expected 42)`）。

**期望能力**：`return self;` 装箱为 `(void *)_self`（接口的 `self` 字段直接指向对象）。

**这是规范缺口还是实现缺陷**：**实现缺陷**。规约的危险形态是「生成物里出现指向返回后栈帧的指针」，
这不是任何条款允许的行为；根因是 `self` 被登记为 `struct Req`（无 `*`）而发射器物化为指针变量，
装箱器据声明类型判「非指针」→ 取地址。

**替代盘**：`return` 一个 struct 指针（放弃接口返回值）；或用 `static` 对象承载状态。两条都要改
API 形态，且第二条不适用于并发/重入。

**影响面**：任何「trait 方法返回本 trait 或其他接口值」且实现体 `return self;` 的包。**卡的是不能做**
（安全地做不出来）。

**放开的风险**：修复只改装箱分类，既有样例里没有期望产物包含 `&_self`（SH-74 已核对），
`--emit-c` 一致性门禁不受影响。

---

### B-4 返回块作用域 struct 作接口值：装箱取局部地址，静默悬垂

| 项 | 值 |
| --- | --- |
| 定性 | **实现缺陷**（静默 UB） |
| 优先级 | **P0**（0.44.1 上无安全绕法；HEAD 已修待发版） |
| 卡住的项目 | ct-json 的 `json_decode` 工厂；ct-http 的自由函数工厂 |
| 有无绕法 | 有代价高的绕法（返回全局/静态对象），等价于不能用局部构造 |
| 版本状态 | v0.44.1 命中；HEAD `b5797cbf` 已修（来源：提交 + 夹具 `test/ast/239_local_iface_return`） |

**需求场景**：

```c
Resp make(int v, void **slot) {
    Res r;
    r.s = v;
    *slot = (void *)&r;
    return r;                       /* 想返回一个新造的响应 */
}
```

**当前行为**（实测，探针 `/tmp/ctgap/p/b4_local_ret.ct`，`ct`/`cc`/运行 rc 全 0）：

```c
/* 生成 C：b4_local_ret.c:34 */
return (struct Resp_iface){ (void *)&r, &Res_Resp_vtable };
```

```text
$ ./b4_local_ret.bin
1 200          # 期望 "0 201"：res.self 仍等于被调栈帧，写回后状态被改
```

**期望能力**：返回块作用域 struct 作接口值时，接口持有的是**返回值本身的寿命**（堆拷贝或其他
定义明确的转移），不是被调栈帧地址。

**这是规范缺口还是实现缺陷**：**实现缺陷**。规约的接口值语义是「`self` 指向对象」，没有任何条款
允许它指向返回后失效的栈帧；SH-75 的修法是解析期标记 + `return` 处改发堆拷贝。

**替代盘**：把对象放到全局/静态（失去重入）；或返回 struct 指针（调用方自己装箱，多一跳）。
两者都改变 API 形态。

**影响面**：所有「工厂返回接口」的包。**卡的是不能做**——0.44.1 上「构造一个新对象并以接口返回」
这条最基本的工厂形态是悬垂的。HEAD 的修法是堆拷贝，寿命是整个进程，**不做自动释放**（编译器没有
owner 句柄，也没有接口析构槽）；包方要靠「不放局部」来控制增长。

**放开的风险**：只有「`return <块作用域 struct>;` 且函数返回接口」这一形态变；SH-75 已逐字节对比
253 份单文件夹具 + 30 份模块夹具，仅 2 份变化。语义上引入了不可回收的堆对象，规约要写清寿命与释放责任。

---

## 4 C 泛型与容器

### C-1 裸泛型类型名不可写

| 项 | 值 |
| --- | --- |
| 定性 | 规范缺口（规约无条款；实现给了诊断） |
| 优先级 | **P3**（总能写全类型实参） |
| 卡住的项目 | 想在包内部做「元素类型未知的容器」的类型擦除层 |
| 有无绕法 | 有（写全实参 / `void *`） |

**需求场景**：

```c
struct Node {
    char *key;
    Map *obj;      /* 想表达「任意 JSON 对象」 */
    Vec *arr;
}
```

**当前行为**（实测，探针 `/tmp/ctgap/p/a2_bare_generic.ct`）：

```text
$ ct a2_bare_generic.ct -o a2_bare_generic.c
a2_bare_generic.ct:3:9: error: generic struct 'Map' needs type arguments in a type position
$ echo $?
1
```

注意：该错误只在能发现 `lib/std` 时出现；发现不了时会**静默放行**并发射 `Map * obj;`（见 §9.3）。

**期望能力**：要么给出「带类型实参的指针」这一正规写法（现状已可），要么明确「不存在未定参的容器」。

**这是规范缺口还是实现缺陷**：**规范缺口**。规约没有「裸泛型名」的条款，实现自行加了诊断。
由于裸 `Map *` 在 C 里也没有意义，**不建议放开**；缺的是一条写明「不允许」的条款与固定文案。

**替代盘**：`Map<char *, void *>` 或 `void *obj;` + 强转。代价是丢类型信息，但这是 C 超集里的常规做法。

**影响面**：只影响「类型擦除」这一种建模方式。**不卡交付。**

**放开的风险**：与 Z3（一切可脱糖到 C）冲突；不建议。

---

### C-2 `Vec::get` 返回值、`Map::get` 返回指针

| 项 | 值 |
| --- | --- |
| 定性 | 规范缺口（语言没有「引用/借用返回值」这一等公民） |
| 优先级 | **P2**（容易记错，但绕法便宜） |
| 卡住的项目 | 所有用容器的包；换容器实现时调用点要跟着改 |
| 有无绕法 | 有（记住两种形态；`Vec` 先落局部再取址也不行，得改 `set`） |

**需求场景**：

```c
Vec<struct P> v = ...;
struct P *got = v.get(0);        /* 想按指针取元素，免得拷贝 */
```

**当前行为**（实测，探针 `/tmp/ctgap/p/b6_vec_get.ct`；`ct` rc=0，`cc` 失败）：

```text
$ cc -std=c99 b6_vec_get.c -o b6_vec_get.bin
b6_vec_get.c:336:16: error: initializing 'struct P *' with an expression of incompatible type 'struct P'
  336 |     struct P * got = Vec_P_get(&v, 0);
```

两种容器的签名（[lib/std/Vec.h.ct:94](../../lib/std/Vec.h.ct#L94)、[:260](../../lib/std/Vec.h.ct#L260)、
[:399](../../lib/std/Vec.h.ct#L399)）：

```c
pub T get(int i)        /* Vec：按值返回 */
pub V *get(char *k)     /* Map<char *, V>：按指针返回 */
pub V *get(K k)         /* Map<K, V>：按指针返回 */
```

**期望能力**：两种容器对「取元素」给出同一种形态，或让调用方按需选择（值 / 指针）而不必知道
容器实现。

**这是规范缺口还是实现缺陷**：**规范缺口**。语言没有引用返回值，容器只能用「值」或「指针」两种
落法，于是两个容器各选了一种。规约与 `lib/std` 都没写「为什么不同」，也没写「换容器要改调用点」。

**替代盘**：记住差异；`Vec` 要指针时用 `&v.get(i)` 不行（临时量），只能先取到局部变量；
或直接用 `v.data[i]`（绕过 API）。

**影响面**：所有容器的调用点。卡的是**只能做得难看**（多一行局部变量）。

**放开的风险**：统一成 `T *` 会改变 `Vec<int>` 的零值语义（越界返回什么）；统一成值会让 `Map`
无法表达缺键。建议新增 `try_get` 一类的并行入口，而不是改既有 `get`。

---

### C-3 越界与缺键退化为零值 / NULL，与真实值不可区分

| 项 | 值 |
| --- | --- |
| 定性 | 规范缺口（库契约；语言无错误通道要求） |
| 优先级 | **P2**（先查 `len()` 即可，但默认写法会静默） |
| 卡住的项目 | ct-json（数组缺项被读成 `null`）；解析器类包 |
| 有无绕法 | 有（取前查 `len()`；`Map` 判 NULL） |

**需求场景**：

```c
int *missing = m.get("nope");   /* 缺键 */
int   oob     = v.get(5);       /* 越界 */
```

**当前行为**（实测，探针 `/tmp/ctgap/p/c4_oob_missing.ct`）：

```text
missing=0x0
oob=0
```

`Vec::get` 的注释写明这是有意行为：「Out of range answers a zero value, never a read past the buffer」
（[lib/std/Vec.h.ct:92-99](../../lib/std/Vec.h.ct#L92-L99)）。

**期望能力**：调用方能区分「取到 0」与「没取到」。最小形态可以是并行的 `has(i)` / `try_get`，
不要求改 `get`。

**这是规范缺口还是实现缺陷**：**规范缺口**。规约与 `lib/std` 都没有定义「失败」怎么表达；`Vec`
选了零值、`Map` 选了 NULL，两者都对，但没有统一契约。

**替代盘**：先 `if (i < v.len())`；`Map` 判 NULL。代价是每个访问点两行，且 `len()` 与 `get()`
之间若有并发写入，仍是 TOCTOU。

**影响面**：所有解析/索引类包。ct-json 的 J7 就踩到「`Vec` 越界返回 0 与 `JSON_TAG_NULL` 撞值」，
数组缺项被误读成 null（来源：ct-json 合论 H-26/J7）。

**放开的风险**：改 `get` 会破坏既有夹具；建议只加并行入口。

---

### C-4 `Map<char *, 用户 struct>` 在 `ct build` 下生成不可编译的共享头

| 项 | 值 |
| --- | --- |
| 定性 | **实现缺陷** |
| 优先级 | **P0**（单文件能过、build 必炸；所有按值装记录的包都会撞） |
| 卡住的项目 | ct-json 的对象节点；任何「记录 / 对象 → `Map` 按值」的包 |
| 有无绕法 | 有（元素改指针），但要改数据表示 |
| 版本状态 | v0.44.1 实测失败 |

**需求场景**：

```c
struct JsonRef { int tag; double num; }
struct JsonDoc { Map<char *, JsonRef> *obj; }
```

**当前行为**（实测，探针 `/tmp/ctgap/j/j10b`；工程里只有一个 `main.ct`）：

```text
$ ct build src/main.ct -o out
In file included from .ctbuild/Vec.c:3:
.ctbuild/Vec.h:31:20: error: field has incomplete type 'struct JsonRef'
   31 |     struct JsonRef value;
.ctbuild/Str.h:16:8: note: forward declaration of 'struct JsonRef'
$ echo $?
1
```

生成器把 `Map` 的条目结构按值放进**共享头**，而该头不 include 元素定义所在的单元：

```c
/* .ctbuild/Vec.h:29-32 */
struct MapEntry_char_p_JsonRef {
    char* key;
    struct JsonRef value;
};
```

对照（都实测）：`Vec<JsonRef>`、`Vec<JsonRef *>`、`Map<char *, JsonRef *>`、`Map<char *, void *>`
在 `ct build` 下全部通过；只有 `Map<char *, 用户 struct>` 失败。单文件模式 `ct x.ct -o x.c`
也能通过——所以这个缺陷在单文件探针上验不出来。

**期望能力**：`Map<K, UserStruct>` 在 `ct build` 下可编译——条目结构的 `value` 字段在使用它的
翻译单元里是完整类型。

**这是规范缺口还是实现缺陷**：**实现缺陷**。语言没有「容器元素必须是完整类型」的限制条款；
`Vec` 的实例已经能把元素留到单元内解决，`Map` 的条目结构没有跟上。

**替代盘**：元素改指针（`Map<char *, JsonRef *>`，`get` 返回 `JsonRef **`）、`void *` 擦除、
或换有序表。代价是每值一次堆分配与更复杂的释放；不丢功能。

**影响面**：ct-json 的对象节点，以及任何「对象 / 记录按值进 `Map`」的包。卡的是**必须改数据表示**。

**放开的风险**：修法只动 `MapEntry` 的发射位置/可见性，不改 `Map` API；需要重跑全部 `Map`
夹具与 `--emit-c` 一致性（`Vec.h` 是跨编译器共享的生成物）。

---

## 5 D 导出与常量

### D-1 `#define` 不进生成头，公开常量没有宏形态

| 项 | 值 |
| --- | --- |
| 定性 | 规范缺口（`#define` 的展开面只定义了「消费者 .c」） |
| 优先级 | **P2**（`pub enum` / `pub` 全局都能替代，但写法不直观） |
| 卡住的项目 | ct-json 的 `JSON_TAG_*`；任何把头文件常量当公开 API 的包 |
| 有无绕法 | 有（`pub enum`、`pub` 全局） |

**需求场景**：

```c
/* cfg.h.ct */
#define JSON_TAG_NUM 2
pub int tag_num(void) { return JSON_TAG_NUM; }

/* main.ct */
import cfg::cfg;
int main(void) { return JSON_TAG_NUM; }
```

**当前行为**（实测，探针 `/tmp/ctgap/m/d1`）：

```text
$ ct build src/main.ct -o out
src/main.ct:12:12: error: use of undeclared identifier 'JSON_TAG_NUM'
$ echo $?
1
```

生成的头里没有这条宏；错误由 `cc` 报出（带 `#line` 指回 `.ct`），`ct build` 退出码 1。

**期望能力**：`.h.ct` 里对外的常量有一种跨单元可用的形态。`#define` 只是候选之一。

**这是规范缺口还是实现缺陷**：**规范缺口**。规约只规定 `.m.ct` 的 prologue（`#include` / `#define`）
按整行展开进**消费者 `.c`**，且「消费者 `.h` 不含 prologue」
（[language-spec.md:591](../language-spec.md#L591)）。`.h.ct` 的 `#define` 没有任何导出路径——不是漏做，
是没定义。

**替代盘**（都实测可用）：

| 方案 | 写法 | 代价 |
| --- | --- | --- |
| `pub enum` | `pub enum JsonTag { Num = 2, Str = 3 }`；消费方用裸名 `Num`，显式 `namespace` 下可用 `cfg::Str` | 成员值只能是整数；不能放字符串/浮点 |
| `pub` 全局 | `pub int LIMIT = 10;` 消费方 `return LIMIT;` → 实测返回 10（`/tmp/ctgap/m/d3`） | 是变量不是常量，可被改；每个常量一个符号 |
| 访问器函数 | `pub int tag_num(void)` | 每个常量一个函数，不能用于 `case` / 数组长度等常量位置 |

**影响面**：导出常量面。卡的是**只能做得难看**——`pub enum` 覆盖了绝大多数枚举常量场景。

**放开的风险**：把宏塞进头会带来展开顺序、重复定义、`#if` 交互；规约需要同时定义「哪些宏允许导出」。
建议维持现状，在规约里写死「公开常量用 `pub enum`，不要用 `#define`」。

---

## 6 E 值模型

### E-1 数值精度与溢出没有任何语言级检查

| 项 | 值 |
| --- | --- |
| 定性 | 规范缺口（Z5：类型检查 opt-in） |
| 优先级 | **P3**（可用显式转换与手工检查；属设计选择） |
| 卡住的项目 | 想「默认安全」的序列化/数值包 |
| 有无绕法 | 有（`long long` / `int64_t` / 显式范围检查） |

**需求场景**：

```c
int big = 99999999999;                  /* 字面量超 int */
double d = 9007199254740993.0;          /* 2^53+1，double 表示不了 */
int i = (int)9007199254740993.0;
```

**当前行为**（实测，探针 `/tmp/ctgap/p/e3_literal_overflow.ct`、`/tmp/ctgap/p/e1_numeric.ct`）：

```text
$ ct build e3_literal_overflow.ct -o e3b
e3_literal_overflow.ct:13:15: warning: implicit conversion from 'long' to 'int' changes value from 99999999999 to 1215752191
$ echo $?
0
```

```text
big=9007199254740992
inf=inf
ll=10000000000
i=14500960        # (int)9007199254740993.0，UB 取值
```

**期望能力**：要么在 `ct check --types` 下挡住常量溢出与越界转换，要么在规约里写明「数值转换一律
按 C 语义，不检查」。

**这是规范缺口还是实现缺陷**：**规范缺口**。Z5 明确规定类型检查是 opt-in，`check` 只挡结构性错误，
类型错误推给 `cc`；`ct build` 只把 `cc` 的 warning 原样透出。不是实现漏了，是边界画在这里。

**替代盘**：用 `long long` / `int64_t` 存整数；比较前显式判范围；避免用 double 承载大整数。
代价是每条路径都要写检查。

**影响面**：ct-json 这类「数字要保真」的包。**卡的是只能做得难看**（要自己写检查），不是不能做。

**放开的风险**：与「C 超集」冲突（C 的隐式转换就是会截断）；建议只在 `ct check --types` 扩面，
不动默认编译。

---

### E-2 `Map` 键只支持 int / long / char\*，长度前缀串不能作键

| 项 | 值 |
| --- | --- |
| 定性 | 规范缺口（编译器硬限制，规约未载） |
| 优先级 | **P1**（数据保真类包**无等价绕法**） |
| 卡住的项目 | ct-json 的对象键；任何键可能含 `\0` / 需要原样往返的数据包 |
| 有无绕法 | 只能改编码（牺牲字节保真）或换数据结构 |
| 真卡住 | **是** |

**需求场景**：

```c
Map<struct Str, int> m;                       /* 想用长度前缀串作键 */
struct Str k = str_from_len("a\0b", 3);       /* 键里带 NUL */
m.put(k, 1);
```

**当前行为**（实测，探针 `/tmp/ctgap/p/e2b_str_key.ct`、`/tmp/ctgap/p/e2_nul_key.ct`）：

```text
$ ct e2b_str_key.ct -o e2b_str_key.c
e2b_str_key.ct:5:26: error: Map does not support key type 'struct Str' (use int, long or char *)
$ echo $?
1
```

用 `char *` 作键时，含 NUL 的两个不同键会撞成一个：

```c
char a[] = "a\0b";   char c[] = "a\0c";
m.put(a, 1);         m.put(c, 2);
```

```text
len=1 v1=2 v2=2      # 两个键撞成一个，后者覆盖前者
```

**期望能力**：容器键要么支持长度前缀 / 字节串，要么允许用户类型通过协议提供「比较 + 哈希 + 所有权」。
最小形态可以只是「`Map` 接受实现了某协议的键类型」。

**这是规范缺口还是实现缺陷**：**规范缺口**。限制由编译器发出
（[selfhost/ct-ast/frontend/parse/Expr.h.ct:2174](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2174)），
负例固定在 [selfhost/check-ast.sh:6964](../../selfhost/check-ast.sh#L6964) / [:7128](../../selfhost/check-ast.sh#L7128)，
但 `language-spec.md` 里搜不到这条限制——它是「实现 + 夹具固定、规范未载」的边界。

**替代盘**：

| 方案 | 写法 | 代价 |
| --- | --- | --- |
| 键转义编码 | 把 `\0` 编成文本（如 `\u0000`）再作 `char *` 键 | 丢原字节；编解码必须可逆，且要自己保证；解析器往返测试要重写 |
| 换成有序表 | `Vec<struct Pair>` + 线性查找 | O(n)；与 `Map` 的 API 面完全不同 |
| 键加长度包装 | 自定义 `struct Key { char *p; int n; }` 当 `V` 的值，另建索引 | 两套结构，所有权更复杂 |

**影响面**：ct-json 的 125 条 golden 里有大量「键必须原样往返」的用例；含 `\0` 的键是 RFC 8259
允许的（`\u0000`）。**卡的是不能做**（不做转义就写不出来），不是难看。

**放开的风险**：要同时定义键的比较、所有权（见 E-4）、以及 `Map` 生成物的变化；`Map<char*,V>`
的既有夹具要保。建议做成「键协议」而不是扩 `Map` 的类型白名单。

---

### E-3 匿名 union 成员不能带名字

| 项 | 值 |
| --- | --- |
| 定性 | 规范缺口（规约明文给了替代写法） |
| 优先级 | **P2**（tagged union 是主流建模，但改名成本低） |
| 卡住的项目 | JSON / AST 的 tagged union 建模 |
| 有无绕法 | 有（先命名 union 类型） |

**需求场景**：

```c
struct JsonRef {
    int tag;
    union {
        double n;
        char *s;
    } v;                 /* 想给联合体一个字段名 v */
}
```

**当前行为**（实测，探针 `/tmp/ctgap/p/a1_anon_union.ct`）：

```text
$ ct a1_anon_union.ct -o a1_anon_union.c
a1_anon_union.ct:6:7: error: an anonymous record member cannot have a name; tag the record instead
$ echo $?
1
```

**期望能力**：匿名 union 可以带字段名（等价于 C 的 `union { … } v;`）。

**这是规范缺口还是实现缺陷**：**规范缺口**。规约 §4.18 只定义「无名字的匿名成员」并把成员名提升
（[language-spec.md:923-942](../language-spec.md#L923-L942)），并明文拒绝具名形态
（[:947](../language-spec.md#L947)）；错误文案自带替代写法。

**替代盘**：

```c
union JsonRefVal { double n; char *s; }
struct JsonRef { int tag; union JsonRefVal v; }
```

代价是多一个类型名，访问写成 `r.v.n`（与 C 习惯一致）。实测 `sizeof(struct JsonRef)=16`、
`sizeof(union)=8`（`/tmp/ctgap/p/e4_sizeof.ct`）。

**影响面**：只影响写法，不影响能力。**不卡交付。**

**放开的风险**：C11 的「具名匿名成员」本身不是标准形态（具名就不是匿名成员了），要定义成
「内联 union 类型 + 字段名」的糖；与名字提升规则、`use` 的 vptr 追加顺序都可能交互。

---

### E-4 容器不复制键/值，所有权契约未定义

| 项 | 值 |
| --- | --- |
| 定性 | 规范缺口（`put` 对键/值的所有权没有条款） |
| 优先级 | **P1**（默认写法会静默失效） |
| 卡住的项目 | 以 `char *` 为键的所有包；ct-json 的字符串键 |
| 有无绕法 | 有（自己 `strdup` + 自己释放），但容器没有释放钩子 |

**需求场景**：

```c
char buf[8];
strcpy(buf, "key1");
m.put(buf, 1);          /* 键指针存进去 */
strcpy(buf, "key2");    /* 复用同一块缓冲 */
```

**当前行为**（实测，探针 `/tmp/ctgap/p/e5_key_copy.ct`）：

```text
key1=0x0 key2=0x1017d6fd8     # 键没有复制：改缓冲后 "key1" 查不到
```

值是按值拷贝的（`Map::put` 收 `V`），键只存指针（`Vec.h.ct:253-255`；`Map::release` 只释放值，
不碰键）。

**期望能力**：规约写明 `put` 是否复制键、谁负责释放、释放时机；或者提供 `put_owned` 一类的显式入口。

**这是规范缺口还是实现缺陷**：**规范缺口**。规约没有任何一句定义容器对键/值的所有权；
`lib/std` 的实现是「值拷贝、键借用」，但这是实现巧合，不是契约。

**替代盘**：调用方 `strdup` 键并自己 `free`（容器不提供钩子，所以要在容器销毁后自己遍历释放）；
或把键放进与容器同寿命的 arena。代价是每个调用点都要记得。

**影响面**：所有 `Map<char*,V>` 的包。默认写法（栈缓冲/临时串作键）会静默失效，属于「出错不报」。
**卡的是只能做得难看**，但很容易漏。

**放开的风险**：改成复制键会改所有 `Map` 生成物与性能，且要同时定义释放（否则泄漏）；
建议只在规约里写死「键是借用，生命周期必须覆盖容器」，并提供 `put_owned`。

---

## 7 F 下标协议与类型转换

### F-1 自定义 `[]` 未立项、未实现

| 项 | 值 |
| --- | --- |
| 定性 | 规范缺口（提案自述「未立项、未过分析，不作数」） |
| 优先级 | **P2**（`x.get(i)` 可写，但上层 DSL 会把容器习惯泄漏出去） |
| 卡住的项目 | ct-pkg agent runtime（`env["key"]`）、RILL DSL、ct-json 的 `doc["k"]` |
| 有无绕法 | 有（方法调用） |

**需求场景**：

```c
struct Box { int x; }
impl Box {
    int get(int i) { return self->x + i; }
    void set(int i, int v) { self->x = v + i; }
}
int main(void) {
    Box b; b.x = 5;
    return b[0];                       /* 想展开为 b.get(0) */
}
```

**当前行为**（实测，探针 `/tmp/ctgap/p/f1b_inherent_subscript.ct`；`ct` rc=0）：

```text
$ cc -std=c99 f1b_inherent_subscript.c -o f1b.bin
f1b_inherent_subscript.c:170:13: error: subscripted value is not an array, pointer, or vector
  170 |     return b[0];
```

注意：非泛型固有 `impl Box { … }` 本身在 v0.44.1 上**已可用**（`ct` 接受，见 §9.1 第 7 条）；
缺的只是 `[]` 的展开。

**期望能力**：类型在 `impl` 里声明签名匹配的 `get` / `set` 后，`obj[k]` 展开为方法调用；未声明时
编译期硬错并指名类型。

**这是规范缺口还是实现缺陷**：**规范缺口**。`REQ-L1` 在需求池里是 `status = open`，
[custom-index-protocol.md](custom-index-protocol.md) 首行自述「提案 / 未立项 / 未过分析，不作数」，
且明确「不做指针接收者」（`:39`）。规约的现状是「`Vec` / `Map` 有糖，其余原样发射 C 下标」，
错误留给 `cc`。

**替代盘**：写 `x.get(i)` / `x.set(i, v)`。代价：宿主语言习惯进入上层 DSL，换容器实现要改调用点。

**影响面**：ct-pkg / RILL 的表达面。卡的是**只能做得难看**。

**放开的风险**：提案已列 7 条（RL1-R1–R7），主要是 `static_ctype` 推不出接收者时糖不生效、
退回 C 下标只在 `cc` 报错（静默到后段）；以及右值接收者的写入静默丢失（提案用硬错挡住）。

---

### F-2 没有协议化的类型转换，只有 C 强转

| 项 | 值 |
| --- | --- |
| 定性 | 规范缺口 |
| 优先级 | **P3**（不做只是写法问题） |
| 卡住的项目 | 想写 `char *s = ref;` 这类糖的包 |
| 有无绕法 | 有（显式函数） |

**需求场景**：

```c
struct Ref { int tag; }
struct Ref r;
char *s = &r;               /* 想表达「取它的字符串视图」 */
```

**当前行为**（实测，探针 `/tmp/ctgap/p/f3_convert.ct`；`ct` rc=0、`cc` 只有 warning、运行输出首字节）：

```text
$ cc -std=c99 f3_convert.c -o f3.bin
f3_convert.c:161:12: warning: incompatible pointer types initializing 'char *' with an expression of type 'struct Ref *'
```

**期望能力**：声明式的转换钩子（如某种 `impl` 方法），或明确「不做隐式转换」。

**这是规范缺口还是实现缺陷**：**规范缺口**。规约没有转换协议；`into` 只做「块内字段赋值」的局部
脱糖，不引入类型规则；隐式转换被 Z3 排除。

**替代盘**：显式函数（`json_ref_to_str(v)`）；调用点多一层。代价小。

**影响面**：只影响写法。**不卡交付。**

**放开的风险**：引入隐式转换会破坏「生成 C 可预测」与 C 超集；**建议永久不做**，在规约里写明。

---

## 8 G 其他

### G-1 同名函数无重载，CT 只告警、产物到 `cc` 才失败

| 项 | 值 |
| --- | --- |
| 定性 | **实现缺陷**（同一名字两处定义，规约没有允许重载的条款） |
| 优先级 | **P2**（一旦撞上，错误指向生成的 C，排查成本高） |
| 卡住的项目 | ct-json 的三个 `json_encode` |
| 有无绕法 | 有（改名） |

**需求场景**：

```c
int encode(int v) { return v + 1; }
char *encode(char *s) { return s; }
```

**当前行为**（实测，探针 `/tmp/ctgap/p/g1_overload.ct`）：

```text
$ ct build g1_overload.ct -o g1b
g1_overload.ct:12:13: warning: type mismatch: 'encode' argument 1: expected 'char *', got 'int'
g1_overload.ct:13:5: error: conflicting types for 'encode'
$ echo $?
1
```

`ct` 在**调用点**按先看到的签名发一条 warning 并继续生成 C；两处定义到 `cc` 才报
`conflicting types`。单文件模式没有 `#line`，错误指向生成的 `.c`。

**期望能力**：同一单元内同名函数在**定义处**就报硬错（或明确支持重载——后者与 C ABI 冲突，不建议）。

**这是规范缺口还是实现缺陷**：**实现缺陷**。规约没有「允许重载」的条款，C 也不允许同签名冲突；
「同单元同名两次定义」应当是编译期硬错，而不是调用点 warning + 后段 `cc` 错误。

**替代盘**：改名（`json_encode_map` / `json_encode_vec` / `json_encode_scalar`）。代价是 API 面变长。

**影响面**：想用「同名不同参」的包。**卡的是只能做得难看**。

**放开的风险**：加「同单元同名即硬错」要区分跨单元的 `static` 同名函数（不同单元各自定义是合法的），
判定要按单元与链接性。

---

### G-2 跨单元 `delete` 不执行 Drop 体

| 项 | 值 |
| --- | --- |
| 定性 | **实现缺陷**（规约说 `delete p` 调用 `<S>_Drop_drop(p)`，跨单元时调用的是空桩） |
| 优先级 | **P1**（多单元资源包的默认写法就在泄漏） |
| 卡住的项目 | ct-http 的 curl 句柄；任何多单元资源包 |
| 有无绕法 | 有（消费方显式调用 `pub` 清理函数） |

**需求场景**：

```c
/* cfg.h.ct */
pub struct Res { int id; } use Drop;
impl Drop for Res { void drop(void) { printf("res drop %d\n", self->id); } }
```

```c
/* main.ct */
import cfg::cfg;
int main(void) {
    struct Res *r = malloc(sizeof(struct Res));
    r->id = 7;
    delete r;                  /* 期望打印 "res drop 7" */
    printf("done\n");
}
```

**当前行为**（实测，探针 `/tmp/ctgap/m/d4`；`ct build` rc=0）：

```text
$ ./out
done                           # "res drop 7" 没有出现
```

生成的 `main.c` 里有一份自己的空桩，并调用了它：

```c
static void __attribute__((unused)) Res_Drop_drop(void *self) {
    struct Res *_self = (struct Res *)self;
    (void)_self;
}
...
if (r) { Res_Drop_drop(r); free(r); r = 0; }
```

真实体在 `cfg.c` 里，但符号是 `static`，消费单元看不到也链接不到。

**期望能力**：`delete` 调用的 Drop 体是**定义该 impl 的单元**里的那一份；跨单元可见（或给出编译期
硬错，而不是发空桩）。

**这是规范缺口还是实现缺陷**：**实现缺陷**。规约 §4.56 明说 `delete p` 调用 `<S>_Drop_drop(p)`，
并说明「无显式 impl 时按字段递归生成胶水」（[language-spec.md:2325](../language-spec.md#L2325)）。
另有一句承认跨单元限制（[:1569](../language-spec.md#L1569)），但**没有**说「跨单元 delete 是空操作」。
空桩是静默替代，不是规范行为。

**替代盘**：在定义单元导出 `pub` 清理函数，消费方手动调用（`cfg::res_free(r)`）并自己 `free`。
代价：绕过 `own`/`delete`，漏写就泄漏，且 `own` 的自动释放也会走空桩——等于整套 Drop 在多单元下不可用。

**影响面**：任何「类型在 `.h.ct`、impl 在 `.h.ct`、消费在别的单元」的资源包。**泄漏而不是崩溃**，
所以很难发现。ct-http 的 §6.2 就是这个。

**放开的风险**：改成 `extern` 链接要处理符号冲突、多单元重复定义、`--lib` 导出、以及 `-fvisibility`
一类的裁剪；过渡期可先给「跨单元 `use Drop` 但本单元无 impl」的编译期警告，把静默变显式。

---

### G-3 `own` 不能接工厂返回值

| 项 | 值 |
| --- | --- |
| 定性 | 规范缺口（`own` 的初始化式被限定为 `malloc` / `calloc`） |
| 优先级 | **P1**（构造器风格 API 全被挡） |
| 卡住的项目 | ct-json 的 `json_decode`；任何 `new_xxx()` 工厂 |
| 有无绕法 | 有（手写 malloc + 逐字段赋值；或放弃 `own`） |

**需求场景**：

```c
struct P *make(int v) { ... }
own struct P *p = make(3);        /* 想拿工厂的返回值并自动释放 */
```

**当前行为**（实测，探针 `/tmp/ctgap/p/g2_own_return.ct`、`/tmp/ctgap/p/g6_own_in_sig.ct`）：

```text
$ ct g2_own_return.ct -o g2_own_return.c
g2_own_return.ct:15:1: error: 'own' requires a malloc or calloc initialiser
ctc: 1 error(s) generated
$ echo $?
1
```

把 `own` 写进返回类型（`own struct JsonDoc *json_decode(...)`）在 v0.44.1 上是**编译期硬错**：

```text
g6_own_in_sig.ct:7:1: error: 'own' is only allowed inside a function body
```

（这一条修正了旧材料里「`own` 写进返回类型会生成非法 C」的说法——现在它根本到不了 C。）

**期望能力**：`own p = factory(...)` 可写；`own` 出现在返回类型位置时，语义是「所有权转移给调用方」，
或明确禁止并给出可操作诊断。

**这是规范缺口还是实现缺陷**：**规范缺口**。规约把 `own` 的初始化式限定为
`malloc` / `calloc`（[language-spec.md:397](../language-spec.md#L397)），并规定 `own` 只在函数体内的
声明位置；返回类型位置没有任何条款。

**替代盘**：工厂内部 `malloc` 并返回普通指针，调用方自己 `delete`（失去自动释放）；或把工厂写成
`void init(struct P *p, ...)`，由调用方 `own struct P *p = malloc(...)` 后传入。后者可用，但要改所有
构造点。

**影响面**：构造器 API 的形态。**卡的是只能做得难看**（每个类型两套入口）。

**放开的风险**：放开需要定义「返回值所有权转移」与失败路径（失败时返回 0，`own` 怎么记账），
与 SH-33 的「autodrop 与 return 交互」相邻；建议先补规约条款再动实现。

---

### G-4 指针字段的自动 Drop 胶水把 `T**` 当 `T*`

| 项 | 值 |
| --- | --- |
| 定性 | **实现缺陷**（静默 UB，读到错误值，无诊断） |
| 优先级 | **P0**（父子指针结构都会撞；默认写法） |
| 卡住的项目 | JSON 树、AST、链表等「父持有子指针 + `use Drop`」的包 |
| 有无绕法 | 有（父类型手写显式 `impl Drop`），但每个父类型都要手写 |

**需求场景**：

```c
struct Leaf { int id; } use Drop;
struct Node { struct Leaf *leaf; int id; } use Drop;

impl Drop for Leaf { void drop(void) { printf("leaf drop %d\n", self->id); } }

int main(void) {
    own struct Node *n = malloc(sizeof(struct Node));
    n->id = 1;
    n->leaf = malloc(sizeof(struct Leaf));
    n->leaf->id = 2;
    delete n;                 /* 期望、且必须只释放一次，打印 id=2 */
    printf("done\n");
}
```

**当前行为**（实测，探针 `/tmp/ctgap/p/g8_ptr_field_glue.ct`；`ct`/`cc` rc=0）：

```c
/* 生成的胶水 */
static void __attribute__((unused)) Node_Drop_drop(void *self) {
    struct Node *_self = (struct Node *)self;
    Leaf_Drop_drop(&_self->leaf);      /* 传 struct Leaf **，形参是 void * */
}
```

```text
$ ./g8_ptr_field_glue.bin
leaf drop 22792752          # 期望 "leaf drop 2"：id 读成了指针的低 32 位
done
```

`ct`、`cc`、运行全部 rc=0，没有任何诊断。

**期望能力**：指针字段的胶水要么传 `_self->f`（不是 `&_self->f`），要么判空后 `delete _self->f`；
两者都不能把 `T**` 当 `T*`。

**这是规范缺口还是实现缺陷**：**实现缺陷**。规约说「无显式 impl 时，编译器按字段声明顺序为每个
`uses_drop` 字段递归生成释放胶水」（[language-spec.md:2325](../language-spec.md#L2325)）。指针字段
的「递归」显然应当是「对子对象调用，而不是对指针槽取地址」。这是实现与条款的偏离。

当前绕法只有「给父类型写显式 `impl Drop`」，但那样又会丢掉自动胶水（规约：显式 impl 即自负全责），
等于每个树节点类型都要手写清理。

**影响面**：任何 `own` 树/链结构。**卡的是不能安全地用默认写法**；因为无崩溃、无诊断，属于最难查的一类。

**放开的风险**：修复只改胶水发射（按字段是否指针分支）；要重跑全部 Drop 夹具、`--emit-c` 一致性，
并补一条「指针字段 + 显式子 impl」的正向夹具与一条 ASAN 夹具。

---

### G-5 前向 typedef（`typedef struct JVal JVal;`）被拒

| 项 | 值 |
| --- | --- |
| 定性 | **实现缺陷**（前端未实现「裸标签 + 别名」这一分支） |
| 优先级 | **P2**（有便宜绕法，但 C 迁移代码的默认写法会撞） |
| 卡住的项目 | RILL 的 CT 实现；任何相互递归类型 |
| 有无绕法 | 有（`struct JVal;` 前置声明 + 一律写 `struct JVal *`） |

**触发条件**：`typedef struct Tag Alias;` / `typedef union Tag Alias;`——即记录定义**没有体**、
标签后面直接跟别名的写法。ct-ast 前端在单文件与 `ct build` 两种模式下都拒（同一套 parser）。

**最小代码**：

```c
typedef struct JVal JVal;

struct JVal {
    int tag;
}

int main(void) {
    JVal v;
    v.tag = 1;
    return v.tag;
}
```

**命令与退出码**（实测，探针 `/tmp/ctgap3/l1_typedef.ct`）：

```text
$ ct l1_typedef.ct -o l1_typedef.c
l1_typedef.ct:1:21: error: unexpected token
$ echo $?
1
$ ct build l1_typedef.ct -o out
l1_typedef.ct:1:1: error: unexpected token
$ echo $?
1
```

**这是规范缺口还是实现缺陷**：**实现缺陷**。规约说 `typedef` 可用、别名可作局部/参数/字段
（[language-spec.md:732-733](../language-spec.md#L732-L733)），没有「记录 typedef 必须带体」的条款；
`struct JVal;` 前向声明本身是支持的。缺的是 `parse_typedef` 的「标签 + 别名 + `;`」分支：
`Parser.h.ct:2432` 直接进 `parse_record_def`，而后者只认下一个 token 是 `;` 的前向形式
（`Parser.h.ct:2178-2184`），否则走 `parse_record_body` 的 `expect("{")`（`Parser.h.ct:1927`），
于是把别名当成缺失的 `{` 报错。坐标见修复单
[ct-build-frontend-defects.md](ct-build-frontend-defects.md) 的 DF-3。

**替代盘**：`struct JVal;` 前置声明 + 全部写 `struct JVal *`（实测 `l1b`/`l1d`：`ct`、`cc`、运行
rc 全 0）；`.h.ct`/`.m.ct` 里规约另给了 `pub type JVal = struct JVal;`（§4.19，未实测）。代价是
把 `struct` 关键字漏到 API 拼写上、改动面随使用点扩散；整体退回单文件 `ctc` 的代价见 G-8。

**影响面**：相互递归类型、想用 typedef 名组织公开 API 的包。**卡的是写法，不是能力**——
报错明确，改拼写即可过。

**放开的风险**：只加一个解析分支与一条 `typedef struct Tag Alias;` 发射；要重跑 typedef 夹具、
`.h.ct` 导出夹具与重复类型诊断（别名与标签同名的情形）。

---

### G-6 `impl` 块尾分号被拒

| 项 | 值 |
| --- | --- |
| 定性 | **规范缺口**（语法宽容度未定义；规约的 `impl-def` 没有尾 `;`） |
| 优先级 | **P3**（删一个字符即可，无能力损失） |
| 卡住的项目 | RILL 的 CT 实现（C 习惯写法） |
| 有无绕法 | 有（删掉 `;`） |

**触发条件**：在 `impl Trait for T { … }` 或 `impl T { … }` 的 `}` 后写 `;`。

**最小代码**：

```c
struct J {
    int n;
}

impl J {
    int get(int i) {
        return self->n + i;
    }
};

int main(void) {
    struct J j;
    j.n = 1;
    return j.get(2);
}
```

**命令与退出码**（实测，探针 `/tmp/ctgap3/l2_impl_semicolon.ct`；单文件与 build 同）：

```text
$ ct l2_impl_semicolon.ct -o l2.c
l2_impl_semicolon.ct:9:2: error: expected a type (tok 4 ';')
$ echo $?
1
```

**这是规范缺口还是实现缺陷**：**规范缺口**。语法定义是
`impl-def ::= "impl" IDENT "for" IDENT "{" { method-def } "}"`（[language-spec.md:75](../language-spec.md#L75)），
没有尾分号；而 `struct` / `enum` 的定义后分号是可选的（`top_decl` 对两者都 `accept(";")`，
`Parser.h.ct:816-825`），`impl` 分支（`Parser.h.ct:808-809`）没有。所以这是**宽容度不一致**，
不是「已定义却没做到」。要么把 grammar 改成与 `struct` 一致的可选 `;` 再补实现，要么维持拒绝
但把诊断改成「`impl` 块后不写分号」。

**替代盘**：删掉 `;`，代价一个字符。注意不要用「退回 `ctc`」绕这一条：实测 `ctc` 不接受固有 impl
（`error: expected 'for' in impl of 'J'`），反而更差。

**影响面**：从 C 迁移、习惯在块后加分号的代码。**不影响语义**，只影响书写。

**放开的风险**：只加 `accept(";")`；要重跑 impl 夹具与 `--emit-c` 一致性。规约需先写明可选 `;`。

---

### G-7 `#define` 的反斜杠续行被当成独立语句

| 项 | 值 |
| --- | --- |
| 定性 | **实现缺陷**（词法层的预处理行拼接未实现） |
| 优先级 | **P1**（撞上的是用多行长宏的包；压成单行后会撞 G-8，等于无绕法） |
| 卡住的项目 | RILL 的 CT 实现；任何用多行宏（关键字表、前缀判断）的包 |
| 有无绕法 | 勉强有（把宏拆成多条短宏，或压成一行且 < 159 字节） |

**触发条件**：一行以 `#` 开头、行尾是 `\` 的预处理行，续行被当作普通 C 代码继续解析。

**最小代码**：

```c
#define ADD(a, b) \
    ((a) + (b))

int main(void) {
    return ADD(1, 2);
}
```

**命令与退出码**（实测，探针 `/tmp/ctgap3/l3_macro_continuation.ct`）：

```text
$ ct l3_macro_continuation.ct -o l3.c
l3_macro_continuation.ct:2:6: error: expected a type (tok 4 '(')
$ echo $?
1
```

**这是规范缺口还是实现缺陷**：**实现缺陷**。规约的模型是「顶层构造展开，其余 C 代码原样透传」
（[language-spec.md:40-41](../language-spec.md#L40-L41)），续行是 C 预处理的标准写法
（换行在翻译阶段 2 就被删除）；规约里的「逐行」描述的是扫描粒度，不是禁止拼接。实现上
`Lexer.h.ct:90-97` 的 T_PP 分支一路读到 `\n` 就返回，不检查行尾 `\`，于是续行进入顶层声明解析，
报错还指在第二行——用户很难联想到上一行的反斜杠。坐标见修复单 DF-2。

**替代盘**：拆成多条短宏（每条 < 159 字节）再组合；或把宏压成一行。两者都改变宏的结构，
且单行超过 159 字节时必然撞 G-8；整体退回单文件 `ctc`（实测三条都能过，代价见 G-8）。

**影响面**：所有多行宏。**卡的是写法**，报错明确（但位置误导）。

**放开的风险**：`#include` / `#define` 的「按整行去重」单位会从物理行变成逻辑行
（[language-spec.md:591](../language-spec.md#L591)），同一宏的两种换行写法可能从两条变一条；
要重跑 prologue 夹具，并把「`\` 后带空格不算续行」的负例写进规约。

---

### G-8 超过 159 字节的预处理行被静默截断（生成 C 与源码不一致）

| 项 | 值 |
| --- | --- |
| 定性 | **实现缺陷（静默错误）**——`ct` rc=0、无诊断，生成物与源码不一致 |
| 优先级 | **P0**（任何 package 的长宏都会撞；不报错，最危险） |
| 卡住的项目 | RILL 的 CT 实现；任何 `#define` / `#include` 长于 159 字节的包 |
| 有无绕法 | 有（把宏压到 159 字节内，或退回单文件 `ctc`），都要放弃一部分能力 |

**触发条件**：任一行首 `#` 的预处理行超过 159 字节（`MAX_TEXT` 为 160，留一个 NUL）。
单文件与 `ct build` 同样截断；`ct build` 的整体 rc 由随后的 `cc` 给出，前端本身不报错。

**最小代码**（510 字节的宏，探针 `/tmp/ctgap3/l4_long_macro.ct`）：

```c
#define is_kw(x) (strcmp((x),"if")==0 || strcmp((x),"else")==0 || strcmp((x),"while")==0 || strcmp((x),"for")==0 || strcmp((x),"return")==0 || strcmp((x),"struct")==0 || strcmp((x),"union")==0 || strcmp((x),"enum")==0 || strcmp((x),"switch")==0 || strcmp((x),"case")==0 || strcmp((x),"default")==0 || strcmp((x),"break")==0 || strcmp((x),"continue")==0 || strcmp((x),"sizeof")==0 || strcmp((x),"typedef")==0 || strcmp((x),"static")==0 || strcmp((x),"const")==0 || strcmp((x),"void")==0 || strcmp((x),"int")==0)

#include <string.h>

int main(void) {
    return is_kw("if") ? 0 : 1;
}
```

**命令与退出码**：

```text
$ ct l4_long_macro.ct -o l4.c
$ echo $?                              # 编译本身通过
0
$ grep '^#define is_kw' l4.c | awk '{print length($0)}'
159                                    # 源 510 字节，生成物只剩 159
$ cc -std=c99 l4.c -o l4
l4.c:11:155: warning: missing terminating '"' character [-Winvalid-pp-token]
l4.c:156:13: error: expected expression
1 warning and 3 errors generated.
$ echo $?
1
```

`ct build` 同样在 `cc` 阶段失败（rc=1），报错位置经 `#line` 映回源文件第 1 行第 155 列。

更坏的情形是截断点正好落在合法边界：探针 `/tmp/ctgap3/l6_valid_trunc.ct` 把 `* 2` 放在第 160
字节之后，`ct` rc=0、`cc` rc=0，运行返回 **3**（源码语义是 6）——**编译通过，行为被改掉**。

**这是规范缺口还是实现缺陷**：**实现缺陷**。规约明文要求「所有固定容量上限……越界一律 `die`
报错，**不静默截断**」（[language-spec.md:55](../language-spec.md#L55)），标识符的超长处理也是报
`identifier is too long`（[language-spec.md:60-61](../language-spec.md#L60-L61)）。预处理行是唯一
被漏掉的入口：`Lexer.h.ct:90-97` 的 T_PP 分支超出即丢字符、且不置 `toktrunc`
（标识符分支在 `Lexer.h.ct:108-110` 会置位），`Parser.h.ct:1313` 再把已经截断的文本用
`snprintf(…, MAX_TEXT, …)` 拷进 `Arena::Node.text`（`char text[160]`）。发射端只原样打印
（`Emitter.h.ct:1339`、`:545`），不是它吞的。坐标见修复单 DF-1。

**替代盘**：把宏压到 159 字节内（丢表达力，且必须人工数字节）；整体退回单文件 `ctc`——实测
`l1`/`l3`/`l4` 在 `ctc` 下 rc=0，长宏原样保留、`cc` 与运行都通过。代价是**失去多单元组织与增量
构建**（这正是 RILL 这次的兜底），且 `ctc` 不接受固有 `impl`（G-6 的实测），`namespace` / `pub`
/ `import` 也不可用。

**影响面**：所有用长宏的包；**超过 159 字节的 `#include` 路径**同理。后果分两档：截断点不合法 → `cc`
报错，但位置指向生成物；截断点合法 → 静默改变宏的语义（`l6`：6 变 3）。第二档没有任何诊断，
是本清单里唯一「`ct` 通过、生成文本与源码不一致」的 P0（G-4 是生成的逻辑错，不是文本截断）。

**放开的风险**：正确的修法是把预处理行改为源码切片存储（`(offset, len)`）并按切片发射，或至少
在越界时 `die`。前者动 `Arena` 节点表示与 prologue 去重，后者只把静默错误变成显式错误。
共同风险：此前「能过」的被截断代码会变成失败或产物变化，需要 release note；要重跑全部夹具
（`grep` 出 `test/` 里所有 `#` 行并量长度）、`--emit-c` 一致性与 `.m.ct` prologue 去重夹具。

---

## 9 核对后的修正

### 9.1 在 v0.44.1 上**复现不出来**的旧结论

这些结论出现在输入材料里（ct-json 三份评审、`modern-oo-gap.md`、更早的 issue），但在 v0.44.1 上
**不成立**。照抄会把它们当成待办。

| # | 旧结论（来源） | v0.44.1 实测 | 探针 |
| --- | --- | --- | --- |
| 1 | 带泛型字段的 struct 不能进 `.h.ct`，报 `expected a field name` / `field has incomplete type`（ct-json H-03 / P-03） | **部分不成立**：`pub struct Holder { Vec<int> v; }`、`Vec<int> *v`、`Vec<JsonRef> *arr` 三种都能导出（build rc=0）；只有 `Map<char *, 用户 struct>` 因 `MapEntry` 按值进共享头而失败——那是 **C-4**，不是导出问题 | `/tmp/ctgap/m/a3`、`a3b`、`/tmp/ctgap/j/j16`、`j10b` |
| 2 | 字段链接收者无法解析方法 trait（ct-json H-08 / P-13） | **部分不成立**：纯 struct 的字段链可用（`h.v->len()`、`o.in->v.len()`、`h.v->get(0)`、`o.obj->get("host")`）；**只有跨 union 成员**的字段链失败（`doc.root.v.obj->get(...)` → `cannot resolve the method trait`）。落局部即可绕开 | `b5`、`b5b`、`b5c`、`j1`、`j9`、`j7`、`j17` |
| 3 | 容器装不了接口值 / 装不了容器（`modern-oo-gap` §2.2，L29-13） | **可用**：`Vec<Show>` 能 push 接口值、`get` 回来能派发（`len=1 area=3`）；`Vec<Vec<int>>` push/get 正常（`len=1 back=1`） | `c2c`、`c1b` |
| 4 | `own` 写在返回类型会生成非法 C（`unknown type name 'own'`）（ct-json H-04 / P-07） | **编译期硬错**：`error: 'own' is only allowed inside a function body`，rc=1，不落 C | `g6` |
| 5 | `pub` 全局跨单元被丢弃（issue `ct-ast-pub-global-dropped`） | **可用**：`pub int LIMIT = 10;` 在 `.h.ct`，消费方 `return LIMIT;` 构建并返回 10 | `/tmp/ctgap/m/d3` |
| 6 | `struct Box<T: Show>` 泛型约束被拒（`modern-oo-gap` T3） | **可用**：声明、实例化 `Box<struct A>`、字段赋值与读回都过 | `g4b` |
| 7 | 非泛型固有方法 `impl P { … }` 被拒（`impl of an unknown trait`）（`modern-oo-gap` T4） | **可用**：`impl Box { int get(int i) … }` 被 `ct` 接受（`[]` 另见 F-1） | `f1b` |
| 8 | 同单元 Drop 胶水是空体、`delete` 等于 `free`（ct-json H-05 / P-08） | **显式 impl 会执行**：`delete n` 打印 `node drop 1`。空体只在「跨单元」（G-2）与「无字段可释放」两种情况下出现 | `g3b`、`g7` |

一句话：`v0.44.1` 里**容器、泛型约束、固有 impl、导出面**都比这些材料描述的强；真正还站着的是
**返回接口值的三条装箱路径**（B-1/B-3/B-4）、**链式/下标**（B-2/F-1）与**键/所有权**（E-2/E-4）。

### 9.2 规约 §4.10.1 的描述与 tag 不同步（文档问题，不计条目）

[language-spec.md:643-670](../language-spec.md#L643-L670) 的小标题写「**0.44.1 实测状态**」，但正文里
混入了 tag 之后的修复：

- 说「返回接口值的调用点推断已修（SH-72）」——`5ff69ac3`，晚于 `v0.44.1`；
- 说「`return self` 自 SH-74 起发射 `(void *)_self`」——`d6e82e25`，晚于 `v0.44.1`；
- 说「**仍未修**：impl 方法或自由函数返回局部接口值……」——`b5797cbf` 已修（SH-75），描述过期。

后果：读者按这段文字判断 `v0.44.1` 的实际能力会同时**高估**（以为 SH-72/74 已发）与**低估**
（以为 SH-75 仍未修）。建议该节标题改成「HEAD 实测状态」或按 tag 分段。**这不是语言缺口**，
单独列出是因为它会直接影响维护者的取舍判断。

### 9.3 环境陷阱：找不到 `lib/std` 会把泛型声明当比较表达式

把 `ct` 复制出安装布局（`~/.local/bin` 之外）后，单文件模式可能找不到 `lib/std`：此时
`Vec<int> v;` / `Map *m;` 会被误解析，前者报 `use of an undeclared variable`，后者**静默放行**并发射
`Map * obj;`（`cc` 才报 `unknown type name`）。设 `CT_STD_DIR=<repo>/lib/std` 后恢复正常诊断
（`generic struct 'Map' needs type arguments in a type position`）。

这不是语言缺口，但它是**外部评估方最容易踩的坑**：同一份探针在不同环境下会得出相反的结论
（ct-json 两席评审的 D-2 分歧就源于此）。建议安装脚本或 `ct -v` 输出里带上标准库搜索路径。

---

## 10 汇总表

> **状态口径（2026-11-15，v0.53.0）**：下表「版本状态」列为最新事实；各条正文保留提出时的
> 复现与绕法，作为历史证据，不再逐节回写。C-4 / E-2 / E-4 / F-1 / G-2 / G-3 / G-4 已由
> PH-46/47/48/49/52 收口，夹具见 `test/ast/24*` 与 `test/modules/p4*`。

| ID | 能力域 | 定性 | 卡住的项目 | 有无绕法 | 建议优先级 | 版本状态 |
| --- | --- | --- | --- | --- | --- | --- |
| A-1 | 单元模型 | 规范缺口 | ct-http、ct-pkg | 有（改形态） | P1 | HEAD `fb55985c` 已修 |
| A-2 | 单元模型 | 规范缺口 | 同上（布局） | 有 | P3 | 维持拒绝 |
| A-3 | 单元模型 | 规范缺口 | 多单元多命名空间包 | 有（alias） | P2 | 未修（SH-18） |
| B-1 | 派发与链式 | **实现缺陷** | ct-http | 0.44.1 无安全绕法 | P1 | HEAD `5ff69ac3` 已修 |
| B-2 | 派发与链式 | 规范缺口 | ct-http（一行链） | 有（多行） | P2 | 有意保留 |
| B-3 | 派发与链式 | **实现缺陷** | ct-http、所有 fluent setter | 无（UB） | P0 | HEAD `d6e82e25` 已修 |
| B-4 | 派发与链式 | **实现缺陷** | ct-json、ct-http 工厂 | 改形态（全局对象） | P0 | HEAD `b5797cbf` 已修 |
| C-1 | 泛型与容器 | 规范缺口 | 类型擦除层 | 有（写全实参） | P3 | 维持拒绝 |
| C-2 | 泛型与容器 | 规范缺口 | 所有容器调用点 | 有（记差异） | P2 | 未定义 |
| C-3 | 泛型与容器 | 规范缺口 | ct-json、解析器 | 有（先查 len） | P2 | 未定义 |
| C-4 | 泛型与容器 | **实现缺陷** | ct-json 对象节点、所有 `Map` 装记录的包 | 有（元素改指针） | P0 | 已修（PH-46，v0.46.0） |
| D-1 | 导出与常量 | 规范缺口 | ct-json | 有（`pub enum`） | P2 | 未定义 |
| E-1 | 值模型 | 规范缺口 | 数值/序列化包 | 有（显式检查） | P3 | Z5 既定 |
| E-2 | 值模型 | 规范缺口 | **ct-json（硬阻塞）** | **无等价绕法** | P1 | 已修（PH-47，v0.47.0；`Str` 键） |
| E-3 | 值模型 | 规范缺口 | tagged union 建模 | 有（命名 union） | P2 | 明文拒绝 |
| E-4 | 值模型 | 规范缺口 | 所有 `Map<char*,V>` | 有（自己复制） | P1 | 已修（PH-47，v0.47.0） |
| F-1 | 下标与转换 | 规范缺口 | ct-pkg、RILL | 有（方法调用） | P2 | 已修（PH-52，v0.52.0；方案 A 单层，`v[0]` 见 REQ-JSACCESS-1） |
| F-2 | 下标与转换 | 规范缺口 | 转换糖 | 有（函数） | P3 | 建议不做 |
| G-1 | 其他 | **实现缺陷** | ct-json（同名 encode） | 有（改名） | P2 | 未修 |
| G-2 | 其他 | **实现缺陷** | ct-http、多单元资源包 | 有（显式清理） | P1 | 已修（PH-48，v0.48.0） |
| G-3 | 其他 | 规范缺口 | ct-json、工厂 API | 有（手写 malloc） | P1 | 已修（PH-49，v0.49.0） |
| G-4 | 其他 | **实现缺陷** | JSON 树 / AST / 链表 | 有（手写 impl Drop） | P0 | 已修（PH-48，v0.48.0） |
| G-5 | 其他 | **实现缺陷** | RILL、相互递归类型 | 有（`struct T *` 拼写） | P2 | 未修 |
| G-6 | 其他 | 规范缺口 | RILL（C 书写习惯） | 有（删 `;`） | P3 | 未定义 |
| G-7 | 其他 | **实现缺陷** | RILL、多行长宏的包 | 勉强（拆宏 / 压一行） | P1 | 未修 |
| G-8 | 其他 | **实现缺陷** | RILL、所有长宏 / 长 `#include` 的包 | 有（压到 159 字节 / 退回 `ctc`） | P0 | 未修 |

---

## 11 探针附录

全部探针在 `/tmp/ctgap`（不在仓库内）。`bin/ct` 是 `~/.local/bin/ct` 的副本，`CT_STD_DIR` 指向仓库
`lib/std`。单文件探针在 `/tmp/ctgap/p/`，多单元探针在 `/tmp/ctgap/m/<id>/`。

### 11.1 单文件

| 探针 | 命令 | 原始结果 |
| --- | --- | --- |
| `a1_anon_union` | `ct a1_anon_union.ct -o a1.c` | `a1_anon_union.ct:6:7: error: an anonymous record member cannot have a name; tag the record instead`，rc=1 |
| `a2_bare_generic` | `ct a2_bare_generic.ct -o a2.c` | `a2_bare_generic.ct:3:9: error: generic struct 'Map' needs type arguments in a type position`，rc=1 |
| `b1_iface_ret` | `ct b1_iface_ret.ct -o b1.c` | `b1_iface_ret.ct:37:24: error: cannot infer the type to box`，rc=1 |
| `b2_tmp_receiver` | `ct b2_tmp_receiver.ct -o b2.c` | `b2_tmp_receiver.ct:22:1: error: method receiver must be a variable, an element, a call or a field chain`，rc=1 |
| `b3_self_ret` | `ct b3_self_ret.ct -o b3.c` + `grep '&_self'` | rc=0；`38: return (struct HttpRequest_iface){ (void *)&_self, &Req_HttpRequest_vtable };` |
| `b4_local_ret` | `ct b4.ct -o b4.c && cc b4.c -o b4 && ./b4` | rc 全 0；输出 `1 200`（期望 `0 201`）；生成 `return (struct Resp_iface){ (void *)&r, … };` |
| `b5_field_chain` | `ct` + `cc` + run | rc 全 0；返回 `h.v->len()` = 1 |
| `b5b_deep_chain` | 同上 | rc 全 0；`o.in->v.len()` = 1 |
| `b5c_field_generic` | 同上 | rc 全 0；`h.v->get(0)` = 4 |
| `b6_vec_get` | `ct` rc=0；`cc` | `b6_vec_get.c:336:16: error: initializing 'struct P *' with an expression of incompatible type 'struct P'` |
| `c1_nested_container` | `ct` + `cc` | rc 全 0（仅声明） |
| `c1b_nested` | `ct` + `cc` + run | rc 全 0；`len=1 back=1` |
| `c2_iface_container` | 同上 | 未零初始化时 rc=139；补 `memset` 后见 `c2c` |
| `c2c_iface_container` | 同上 | rc 全 0；`len=1 area=3` |
| `c4_oob_missing` | 同上 | `missing=0x0`、`oob=0` |
| `e1_numeric` | 同上 | `big=9007199254740992`、`inf=inf`、`ll=10000000000`、`i=14500960` |
| `e2_nul_key` | 同上 | `len=1 v1=2 v2=2` |
| `e2b_str_key` | `ct` | `e2b_str_key.ct:5:26: error: Map does not support key type 'struct Str' (use int, long or char *)`，rc=1 |
| `e4_sizeof` | 同上 | `sizeof=16 union=8` |
| `e5_key_copy` | 同上 | `key1=0x0 key2=0x1017d6fd8` |
| `f2_ptr_subscript` | 同上 | rc 全 0（C 指针算术，保持 Z3） |
| `f3_convert` | `cc` | warning `incompatible pointer types initializing 'char *' with an expression of type 'struct Ref *'`；rc=0 |
| `g1_overload` | `ct build g1.ct -o g1b` | warning `type mismatch: 'encode' argument 1` + `error: conflicting types for 'encode'`，rc=1 |
| `g2_own_return` | `ct` | `g2_own_return.ct:15:1: error: 'own' requires a malloc or calloc initialiser`，rc=1 |
| `g3b_drop` | `ct` + `cc` + run | rc 全 0；`node drop 1` / `done`（显式 impl 执行；`leaf` 由显式 impl 自负） |
| `g4b_generic_bound` | 同上 | rc 全 0；返回 3 |
| `g6_own_in_sig` | `ct` | `g6_own_in_sig.ct:7:1: error: 'own' is only allowed inside a function body`，rc=1 |
| `g7_field_glue` | 同上 | rc 全 0；`done`（无显式 impl 时胶水存在） |
| `g8_ptr_field_glue` | 同上 | rc 全 0；`leaf drop 22792752`、`done`；生成 `Leaf_Drop_drop(&_self->leaf);` |
| `f1b_inherent_subscript` | `ct` rc=0；`cc` | `f1b.c:170:13: error: subscripted value is not an array, pointer, or vector` |
| `j7_union_chain` | `ct j7.ct -o j7.c` | `j7_union_chain.ct:32:1: error: cannot resolve the method trait (unknown receiver type)`，rc=1 |
| `j9_struct_chain` | `ct` + `cc` + run | rc 全 0；输出 `7`（同深度、全 struct） |
| `j17_local_bind` | 同上 | rc 全 0；输出 `7`（跨 union 链落局部后可解） |
| `j5_int64` | 同上 | `ll=9007199254740993`（`long long` 保住 2^53+1） |
| `j6_str_nul` | 同上 | `len=3 3 cmp=-1`（`Str` 保住内嵌 NUL） |
| `e2b_str_key` | `ct` | `Map does not support key type 'struct Str' (use int, long or char *)`，rc=1 |
| `j4_builtin_subscript` | `ct` + `cc` + run | rc 全 0；生成 `Vec_int_get(&v, 0)` / `Map_char_p_int_get(&m, "k")` |
| `j8_vec_write` | `ct` | `a Vec subscript is read-only; use set(i, v)`，rc=1 |

### 11.2 多单元

| 探针 | 命令 | 原始结果 |
| --- | --- | --- |
| `a3` / `a3b` | `ct build src/main.ct -o out` | rc=0；生成头含 `#include "Vec.h"`、`struct Vec_int v;`（值/指针两种字段都过） |
| `a4` | 同上 | rc=0（`cfg::make` 工厂可调用；但内部返回局部，运行语义受 B-4 影响） |
| `a4b` | 同上 | `src/main.ct:6:14: error: no variable of that name in that namespace (qualified type names are not supported; …)`，rc=1 |
| `a5` | 同上 | `src/cfg/cfg.h.ct:5:21: error: a type host is only allowed in a .m.ct unit`，rc=1 |
| `d1` | 同上 | `src/main.ct:12:12: error: use of undeclared identifier 'JSON_TAG_NUM'`，rc=1 |
| `d2` | 同上 | rc=1（无 `namespace` 时 `cfg::Str` 报 `no variable of that name`） |
| `d2b` | 同上 | rc=0（裸名 `Num` 可用） |
| `d2c` | 同上 | rc=1（显式 `namespace cfg;` 后 `cfg::Str` 通过，裸函数调用改为需要 `cfg::tag_num()`） |
| `d3` | 同上 + run | rc=0；`pub int LIMIT = 10;` 可跨单元，返回 10 |
| `d4` | 同上 + run | rc=0；只输出 `done`（Drop 体未执行） |
| `m1` | `ct build src/main.ct -o out [-I src]` | 无 `-I`：`ctc: cannot resolve import 'http/http'`；有 `-I`：`src/api/api.m.ct:1:1: error: a .m.ct unit can only import another .m.ct unit`，rc=1 |
| `j10b`（C-4） | `ct build src/main.ct -o out` | `.ctbuild/Vec.h:31:20: error: field has incomplete type 'struct JsonRef'`，rc=1 |
| `j14b` / `j15b`（C-4 绕法） | 同上 | rc=0；`Map<char *, JsonRef *>`、`Map<char *, void *>` 均可编译并运行 |
| `j16`（`Vec<JsonRef> *` 导出） | 同上 | rc=0；run rc=0（Vec 侧可导出） |
| `j2`（树类型进 `.h.ct`） | 同上 | 与 `j10b` 同根因：`field has incomplete type` |
| `j3`（`pub enum` 进 `.m.ct`） | 同上 | `a .m.ct unit cannot declare a type`，rc=1 |

### 11.3 RILL 四条（`/tmp/ctgap3`，`ct v0.44.1`，`CT_STD_DIR=<repo>/lib/std`）

| 探针 | 命令 | 原始结果 |
| --- | --- | --- |
| `l1_typedef`（G-5） | `ct l1_typedef.ct -o l1.c` | `l1_typedef.ct:1:21: error: unexpected token`，rc=1 |
| `l1_typedef`（build） | `ct build l1_typedef.ct -o out` | `l1_typedef.ct:1:1: error: unexpected token`，rc=1 |
| `l1b_struct_fwd`（G-5 绕法） | `ct` + `cc` + run | rc 全 0（`struct JVal;` 前向声明可用） |
| `l1c_typedef_body`（G-5 绕法） | 同上 | rc 全 0（`typedef struct JVal { … } JVal;` 可用） |
| `l1d_mutual`（G-5 绕法） | 同上 | rc 全 0（两个类型互相引用，写 `struct B *`） |
| `l2_impl_semicolon`（G-6） | `ct l2.ct -o l2.c` | `l2_impl_semicolon.ct:9:2: error: expected a type (tok 4 ';')`，rc=1 |
| `l3_macro_continuation`（G-7） | 同上 | `l3_macro_continuation.ct:2:6: error: expected a type (tok 4 '(')`，rc=1 |
| `l4_long_macro`（G-8） | `ct l4.ct -o l4.c` | rc=0；生成 C 第 11 行 159 字节（源 510）；`cc` → `l4.c:156:13: error: expected expression`，rc=1 |
| `l4_long_macro`（build） | `ct build l4.ct -o out` | `ct` 侧 rc=0，`cc` 侧 rc=1（报错经 `#line` 映回源文件 1:155） |
| `l5_num_macro`（G-8） | `ct` + `cc` | `ct` rc=0；`cc`：`integer literal is too large to represent`（截断成 159 位数字） |
| `l6_valid_trunc`（G-8，静默改行为） | `ct` + `cc` + run | rc 全 0；返回 `3`（源码语义 `6`；`* 2` 落在第 160 字节后被丢） |
| `ctc` 对照（G-5/G-7/G-8） | `ctc <file>.ct -o <file>.c` | `l1`/`l3`/`l4` rc=0；`l4` 生成物保留 510 字节宏，`cc` + run rc=0 |
| `ctc` 对照（G-6） | 同上 | `l2_impl_semicolon.ct:5:8: error: expected 'for' in impl of 'J'`，rc=1（L0 不接受固有 impl） |

---

## 12 事实与推断的边界

- **事实**：§2–§8 的「当前行为」全部来自 §11 的实测，或明确标注的提交/夹具/规约原文；
  G-5–G-8 的四条另由 §11.3 的 `l1`–`l6` 与 `ctc` 对照支撑（`ct v0.44.1`，2026-11-15 重跑）。
- **推断（需证据确认）**：
  1. A-1 放开后「构建产物顺序不变、缓存键稳定」——来自 `fb55985c` 的提交说明与 SH-71 记录，
     **本文未重跑 HEAD**（工作区 `selfhost/` 由另一会话占用）。要确认需在干净 clone 上跑
     `bash selfhost/check-all.sh`。
  2. B-1/B-3/B-4 在 HEAD 上的行为——依据是提交 diff 与夹具（`238_iface_ret_value`、
     `237_iface_ret_self`、`239_local_iface_return`），**未在本机重跑**。要确认需构建 HEAD 并跑三条夹具。
  3. G-2 的修法代价（`extern` vs 空桩）——本文只给出候选，没有做原型；`--lib` 与符号可见性的
     交互需要单独评估。
  4. E-2 的「键协议」工作量——未做原型；`Map` 生成物与既有 125 条 golden 的迁移面未估。
- **本文不主张的事**：
  - 不主张 ct-json / ct-http 的任何具体 API 形态（路径查询、流式编码、视图 vs 树，都是包的选择）。
  - 不主张任何 phase 编号；`REQ-L1` 仍在需求池，本文不改它的状态。
  - 不主张「这些缺口都应该补」——§10 的 P3 条目（C-1、E-1、F-2、A-2）本文的建议是**不做**。
