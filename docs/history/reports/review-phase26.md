# 代码审查（2026-11-09）：Phase 26 泛型函数与 `v0.26.0` 发布

| 项 | 值 |
| --- | --- |
| 源码锚点 | 首轮 `ac1c7cd`（tag `v0.26.0`）；复核 `d29de8f`（tag `v0.26.1`）；收尾复核 `5b43fac`（annotated tag `v0.26.2`） |
| 适用版本 | ct 主线 `ct-ast`（版本以 `ct -v` 为准）；首轮 `v0.26.0`，复核 `v0.26.1`，收尾复核 `v0.26.2` |
| 版本 | **`v0.26.0`（首轮）+ `v0.26.1`（复核）+ `v0.26.2`（收尾）**；三轮五处 `CTC_VERSION` 均同步 |
| 工作树 | 首轮干净；复核轮与收尾轮工作树仅评审产物（issue 状态回写 + 本报告），未改代码/测试 |
| 审查对象 | `docs/design/phase26.md` 立项节 §1（六字段）与 E1–E8；实现提交 `f3be73e`、`c6b1220`、`7287044`、`ac1c7cd`；复核提交 `87b03ec`、`f5f1092`、`4995dff`、`5762f1e`、`d29de8f`；收尾提交 `5b43fac` |
| 基线 | 首轮：`check-ast.sh` **803 passed**；复核：**815 passed**；收尾：**817 passed**；三轮均 **11 hard gates green**、`check-docs` OK |
| 结论 | 首轮**有条件放行**；`v0.26.1` 复核**未通过**（见 §11）；`v0.26.2` 收尾：SH-62 / TEST-17 `verified`，但新立 **[SH-64](../../../issues/selfhost/sh64-generic-tparam-value-position.md)（P1）**——类型参数出现在值位置仍退出 0 发射裸 `T`，故 **Phase 26 仍未收口**（见 §12） |

> 本轮只审不改。新增 issue：**[SH-62](../../../issues/selfhost/sh62-generic-subst-uppercase-tparam.md)（P1）**、
> **[TEST-17](../../../issues/testing/test17-phase26-generic-coverage-gap.md)（P1）**、
> **[SH-63](../../../issues/selfhost/sh63-generic-subst-struct-t-collision.md)（P2）**、
> **[DOC-67](../../../issues/docs/doc67-phase26-doc-impl-mismatch.md)（P2）**；另有 3 条 P2/Info 观察记在 §8，不占 ID。

---

## 0. 结论先行

**放行判断：有条件放行。** `v0.26.0` 可以保留（tag 指向正确、安装链路正常），但发布说明中“S4 完成”的口径不成立，
必须按 §8 的条件修完，才能把 Phase 26 记为真正完成。

| 判据 | 文档要求 | 实跑结果 | 成立 |
| --- | --- | --- | --- |
| E1 | 正例 123 两端 `cmp` 一致、至少 2 行实例、无残留 `T` | `p26_generic_identity` ok；`grep -c '__ct[0-9]'` = **6**；`grep -E '\bT\b'` 无命中 | ✅ |
| E2 | 正例 124 输出 `x=3 y=4`、签名 `pass__ct1(struct Point)` | `p26_generic_struct` ok，运行输出 `x=3 y=4` | ✅ |
| E3 | 五条负例各只一条 L26 错误，位置/文案精确；旧编译器结果不同 | 五条各 **1** 条 `error:`，位置文案全中；`~/.local/bin/ct`（v0.25.0）结果逐条不同（§2） | ✅ |
| E4 | `check-ast` ≥ 792 且 0 失败；非泛型 golden 逐字节不变 | **803 passed, 0 failed**；`check-goldens: OK`；golden 差异归一化版本后 **UNPAIRED=0** | ✅ |
| E5 | `check-all.sh` 11 道门禁全绿 | `check-all: OK (11 hard gates green)`，退出 0 | ✅ |
| E6 | 五处 `CTC_VERSION` = 0.26.0；`install.sh` 后 `ct -v` 为 0.26.0 | 五处一致；`/tmp/p26rev/install/ct -v` → `ct v0.26.0` | ✅ |
| E7 | `docs/README.md` 索引含 phase26；`check-docs` 退出 0 | 索引命中；`check-docs: OK (… v0.26.0, 11 hard gates, 10 phase status …)` | ✅ |
| E8 | 五条负例 `ct check` 非零退出并含对应文案 | 五条 `p26_check_*` 全 ok，且各只 1 条 error | ✅ |

