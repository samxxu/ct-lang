# 裁判（EDITOR）：九条能力缺口的定性

> 基线：仓库 HEAD `3337ac7a`（v0.53.1）。行为探针用 `~/.local/bin/ct` v0.53.0 在 `/tmp` 下跑；
> v0.53.0 与 v0.53.1 的差异只有 LANG-1 / LANG-2 两处解析修复，不涉及本轮的九条。
> 判定口径：**A = 既有承诺未兑现（bug）**；**B = 从未支持（需求）**；**C = 明确不做（设计拒绝）**；
> **D = 主张不成立（已支持或文档旧句）**。每条必须给「原文 + 位置」；没有原文的一律不判 A。

## 0 结论先行

| # | 条目 | 判定 | 一句话 | Issue |
| --- | --- | --- | --- | --- |
| 1a | `.h.ct` 内 `pub const` 标量 / 数组 / struct 值 + 跨单元引用 | **D 已支持** | 三种常量都通过，消费方 `ns::K` / `ns::ARR[1]` / `ns::P.a` 读到 `14` | 无 |
| 1b | 同名 `.h.ct` + `.ct` 的 C 式分离 | **A bug** | 两个单元共用 `.ctbuild/<base>.c`，实现单元不自动编译，手加入参即 `duplicate symbol` | **LANG-11（新建）** |
| 1c | namespace 下的 `.h.ct` 声明 + `.ct` 定义 | **B 需求** | `extern` 按设计不 mangling（指向 C 库），与 namespace 定义的 `ns_K` 对不上 | 归并行会话 |
| 2 | `FsErrCode::FS_ERR_NOT_FOUND` | **B 需求** | `ns::FS_ERR_NOT_FOUND` 已可用；enum 类型作用域从未承诺，诊断文案误导 | 归并行会话；参 SH-18 |
| 3 | `ct install` 只发 `-I vendor/<包名>`，`src/<ns>/` 无法 import | **C 设计拒绝（现状契约）** | 包指南写死「包根 = 单元根」，`src/` 是布局选择；支持它是 PKG-2 需求 | PKG-2 / LANG-6（既有） |
| 4 | 自定义类型属性访问 `doc.server.host` | **B 需求** | 仓库只给 `union` + tag + `.v.i` 的写法，没有属性协议 | **LANG-12（新建）** |
| 5a | 单一 `get(char *)` 时 `v[0]` 静默空值 | **A bug（静默）** | 编译通过、运行返回「缺键」，无诊断；规约 D52-6 已承认，REQ-JSACCESS-1 已承诺硬错 | LANG-4（既有） |
| 5b | `get(char *)` 与 `get(int)` 并存 | **B 需求** | C 无重载；`REQ-JSACCESS-1` 已承诺并存，需内部名 mangling | REQ-JSACCESS-1；LANG-4 |
| 6a | 同类型三级下标链 `doc["a"]["b"]["c"]` | **A bug（声称已修，待验证）** | 物化深度只允许一层；LANG-13 声称 v0.53.1 已修，但 `test/ast/263_index_chain3` 在本轮工作树中不存在 | LANG-13（既有） |
| 6b | 固有方法结果作接收者（含 `doc["server"].has(k)`） | **A bug（修复在途，待验证）** | 非泛型固有方法结果没有静态类型；LANG-5 / `JSON-2` 正在 TypeCheck 修，尚未提交 | LANG-5（既有，`JSON-2`） |
| 6c | 下标结果取字段 `b["k"].v` | **A bug（静默，open）** | 没守卫，发射 `Box_get(&b,"k").v` 交 `cc` | LANG-5（既有） |
| 6d | trait 动态派发 `a.m().n()` | **C 设计拒绝** | SH-73 定性「有意的实现边界」；LANG-5 明确「SH-73 不动」 | SH-73 |
| 7a | `doc["port"] + 1` 运算符协议 | **C 设计拒绝** | 「明确不做」清单含运算符重载 | modern-oo-gap §6.3 |
| 7b | `printf("%s", ref)` 格式化协议 | **C 设计拒绝** | 规约写明格式串与实参匹配由用户负责，与 C 一致 | spec:1209 |
| 8a | `for (e in arr)` | **C 设计拒绝** | D27-4 明确不做 `in` 形式 | spec:2249-2250 |
| 8b | 「foreach 只接受一维 C 数组」 | **D 主张不成立** | 现状已覆盖数组 / `Vec` / `Map`；旧句是文档缺陷 | spec:2367-2370 |
| 9a | 字符串字面量到 `Str` 的隐式转换 | **C 设计拒绝** | `Str` 只有显式 `str_from`；无隐式转换条款 | spec:2492；F-2 |
| 9b | `char *` 传 `Str` 的诊断级别 | **A bug（声称已修，待验证）** | C 必然拒绝的 struct 形态却只报 warning；LANG-14 声称 v0.53.1 升 error，但 `test/ast/264_struct_arg_mismatch` 未在仓库中找到 | LANG-14（既有） |

**总裁定**：9 条里没有一条是「整条都没实现」。真正落在 **A（bug）** 的有六处：
**同名 `.h.ct` / `.ct` 产物冲突（1b，open）**、**数字下标静默空值（5a，open）**、
**同类型三级下标链（6a，LANG-13 声称已修，待验证）**、**固有方法结果作接收者（6b，LANG-5 / JSON-2 修复在途）**、
**下标结果取字段静默坏 C（6c，open）**、**`char *` 传 `Str` 只报 warning（9b，LANG-14 声称已修，待验证）**。
其余是「已支持但主张写错了」（1a / 8b）、「从未承诺的新需求」（1c / 2 / 4 / 5b）、
「明文拒绝的设计」（3 / 6d / 7 / 8a / 9a）。

