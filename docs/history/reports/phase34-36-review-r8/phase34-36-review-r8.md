# Phase 34 / 36 第七轮（r8）窄范围复核

- 复核对象：`fa10455`（只含 `docs/design/phase34-draft.md`、`phase36-draft.md`）
- 范围：只验上一轮 2 High + 3 Medium + 1 Low（P36）与 1 Medium + 3 Low（P34）是否闭合；重点验新写 shell 片段在 `check-ast.sh` 实际 shell（`#!/bin/sh`）下的可执行性。
- 方法：读 diff → 对照源码 → 在 `/tmp` 用**本轮源码重建的 `ct-ast`（v0.30.0）**实测；未运行 `bash selfhost/check-all.sh`。
- 约束：`2026-11-11/` 未跟踪目录未提交；未改卡片/commit/golden/版本号/门禁。

## 0 条件闭合总表

| 编号 | 上一轮条目 | 本轮结论 | 证据 |
| --- | --- | --- | --- |
| 36 H1-a | `impl_emit_one` 旁路 | **部分闭合** | 旁路条件 `find_trait(use) < 0` 成立（无内建 Trait 行）；但回填缺同一谓词，用户 `trait Drop` 会被误伤；`for` 解析今天不存在（S1a 新代码） |
| 36 H1-b | post-scan 作用域 | **闭合** | 改为两处 build-wide 回填 + glue 循环对全局 `ct_impls()` 求值，方向已实证 |
| 36 H1-c | 两向回填前提 | **闭合** | `Expr.h.ct:1963-1970` / `Parser.h.ct:2770-2779` 确为两个相反方向 |
| 36 H2-a | 生成 C 定义行 grep | **闭合** | 真实产物逐字 `static void __attribute__((unused)) Box_int_Drop_drop(void *self) {`；`grep -cE '^static .*Box_int_Drop_drop\(void \*self\) \{'` = 1 |
| 36 H2-b | 模板 `nm` 恒真 | **闭合** | 改成生成 C `grep == 0`；实测模板 glue 行确为 `static void __attribute__((unused)) Box_Drop_drop(void *self) {`，非空转 |
| 36 Low | `has_drop_impl` 位置/清零 | **闭合** | 与 `has_handback_impl`（`Symbols.h.ct:232`）相邻；`add_struct`（`:834-843`）逐字段清零 |
| 34 Medium | `p34_pub_bound` 扫描空转 | **闭合** | 加无 bound 的 `pub T id<T>(T)` 后，`sed` 抽取式实测能抽出 `T` |
| 34 Low-1 | `T(1)` 尾空格 | **闭合** | 已改 `case "$tp" in *"T(1)"*)`；`/bin/sh` 实测匹配 `T(1) ` |
| 34 Low-2 | `test/probes/` 归属 | **闭合** | L179 明写“由 P33 S0 创建，S3a 只加文件” |
| 34 Low-3 | 独立输出目录 | **命名闭合，实现片段有新 High** | `$mod-p34g`/`$mod-p34b` 风格一致、无撞名；但 L202 实际写的是未绑定的 `$d` |

**结论先行：P36 = GO（附 1 Medium + 2 Low）；P34 = NO-GO（1 High + 1 Medium + 1 Low，High 修法一行）。**

---

## 1 实测证据（原始输出）

1. 无内建 `Drop` Trait 行：`add_trait` 只在 `Parser.h.ct:2244` 由用户 `trait` 声明调用；`find_trait` 只扫 `traits[]`。普通程序 `find_trait("Drop") == -1`。
2. 但 `ct-ast` **不拦** `trait Drop`：

```
$ /tmp/r7ctast drop_trait.ct -o /tmp/p34r7/drop_trait.c ; echo rc=$?
rc=0
```

   同文件在旧 L2 上被拒：

```
$ /tmp/r7l2 test/archive/errors/drop_reserved.ct
test/archive/errors/drop_reserved.ct:1:11: error: 'Drop' is a reserved built-in trait and cannot be defined
```

3. 用户 `trait Drop` + 泛型 use 形态今天可编译，并带 `__drop_vptr`：