**但**：E1/E2 的“无残留 `T` / 类型替换”只证明了**返回类型与形参**；§4.48 承诺的
`(T)`、`sizeof(T)`、`_Alignof(T)`、`offsetof(T, …)` 四处实测不成立，`sizeof(T)` 还是退出 0 的坏产物（SH-62）。

---

## 1. 方法与基线

1. **固定锚点**：`git log e9576b0..HEAD` 得到 4 个提交（`f3be73e` → `c6b1220` → `7287044` → `ac1c7cd`），
   先读 `docs/design/phase26.md` 与 `git show --stat`，再按“功能 / 夹具 / 文档 / 发布”拆分。
2. **先跑门禁再读代码**：`check-ast.sh`（803）、`check-all.sh`（11 关）、`check-docs.py`（OK）三项全绿，
   避免把既有回归误记为新发现。
3. **候选发现一律实测**：把四层自举链（`ctc.c` → L1 → L2 → `ct-ast`）建到 `/tmp/p26rev/b`，
   另在 `/tmp/p26rev/repo` 的副本上做“删守卫”变异，重新构建 `ct-ast`，不靠读注释下结论。
4. **反假完成**：对五条负例的断言做变异测试（§3），对 S4 的每个替换点写 `/tmp` 探针（§4）。

自举链构建（与 `docs/design/phase26.md` §6.3 同法）：

```console
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/p26rev/b/ctc
$ /tmp/p26rev/b/ctc selfhost/l1/ctc.ct -o /tmp/p26rev/b/l1.c
$ cc -Wall -Wextra -std=c99 /tmp/p26rev/b/l1.c -o /tmp/p26rev/b/l1
$ /tmp/p26rev/b/l1 build selfhost/l2/driver.ct -o /tmp/p26rev/b/l2src
$ cc -Wall -Wextra -std=c99 /tmp/p26rev/b/l2src/*.c -o /tmp/p26rev/b/l2
$ /tmp/p26rev/b/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/p26rev/b/astsrc
$ cc -Wall -Wextra -std=c99 /tmp/p26rev/b/astsrc/*.c -o /tmp/p26rev/b/ct-ast
$ /tmp/p26rev/b/ct-ast -v
ct v0.26.0
```

---

## 2. E1–E8 逐条核验（原始输出）

### E1 / E2 正例

```console
$ grep -n 'p26' /tmp/p26-ast.log
239:  ok    p26_generic_identity (two instances, no template symbol, no residual T)
240:  ok    p26_generic_struct (a struct type argument is substituted)
...
$ /tmp/p26rev/b/ct-ast test/ast/123_generic_identity/prog.ct -o /tmp/p26rev/out/123.c
$ grep -n '__ct[0-9]' /tmp/p26rev/out/123.c
4:static int id__ct1(int);
5:static char * id__ct2(char *);
11:    a = id__ct1(42);
13:    q = id__ct2(p);
17:static int id__ct1(int x) {
20:static char * id__ct2(char * x) {
$ grep -c '__ct[0-9]' /tmp/p26rev/out/123.c
6
```

`124` 的生成物含 `static struct Point pass__ct1(struct Point);` 与同签名定义，编译运行输出 `x=3 y=4`。

### E3 五条负例 + 旧编译器对照

```console
$ for f in generic_missing_arg generic_pub generic_two_params generic_void_arg generic_recursive; do
    /tmp/p26rev/b/ct-ast test/ast/errors/$f.ct -o /tmp/x.c 2>&1 | grep 'error:'; done
generic_missing_arg.ct:10:14: error: generic function 'id' needs a type argument
generic_pub.ct:2:9: error: generic functions cannot be pub
generic_two_params.ct:2:9: error: only one type parameter is supported
generic_void_arg.ct:9:19: error: 'void' cannot be a generic type argument
generic_recursive.ct:10:17: error: recursive generic calls are not supported
```

