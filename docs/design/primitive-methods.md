# 基本类型方法 · 设计与实施记录

> 中文 · [English](#english)
> 状态：**已完成（P0 / P1 / P2 全部落地并验证）** · 2026-11-06
> 锚点：工作树 `v0.19.1`（未 bump 版本、未打 tag）；P0 用现装 `ct v0.19.1` 自举并对拍
> 关联：同级仓库 `ct-pkg` 的 `std` 包（落点：`std::str` / `std::num`；仓库外路径，不在此仓库内链）· `std` 包（`ct get std` 后为 `vendor/std/std/README.md`，对照约定）
>
> **2026-11-06 更新**：`ct-pkg/clib` 已删除、版本线重置到 `0.1.0`，本文的落点改为 `ct-pkg/std`
> （`std::str::String` / `std::num`）。下文出现的 `clib` 路径是当时的方案记录。

---

## 中文

### 1. 目标

让基本类型具备方法写法，例如 `(5).toString()`、`a.cmd.compare("status")`、`s.len()`、
`d.sqrt()`。生成物仍是手写质量的 C：**没有 wrapper、没有 vtable、没有间接调用**。

不在本批范围：泛型、运算符重载、`void *` 上的通用方法（与 `png` 包冲突）、自动内存管理。

### 2. 已批准的取舍（用户 2026-11-06 拍板）

| # | 决策 | 结论 |
| --- | --- | --- |
| 1 | 落点 | **`ct-pkg/clib`**，与 `String` / `Math` / `Stdio` 同层；`std` 包保持「只用 `pub` 自由函数」 |
| 2 | 字符串化 | `toStr(buf, cap)` 为**正确路径**；`toString()` 为 4 槽环形缓冲**便利版**，文档写死「非线程安全、多值打印会互相覆盖」 |
| 3 | 类型键 | 在 `map_type_key` 做**最小归一化**：丢弃任意位置的 `const` / `volatile`（有损，键仅用于宿主匹配）、整数别名合并 |
| 4 | `void *` | **不做**通用指针方法（`png` 的 `Handle` 已占用 `width/height/pixels/stride/close/free`） |
| 5 | 比较语义 | 保留 `compare`（= `strcmp(receiver, argument)`），新增 `equals` |

约束：不 bump 版本、不打 tag；编译器改动只落 `selfhost/ct-ast/**`；不动 L0/L1/L2；不重生成既有 golden；
既有与本事无关的代码（含 `png`）不动。

### 3. P0：编译器前置

四条改动，彼此独立，可单独回退。

| # | 文件 | 改动 | 阻塞的写法 |
| --- | --- | --- | --- |
| P0-1 | `frontend/type/TypeCheck.h.ct` `expr_type` | 新增 `N_NUM` / `N_FNUM` / `N_STR` 分支 | `(5).toString()`、`(1.5).sqrt()`、`"x".equals(y)` |
| P0-2 | 同上 `N_MEMBER` / `N_ARROW` 分支 | 字段 `dims` **只含一个** `[` 时输出 `type + " *"`（数组 decay）；多维字段无法拼写元素类型，保持「无法推断」 | `a.cmd.compare(...)`（`cmd` 是 `char[16]`） |
| P0-3 | `tool/driver/Driver.h.ct` `check` 分支 | `unit_is_map` 按输入后缀 `.m.ct` 置位 | `ct check foo.m.ct` 误报 `a type host is only allowed in a .m.ct unit` |
| P0-4 | `backend/emit/Emitter.h.ct` `map_type_key` | 丢弃任意位置的 `const` / `volatile`；整数别名合并（`unsigned`↔`unsigned int`、`long`↔`long int`、`short`↔`short int`、`signed` 前缀丢弃） | `const char *` 接收者、`unsigned` / `long` 与长写混用（`size_t` **不折叠**，见 §7） |

#### P0-1 的细节

- `N_NUM` 的 `text` 存**规范化后缀**（`Emitter.h.ct` 的 `N_NUM` 发射注释已写明）：
  无后缀 → `int`，`U` → `unsigned`，`L` → `long`，`UL` → `unsigned long`，
  `LL` → `long long`，`ULL` / `LLU` → `unsigned long long`。
- `N_FNUM` 保留原始拼写（`1.5` / `2.25f` / `1e9`）：尾字母 `f` → `float`，`L` → `long double`，否则 `double`。
- `N_STR`：以 `'` 开头的是字符字面量，按 C 语义给 **`int`**；其余给 `char *`。

#### P0-4 的归一化规则

只做**文本层**等价，不做语义转换：不改写 `host_type` 的原文（`&p` 的 compound literal 与 `sizeof p`
仍用声明拼写），只在比较用的键上**丢弃任意位置**的 `const` / `volatile`、合并整数别名。因此
`const char *`、`char *`、`char * const` 都归到同一个键 `char*`。这一步是**有损归一化**：键只用于
宿主匹配，绝不回写声明——`sizeof`、compound literal、生成 C 的类型拼写都保持原文。

### 4. P1：纯映射（A 类）

新增 `ct-pkg/clib/clib/Str.m.ct`（字符串宿主）与 `ct-pkg/clib/clib/Num.m.ct`、`Real.m.ct`（数值宿主）。
`.m.ct` 不产 `.c` / `.h`，删文件即回退。

#### 4.1 `char *` / `const char *`

| 方法 | 签名 | recipe | 类 |
| --- | --- | --- | --- |
| `len` | `unsigned long len()` | `strlen(s)` | A |
| `compare` | `int compare(char *other)` | `strcmp(s, other)` | A |
| `toInt` | `int toInt()` | `atoi(s)` | A |
| `toDouble` | `double toDouble()` | `atof(s)` | A |
| `equals` / `startsWith` / `contains` / `indexOf` | — | 见 P2 | B |

#### 4.2 数值

| 类型 | 方法 | recipe | 类 |
| --- | --- | --- | --- |
| `int` | `abs` | `abs(v)` | A |
| `long` / `long long` | `abs` | `labs` / `llabs` | A |
| `float` / `double` | `abs` / `sqrt` / `floor` / `ceil` / `round` | `fabsf`… / `sqrtf`… | A |
| `double` | `isNan` / `isInf` | `isnan` / `isinf` | A |
| `int` | `isDigit` / `isAlpha` / `isSpace` / `isUpper` / `isLower` | `isdigit`… | A−（见 P2 安全版） |

> `'7'.isDigit()` 命中的是 **`int`** 宿主：C 的字符字面量类型是 `int`。

### 5. P2：shim（B 类）

shim 文件 `<base>.shim.h` 必须与 `.m.ct` **同名同目录**，否则不会被自动包含。

| 方法 | 形态 | shim |
| --- | --- | --- |
| `toStr(buf, cap)` | `char *toStr(char *out, int cap)` | `snprintf` |
| `toString()` | `char *toString()` | 4 槽环形 `static char[4][32]` |
| `equals` | `int equals(char *other)` | `strcmp(...) == 0` |
| `startsWith` | `int startsWith(char *prefix)` | `strncmp(s, p, strlen(p)) == 0` |
| `contains` | `int contains(char *needle)` | `strstr(s, n) != 0` |
| `indexOf` | `int indexOf(char *needle)` | `strstr` 差值，缺席 `-1` |
| `clamp` / `max` / `min` | `int clamp(int lo, int hi)` 等 | 三目 |
| `toUpper` / `toLower` | `int toUpper()` | `toupper((unsigned char)v)` |
| `toBase` | `char *toBase(int base, char *out, int cap)` | 手写进制 |
| `isDigit` 等安全版 | `int isDigit()` | `isdigit((unsigned char)v)`，非负保护 |

### 6. 验证

| 阶段 | 验证 | 结果 |
| --- | --- | --- |
| P0 | 全量对拍：`test/{ast,acceptance,patterns,std,unit,cases}` 全部单文件 + `test/modules` 全量 `build`，输出/错误/退出码与现装 `ct` **逐字节零差异**；`ct check` 对仓库内所有 `.m.ct` 返回 0 | 182 个单文件 + 105 次 build，**0 差异**；当时 17 个 `.m.ct`（ct 7 + ct-pkg 10）中 16 个返回 0，`map_unit_chain/lib/lib.m.ct` 因 check 不解析 import 在旧/新下同样返回 1；`selfhost/check-ast.sh` 465 passed / 0 failed |
| P1 | 每个方法一个最小示例；生成 C 为直接调用；`-Wall -Wextra` 无告警；`-O2` 反汇编无 `blr` | 全部通过（`blr=0`） |
| P2 | 同上；另加「同一表达式两次 `toString()`」的行为测试，以及 shim 改名后的负例（应报未声明函数） | 全部通过；负例已进 `selfhost/check-ast.sh`（`a shim header must share the .m.ct base name`）；「两次 `toString()` 互不覆写」由 `map_unit_literals` 夹具断言（两个槽位，输出 `5 6`） |

回退：P1/P2 删对应 `.m.ct` + `.shim.h` 即成对回退；P0 的四条是独立 hunk。

> 关于上表的数字：**182 / 105 / 465 目前没有脚本可复现**。182 与 105 来自当时的临时对拍脚本
> （归一化路径、缓存键与 mtime 后比较），仓库内没有留下；465 是当时 `selfhost/check-ast.sh` 的通过数，
> 会随断言增删变化。对拍脚本另开一批，本批不做。

### 7. 已知限制（写进 clib 文档）

- `5.toString()` 不能写：`5.` 被词法吞成浮点字面量，必须 `(5).toString()`。`2.0.sqrt()` 反而可解析。
  统一规定：**数值字面量接收者一律加括号**。
- recipe 只能是一次顶层调用，实参里只允许绑定参数与字面量（`s + 1` 可以，`strlen(p)` 不行），
  所以任何需要二次调用的能力都必须进 shim。
- 类型宿主按声明文本匹配，不做隐式提升；归一化只覆盖**任意位置**的 `const` / `volatile` 与整数别名。
  `size_t` **不折叠**——宿主须照写 `unsigned long`，声明为 `size_t` 的变量直接调用会报 `no method`。
- 多维数组字段（如 `char names[2][8]`）decay 后的类型是 `char (*)[8]`，没有宿主能拼写，故按「无法推断」
  处理（构建报 `cannot resolve the method trait (unknown receiver type)`），不会静默变成 `char *`；
  `sizeof s.names` 走 `N_SIZEOF`，仍给 `int`，不受影响。
- 带符号负字面量（`(-5).abs()`）是**一元表达式**而不是字面量，`expr_type` 不为其推断类型；
  先赋给变量再调用。正字面量仍必须加括号（`5.toString()` 不解词）。

### 8. 实施记录（实际落地）

#### 8.1 编译器（`selfhost/ct-ast/**`，未 bump 版本）

| 文件 | 实际改动 |
| --- | --- |
| `frontend/type/TypeCheck.h.ct` | 新增 `N_NUM` / `N_STR` / `N_FNUM` 宏；`expr_type` 三个字面量分支（后缀细分）；`N_MEMBER` / `N_ARROW` 数组字段 decay（仅单维，多维返回「无法推断」）；`type_key` 归一化 |
| `backend/emit/Emitter.h.ct` | `map_type_key` 与前端 `type_key` 完全同表（注释写明两文件必须一起改） |
| `tool/driver/Driver.h.ct` | `unit_is_map` 按输入 `.m.ct` 后缀置位 |
| `frontend/parse/Expr.h.ct` | 配套修正：`argtype_check` 放行「指针形参 + 字面量 `0`」。字面量有了类型后，编译器编自己源码会对 `emit_field_vptrs(si, has_vptr, 0)` 产生 3 条假警告，而 9.6 自举门禁要求 warning-free；`0` 本就是空指针常量，放行后全量语料零差异 |

既有 golden 未重生成；L0/L1/L2 未改。

#### 8.2 clib（新增 6 个文件）

- `Str.m.ct` + `Str.shim.h`：`len` / `compare` / `equals` / `startsWith` / `contains` / `indexOf` /
  `toInt` / `toDouble`。
- `Num.m.ct` + `Num.shim.h`：`int` 宿主（`abs` / `isX` / `toUpper` / `toLower` / `clamp` / `max` /
  `min` / `toStr` / `toString` / `toBase`），`long` / `long long` 宿主（`abs` / `toStr` / `toString`）。
- `Real.m.ct` + `Real.shim.h`：`float` 与 `double` 的 `abs` / `sqrt` / `floor` / `ceil` / `round`，
  `double` 另有 `isNan` / `isInf` / `toStr` / `toString`。
- `len` 实际签名为 `unsigned long`（recipe 直接展开 `strlen`，声明成 `int` 会让 `-Wall` 在调用点报格式不匹配）。
- `toUpper` / `toLower` 实际声明为 `int`（ctype 的返回类型），不是 `char`。
- `toString()` 的环形缓冲：整数与浮点各自 4 槽 × 32 字节，**非线程安全**，第五个存活结果覆盖第一槽。
- `png` 的 `void *` 映射未动；未新增任何 `void *` 宿主。

#### 8.3 负例

`selfhost/check-ast.sh` 新增一条：`lib.m.ct` 旁放 `Wrong.shim.h` → CT 层构建成功但生成 C 不含该头，
`cc` 报 `call to undeclared function`。断言同时检查「未包含」和「C 构建失败」，避免依赖具体编译器措辞。

---

## English

### 1. Goal

Give primitive types method spellings — `(5).toString()`, `a.cmd.compare("status")`, `s.len()`,
`d.sqrt()` — while the generated C stays hand-written quality: no wrapper, no vtable, no indirect call.

Out of scope: generics, operator overloading, a generic `void *` host (it would collide with the
`png` package), automatic memory management.

### 2. Approved trade-offs (user, 2026-11-06)

1. Location: **`ct-pkg/clib`**, beside `String` / `Math` / `Stdio`; the `std` package keeps its free-function shape.
2. Stringification: `toStr(buf, cap)` is the correct path; `toString()` is a four-slot ring-buffer
   convenience, documented as non-thread-safe and alias-prone.
3. Type keys: minimal normalisation inside `map_type_key` — drop `const` / `volatile` wherever they
   appear (a lossy key used only for host matching), merge integer aliases (`unsigned` = `unsigned
   int`, `long` = `long int`, …).
4. No generic `void *` host (the `png` `Handle` map owns that type).
5. Keep `compare` (`strcmp(receiver, argument)`) and add `equals`.

### 3. P0 — compiler prerequisites

| # | Site | Change | Unblocks |
| --- | --- | --- | --- |
| P0-1 | `expr_type` | add `N_NUM` / `N_FNUM` / `N_STR` | `(5).toString()`, `(1.5).sqrt()`, `"x".equals(y)` |
| P0-2 | `expr_type`, member branch | decay an array field to `type + " *"` only when its `dims` hold exactly one `[`; a multi-dimensional field stays unknown | `a.cmd.compare(...)` on `char[16]` |
| P0-3 | driver `check` branch | set `unit_is_map` from the `.m.ct` suffix | `ct check foo.m.ct` false positive |
| P0-4 | `map_type_key` | drop `const` / `volatile` at any position, merge integer aliases | `const char *` receivers, `unsigned` / `long` vs their long spellings (`size_t` is **not** folded — §7) |

### 4–5. P1 / P2

P1 is pure `map ... for type` (A class: `strlen`, `strcmp`, `atoi`, `abs`, `sqrt`, `floor`, `isnan`, …).
P2 adds `<base>.shim.h` with `static inline` helpers for everything a single C call cannot express
(`equals`, `startsWith`, `contains`, `clamp`, `toStr`, ring-buffer `toString`, `toBase`).
A shim must share the base name of its `.m.ct` or it is never included.

### 6. Verification

Byte-identical output over the whole corpus for P0; one minimal example per method plus `-Wall
-Wextra` and `-O2` disassembly (no `blr`) for P1/P2; a negative test for a misnamed shim.

### 7. Known limits

`5.toString()` does not lex (`5.` is a float literal) — always parenthesise numeric literal receivers.
A recipe is one top-level call whose arguments may only mention binding parameters and literals, so
anything needing a second call lives in a shim. Type hosts match declared text exactly, with only the
normalisation of §2.3: every `const` / `volatile` is dropped regardless of position (a lossy key, never
written back into a declaration), and `size_t` is **not** folded — the host must spell `unsigned long`,
and a `size_t` variable is not a receiver. A multi-dimensional array field (`char names[2][8]`) decays to
`char (*)[8]`, which no host spells, so it stays unknown instead of becoming `char *`; the build fails
with `cannot resolve the method trait (unknown receiver type)`, while `sizeof s.names` still comes from
`N_SIZEOF` and is unaffected.

### 8. Implementation record

Compiler (`selfhost/ct-ast/**`, no version bump): `TypeCheck.h.ct` gained the three literal branches and
the member-array decay plus the `type_key` normalisation; `Emitter.h.ct`'s `map_type_key` carries the
identical table; `Driver.h.ct` sets `unit_is_map` from the `.m.ct` suffix; `Expr.h.ct` accepts a literal
`0` for a pointer parameter (without it the literal's new static type turned three self-hosting calls
into false warnings and broke the warning-free gate).

`clib` gained six files: `Str.m.ct` / `Num.m.ct` / `Real.m.ct` and their same-named `.shim.h`.
`len` is `unsigned long` (it expands to `strlen`), `toUpper` / `toLower` return `int`, and each
`toString()` ring is four static 32-byte slots — not thread-safe, and the fifth live result reuses the
first slot. `png`'s `void *` host was left untouched.

Verification: 182 single-file cases and 105 module builds byte-identical to the installed `ct`;
`selfhost/check-ast.sh` 465 passed / 0 failed; `-Wall -Wextra` clean and zero `blr` at `-O2` on the
generated C. The misnamed-shim negative now lives in `selfhost/check-ast.sh`; batch 40 adds
`test/ast/66_type_host_literals` (suffixes, float spellings, `const` / alias keys, one- vs
two-dimensional fields), `test/modules/map_unit_literals` (literal receiver + shim + two ring slots in
one expression) and two `ct check` assertions (a valid `.m.ct` exits 0, a drifted signature does not).

Those counts — **182 / 105 / 465 — have no script that reproduces them today**. The first two came from
a throwaway diff harness (paths, cache keys and mtimes normalised before comparing) that was not kept in
the tree; 465 is whatever `selfhost/check-ast.sh` reported at the time and moves as assertions are added.
The diff harness is a separate batch; this one does not build it.