```
$ /tmp/r7ctast gdrop_user.ct ... ; echo rc=$?
rc=0
grep: __drop_vptr（Box<int> 字段）、Box_int_Drop_drop（显式方法）、Box_int_Drop_vtable（vtable 对象）
```

4. 内建形态今天解析不过：

```
impl<T> Drop for Box<T>        -> gdrop.ct:2:14: error: unexpected token
impl<T> Box<T> use Drop        -> gdrop_use.ct:2:20: error: impl of an unknown trait
```

5. H2-a 真实产物行（`/tmp/p34r7/bl.c`）：

```
static void __attribute__((unused)) Box_int_Drop_drop(void *self);   /* 声明 */
static void __attribute__((unused)) Box_int_Drop_drop(void *self) {  /* 定义 */
$ grep -cE '^static .*Box_int_Drop_drop\(void \*self\) \{' bl.c
1
```

   泛型显式 impl 的另一种拼写（`impl<T> Box<T> { void f() }` 实测）：

```
static __attribute__((unused)) void Box_int_f(void *self) {
```

6. `ct_inst_find` / `ct_impl_matches`：

```
int ct_inst_find(const char *name) { ... for (...) if (strcmp(t[i].name,name)==0) return i; return -1; }
int ct_impl_matches(int ii, int inst) { ... if (ii<0 || ii>=n || inst<0 || inst>=nins) return 0; ... }
```

7. shell：

```
$ /bin/sh -c 'tp="T(1) "; case "$tp" in *"T(1)"*) echo MATCH;; *) echo NOMATCH;; esac'
MATCH
$ /bin/sh -c 'tp=""; case "$tp" in *"T(1)"*) echo MATCH;; *) echo NOMATCH;; esac'
NOMATCH
$ /bin/sh -c 'set -u; d=/tmp/p34r7/emptydir; set -- "$d"/*.c && [ -f "$1" ]; echo rc=$?; echo pos1=$1'
rc=1
pos1=/tmp/p34r7/emptydir/*.c
```

   `check-ast.sh` 是 `#!/bin/sh`，只有 `set -u`（无 `set -e`）；顶层没有 `$1/$2/$@/shift/getopts` 依赖，所有位置参数都在函数体内。

---

## 2 Phase 36

### 2.1 H1-a 旁路条件（point 1）

**旁路本身成立。** `impl_emit_one`（`Emitter.h.ct:1618-1642`）里 `im` 是 `ct_impls()` 的 `StructImpl *`，`im[ki].use` 是 `char[160]` 字符串；`if (im[ki].use[0])` 在 `:1629`。卡片的 `find_trait(use) < 0` 与既有 `parse_impl`（`Parser.h.ct:2457-2462`，`ti < 0 && name == Drop/Handback`）是同一条规则，`find_trait` 对无用户声明的 `Drop` 返回 -1，所以内建旁路会触发。

**但有一个 Medium：回填条件漏了同一谓词。**
L79 写“命中 `use == "Drop"` 且 `ct_impl_matches` 时只置 `has_drop_impl = 1`，**不调 `adopt_use`、不把 `Drop` 加进 `use[]`**”；L197 又承诺“用户自声明 `trait Drop` 走既有路径”。这两句在用户声明 `trait Drop` 时互相打架：

- `parse_use_list`（`Parser.h.ct:2172-2187`）先查 `find_trait`，再**无条件**命中 `strcmp(tname,"Drop")==0` → 只设 `uses_drop=1`，不把 `Drop` 加进 `use[]`；
- 用户 trait 的 `__drop_vptr` 只能靠 `impl` 的 `adopt_use` 补（实测 `gdrop_user.c` 正是这样得到 `__drop_vptr` + `Box_int_Drop_vtable`）；
- 若回填按 L79 无条件跳过 `adopt_use`，`__drop_vptr` 消失，而 `impl_emit_one` 因 `find_trait("Drop") >= 0` 仍会发 vtable → 结构体缺字段、vtable 变孤儿，静默改变一个今天能编译的程序。