每条夹具的 `grep -c 'error:'` 均为 **1**（满足“各自只产生一条 L26 错误”）。旧编译器
`~/.local/bin/ct`（v0.25.0）对同一批夹具的结果（节选）：

```console
123/generic_identity   exit=1 | error: unexpected token
124/generic_struct      exit=1 | error: unexpected token
generic_missing_arg    exit=1 | error: 'id' is not a function
generic_pub            exit=1 | error: 'T' is not a known type
generic_two_params     exit=1 | error: 'T' is not a known type
generic_void_arg       exit=1 | error: 'T' is not a known type
generic_recursive      exit=1 | error: 'T' is not a known type
```

行、列、文案全部不同，证明 E3 的断言不是“新旧都报错即可”。

### E4–E8

```console
$ bash selfhost/check-ast.sh | tail -1
== summary: 803 passed, 0 failed ==

$ grep -nE '^\[[0-9]+/11\]|== summary:|OK \(|== check-all' /tmp/p26-all.log | tail -12
== summary: 118 passed, 0 failed ==
check-goldens: OK (no regression, and the self-hosted rebuild agrees)
check-archive: OK (no regression)
== summary: 82 passed, 0 failed ==
== summary: 803 passed, 0 failed ==
check-semantics: OK (23 assertions)
check-docs: OK (850 relative links in 172 files, v0.26.0, 11 hard gates, 10 phase status, 3 适用版本 header(s))
== summary: 20 pass, 0 new, 0 pending, 0 regression ==
check-all: OK (11 hard gates green)

$ /tmp/p26rev/install/ct -v
ct v0.26.0
```

`check-docs` 与 phase26 §6.3 引用的每个数字（118 / 82 / 803 / 245 / 23 断言 / 850 链接 / 172 文件 / 20 验收探针）
逐一对得上，未发现数字漂移。

---

## 3. 反假完成：负例断言确实会红

除“现在报错”外，我做了**删守卫变异**：在 `/tmp/p26rev/repo`（HEAD 副本）里去掉五处诊断守卫
（L26-1/L26-2/L26-3/L26-4/L26-5），用同一套 L2 重建 `ct-ast`，再用与 `check-ast.sh` **完全相同**的
grep 条件（`file:line:col: error: message`）判定：

```console
=== baseline (guards intact) ===
GREEN p26_diag_generic_missing_arg
GREEN p26_diag_generic_pub
GREEN p26_diag_generic_two_params
GREEN p26_diag_generic_void_arg
GREEN p26_diag_generic_recursive

=== mutated (five guards disabled) ===
RED   p26_diag_generic_missing_arg  (expected a non-zero exit, got 0)
RED   p26_diag_generic_pub  (expected a non-zero exit, got 0)
RED   p26_diag_generic_two_params  (actual: ...:2:9: error: expected '>' after the type parameter)
RED   p26_diag_generic_void_arg  (expected a non-zero exit, got 0)
RED   p26_diag_generic_recursive  (expected a non-zero exit, got 0)
```

五条全部变红，说明：断言对守卫、文案、行列都敏感，没有“删守卫后仍绿”的空转；`p26_chk`（E8）与 `p26_diag`（E3）
的 grep 也不是恒真。**这一项通过。**

但同一种方法用到 S4 就露馅：正例夹具的模板体只有 `return x;`，`! grep -E '\bT\b'` 没有可命中的类型位置。

```console
$ grep -qE '\bT\b' /tmp/p26rev/out/user-sizeof.c ; echo $?
0        # 命中第 12 行 `return sizeof(T);`——若夹具含该形态，门禁会红
```

即断言本身有效，**夹具没覆盖**（TEST-17）。

---

## 4. 单态化产物与“四点替换”

### 4.1 产物形态（通过）

以 123 为例，生成物满足：实例都是 `static`、C 名带 `__ct<N>` 后缀、模板本身不落符号：

```c
static int id__ct1(int);
static char * id__ct2(char *);
int main(void);
...
static int id__ct1(int x) {
    return x;
}
```

去重（同一 `(模板,类型)` 多处调用只一份实例）、`char *` 复合类型、`struct Point` 复合类型均实测正常：

```console
$ /tmp/p26rev/b/ct-ast /tmp/p26rev/probe/dedup.ct -o /tmp/p26rev/out/dedup.c
$ grep -n '__ct[0-9]' /tmp/p26rev/out/dedup.c
4:static int id__ct1(int);
5:static char * id__ct2(char *);
...
```

