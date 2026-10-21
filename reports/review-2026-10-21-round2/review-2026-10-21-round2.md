# 全面评审（第二轮，2026-10-21，扩展版）

| 项 | 值 |
| --- | --- |
| 源码锚点 | `dde0dda`（`docs(issues): record two unfixed findings`） |
| HEAD 自上一轮 | **无新提交**（同一 commit），第二轮为同一 HEAD 的更深层扫描 |
| 工作树 | 新增 8 个 issue 文件 + 本报告目录 + `issues/README.md` 编辑；均为只读产物，不触碰源码 |
| 范围 | 全量生成物 `-Wall -Wextra` 扫描、map 正例覆盖排查、差分实验（上一轮 3 个 + 本轮 map/switch/import/pub） |
| 结论 | 八道硬关卡全绿（310 项 `ok`、0 `FAIL`）；新增 8 条 issue：SH-8（High）、SH-9/10/11/12/DOC-19（Medium）、DOC-20/21（Low）；SH-10 从 Low 升级为 Medium |
| 前一轮问题 | DOC-10…15、SH-5、SH-6 **已确认修复**；SH-7、DOC-18 仍复现（未修） |

> 本报告只记录发现，不做修复。所有行号以 `dde0dda` 为准。

---

## 1. 验证记录（原始输出）

### 1.1 硬关卡

```text
$ bash selfhost/check-all.sh
== summary: 20 pass, 0 new, 0 pending, 0 regression ==
=============================================================
VERDICT
=============================================================
check-all: OK (8 hard gates green)
SCRIPT_EXIT=0
```

`ok` 行 **310** 条，`FAIL` 0 条；第 8 关含自编不动点与全量语料等价（`test/cases` 25、`examples` 7、
`test/modules` 5）。

### 1.2 全链与安装脚本

```text
$ gcc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/rev23/ctc
$ /tmp/rev23/ctc selfhost/l1/ctc.ct -o /tmp/rev23/l1.c && gcc ... -o /tmp/rev23/l1
$ /tmp/rev23/l1 build selfhost/l2/driver.ct -o /tmp/rev23/l2src && gcc ... -o /tmp/rev23/l2
$ /tmp/rev23/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/rev23/astsrc
$ gcc ... -o /tmp/rev23/ct
BUILD_OK
ct v0.12.0
ctc v0.12.0
```

四层零警告。另对新增的 `install.sh` 做了端到端验证（本地源，不下载）：

```text
$ CT_SOURCE_DIR=. ./install.sh -p /tmp/rev23/install
install_exit=0
```

### 1.3 check-archive 编译器澄清（第二轮新增）

`check-archive.sh` 第 28 行原文：**"The compiler under test is L2, not L1"**。archive cases 的
expected 全部由 L2 生成（L2 接受 block-style namespace，ct-ast 在解析期直接拒绝——已知分叉，
DOC-11 已记录）。`ctc: line 6: a namespace is file-scoped: write 'namespace A::B;' (at '{')`。
check-archive 的 `47 designed / 0 pending / 0 regression` **全部来自 L2**，ct-ast 对 archive
cases 的兼容性不在此关卡覆盖范围内——ct-ast 的多单元覆盖由 check-ast.sh 钉住。

### 1.4 差分实验（三轮）

| 实验 | L0 (`ctc`) | L2 | ct-ast（安装入口） |
| --- | --- | --- | --- |
| `impl` 少实现一个 trait 方法 | `exit=1`，`trait method 'b' is not implemented` | 同上 `exit=1` | **`exit=0`**，生成 `.b = 0` 的 vtable → 调用即 SIGSEGV |
| 语法错误 `int x = ;` | `exit=0`（透传） | `exit=0` | `exit=1`，`ctc: line 2: expected an expression` |
| 右值接收者在表达式中间 | 不重写 | 不重写 | **静默提升**，`mk()` 改变读取 `gi` 的值 |
| `switch` 语句 | 透传 | 透传 | `ctc: line 4: unexpected token (at '{')`（子集限制，已知） |
| `map` 语法 + interface 值派发 | N/A | N/A | **正确编过运行**；但 test/cases / examples 无正例（SH-12） |