**修法（二选一，推荐 1）**：
1. 两处回填都加 `self->sym->find_trait(use) < 0` 才走 Drop 分支；否则保持 `adopt_use`。即 `impl_emit_one` 与回填用**同一个**谓词；
2. 或在 `ct-ast` 补 L2 已有的保留名检查（`selfhost/l2/core.ct:2102`），把 `trait Drop` 直接拒掉，使 `find_trait("Drop") < 0` 恒成立。

这条不阻塞 P36 主夹具（夹具不声明 `trait Drop`），但卡片的“用户 trait 走既有路径”承诺必须与回填一致。

### 2.2 解析侧（point 2）

`parse_impl_inst` **今天接不住** `for`：实测 `2:14: unexpected token`；`use` 形态也被 `Parser.h.ct:2755-2756` 的 `if (ti < 0) fail("impl of an unknown trait")` 拒掉（`2:20`）。所以“内建名不要求 trait 行”在泛型路径**不是现有事实**，是 S1a 要新增的代码——卡片把它写成 S1a 的工作，没伪称现状。非泛型 `parse_impl`（`2457-2462`）已有同样的 `ti < 0 && Drop/Handback` 特例，可直接照抄。

我**无法**在今天的编译器上让内建 `impl<T> Drop for Box<T>` 解析通过；唯一能跑通的是“用户先声明 `trait Drop`，再写 `impl<T> Box<T> use Drop`”（rc=0，走用户 trait 路径），这恰好证明了 2.1 的边界。

补充：`for` 形态要求把“trait 名在 `for` 前、struct 名在 `for` 后”的顺序反过来，现有 `parse_impl_inst` 是先读 struct 名和实参再读 `use`。S1a 的 `~15–25 行` 偏乐观（更像 25–40 行），但 S1a 总预算 60–100 行仍够，属 Low。

### 2.3 H1-b / H1-c（Medium 1、Medium 2）

**H1-b 闭合。** L80 改为“保留非泛型 `N_IMPL.aux == si`，泛型侧对全局 `ct_impls()` 求值”，正是消除 unit 作用域的正确形态；`ct_impl_matches(ij, ct_inst_find(structs[si].name))` 中：
- `ct_inst_find` 存在（`Symbols.h.ct:371` 声明、`:1547` 定义），按名字查实例行，**查不到返回 -1**；
- `ct_impl_matches`（`:1648`）在入口有 `inst < 0 || inst >= nins → return 0`，收到 -1 **不会越界**。

所以非实例 struct 回落到 `aux == si`，实例 struct 由全局匹配命中，安全。

**H1-c 闭合。** 两个方向确认：
- 实例晚于 impl：`Expr.h.ct:1963-1970`，此时 `k` 是 `ct_inst_add` 返回的实例下标（`:1920`），`ct_impl_matches(ii3, k)` 命中即 `adopt_use`；
- impl 晚于实例：`Parser.h.ct:2770-2779`，`num` 是 `ct_impl_add` 返回值，`ct_impl_matches(num, ii2)` 命中即 `adopt_use`。

两处都操作全局单例表（`ct_impls()`/`ct_insts()`），与 unit 无关。

**关于“不把 Drop 加进 `use[]` 后 `uses_drop` 还进不进 glue 循环”的推演：**
- `uses_drop` 来自 `parse_use_list` 的 `struct … use Drop`（`Parser.h.ct:2179-2180`），与 `use[]` 无关；
- 模板行 `uses_drop=1`，实例行由 ①（S2a1）复制；
- glue 循环只看 `structs[si].uses_drop`（`Emitter.h.ct:2335`），所以**会进**；
- 正因如此，内建 Drop 不能进 `use[]`（否则会多出 `__drop_vptr` 和一个无定义的 `Drop_vtbl`），卡片保持 `Parser.h.ct:2177-2180` 特例是对的。
- 但用户 `trait Drop` 是例外，见 2.1：那一路必须继续 `adopt_use`。

### 2.4 H2-a（point 3）

**闭合。** 真实产物行逐字为：

```
static void __attribute__((unused)) Box_int_Drop_drop(void *self);
static void __attribute__((unused)) Box_int_Drop_drop(void *self) {
```