（`id<int>` 调用三次只生成一份 `id__ct1`；局部变量 `TOTAL` 因整词边界未被误替换。）

### 4.2 四点替换（**不通过**）

| 位置 | 探针 | 实测 |
| --- | --- | --- |
| 返回类型 | 123 / 124 | ✅ `static int id__ct1(int)` |
| 形参 | 123 / 124 | ✅ `static char * id__ct2(char *)` |
| 局部声明 | `T y;` | ✅ 发射 `int y;`（无夹具，见 TEST-17） |
| `(T)` 转型 | `return (T)x;` | ❌ `error: unexpected token` |
| `sizeof(T)` | `return sizeof(T);` | ❌ **退出 0**，发射 `sizeof(T)`，`cc` 报 `‘T’ undeclared` |
| `_Alignof(T)` | `return _Alignof(T);` | ❌ `error: _Alignof needs a type in parentheses` |
| `offsetof(T, y)` | `return offsetof(T, y);` | ❌ `error: offsetof needs a struct type` |

根因是 `next_is_type_name()` 的 ALL_CAPS 启发式把单字母 `T` 当成宏常量，
[Expr.h.ct:1684-1694](../../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1684-L1694)。**反证**：把类型参数改成小写 `t`，
同一实现立刻正确：

```console
$ grep -n 'sizeof\|return (int)' /tmp/p26rev/out/lower.c
13:    return sizeof(int);
16:    return (int)(x);
$ /tmp/p26rev/out/lower
4 9
```

另有 `struct T` 被替换成 `struct int` 的静默坏产物（SH-63）：

```console
$ grep -n 'struct int' /tmp/p26rev/out/user-structT.c
9:static struct int getv__ct1(struct int *);
17:static struct int getv__ct1(struct int * p) {
```

### 4.3 容量与边界