---

## 2. 全量生成物 `-Wall -Wextra` 扫描（第二轮新增）

对 ct-ast 生成的 `.c` 文件统一做 `gcc -Wall -Wextra -std=c99 -fsyntax-only`，结果：

### 2.1 汇总表

| 语料集 | 总数 | 零告警 | 有告警 | 告警类型 |
| --- | --- | --- | --- | --- |
| test/cases/（25） | 25 | 23 | **2** | `_self` unused、`Dict_Hashable_vtable` unused |
| test/ast/（18 正例） | 18 | 17 | **1** | `uart1_Controller_vtable` unused（map 实例） |
| test/modules/（≥46 .ct） | ≥46 | ≥40 | **≥6** | `_self` unused、`Person_Drop_drop` unused |
| examples/（7） | 7 | **7** | 0 | — |
| ct-ast 自举产物（20） | 20 | **20** | 0 | — |

### 2.2 三类告警家族

| 告警 | 类别 | 代表位置 | 来源 |
| --- | --- | --- | --- |
| `-Wunused-variable: '_self'` | L2 与 ct-ast 同 | `02_multi_trait.c:38`、`04_signatures.c:23,32`、`sig_mismatch.c:20` | impl 方法体第一行固定强转，方法内未引用 `self` |
| `-Wunused-variable: '<T>_<S>_vtable'` | ct-ast 独有 | `04_signatures.c:35`（`Dict_Hashable_vtable`）、`13_map_instance.c:24`（`uart1_Controller_vtable`） | 发射了 trait 的 vtable 但程序从未调用该 trait 的方法 |
| `-Wunused-function: '<S>_<T>_<m>'` | ct-ast 独有 | `map/prog.ct`、`map_file/prog.ct`、`map_file_build/prog.ct`（`Person_Drop_drop`） | 发射了 Drop 函数但程序从未调 `delete` |

三类均为 `static` 对象——编译器不消除死代码。**关键洞察**：examples 和自举产物全零告警是因为它们**都用到了每个被发射的 trait 方法**；test/cases/ast/modules 里出现告警是因为有些正例用了 trait 声明却**从未调用**该 trait 的方法（只测声明、或 trait 是为另一个 struct 写的）。

### 2.3 为什么 check-all.sh 没发现