> **修复状态的证据边界**：LANG-13 / LANG-14 的 issue 正文写「已修（v0.53.1 工作树）」，
> 但本轮在仓库里只找到 `test/ast/262_inherent_mcall_receiver`（LANG-5 的回归），
> 找不到 LANG-13 提到的 `test/ast/263_index_chain3`、LANG-14 提到的 `test/ast/264_struct_arg_mismatch` /
> `test/ast/errors/struct_arg_from_charptr.ct`。因此本判决只承认「issue 声称已修」，
> 不把它当已验证事实；待对应夹具与实现一起提交后，再按实测改判。

---

## 1 逐条裁定

### J-1 namespace 常量

**1a. `.h.ct` 内直接定义 + 跨单元引用：D（已支持）。**

```ct
/* ns/cfg.h.ct */
namespace ns;
pub struct Pair { int a; int b; };
pub const int K = 5;
pub const int ARR[3] = { 1, 2, 3 };
pub const Pair P = { 7, 8 };

/* app/main.ct */
import ns::cfg;
int main(void) { return ns::K + ns::ARR[1] + ns::P.a; }
```

实测 `ct build -I . app/main.ct -o out` rc=0，`./out` 退出码 `14`（`5 + 2 + 7`）。
生成头含 `extern const int ns_K;` / `extern const int ns_ARR[3];` / `extern const struct ns_Pair ns_P;`，
定义在对应 `.c`。这条由 [language-spec.md:774-775](../../docs/language-spec.md#L774-L775)
（`pub` 全局定义 / `extern` 导出）与 [:783-785](../../docs/language-spec.md#L783-L785)
（namespace mangling 与限定名引用）直接覆盖。**主张席「namespace 内定义常量不可用」不成立。**

**1b. 同名 `.h.ct` + `.ct`：A（bug）。**

单元表把 `.ct` 定义为「实现 / 入口；接口写在同目录的 `.h.ct`」
（[language-spec.md:616](../../docs/language-spec.md#L616)）。实测：

```console
$ ct build -I . app/main.ct lib/cfg.ct -o out
'cc' ... '.ctbuild/main.c' '.ctbuild/cfg.c' '.ctbuild/cfg.c' '-o' 'out'
duplicate symbol '_K' in:
    .../cfg-a54c9a.o
    .../cfg-8b58ac.o
rc=1
```

两个入参映射到同一个 `.ctbuild/cfg.c`：`.h.ct` 的生成物先被 `.ct` 的生成物覆盖，
`cc` 行又同时列入两次。只 `import cfg` 时不会自动编译同目录 `.ct`，链接期报 `_K` 未定义。
这是工具层的单元配对缺陷，与 namespace 无关；**判 A**，登记为 **LANG-11**。

**1c. namespace 下的 `.h.ct` 声明 + `.ct` 定义：B（需求）。**

`pub extern const int K;` 在 `namespace ns;` 里生成 `extern const int K;`（不 mangling），
而 `namespace ns;` 的 `.ct` 定义发射 `ns_K`。消费者写 `ns::K` 在解析期就报
`no variable of that name in that namespace`；写裸 `K` 能过解析，但链接期 `_K` 未定义。
根因是规约把 `extern` 定义为「指向 C 库的符号、不参与 mangling」
（[language-spec.md:778-779](../../docs/language-spec.md#L778-L779)），
它从未承诺「CT 侧头声明 + 实现定义」的分离。**判 B**；登记归并行会话（namespace 常量/限定名），
本轮不抢号。

**最小修法与影响面（1c，若未来做）**：先裁定 `pub extern` 在 namespace 内是否按命名空间 mangling。
若支持分离，符号表要把 `pub extern` 登记成 `ns_K`（而不是空命名空间），`.h` 发 `extern const int ns_K;`，
`.ct` 定义发 `const int ns_K = 5;`；代码生成只改声明名；ABI 会改变已发布 `pub extern` 的 C 符号名，
必须跟语言版本说明；既有「指向 C 库」的 `extern` 保持不 mangling（需要一个显式区分语法，如 `pub extern "C"`）。
**回归断言**：`.h.ct` 只声明 + `.ct` 定义时 rc=0、`ns::K` 读到 5；未加 `pub` 的 `.ct` 定义不进头；
C 库 `extern` 用例零回归。

**最小修法与影响面（1b）**：给 `.h.ct` 与 `.ct` 的产物分配不同路径（例如
`.ctbuild/<base>.c` 与 `.ctbuild/<base>_impl.c`），或在 `import <h.ct>` 时按同 base 自动带上 `.ct`。
不动符号表；不动 ABI；既有 `.h.ct` 单文件的产物路径不变，只影响「同 base 双单元」这一种组合。
**回归断言**：两单元工程 `ct build` rc=0，`cfg.h` 含 `extern const int ns_K;`，
`cfg_impl.c` 含 `const int ns_K = 5;`，消费者 `ns::K` 读到 5；`cc` 行中每个 `.c` 只出现一次。

### J-2 限定名取值 `FsErrCode::FS_ERR_NOT_FOUND`

**裁定：B（从未支持，需求）；不是 bug。**

实测三种写法（`namespace ns; pub enum FsErrCode { FS_ERR_NOT_FOUND = 1 };`）：

| 写法 | 结果 |
| --- | --- |
| `ns::FS_ERR_NOT_FOUND` | **rc=0**（namespace 限定 enum 成员可用） |
| `FsErrCode::FS_ERR_NOT_FOUND` | `error: no variable of that name in that namespace (qualified type names are not supported; use the bare name or an alias import)` |
| `ns::FsErrCode::FS_ERR_NOT_FOUND` | 同上 |

规约只承诺「enum 成员的 namespace mangling」与「限定名 `app::High`」
（[language-spec.md:905-908](../../docs/language-spec.md#L905-L908)），没有承诺 **enum 类型作用域**。
C 也没有 `Enum::Member`；这是 C++ 风格的新语法。SH-18 只覆盖「类型位置的 `A::B`」
（[ct-ast-qualified-type-name-rejected.md:11-55](../../issues/selfhost/ct-ast-qualified-type-name-rejected.md#L11-L55)），
不覆盖值位置。**判 B**，登记归并行会话；本轮只补一条诊断建议：值位置遇到 `Type::Member` 时
不要复用「qualified type names」文案，应报「`FsErrCode` 是类型，成员访问请写 `ns::FS_ERR_NOT_FOUND`
或改用 `ns::FsErrCode` 作 namespace」。

**最小修法与影响面**：在 `parse_primary` 的限定名分支里，若首段是已注册的 enum 标签，
把 `Member` 解析为 `<enum C 名>_<Member>`（enum 成员已按全局常量登记，见
[language-spec.md:905](../../docs/language-spec.md#L905)）。符号表只多一条「类型名 → enum 标签」判别；
代码生成不变；ABI 不变。**回归断言**：`return FsErrCode::FS_ERR_NOT_FOUND;` 编译并返回 `1`；
未知成员报错且不落 `.c`；`ns::FS_ERR_NOT_FOUND` 零回归。

### J-3 包形态：`ct install` 只发 `-I vendor/<包名>`

**裁定：C（现状契约如此）；「工具缺陷」不成立；`src/` 支持是需求 PKG-2。**

包指南开头就把「包根」定死：「包仓库的**根目录就是包根**：`ct.pkg`、`LICENSE` 与源码单元并列，
不嵌套子目录」（[package-guide.md:16](../../docs/package-guide.md#L16)）；命名空间单元的位置是
`<包根>/a/b/`，不是 `<包根>/src/a/b/`
（[package-guide.md:42-43](../../docs/package-guide.md#L42-L43)）。按这个契约，`-I vendor/<包名>`
正是正确的 include 根；`src/<ns>/` 是包作者自己的布局选择，需要消费者自己加 `/src`。
PKG-2 已经把「让 `src/` 成为合法布局」登记为需求（`ct.pkg` 的 `include =` / 自动探测 / 强制包根三选一），
并明确「未来处理，不阻塞当前相」
（[pkg-2:100-118](../../issues/packages/pkg-2-ct-install-package-root-import.md#L100-L118)）。
**所以：包布局必须迁就现状；若生态要统一 `src/`，走 PKG-2 的裁定，不是修 `ct install` 的 bug。**

**最小修法与影响面**：不改编译器。二选一：在 `package-guide.md` 的 §1 加一句「`src/<ns>/` 不在契约内，
消费方需自加 `-I vendor/<pkg>/src`」；或采纳 PKG-2 方案 1（`ct.pkg` 增 `include =`），
只动 `Pkg.h.ct` 的打印与 `ct.lock` 的 include 根记录，不动 import 解析器。
**回归断言**（若采纳 PKG-2）：`ct install` 输出含 `-I vendor/<pkg>/src`，照抄执行 rc=0；
未声明 `include` 的包仍输出包根，零回归。

### J-4 自定义类型属性访问 `doc.server.host`

**裁定：B（从未支持，需求）；不是 bug。**

仓库里没有任何「属性访问协议」条款。bindings 的基线写法是 `union` + `int tag`，
访问写 `p->tag` / `(*p).v.i`（[bindings-and-patterns.md:10-47](../../docs/bindings-and-patterns.md#L10-L47)）；
`?.` 只做**字段**访问（[language-spec.md:2652-2667](../../docs/language-spec.md#L2652-L2667)），
`into` 只做块内字段赋值（[:2375-2390](../../docs/language-spec.md#L2375-L2390)）。
`doc.server` 在 C 语义下就是「`JsonRef` 的 `server` 字段」，字段不存在时 `cc` 报
`no member named 'server' in 'struct JsonRef'`；CT 不检查成员存在性（Z5），所以 `ct` 放行。
这是 C 的字段规则，不是「属性协议没实现」。**判 B**，登记为 **LANG-12**。

**最小修法与影响面**：语言层若要做，最小形态是「声明了 `get(char *)` 协议的类型，把 `.name`
脱糖为 `get("name")`」，复用 PH-52 的 `N_MCALL` 路径；需要（a）类型信息判断接收者是否声明了 `get`，
（b）与真实字段同名的歧义规则（字段优先），（c）`a.b.c` 的逐跳物化（与 J-6 同源）。
符号表需保留「类型 → 是否有 get」；代码生成只多 `T_get(&recv, "name")`；ABI 不变；既有字段访问零改动。
**更小的替代**：库层提供 `json_at(doc, "server")` / `json_obj(doc).get("server")`，
调用点写 `json_get(doc, "server.host")`；不动语言。**回归断言**（若做语言层）：
`doc.server.host` 编译并返回预期字符串；真实字段 `doc.kind` 仍走字段；无 `get` 的类型报错并提示 `get`。

### J-5 无重载 / 无按键类型分派

**5a. 单一 `get(char *)` + `v[0]` 静默空值：A（bug，静默）。**

实测：`struct J { int n; } impl J { char *get(char *k) {...} }` 后 `j[0]` 发射为 `J_get(&j, 0)`，
`ct` rc=0，`cc` 零告警，运行返回 `"empty"`（缺键分支）。这与「编译通过、运行给错值」的静默错误定义一致；
LANG-4 已按 High 登记（[lang-4:11-16](../../issues/lang/lang-4-subscript-type-mismatch-silent-empty.md#L11-L16)、
[:47-55](../../issues/lang/lang-4-subscript-type-mismatch-silent-empty.md#L47-L55)）。
规约把这个行为写成「已知洞（D52-6）」
（[language-spec.md:2646-2648](../../docs/language-spec.md#L2646-L2648)），但同一份规约在
`REQ-JSACCESS-1` 里承诺了修法；「已知」不等于「不是缺陷」。**判 A**，沿用 LANG-4。

**5b. `get(char *)` 与 `get(int)` 并存：B（从未支持，需求）。**

实测：

```console
a.ct:17:36: error: conflicting types for 'J_get'
a.ct:17:36: note: previous definition is here
```

C 没有重载，CT 也没有重载条款；两个方法都发射同名 `J_get`。`REQ-JSACCESS-1` 已把
「同一类型可并存 `get(char *)` 与 `get(int)`，`v["k"]` 与 `v[0]` 各选其版」写成 P1 / open
（[requirements-pool.md:76-82](../../docs/planning/requirements-pool.md#L76-L82)），
`REQ-INDEX-1` 进一步把借用形态与写形态列入（[:110-116](../../docs/planning/requirements-pool.md#L110-L116)）。
这是**新需求**，不是 bug；但「同名定义不在定义处硬错、拖到 cc」这一层是既有 G-1 的实现缺陷
（[language-capability-gaps.md:1028-1056](../../docs/proposals/language-capability-gaps.md#L1028-L1056)），
应顺手在定义处报硬错。

**最小修法与影响面（5a）**：在 `custom_index_method` 选方法时把「名 + 参数个数」升级为
「名 + 实参静态类型 × 形参类型」；无候选时硬错并列出可用 `get`。符号表需保留方法的参数类型；
代码生成不变（仍发射 `T_get(&recv, arg)`）；ABI 不变；既有单 `get` 工程零改动，但错误面从
「静默空值」变成「编译期硬错」，需要新增负例夹具并重跑相关 golden。
**回归断言**：`v[0]` 在只有 `get(char *)` 时 rc=1、文案列出 `get(char *)`、不写 `.c`；
`v["k"]` 仍 rc=0；`v[0]` 在 `get(int)` 存在时选中 `get(int)`。

**最小修法与影响面（5b）**：先做 5a 的「实参类型匹配 + 无候选硬错」，再做并存：
方法表按 `(name, 参数类型序列)` 建键，发射内部名（如 `J_get_str` / `J_get_int`），
调用点按实参静态类型选名；源级 `get` 不变。符号表要存参数类型；代码生成多一层内部名；
ABI 新增符号（对已发布包是破坏性，需要版本说明）；既有测试只覆盖单 `get`，需新增双 `get` 夹具。
**回归断言**：`j["k"]` 与 `j[0]` 分别调用两个实现并返回不同值；只有 `get(char*)` 时 `j[0]` 硬错并列出候选；
同名同参重复定义在定义处硬错（G-1）。

### J-6 临时值作接收者

先拆形态：**同类型下标链**、**一般方法结果**、**下标结果取字段**、**下标结果调方法**是四条不同的路径，
不能用一个「临时值」标签一锅端。

**6a. 同类型三级下标链 `doc["a"]["b"]["c"]`：A（bug，LANG-13 声称已修，待验证）。**

实测（v0.53.0）：

```console
a.ct:8:1: error: a method call on a temporary is only allowed at the start of a statement or of an assignment
```

LANG-13 已把根因定到发射器的 `hoist_scan`：每个 `[k]` 展开成 `N_MCALL`，两级以内物化一层接收者即可，
三级需要级联物化，而 `hoist_scan` 只允许语句表达式根（`top == 1`）那一层物化
（[lang-13:36-51](../../issues/lang/lang-13-three-level-subscript-chain.md#L36-L51)）。
它明确与 LANG-5 拆开：LANG-13 是物化**深度**，LANG-5 是 `expr_type` 对方法结果失明
（[:43-51](../../issues/lang/lang-13-three-level-subscript-chain.md#L43-L51)）。issue 状态写「**已修**（v0.53.1 工作树）」
（[:8](../../issues/lang/lang-13-three-level-subscript-chain.md#L8)），但本席在仓库里找不到它引用的
`test/ast/263_index_chain3`，所以只记为「声称已修」。**判 A**，不是 SH-73 的方法结果边界；
本轮只需引用，不重复开号。

**最小修法与影响面（6a）**：LANG-13 的方案是让 `hoist_scan` 允许级联物化，`emit_hoists` 按内层先于外层
顺序发射 `__ct_tmpN`。符号表多临时变量；代码生成改物化链；ABI 不变；既有两级链与单级链零回归。
**回归断言**：`doc["a"]["b"]["c"]` 在声明初始化 / 赋值右值位置 rc=0 并返回句柄；
二元表达式内部仍按既有规则拒绝；`test/ast/263_index_chain3` 与 `errors/index_chain3_bin.ct` 一正一负
（夹具落地前不计通过）。

**6b. 固有方法结果作接收者（含 `doc["server"].has(k)`）：A（bug，修复在途，待验证）。**

LANG-5 把 `f().m()` 与 `b["k"].m()` 归为形态 1/2，根因是 `TypeCheck::inst_method_ret` 只认泛型实例，
非泛型固有 `impl` 的方法结果没有静态类型，后续 `.m()` 解析不到固有方法，落到 trait 分支后被
接收者白名单拒绝（[lang-5:62-70](../../issues/lang/lang-5-result-as-receiver.md#L62-L70)）。
`JSON-2`（`doc["server"].has(k)`）与它是同一根因，已合并进 LANG-5
（[lang-5:12-14](../../issues/lang/lang-5-result-as-receiver.md#L12-L14)）。
本轮工作树里能看到 `selfhost/ct-ast/frontend/type/TypeCheck.h.ct` 与
`test/ast/262_inherent_mcall_receiver` 的在途改动，但**尚未提交**；本席用 v0.53.0 复跑仍是旧报错。
**判 A**，不再按 SH-73 的 C 处理——SH-73 只保留给 **trait 动态派发**（见 6d）。

**最小修法与影响面（6b）**：LANG-5 的方案是让 `inst_method_ret` 在无实例行时扫描非泛型固有 `impl`，
直接读声明返回类型（`struct` 前缀补全，与 `static_ctype` 同形）。符号表要存非泛型固有方法的返回类型；
代码生成不变（仍是 `T_m(&tmp, ...)`）；ABI 不变；trait 动态派发路径不动，`test/ast/errors/temp_receiver_trait_chain.ct`
仍需报错。**回归断言**：`doc.get(2).get(4)` 与 `doc[3].has(3)` rc=0；`a.m().n()`（trait）仍硬错；
`doc["k"].v`（字段形态）仍按 6c 处理，不得被这次修复顺手放开。

**6c. 下标结果取字段 `b["k"].v`：A（bug，静默，open）。**

`b["k"]` 已展开为 `Box_get(&b,"k")`，随后 `.v` 直接按成员处理，发射
`Box_get(&b,"k").v`；`ct` rc=0，`cc` 才报「member reference base type 不是结构体」。
规约 §4.64 的「范围外」写的是「`x[k].field = v`、`x[k].m()` 在编译期报错（不落 `cc`）」
（[language-spec.md:2649](../../docs/language-spec.md#L2649)），读形态 `x[k].field` 只是没被那句字面覆盖，
但同属「成员跳转」的承诺。LANG-5 已登记并明确「方法硬错、字段静默」的不一致
（[lang-5:22-23](../../issues/lang/lang-5-result-as-receiver.md#L22-L23)、
[:52-56](../../issues/lang/lang-5-result-as-receiver.md#L52-L56)）。**判 A**，沿用 LANG-5。

**最小修法与影响面（6c，小）**：在 `[` 后缀产出 `N_MCALL` 后、`.field` 解析前加一条守卫：
接收者是临时 `N_MCALL` 且不是可回溯左值时，报与 LANG-5 方法形态同一句文案并给「先落变量」提示。
不动 Emitter 的物化逻辑；不改既有通过形态；`cc` 面的坏 C 提前成 `ct` 错。
**回归断言**：`b["k"].v` 编译期硬错、退出 1、不写 `.c`；`JsonRef t = b["k"]; t.v` 通过；
`b["k"].twice()` 走 6b 的通过路径（不是字段形态）。

**6d. trait 动态派发 `a.m().n()`：C（明确不做，SH-73 保持）。**

SH-73 定性为「**有意的实现边界**」，理由是「不会静默产出坏 C」，并给出 100–300 行、
会改既有生成物、需要重跑 golden 的代价（[sh73:59-69](../../issues/selfhost/sh73-temp-receiver-dynamic-dispatch.md#L59-L69)、
[:80-93](../../issues/selfhost/sh73-temp-receiver-dynamic-dispatch.md#L80-L93)）。
LANG-5 在修 6b 时明确「**SH-73 不动**：trait 动态派发的 `a.m().n()` 仍拒绝」
（[lang-5:66-67](../../issues/lang/lang-5-result-as-receiver.md#L66-L67)）。
规约把「接收者是一次方法调用当前一律拒绝」写进 0.44.1 的逐段实测与现状约束
（[language-spec.md:738-740](../../docs/language-spec.md#L738-L740)、
[:762-763](../../docs/language-spec.md#L762-L763)）。**判 C**；用户可用逐跳落变量或静态宿主链。

**最小修法与影响面（6d，若未来做）**：在 Emitter 里把接收者表达式物化为 `__ct_tmpN`，再把下一跳改成
对临时变量的调用/字段访问；需要决定 hoist 位置（语句起点 / 赋值起点）与临时值生命周期，
100–300 行，改既有生成物并重跑 golden；符号表只多临时变量；ABI 不变。**回归断言**：
`a.m().n()` 编译并返回预期值；求值顺序与「先落变量」写法一致；原有拒绝用例改成通过，
需要同步改 SH-73 的边界。

### J-7 运算符与格式化协议

**7a. `doc["port"] + 1`：C（明确不做）。**

`modern-oo-gap.md` §6.3 的「明确不做（判据，不是偏好）」清单含「运算符重载（`into` 是脱糖例外）」
（[modern-oo-gap.md:339](../../docs/modern-oo-gap.md#L339)）；
`REQ-INDEX-1` 的范围外也写「不做其它运算符重载（`+` / `==` / `()`）」
（[requirements-pool.md:133](../../docs/planning/requirements-pool.md#L133)）。
实测 `invalid operands to binary expression ('struct JsonRef' and 'int')` 是 C 对 struct 的规则。
**判 C**；不排期。

**7b. `printf("%s", ref)`：C（明确不做，用户负责）。**

规约：「`printf` 的格式串与实参类型匹配由用户负责，与 C 一致」
（[language-spec.md:1209](../../docs/language-spec.md#L1209)）。实测 `ct build` rc=0，
clang 给一条 `-Wformat` warning（`format specifies type 'char *' but the argument has type 'struct JsonRef'`），
运行输出按 UB 处理。CT 不解析格式串，这是设计边界；若要收，只能走 `ct check --types` 的 opt-in
格式串检查（新需求），不是修 bug。**判 C**。

**最小修法与影响面**：不修。若未来做运算符协议，需要新的 AST 节点/类型分派与 ABI 约定，
属 L 级；若只做格式串检查，放在 `ct check --types`，不动默认编译，M 级。
**回归断言**（若做格式串检查）：`ct check --types` 对 `%s` + struct 报错、退出 1；
默认 `ct build` 行为不变。

### J-8 容器迭代协议

**8a. `for (e in arr)`：C（明确不做）。**

实测 `a.ct:4:16: error: unexpected token`。§4.49 的「不做（D27-4）」明列「`in` 形式、显式绑定名、
迭代器、容器协议」（[language-spec.md:2249-2250](../../docs/language-spec.md#L2249-L2250)）。
**判 C**；`foreach` 是既定写法。

**最小修法与影响面（8a，若未来做）**：在 parser 把 `for (T e in expr)` 脱糖成 `foreach (expr)` +
绑定名；只动 AST/解析，不动代码生成；ABI 不变；需处理与 C `for` 的歧义（看 `in` 关键字）。
**回归断言**：`for (int e in a)` 与 `foreach (a)` 等价；`for (int i = 0; ...)` 零回归。

**8b. 「foreach 只接受一维 C 数组」：D（主张不成立，文档旧句）。**

§4.51 的容器协议写的是「数组与 `Vec` 同时绑定 `item` 与只读 `i`；`Map` 只绑定 `item`」
（[language-spec.md:2367-2370](../../docs/language-spec.md#L2367-L2370)）；
教程 10.8 与 `modern-oo-gap` §3.7 也写「数组 / `Vec` / `Map`」
（[tutorial.md:1343-1399](../../docs/tutorial.md#L1343-L1399)、
[modern-oo-gap.md:195](../../docs/modern-oo-gap.md#L195)）。实测 `foreach (Vec<int>)` rc=0。
§3 的语法总览也写「数组、`Vec`、`Map`」（[language-spec.md:148](../../docs/language-spec.md#L148)）。
**只有 §4.49 开头那句「在一维数组上迭代」是旧句**，属文档缺陷；若用户观察到仅数组，需核对版本（v0.53.x 已覆盖容器）。
**动作**：改 §4.49 的旧句，指向 §4.51 的容器协议；不改实现。

### J-9 字符串字面量到 `Str`

**9a. 隐式转换：C（明确不做）。**

`Str` 的 API 是显式 `str_from(s)` / `str_from_len(p,n)`
（[language-spec.md:2492](../../docs/language-spec.md#L2492)）；教程示例也是
`Str s = str_from("hello");`（[tutorial.md:1609](../../docs/tutorial.md#L1609)）。
仓库没有隐式转换条款；`F-2` 明确「没有协议化的类型转换」，并建议「永久不做」隐式转换
（[language-capability-gaps.md:985-1018](../../docs/proposals/language-capability-gaps.md#L985-L1018)）。
**判 C**。

**9b. 诊断级别：A（bug，已由 LANG-14 修复）。**

实测（v0.53.0）：

```console
$ ct build a.ct -o out
a.ct:3:40: warning: type mismatch: 'has' argument 1: expected 'struct Str', got 'char *'
a.ct:16:16: error: passing 'char[5]' to parameter of incompatible type 'struct Str'
rc=1

$ ct check a.ct
a.ct:3:40: error: type mismatch: ...
rc=1
```

LANG-14 把这条定为「struct 形参收到非 struct 实参只报 warning，由 `cc` 兜底」，方案是
`argtype_mismatch` 对「任一侧基类型是 struct」返回 2，`argtype_check` 升为
`error: type mismatch: ...`（[lang-14:34-50](../../issues/lang/lang-14-charptr-to-struct-arg-warning.md#L34-L50)）。
它只收紧「C 必然拒绝」的 struct 形态，`int *` ↔ `char *` 这类仍保持 warning
（[:43-49](../../issues/lang/lang-14-charptr-to-struct-arg-warning.md#L43-L49)）；issue 状态写「已修（v0.53.1 工作树）」
（[:8](../../issues/lang/lang-14-charptr-to-struct-arg-warning.md#L8)），但本席找不到它引用的
`test/ast/264_struct_arg_mismatch` / `test/ast/errors/struct_arg_from_charptr.ct`，所以只记为「声称已修」。
**判 A**，引用 LANG-14，不重复开号；它不涉及隐式转换（§9a 另行判 C，LANG-14 的「残留」也明确写了，
[:52-54](../../issues/lang/lang-14-charptr-to-struct-arg-warning.md#L52-L54)）。

**最小修法与影响面（9b）**：只改 `argtype_mismatch` 的返回码与 `argtype_check` 的分级；
符号表 / 代码生成 / ABI 不变；既有 warning 类诊断（算术、指针层数）不受影响，
但需要重跑含 struct 误用的 golden，并把 `test/ast/errors/struct_arg_from_charptr.ct` 纳入硬门禁
（夹具落地前不计通过）。
**回归断言**：`take("k")`（`Str` 形参）在 `ct build` 直接 `error`、退出 1、不落 `.c`；
`int *` ↔ `char *` 仍 warning；合法 `take(str_from("k"))` 零回归。

---

## 2 Issue 映射

| 条目 | 处理 | 编号 |
| --- | --- | --- |
| 1b 同名单元产物冲突 | **新建** | [LANG-11](../../issues/lang/lang-11-same-base-unit-output-collision.md) |
| 4 属性访问协议 | **新建** | [LANG-12](../../issues/lang/lang-12-property-access-protocol.md) |
| 5a 下标静默空值 | 引用既有 | [LANG-4](../../issues/lang/lang-4-subscript-type-mismatch-silent-empty.md) |
| 5b 并存 / 类型分派 | 引用既有需求 | [REQ-JSACCESS-1](../../docs/planning/requirements-pool.md#L71-L103)、[REQ-INDEX-1](../../docs/planning/requirements-pool.md#L105-L142) |
| 6a 三级下标链 | 引用既有（声称已修） | [LANG-13](../../issues/lang/lang-13-three-level-subscript-chain.md)（上游 `JSON-1`） |
| 6b 固有方法结果作接收者 | 引用既有（修复在途） | [LANG-5](../../issues/lang/lang-5-result-as-receiver.md)（`JSON-2` 已并入） |
| 6c 下标结果取字段 | 引用既有（open） | [LANG-5](../../issues/lang/lang-5-result-as-receiver.md) |
| 6d trait 动态派发方法链 | 引用既有 | [SH-73](../../issues/selfhost/sh73-temp-receiver-dynamic-dispatch.md) |
| 3 包布局 | 引用既有 | [PKG-2](../../issues/packages/pkg-2-ct-install-package-root-import.md)（LANG-6 并入） |
| 2 限定名 | 不新建，归并行会话 | 参 [SH-18](../../issues/selfhost/ct-ast-qualified-type-name-rejected.md) |
| 9b 诊断级别 | 引用既有（声称已修） | [LANG-14](../../issues/lang/lang-14-charptr-to-struct-arg-warning.md)（上游 `JSON-3`） |
| 1a / 7 / 8 / 9a | 不建 issue | 已支持或设计拒绝，见本判决 |

> **交接核对**：本席开工时 `issues/lang/` 只有 LANG-1..5、7..10；写作过程中并行会话提交了
> `89b1124b`，新增 **LANG-13**（三级链，`JSON-1`）与 **LANG-14**（`char *` 传 `Str`，`JSON-3`），
> 并把 `JSON-2` 合并进 **LANG-5**。三者的 issue 正文都写「已修 / 修复在途（v0.53.1 工作树）」，
> 但本轮只找到 `test/ast/262_inherent_mcall_receiver`，找不到 LANG-13 / LANG-14 引用的夹具，
> 所以判决只承认「声称已修」。本轮占用 **LANG-11 / LANG-12**；LANG-6 已并入 PKG-2
> （[issues/README.md:346-365](../../issues/README.md#L346-L365)）。namespace 常量与限定名的并行登记
> 请顺延到下一个空闲号（LANG-15 起），不要复用本轮或并行会话已占的号。

---

## 3 优先级（按修复代价 × 阻塞程度）

| 优先级 | 条目 | 代价 | 阻塞面 | 理由 |
| --- | --- | --- | --- | --- |
| **P0** | 5a 数字下标静默空值（LANG-4） | 小–中（先做类型匹配） | 所有「字符串键 + 数字下标」容器；ct-json / rill-dsl | 唯一「编译通过、运行给错值且无诊断」；先做「无候选硬错」就能止血，不必等重载 |
| **P1** | 6c 下标结果取字段（LANG-5） | 小（一条守卫） | ct-json 的 `doc["k"].x` | 静默坏 C；与方法形态的文案统一后可立刻关闭 |
| **P1** | 1b 同名单元产物冲突（LANG-11） | 小（产物命名 / 配对） | 任何按「`.h.ct` 接口 + `.ct` 实现」组织的包 | 直接违反单元表的配对形态；只影响同 base 双单元，回归面窄 |
| **P2** | 4 属性访问（LANG-12） | 中（新协议） | ct-json 的 `doc.server.host` | 有库层绕法（`json_get` / 逐跳落变量），不挡 0.1.0 |
| **P2** | 5b `get` 并存（REQ-JSACCESS-1） | 中–大（内部名 mangling） | ct-json 的 `doc[0]` + `doc["k"]` | 先做 5a 的硬错；并存是完整 JS 风格访问的前提，需排独立相 |
| **在途** | 6b 固有方法结果作接收者（LANG-5 / `JSON-2`） | 小（类型推断补返回类型） | ct-json 的 `doc["server"].has(k)` / `doc.get(2).get(4)` | 工作树已有 `TypeCheck.h.ct` + `262_inherent_mcall_receiver`；提交并复跑后即可关闭 |
| **已修（声称）** | 6a 三级下标链（LANG-13） | 小–中（级联物化） | ct-json 的 `doc["a"]["b"]["c"]` | issue 写已修，但 `test/ast/263_index_chain3` 不在仓库；夹具落地后再确认 |
| **已修（声称）** | 9b `Str` 形参诊断（LANG-14） | 小（分级） | 所有 `Str` 调用点 | issue 写已修，但 `test/ast/264_struct_arg_mismatch` 不在仓库；夹具落地后再确认 |
| **P3** | 1c namespace 分离 | 小–中 | 包内「头声明 + 实现定义」 | 需要先裁定 `extern` 是否 mangling；归并行会话 |
| **P3** | 2 enum 作用域 | 小 | 迁移 C++ 风格的常量访问 | 有 namespace 限定写法；先改诊断文案即可 |
| **P3** | 3 `src/` 包布局（PKG-2） | 小（工具）/ 文档 | ct-fsguard 等 `src/` 包 | 现状契约已成立；是否放宽是生态决策 |
| **P3** | 6d trait 动态派发（SH-73） | 中（100–300 行） | 接口值一行链 | 逐跳落变量可绕；改生成物风险高，延后 |
| **不排期** | 7 运算符 / printf | — | — | 明文「不做」；printf 由用户负责 |
| **不排期** | 8a `for-in` | — | — | D27-4 明确不做；`foreach` 已覆盖容器 |
| **不排期** | 9a 隐式 `Str` 转换 | — | — | 无隐式转换条款；显式 `str_from` 是既定写法 |
| **文档** | 8b §4.49 旧句 | 文档 | 误导读者 | 与 §4.51 / §3 / 教程冲突；改一句即可 |

---

## 4 证据与复现

环境：`~/.local/bin/ct` v0.53.0（`ctc v0.53.1` 的单文件入口不支持 `build`），
`CT_STD_DIR=/Users/samxx/trae-ws/ct-lang/lib/std`，探针在 `/tmp/lcb/**`，未写入仓库。
**注意**：v0.53.0 尚未含 LANG-13 / LANG-14 / LANG-5 的最新修复；这三条的「已修 / 在途」结论取自
v0.53.1 工作树里的 issue 正文与并行会话的在途改动，不是本席用 v0.53.0 复跑出来的。
本轮只找到 LANG-5 引用的 `test/ast/262_inherent_mcall_receiver`；LANG-13 / LANG-14 引用的
`test/ast/263_index_chain3`、`test/ast/264_struct_arg_mismatch`、`errors/struct_arg_from_charptr.ct`
均不存在，所以判决只承认「声称已修」。其余六条的实测与 HEAD 一致。
完整命令与退出码见 [verify.json](verify.json)。

| 编号 | 探针 | 结果 |
| --- | --- | --- |
| V1 | `ns/cfg.h.ct` 三种 `pub const` + 消费方 | rc=0，运行 `14` |
| V2 | 同名 `cfg.h.ct` + `cfg.ct` 双入参 | `duplicate symbol '_K'`，rc=1 |
| V3 | namespace 分离（`pub extern` + `.ct` 定义） | `ns::K` 解析错；裸 `K` 链接 `_K` 未定义 |
| V4 | 三种 enum 限定写法 | `ns::FS_ERR_NOT_FOUND` rc=0；`FsErrCode::...` 两条报错 |
| V5 | 属性访问 `r.server.host` | `cc` 报 `no member named 'server' in 'struct JsonRef'` |
| V6 | 双 `get` 并存 | `conflicting types for 'J_get'` |
| V7 | 三级链 / 下标结果作接收者 | v0.53.0 两条拒绝文案；LANG-13 / LANG-5 声称修复，夹具未齐 |
| V8 | `r["port"] + 1` / `printf("%s", r)` | `invalid operands` / `-Wformat` |
| V9 | `for-in` / `foreach (Vec)` | `unexpected token` / rc=0 |
| V10 | `Str` 形参传字面量 | v0.53.0 `ct build` warning + `cc` error；LANG-14 声称升 error，夹具未齐 |

---

## 5 未决与边界

1. **1c 的裁定权**在并行会话：`extern` 是否要对 CT 侧定义 mangling，会改变已发布 `pub extern` 的符号名；
   本轮只给证据，不预设方案。
2. **5b 的 ABI**：并存需要内部名 mangling。若包已发布 `get`，改名会破坏 C 符号；需要版本策略。
3. **4 的属性协议**可能和 J-6 的逐跳物化共用同一套 `__ct_tmp`，不要分两次改 Emitter。
4. **8b 的旧句**是文档缺陷，不是语言缺口；本轮不改 `language-spec.md`，登记给后续文档修订。
5. **LANG-13 / LANG-14 的「已修」未经本席复验**：issue 引用的 `263` / `264` 夹具不存在；
   在夹具与实现一起提交并跑出绿之前，只能按「声称已修」引用，不得写成已验证。
6. 本轮不跑全量门禁（只改 `battle/` 与 `issues/`）；提交前用 `git diff --stat` 确认未触碰
   `selfhost/`、`test/`、`lib/`、`docs/language-spec.md`。