- 参数名在**签名**里恒为 `self`；`_self` 只是函数体内的接收者别名（`emit_impl_method`/`emit_impls` 都是先声明 `void *self`，再 `struct X *_self = (struct X *)self;`）。
- 左花括号前恰好一个空格：源码是 `fputs(") {\n")`。
- 泛型显式 impl 的拼写是 `static __attribute__((unused)) void Box_int_Drop_drop(...)`（由实测 `Box_int_f` 同路径推得），卡片的 `^static .*` 同时覆盖两种顺序。
- `grep -cE '^static .*Box_int_Drop_drop\(void \*self\) \{'` 实测 = **1**（声明以 `);` 结尾，不匹配 `\{`）。

唯一 Low：L219 括注“声明 + 定义合计 2 行”与 `== 1` 并列，容易误读（文件确有 2 行，但 `\{` grep 只数定义 1 行）。建议改成“文件内声明+定义共 2 行；此处只数定义行，期望 1”。

### 2.5 H2-b（point 6）

**闭合。** L202 改成生成 C 的 `grep == 0`，模式与被测对象是同一拼写假设。实测（`bl.c` 无模板；含模板的产物）：

```
static void __attribute__((unused)) Box_Drop_drop(void *self) {
```

匹配 `^static .*Box_Drop_drop\(void \*self\) \{`，`grep -c` = 1（今天），② 落地后 = 0；它不会误命中 `Box_int_Drop_drop`（后者的 `Box_` 后是 `int_`，不含字面 `Box_Drop_drop`）。非空转。

### 2.6 Low（point 7）

**闭合。** `StructDef` 的 `has_handback_impl` 在 `Symbols.h.ct:232`，`add_struct` 在 `:834-843` 逐字段清零（`uses_drop`/`uses_handback`/`has_handback_impl`/`ntparams`/…）。`has_drop_impl` 贴着 `has_handback_impl` 加、并在 `add_struct` 补一行 `= 0`，与现有写法一致。

### 2.7 P36 结论

**GO（附条件）**：2 条 High 已真闭合（旁路条件可触发、H2-a 的 grep 与真实产物逐字一致、模板断言不再空转），H1-b/H1-c 的方向与全局性都成立。剩余：
- **Medium**：回填（`Expr.h.ct:1963-1970` / `Parser.h.ct:2770-2779`）的 Drop 分支要加 `find_trait(use) < 0`，否则用户 `trait Drop` 丢 `__drop_vptr`；
- **Low**：`for` 解析是 S1a 新代码（今天不可验证，不是伪称）；`~15–25 行` 偏紧；E36-1“2 行”措辞、`*_vtbl` 措辞（Drop 本来就没有 `*_vtbl` 要声明）。

---

## 3 Phase 34

### 3.1 夹具补 `pub T id<T>(T)`（point 8）

**闭合。** 用 `check-ast.sh:438` 的原抽取式实测：

```
输入：pub T id<T>(T x) / pub T pick<T: Show>(T a, T b) / struct Box<T> { T n; }
抽取：T        （只来自无 bound 的第一行）
```

`<T: Show>` 与 `struct Box<T>` 都不匹配；所以 `p34_pub_bound` 里必须另放无 bound 的 `pub T id<T>(T)`，L179/L202 已经写明，能抽出 `T(`，扫描不再空转。

### 3.2 shell 片段（point 9，本轮重点）

**(a) `case "$tp" in *"T(1)"*)`：合法。** `check-ast.sh` 是 `#!/bin/sh`；`case` 是 POSIX，引号内 `(1)` 按字面处理。实测 `T(1) ` 匹配、空串不匹配。尾空格不影响（子串匹配），`tparam_residue` 输出无换行。**Low**：空串时 `case` 若无 `*)` 分支会返回 0，dirty 断言必须保留 `[ -n "$tp" ]` 并给 `*)` 失败分支，否则 `T(2)` 之类会假通过。