check-all.sh 对 ct-ast **自身的 `.c` 构建**跑 `-Wall -Wextra`；但从不对**生成物**（test/cases/*.c、test/ast/*.c、examples/*.c、test/modules/*.c）跑。这是一个门禁盲区——生成物告警不会触发红。

### 2.4 leak 系列的特殊情况

test/modules/leak / leak_build / leak_json 里还出现了源文件层面的 `p unused` 告警：

```c
struct S * p = malloc(sizeof(struct S));
return 0;           // p 从未被再引用，也没有调 delete
```

这不是 ct-ast 发射的问题——`.c` 里 `p` 就是普通 C 的局部变量，源文件本身就有问题（但 check-archive 的 expected 用例就是这么写的——故意钉住 leak 警告路径）。不计为 SH-10 的范围。

---

## 3. 新发现的问题

| ID | 严重度 | 摘要 | 位置 | 新/旧 |
| --- | --- | --- | --- | --- |
| SH-8 | **High** | ct-ast 不校验 impl 完整性：缺方法时生成 NULL vtable 槽，运行期 SIGSEGV；L0 / L2 都正确报错 | `frontend/parse/Parser.h.ct`、`backend/emit/Emit.h.ct` | 上一轮 |
| SH-9 | Medium | ct-ast 解析期诊断缺文件名与列号（`ctc: line N:`），与多处文档的 `file:line:col: error:` 不符 | `frontend/parse/**` | 上一轮 |
| **SH-10** | **Medium（升级）** | 生成物 `-Wall -Wextra` 告警家族扩大到三类：`_self` 未使用、未被引用的 vtable、未被引用的 Drop 函数；10+ 个语料 | `Emit.h.ct:493,531` 及各发射点 | 上一轮 + 本轮扩展 |
| SH-11 | Medium | ct-ast 对处于表达式中间的右值接收者静默提升，改变求值顺序；规范要求报错 | `backend/emit/Emit.h.ct:188-210` | 上一轮 |
| **SH-12** | **Medium（新增）** | `map` 语法在 test/cases（25 正例）与 examples（7 正例）中无端到端正例，新用户入口缺失 | `test/cases/`、`examples/` | **本轮新增** |
| DOC-19 | Medium | 教程四处与实现不符：`delete` 的 `p = 0`、`ctc` 建议、数组字段、示例行号 | `docs/tutorial.md:305,401,403,322/334` | 上一轮 |
| DOC-20 | Low | README 快速开始 1b 只构建 `ctc`，步骤 2/3 却调用 `ct` | `README.md:34-41`、`:478-484` | 上一轮 |
| DOC-21 | Low | `construction.md` 未标适用编译器，两处描述在 ct-ast 上不成立 | `docs/construction.md:16-18,62` | 上一轮 |

---

## 4. 细节与证据

### 4.1 SH-8（High）impl 完整性缺口

ct-ast 接受「trait 声明 2 个方法、impl 只实现 1 个」，生成：

```c
static struct G_vtbl P_G_vtable = { .a = P_G_a };   /* .b 缺省为 0 */
```

`cc -Wall -Wextra` 零错误，运行 `p.b();` 直接 `exit 139`。同一输入 L0 与 L2 都报
`trait method 'b' is not implemented for struct 'P'`（并有负例 `test/errors/missing_method`）。
这是**主线编译器相对回归 oracle的行为退化**，且 `check-ast.sh` 没有对应负例。

### 4.2 SH-10（Medium）生成物告警家族（升级）

详见第 2 节。关键点：

1. **家族范围**：三类告警都来自发射器（不是用户源文件）；`_self` unused 是既有行为（L2 同），vtable / Drop unused 是 ct-ast 独有。
2. **影响面**：test/cases 2/25、test/ast 1/18、test/modules ≥6 个文件——不是边角案例。
3. **门禁盲区**：check-all.sh 对生成物不跑 -Wall -Wextra。
4. **修复方向**：两类——发射器侧判断可达性（改动大）、局部抑制 `(void)<obj>;` 或 `__attribute__((unused))`（改动小，但要确认 golden 受不受影响）。

### 4.3 SH-12（Medium）map 正例覆盖缺口（新增）

```text
$ grep -rn 'map trait .* for instance' test/cases/ examples/  # 无命中
$ grep -rn 'map trait .* for instance' test/ast/               # 13_map_instance / 14_map_dispatch / 15_map_args
$ grep -rn 'map trait .* for instance' test/modules/           # map/、map_file/、map_file_build/
```

**Phase 11 的 map 语法**（`map trait T for instance x { m(params) -> CALL; }`）与 **Phase 9 的 `-emit-map` 元数据** 是两套独立机制：`test/ast/11_map/prog.ct` 含 trait + impl + 函数调用但**不含** map 语法构造，它测的是后者。真正的 map 语法正例集中在 test/ast/13-15 和 test/modules/map*——这些路径不在 test/cases / examples 中，文档（tutorial.md）里完全没提到 map 语法。

### 4.4 SH-11（Medium）右值提升越界

`docs/language-spec.md:211-214` 规定提升**只允许**出现在「语句行首」或「赋值/声明初始化式 RHS 行首」，
其它位置（原文点名的 `x = 1 + f().m();`）**必须报错**。实测 ct-ast 保留 0 退出并提升到语句之前：

```c
struct P __ct_tmp0 = mk();                 /* 被提到前面 */
x = (gi++ + __ct_tmp0.__g_vptr->m(&__ct_tmp0));
```

`mk()` 读到 `gi=0`，原位求值应为 `gi=1`。属于静默语义变更。L0 / L2 在此位置不做重写（产出不可编译的
`mk().m()`），三方都不满足规范里的「报错」条款。

### 4.5 SH-9（Medium）解析期诊断格式

```text
$ ct bad.ct -o bad.c
ctc: line 2: expected an expression (at ';')
```

无文件名、无列号。而 `README.md:68`（英文 `:509`）、`docs/tutorial.md:388`（英文 `:789`）、
`docs/glossary.md:81`（英文 `:243`）都写「错误格式为 `文件:行:列: error: 描述`」。语义期诊断
（重复 trait / struct、`map` 绑定）倒是 `file:line:col: error:`——两类诊断格式不统一。

### 4.6 DOC-19（Medium）教程与实现不符

| 教程说 | 实测 |
| --- | --- |
| `delete p;` → `if (p) { Box_Drop_drop(p); free(p); p = 0; }`（`:305`，英文 `:705`） | `if (p) { Box_Drop_drop(p); free(p); }`，**没有** `p = 0` |
| `switch` / `do-while` 要写就「用 `ctc`（L0 种子）」（`:401`） | `install.sh` 装出的 `ctc` 是 `ct` 的软链（ct-ast），实测 `ctc: line 1: unexpected token` |
| §11 第 7 条「**struct 类型的数组字段**等少数组合仍不支持」（`:403`） | 同一篇 §6（`:236-237`）说 ct-ast 已支持，实测 ct-ast 可用（见 DOC-18） |
| 同一段泄漏示例先写 `leak.ct:20:`（`:322`）后写 `leak.ct:9:`（`:334`） | **实际** `test/modules/leak/prog.ct:6: warning: potential leak: 'p' (S*) allocated but never deleted` |
| 错误格式 `文件:行:列: error: 描述`（`:388`） | 与 ct-ast 解析期实际输出不符（见 SH-9） |

### 4.7 DOC-20（Low）README 快速开始不自洽

`README.md:34-41`（英文 `:478-484`）给两条路：1a 安装 `ct`，1b 只编 L0 得 `ctc`；随后第 2 步却统一用
`ct examples/01_greeter/greeter.ct`。走 1b 的用户没有 `ct`，命令必然失败。1b 分支应改用 `./ctc`，
或明确「1b 仅用于核心语法、后续命令请用 `./ctc`」。

### 4.8 SH-10（Low → Medium）`_self` 未使用告警

impl 方法体不引用 `self` 时，生成物仍无条件输出

```c
struct P *_self = (struct P *)self;      /* Emit.h.ct:493 / 531 */
```

`cc -Wall -Wextra` 报 `-Wunused-variable`（L2 与 ct-ast 同）。上一轮只记录这一条，本轮扩展为完整家族。

### 4.9 DOC-21（Low）construction.md 的口径

`docs/construction.md:16-18` 以「现在的实现里，vptr 只在**一处**被写入：`try_var_decl()`」开篇，并自称
「机制说明（描述现状）」。`try_var_decl` 只存在于 L0（`selfhost/l0/ctc.c`），ct-ast 里没有这个函数；
`:62` 仍把「字段数组 `Person xs[3];`」列为「明确不处理」，而 ct-ast 已支持（DOC-18）。
文档没有标注它描述的是哪一层。

---

## 5. 上一轮问题的复核

### 5.1 已修复（确认）

| ID | 复核结论 |
| --- | --- |
| DOC-10 glossary 块式 namespace | 已改为分号式 |
| DOC-11 language-spec「行为等价」 | 已改为按编译器分述两处分叉 |
| DOC-12 README 透传范围 | 已限定为「L0 / L2 透传；ct-ast 只接受子集」 |
| DOC-13 D44 两态 / PkgOps 28 | 已改为三态与 29 个方法 |
| DOC-14 关卡注释 20 assertions | 已改为 21，第 8 关标签补 11.x + 12.1 |
| DOC-15 陈旧 `selfhost/ast/**` 路径 | 已加历史快照声明 |
| SH-5 死宏（27 个） | 机器复扫 **0 命中** |
| SH-6 悬空「caps in main.ct」注释 | 全仓仅剩 2 处 `old pipeline / no longer` 型历史注释 |

补充：头注释文件名一致性扫描（20 个单元）**全部匹配**。

### 5.2 仍复现（未修）

| ID | 复核 |
| --- | --- |
| SH-7 struct 值字段重复 vptr 初始化 | 复现成功：`cc -Wall -Wextra` 报 2 条 `-Winitializer-overrides` |
| DOC-18 §4.8 与 §6 相反 | 仍存在；且新增两处同源站点 `docs/tutorial.md:403`（并入 DOC-19） |

---

## 6. 非缺陷与观察

1. **L0 对普通 C 语法零校验**是设计使然：L0 只做行重写、透传其余内容，不是本轮回归。
2. **两个 BSD 探针在 Linux 上 `skip`** 是 `6395f5d` 的有意设计，测试总数随之 118 → 116，文档已说明。
3. **`install.sh` 的 `ctc` 分支**：若目标目录已有同名**普通文件**则用 `cp` 覆盖，否则 `ln -sf`。
   与 README「`ln -s ct ctc`」措辞略有出入，但行为正确（保留非软链不被强改）。
4. **`docs/construction.md` 的四种构造形态描述**（栈/嵌套/数组/堆）与 L0 的实际能力一致，仅
   「适用编译器」缺标注（见 DOC-21）。
5. **check-archive 用 L2 被测**：archive cases 的 expected 全部由 L2 生成，ct-ast 不能编（block-style
   namespace 被拒）。这是设计上的分层——L2 作为冻结 oracle 覆盖 L0 的历史语料，ct-ast 作为安装入口
   覆盖新的多单元模块。文档（AGENTS.md、issues/README.md）需要明确这点。
6. **leak 系列的 `p` unused**：源文件层面的告警（`malloc` 后没再引用），不是 ct-ast 发射问题。
   check-archive 用例就是这样写的——故意钉住 leak 警告路径。
7. **map 实例化不能直接在 struct 变量上调方法**：语法是 `map trait T for instance x { ... }`，
   调用必须把实例装进 interface 值后再调（`Stringify s; s = g_box; s.str();`），不能直接 `g_box.str()`。
   这是 ct-ast 有意设计的能力边界。

---

## 7. 建议优先级

| 优先级 | 条目 | 理由 |
| --- | --- | --- |
| **P0** | SH-8 | 主线编译器接受非法输入并产出会崩溃的 C，与其自身 oracle 行为相反 |
| **P1** | SH-10（Medium） | 生成物告警家族跨多个语料集，修复方案明确（局部 `(void)<obj>;`），改动廉价 |
| P1 | SH-11 | 静默改变求值顺序，属正确性风险；规范同时需要与实现对齐 |
| P1 | SH-12 | Phase 11 的 map 语法在 examples / test/cases 零正例，文档也未提及，新用户入口完全缺失 |
| P1 | DOC-19 | 教程是新用户第一入口，`delete` / `ctc` / 数组字段 / 行号四处会直接误导 |
| P2 | SH-9 | 诊断格式与四份文档冲突，影响定位效率 |
| P2 | DOC-20 | 快速开始的 1b 分支照抄必失败 |
| P3 | DOC-21 | construction.md 补一行适用编译器即可，零风险 |

---

## 8. 局限

- 未逐行通读 9 625 行 ct-ast 源码；死宏/死代码用于机器扫描 + 定向阅读，注释类问题用 grep 模式筛查。
- 未在 Linux / 容器内复跑门禁（本轮只在本机 macOS 跑），BSD 探针的 `skip` 分支未实测。
- 未验证 `install.sh` 的**下载**路径（只验证了 `CT_SOURCE_DIR` 本地分支，避免联网）。
- 生成物 `-Wall -Wextra` 扫描对 ct-ast 自身（自举产物）零告警，examples 零告警；告警集中在带未调用方法的正例上。这是发射器设计问题，不是 examples / 自举的问题。