- `MAX_GENERIC_INSTS = 64` 越界不是静默截断：构造 65 个不同 struct 实参，编译退出 1 并给出错误（符合要求）。
- 泛型前置声明后先调用、后定义：`error: a generic function needs a definition in this unit`，没有静默坏产物。
- 泛型调用 arity 不符：与非泛型函数行为一致（`warning: arity mismatch` + 退出 0）。
  唯一瑕疵是告警里显示实例名 `id__ct1` 而非源名 `id`（[Diag.h.ct:368](../../../selfhost/ct-ast/tool/diag/Diag.h.ct#L368)，P2 观察）。

---

## 5. 冻结层与版本

`git diff e9576b0..ac1c7cd -- selfhost/l0 selfhost/l1 selfhost/l2 selfhost/ct-ast/main.ct` 只有 4 处版本串：

```diff
--- a/selfhost/l0/ctc.c
-#define CTC_VERSION "0.25.0"
+#define CTC_VERSION "0.26.0"
--- a/selfhost/l1/ctc.ct          （同上）
--- a/selfhost/l2/core.ct         （同上）
--- a/selfhost/l2/driver.ct       （同上）
--- a/selfhost/ct-ast/main.ct     （同上）
```

**L0/L1/L2 除版本串外零变化，符合冻结约定。** 74 个 golden 的差异也只在版本 token：
把 `0.25.0`/`0.26.0` 归一后按 `+/-` 配对统计，`UNPAIRED=0`（无多余内容变化）。

---

## 6. 提交粒度与范围

| 提交 | 主题 | 文件范围 | 评价 |
| --- | --- | --- | --- |
| `f3be73e` | `feat(ct-ast): monomorphise generic function calls` | 5 个 `selfhost/ct-ast/**` 源文件 | ✅ 一事一提交 |
| `c6b1220` | `test(ct-ast): pin generic function fixtures and diagnostics` | 7 个 `test/ast/**` + `check-ast.sh` | ✅ 与功能分离，便于回滚 |
| `7287044` | `docs: document generic functions and close phase 26` | `docs/**`、`AGENTS.md`、`README.md` | ✅ |
| `ac1c7cd` | `chore(release): bump CTC_VERSION to 0.26.0` | 5 处版本 + 74 golden + README | ✅ |

全部路径落在 [AGENTS.md §2](../../../AGENTS.md#L74-L121) 允许的 `selfhost/**`、`test/**`、`examples/**`、
`docs/**`、`AGENTS.md`、`README.md` 内，**没有夹带 issues/、ci/、脚本工具链等无关改动**。
与 phase26 §3 的一处计划偏差：原文说“26.4 与 26.1–26.3 合并为一个功能提交”，实际把夹具拆成 `c6b1220`；
这属于更好回滚的粒度，不构成风险，但应在 §6.2 登记（可并入 DOC-67）。

---

## 7. 文档一致性

- phase26 状态行“完成” ↔ roadmap `v0.26.0` 的 ✅ 行一致；`check-docs` 的 10 个 phase 状态全部通过。
- `docs/README.md` 索引已含 phase26；`language-spec` §4.48 与教程 §10.5 的中英双份都存在且互相对称。
- **但内容有假**：中英 §4.48 都承诺 `(T)` / `sizeof(T)` / `_Alignof(T)` / `offsetof(T, …)` 会被替换（SH-62），
  §4.48 末句“这些都在源码处硬报错，不静默降级”被 `sizeof(T)` 直接反证；L26-3/L26-4 的文案描述也与实测不符（DOC-67）。
- `AGENTS.md:92` 的版本 bump 登记清单停在 `v0.17.0`（既有漂移，Phase 26 改到该节但未顺手补齐）。

---

## 8. 发现清单

### P1（须在 `v0.26.1` 前处置）

1. **[SH-62](../../../issues/selfhost/sh62-generic-subst-uppercase-tparam.md)**：`T` 全大写使 `(T)` / `sizeof(T)` /
   `_Alignof(T)` / `offsetof(T, …)` 四处替换失效；其中 `sizeof(T)` 静默退出 0 并产出非法 C，违反
   [AGENTS.md](../../../AGENTS.md#L120-L121)。
2. **[TEST-17](../../../issues/testing/test17-phase26-generic-coverage-gap.md)**：夹具只覆盖返回/形参替换，
   S4 其余替换点、去重精确计数、容量边界、命名回退均无断言；门禁全绿不能证明 S4 完成。

### P2

3. **[SH-63](../../../issues/selfhost/sh63-generic-subst-struct-t-collision.md)**：`ct_generic_subst` 把 `struct T`
   改写成 `struct int`，与其自身注释相反，静默产出非法 C。
4. **[DOC-67](../../../issues/docs/doc67-phase26-doc-impl-mismatch.md)**：S4 承诺、L26-3/L26-4 文案、E1 断言作用域
   描述、AGENTS 版本登记四处文档失真。

### 不占 ID 的观察（P2/Info）

- `p26_generic_identity` 用 `grep -c '__ct[0-9]' -ge 2` 只能证明“至少两行实例”，不能证明“每个类型实参恰好一份”（TEST-17 已记）。
- 泛型调用 arity 告警显示 `id__ct1` 而非 `id`；对用户是噪音（[Diag.h.ct:368](../../../selfhost/ct-ast/tool/diag/Diag.h.ct#L368)）。
- roadmap 的 `v0.24.0`/`v0.25.0`/`v0.26.0` 三行都写“待发布”，与已打 tag 的事实不符；属沿袭写法，非本相引入。
- `ct_generic_subst` 的 `MAX_TEXT` 溢出分支会静默保留未替换文本；当前 `ptype` 长度下不可达，仅记录。

---

## 9. 放行条件

1. **必须二选一**（SH-62）：实现 `T` 在 `(T)` / `sizeof` / `_Alignof` / `offsetof` 位置的替换；
   或者明确不做，但**至少把“静默产出非法 C”改成硬错误**，并删除 language-spec §4.48（中英）与
   phase26 §2.3/§2.4 的相应承诺，在 §6.2 登记偏差。
2. 补 TEST-17 的夹具；修完后 `check-ast` / `check-all` 必须仍全绿且 golden 零变化。
3. 修 SH-63 与 DOC-67（含 AGENTS 版本登记写法）。

在上述条件完成前，建议把 Phase 26 的“完成”表述收窄为“功能可用，S4 部分兑现”，避免对外文档继续失真。

---

## 10. 本轮未覆盖

- 多单元 `build` 下的泛型使用：语言规则已规定实例不跨单元、`pub` 泛型被拒，本轮只按文档边界抽查了
  “前置声明 + 后定义”与容量上限，未构造多单元交叉调用矩阵。
- `--emit-map` / `.h` 导出路径下的实例表现（实例是 `static`，本相不导出，未逐项展开）。
- Windows/macOS 平台差异（本轮全部在 Linux + `cc` 下完成）。

---

## 11. `v0.26.1` 收尾复核（2026-11-09，锚点 `d29de8f`）

### 11.1 结论

**复核未通过。** 四条 issue 的判据如下：

| Issue | 复核结论 | 判据 |
| --- | --- | --- |
| SH-62 | **reopened** | 括号形式的 `sizeof(T)` / `_Alignof(T)` / `offsetof(T, …)` / `(T)` / `va_arg(ap, T)` / `struct T` 全部正确；但无括号 `sizeof T` 仍退出 0 发射 `sizeof(T)`，`cc` 报 `‘T’ undeclared` |
| SH-63 | **verified** | `struct T` 保持标签，运行输出 `7`；v0.26.0 基线发射 `struct int` 的反证成立 |
| TEST-17 | **reopened** | 新增夹具与 815 数字属实、两条新负例会红；但门禁对无括号 `sizeof T` 无夹具，仍会放过静默坏产物 |
| DOC-67 | **verified** | §4.48 承诺、L26-3/4 文案、E1 作用域、AGENTS 版本登记四项逐条对上 |

### 11.2 门禁实跑（评审方命令，非实现方证据）

```console
$ bash selfhost/check-ast.sh | tail -1
== summary: 815 passed, 0 failed ==

$ bash selfhost/check-all.sh | tail -1
check-all: OK (11 hard gates green)
$ grep -nE '^[0-9]+\) |^== summary:|check-all: OK' /tmp/p261-all.log | tail -12
== summary: 118 passed, 0 failed ==        # bootstrap
check-goldens: OK (no regression, and the self-hosted rebuild agrees)
check-archive: OK (no regression)
== summary: 82 passed, 0 failed ==         # packages
== summary: 815 passed, 0 failed ==        # check-ast
check-semantics: OK (23 assertions)
check-docs: OK (863 relative links in 173 files, v0.26.1, 11 hard gates, 10 phase status, 3 适用版本 header(s))
== summary: 20 pass, 0 new, 0 pending, 0 regression ==
check-all: OK (11 hard gates green)
```

`815` 属实（v0.26.0 为 803，+12 与实现方登记一致）。

### 11.3 “静默坏产物”回归矩阵

| 探针 | 结果 |
| --- | --- |
| `sizeof(T)` | ✅ `sizeof(int)` |
| `_Alignof(T)` | ✅ `_Alignof(int)` |
| `offsetof(T, y)` | ✅ `offsetof(struct Point, y)` |
| `(T)` | ✅ `(int)` |
| `va_arg(ap, T)` | ✅ `va_arg(ap, int)` |
| `_Generic(x, T: …)` | ✅ 硬错 |
| `struct T` | ✅ 标签保留 |
| **`sizeof T`（无括号）** | ❌ **退出 0，发射 `sizeof(T)`，`cc` 报 `‘T’ undeclared`** |

```console
$ /tmp/p261/b/ct-ast /tmp/p261/probe/sizeof_noparen.ct -o /tmp/p261/out/p-sizeof_noparen.c; echo ct=$?
ct=0
$ grep -n 'sizeof' /tmp/p261/out/p-sizeof_noparen.c
11:    return (int)(sizeof(T));
$ cc -std=c99 /tmp/p261/out/p-sizeof_noparen.c -o /tmp/p261/out/p-snp; echo cc=$?
...:11:25: error: ‘T’ undeclared (first use in this function)
cc=1
```

非泛型对照 `sizeof Missing` → `use of an undeclared variable`（退出 1）；无括号 `_Alignof T` →
`_Alignof needs a type in parentheses`（退出 1）；`sizeof(T *)` → `sizeof(int *)`。
残余只落在「`sizeof` 无括号 + 类型参数」这一条解析分支。

### 11.4 新增负例的“会红”验证

在 `/tmp` 副本上做两组独立变异（只改实现副本，不动仓库），再用 `check-ast.sh` 同一条
`file:line:col: error:` 判定：

```console
# A. 删掉 _Generic 守卫
$ /tmp/p261/mut-sel/b/ct-ast test/ast/errors/generic_generic_selector.ct -o ...
ct_exit=0
$ grep -n '_Generic' ...
11:    return _Generic ( x , T : 1 , default : 0 );
RED

# B. MAX_GENERIC_INSTS 64 → 1000000
$ /tmp/p261/mut-many/b/ct-ast test/ast/errors/generic_too_many.ct -o ...
ct_exit=0
RED

# C. v0.26.0 基线
$ ct-ast-v0.26.0 test/ast/125_generic_type_positions/prog.ct
test/ast/125_generic_type_positions/prog.ct:21:12: error: unexpected token   （exit 1）
$ ct-ast-v0.26.0 test/ast/126_generic_struct_tag/prog.ct ...; grep getv__ct1 ...
static struct int getv__ct1(struct int *);                                    （exit 0，坏产物）
```

两条新负例都不是“恒绿断言”；127 的 R6 回退在基线已工作，只作既有行为固定。

### 11.5 P2 观察

- `_Generic(x, struct T: 1, ...)` 在泛型体内被误拒
  （`7:31: error: type parameter cannot be used inside _Generic`）：方向安全，但把标签名也一并拒绝，
  损失表达力。修复 SH-62 时应只拒绝裸类型参数。
- 复核轮未改任何代码/测试；所有探针与变异都在 `/tmp/p261/**`。

---

## 12. `v0.26.2` 收尾复核（2026-11-09，锚点 `5b43fac`）

### 12.1 结论

| Issue | 结论 | 判据 |
| --- | --- | --- |
| SH-62 | **verified** | 无括号 `sizeof T` / `_Alignof T` / `alignof T` / `sizeof T * 2` / `sizeof(T) + sizeof T` 全部真替换，运行 `4 4 8 8` |
| TEST-17 | **verified** | 128 夹具与 `tparam_residue()` 属实；817 数字核实；旧基线与变异均能令其变红；盲区见 12.3 |
| **SH-64（新）** | **open / P1** | 类型参数出现在**值**位置（`return T;` / `h(T)` / `sizeof T * T` / `sizeof T + T`）仍退出 0 发射裸 `T`，`cc` 报未声明 |

**Phase 26 仍有阻断**：`ct compile` 仍存在“退出 0 发射未声明类型名”的路径，见 12.6。

### 12.2 无括号类型操作数（SH-62）

```console
$ /tmp/p262/b/ct-ast -v
ct-ast v0.26.2
$ /tmp/p262/b/ct-ast probe/operands.ct -o out/operands.c; echo ct=$?
ct=0
$ grep -nE 'sizeof|_Alignof' out/operands.c
16:    return (int)(sizeof(int));
20:    return (int)(_Alignof(int));
24:    return ((int)(sizeof(int)) * 2);
28:    return (int)((sizeof(int) + sizeof(int)));
$ cc -Wall -Wextra -std=c99 out/operands.c -o out/operands && ./out/operands
4 4 8 8
```

标签形式 `sizeof struct T` / `_Alignof(struct T)` → `sizeof(struct T)` / `_Alignof(struct T)`，运行 `4 4`；
无括号 `alignof T` → `alignof(int)`。`sizeof T * 2` 的优先级正确（`((int)sizeof(int)) * 2`）。

### 12.3 `tparam_residue()` 的拦截、放行与盲区

拦截与放行（用门禁同款 shell 函数复算）：

```console
# v0.26.1 坏产物
tparam_residue(probe/sizeof_noparen.ct, p-sizeof_noparen.c) = T(1)      → RED
# v0.26.2 新产物
tparam_residue(probe/operands.ct, out/operands.c) = ""                  → GREEN
tparam_residue(repo/test/ast/126_generic_struct_tag/prog.ct, out/126.c) = ""  → GREEN
```

126 的产物共有 7 处 `T`，全部形如 `struct T`；去掉 `\b(struct|union|enum)\s+T\b` 豁免后会误红，
说明豁免是载荷性的（`_Generic(..., struct T: …)` 依赖它）。

**盲区（P2，已记录）**：

1. 非泛型夹具完全不扫（源码没有 `<TP>` 声明，提取为空）；该场景由门禁的 `cc` 编译兜底。
2. 全文本计数会在“类型参数名与既有标识符/宏/字符串重名”时**误报**：`int T = 5;` + `f<T>` 的产物判
   `T(2)`，但 `cc` 0 且运行输出 `5 4`；`#define T 42`、`printf("T=…")` 同样会误红。
3. 只扫 `test/ast/*/` 单文件夹具的 `.c`；`.h`、`test/ast/errors/*`、module/build 产物不扫。
   imported `.h.ct` 里的泛型声明不在被扫源码内，提取不到参数名。
4. 提取依赖单行出现 `<TP>(`；当前 `f<T>(` 行内形态可命中，跨行且函数名与 `<` 分离的变体需复核。

### 12.4 新增夹具的“会红”证明

```console
# 旧基线（v0.26.1 源码编出的 ct-ast）
$ ct-ast-v0.26.1 test/ast/128_generic_type_operands/prog.ct
test/ast/128_generic_type_operands/prog.ct:16:26: error: _Alignof needs a type in parentheses   （exit 1）
$ ct-ast-v0.26.1 test/ast/126_generic_struct_tag/prog.ct
test/ast/126_generic_struct_tag/prog.ct:22:31: error: type parameter cannot be used inside _Generic （exit 1）

# 变异：把 parse_unary 的 `if (self->tok_is_type_name())` 置 0 后重编
$ ./b/ct-ast test/ast/128_generic_type_operands/prog.ct -o out/128-mut.c
ct=0；产物含 sizeof(T)，cc 报 ‘T’ undeclared（exit 1）
```

`v0.26.2` 下 128 与 126 均绿；817 = 815 + 128 用例 + `p26_generic_type_operands` 断言。

### 12.5 门禁实跑

```console
$ bash selfhost/check-ast.sh | tail -1
== summary: 817 passed, 0 failed ==
$ bash selfhost/check-all.sh | tail -1
check-all: OK (11 hard gates green)
$ grep -nE '^== summary:|check-all: OK' /tmp/p262-all.log | tail -8
== summary: 118 passed, 0 failed ==
== summary: 82 passed, 0 failed ==
== summary: 817 passed, 0 failed ==
check-semantics: OK (23 assertions)
check-docs: OK (863 relative links in 173 files, v0.26.2, 11 hard gates, 10 phase status, 3 适用版本 header(s))
== summary: 20 pass, 0 new, 0 pending, 0 regression ==
check-all: OK (11 hard gates green)
```

评审回写后复跑 `python3 test/docs/check-docs.py` → `866 relative links in 173 files`（新增 SH-64 与 §12 链接）。
`817 passed` 属实。

### 12.6 阻断项：值位置类型参数（SH-64）

```console
$ /tmp/p262/b/ct-ast probe/leak1.ct -o out/leak1.c; echo ct=$?
ct=0
$ grep -n 'return' out/leak1.c | tail -1
10:    return T;
$ cc -std=c99 out/leak1.c -o out/leak1.bin; echo cc=$?
out/leak1.c:10:12: error: ‘T’ undeclared (first use in this function)
cc=1
```

同族的 `return h(T);` → `return h(T);`、`sizeof T * T` → `(sizeof(int) * T)`、
`sizeof T + T` → `(sizeof(int) + T)` 全部退出 0。对照：小写类型参数
`g<elem>(elem x){ return elem; }` 与非泛型 `return Zzz;` 均硬错；非泛型 `return T;` 退出 0
属 ALL_CAPS 宏常量设计，但泛型体内 `T` 已声明为类型参数，不应再走该兜底。

根因在 [Expr.h.ct](../../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3258-L3275)：ALL_CAPS 兜底
在发射 `N_RAW` 前没有检查 `self->in_generic && strcmp(nm, self->in_generic_tparam) == 0`。
`tparam_residue()` 可检出该残留（`leak1/2/4` → `T(1)`），但只有夹具覆盖到该形态时才触发，
不能替代编译期硬错。关闭条件与建议见 [SH-64](../../../issues/selfhost/sh64-generic-tparam-value-position.md)。