**(b) `set -- "$d"/*.c && [ -f "$1" ]`：语法可跑，但有两个问题。**
- `set -e` **不存在**（只有 `set -u`）。无匹配时 glob 退化为字面量，`[ -f ]` 返回 1，但整条 `&&` 作为**裸语句**不会阻止下一行 `tp=` 执行——它只在包进 `if`/`||` 时才是守卫。卡片写“先 … 再 …”，必须落成 `if set -- … && [ -f "$1" ]; then tp=…; else bad …; fi`，否则防空目录的逻辑等于没写（**Medium**）。
- `set --` 会**覆盖脚本位置参数**。实测 `check-ast.sh` 顶层没有 `$1/$2/$@/shift/getopts` 依赖（所有 `$1`/`"$@"` 都在 `tparam_residue`、`ok`/`bad` 等函数体内，函数有自己的位置参数），所以**当前不会立刻坏**；但这是全局副作用，建议 `( set -- … )` 子 shell 或改用普通变量（**Low**）。

**(c) 新 High：`$d` 没有被绑定到输出目录。**
L202 明写两个输出目录 `$mod-p34g`/`$mod-p34b`，但片段用的是 `"$d"/*.c`。`d` 在 modules 段之前只由 `for d in test/ast/*/`（`check-ast.sh:502`）赋值，循环结束后 `d` 是**最后一个 `test/ast/*/` 夹具目录**。后果：
- `set -u` 下 `d` 已绑定（陈旧值），不报错；
- `"$d"/*.c` 指向 ast 夹具目录（里面没有 `.c`），glob 无匹配；
- 若守卫写成裸 `&&`，`tp` 读不到任何产品 → 空 → `[ -z "$tp" ]` **恒真**，E34-2a 的核心断言假绿；若守卫写成 `if`，则因 `[ -f ]` 为假而恒走失败分支。
两种写法都不测 `$mod-p34g`/`$mod-p34b` 的产物。
**修法（一行）**：`d="$mod-p34g"`（bound 夹具用 `d="$mod-p34b"`），或直接把片段里的 `"$d"` 换成 `"$mod-p34g"`/`"$mod-p34b"`。

**(d) 命名与撞名：** `mod="$work/mod"`（`:889`），既有风格是 `$mod-split`/`$mod-ns`/`$mod-nsf`；`$mod-p34g`/`$mod-p34b` 一致，`grep p34g` 无既有命中，**不撞名**。

### 3.3 估算与切片（point 10）

**未漂移。**
- P34 §10：编译器 415–720 = `45+50+60+50+70+60+80` / `80+90+110+90+110+100+140`；夹具 270–450 = `30+60+100+80` / `60+110+150+130`；文档 200–360 = `20+80+80+20` / `50+150+120+40`；合计 885–1,530。逐片上限最大 150（S7、S10），满足 ≤150。
- P36 §10：编译器 240–430 = `60+40+60+25+25+30` / `100+80+100+45+45+60`；库 240–420 = `20+50+40+90+20+20` / `40+80+70+150+40+40`；逐片最大 150（S4b），满足 ≤150。

### 3.4 P34 结论

**NO-GO（1 High + 1 Medium + 1 Low，另 2 条 Low 已闭合）。** 四条收尾里三条真闭合（无 bound 夹具可抽取、尾空格已改子串判断、`test/probes/` 归属已写、目录命名一致），但 L202 的 shell 片段把输出目录写成了未绑定的陈旧 `$d`，导致 E34-2a 的 `p34_pub_generic`/`p34_pub_bound` 清洁扫描**不测目标产物、假绿**。这是一行修法：
1. **High**：`$d` → `$mod-p34g`/`$mod-p34b`（或先 `d="$mod-p34g"`）；
2. **Medium**：守卫必须包进 `if`（无 `set -e`，裸 `&&` 不阻断）；
3. **Low**：`case` 补 `*)` 失败分支；`set --` 建议子 shell/局部变量。

---

## 4 终态

- **Phase 36：GO（附条件）** — 2 High 已闭合；条件是把回填的 Drop 分支也加上 `find_trait(use) < 0`（用户 `trait Drop` 不被误伤），并吸收 3 条 Low 措辞。
- **Phase 34：NO-GO** — 1 High（`$d` 未绑定，E34-2a 假绿）+ 1 Medium（裸 `&&` 守卫不阻断）+ 1 Low（`case` 缺失败分支）；修法均为一两行，改完即可复评。
