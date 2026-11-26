# REVIEW：`Str` / `String` 直接打印入口提案（LANG-30 / REQ-PRINT-1）

| 项 | 值 |
| --- | --- |
| 基线 | `84a7ad07`（v1.1.0-204，2026-11-27） |
| 评审对象 | [str-print-api 提案](../proposals/str-print-api.md)、[LANG-30](../../issues/lang/lang-30-str-print-api.md)、[REQ-PRINT-1](../planning/requirements-pool.md) |
| 角色 | REVIEW |
| 结论 | **方向接受（方案 A），但“可实施”结论暂不成立**：`fwrite`/`stdout` 的 C 边界落点没有定到文件与声明；零分配也没有可判据。补齐这两项后可以进 DEV。 |

## 0. 结论先行

提案把问题定得很准：`cstr()` 会分配，`printf("%s")` 又只认 C 字符串，所以 E3 的 26 个样例
“去指针”只能变成“`cstr()` + `free`”，没有真正减少指针/分配。

推荐方案 **A（`Str.print()` / `Str.println()`，`String` 转发）** 是正确的 API 方向：
- 方法面与 `Vec`/`Map`/`Box` 一致；
- 零格式化、零分配，`Str` 的 `{ptr,len}` 语义直接可用；
- 不需要改 `printf` 的 C 语义。

但当前提案还缺两个**实施前必须钉死**的条件：

1. **`fwrite` / `stdout` 的 C 边界落点**：§4.67 的自动补头集合只覆盖 `printf`/`scanf`/`puts`
   一族，`fwrite` 不在其中；提案只写“`.m.ct` / shim”是方向，不是可执行的落点。
2. **“零分配”的证据**：ASAN 无泄漏不等于零分配；需要分配计数（或禁用 `cstr()` 路径的断言），
   否则验收第 1 条无法判。

## 1. 提案与现状核对

| 项 | 提案说法 | 现状 | 判定 |
| --- | --- | --- | --- |
| `cstr()` 会分配，调用方 `free` | `String.cstr` / `Str.cstr` | `lib/core/Str.h.ct` 仍是一个文件，`cstr` 在 `String`/`Str` 上分别实现 | 成立 |
| `lib/core` 没有 `print`/`puts`/`write` | 无文本出口 | `grep 'pub .*print' lib/core` 无命中 | 成立 |
| E3 26 个样例阻塞 | [pointer-free-exemptions](../planning/pointer-free-exemptions.md) E3 | 清单在；26 个文件未改 | 成立 |
| `fwrite` 补头 | 不在 §4.67 集合 | 需要 shim/`.m.ct` 或扩补头集合 | 提案只给方向，缺落点 |
| `String` 转发 | `String.print` → `as_str()` | 可行；但 `lib/core/String.h.ct` 尚不存在（SH-120 拆分未落） | 需写“拆分后/当前文件”二选一 |
| 零分配 | “ASAN 无泄漏” | ASAN 只能证明未泄漏，不能证明未分配 | 判据不足 |

## 2. P1：`fwrite` / `stdout` 边界必须先定

提案的 §3 写：

> 要么把它加进补头集合（改 spec，影响面大），要么在 `lib/core` 里用 `.m.ct` / shim 声明
> （与 S9 的迁移方向一致，推荐后者）。

这是正确的取舍方向，但还不是实施设计。需要至少写清：

1. **文件**：是 `lib/core/StrPrint.m.ct`，还是 `lib/core/str/StrPrint.m.ct`（取决于 SH-120 的目录）？
2. **声明**：`fwrite(const void *, size_t, size_t, FILE *)` 与 `stdout` 用哪个 C 头/符号；
   `size_t`/`FILE` 的 typedef 从哪来；
3. **C 边界**：`.m.ct` 是否允许 `#include <stdio.h>`？若不允许，shim 的目录、命名、链接方式是什么；
4. **失败语义**：`fwrite` 返回值忽略还是检查；`stdout` 写失败是否静默（提案说与 `printf` 一致，
   可以接受，但要在 spec 里写成契约）。

没有这四项，DEV 只能边写边猜；而 `lib/core` 是自举层，猜错的代价是 seed/global 迁移。

**建议**：在提案里加一张“边界落点表”，把 `.m.ct`/shim 的具体路径与声明写成可审查的文本；
这属于 REQ/DEV 补，不是 REVIEW 代写。

## 3. P1：“零分配”需要可判据

提案验收第 1 条：

> `print` / `println` 在 `ct build` 与 `ct compile` 下都可用，零分配（ASAN 无泄漏）。

ASAN 的 leak check 只能说明“没有泄漏”，不能说明“没有分配”。如果实现里偷偷调用 `cstr()`，
再把返回值 `free`，ASAN 仍可能全绿，但提案要解决的“去指针/去分配”没有发生。

建议验收改成至少两条：

1. 用 `--alloc` 注入自定义 allocator（或现有 `ct` 的分配计数钩子）记录 `print` 调用前后
   分配次数不变；
2. 生成 C 的 `Str_print` 路径里不出现 `cstr` 调用（`grep` 可判），并用含内嵌 `\0` 的
   `Str` 测 `fwrite` 的字节语义（`printf("%s")` 会截断，`fwrite` 不会）。

这样“零分配”和“字节透传”两个承诺才都有证据。

## 4. P2：API 细节

| # | 问题 | 建议 |
| --- | --- | --- |
| A | `print`/`println` 是否与用户已有方法冲突 | `Str`/`String` 是内建类型，方法表新增；在 spec 里写明“这是内建方法，不是可覆盖 trait 方法” |
| B | `println` 的换行 | 明确写 `\n` 一个字节；Windows 文本模式由 C runtime 处理，不承诺 `\r\n` 字节 |
| C | 空视图 | `len == 0` 写 0 字节；`println` 仍写换行；加空 `Str` 用例 |
| D | `String` 转发 | `String.print` 必须等价于 `self.as_str().print()`；不要在 `String` 里再走 `cstr` |
| E | `cstr()` | 保留，但文档明确“仅 C 互操作，会分配”；不要在新样例里继续用 |
| F | 错误处理 | 只做 stdout；写失败静默，与 `printf` 一致；stderr 另立需求，不夹带 |
| G | 文件落点 | 当前 `lib/core/Str.h.ct` 单文件；SH-120 未落。提案应写“当前落到 `Str.h.ct`；SH-120 落地后移到 `String.h.ct`/`Str.h.ct`”，否则 `String.h.ct` 是空引用 |

## 5. P2：与 TEST-27 / SH-120 的关系

- E3 的 26 个样例是 [TEST-27](../../issues/testing/test27-feature-examples-pointer-free.md) 的硬阻塞；
  提案通过后，H4 的 E3 部分才能动；不要先改样例再补 API。
- SH-120 的 `String`/`Str` 拆分尚未落地；本提案的方法最终应落在拆分后的
  `lib/core/String.h.ct` / `Str.h.ct`。如果 SH-120 先落，提案的落点表要同步；如果本提案先落，
  先写进当前 `Str.h.ct`，SH-120 再搬。
- 这不影响方案 A 的 API 方向，但影响“改哪个文件”的验收。

## 6. 结论与处置

**REVIEW 结论：方案 A 接受，B 作为退路，C 不采纳；但提案需补 P1 两项后才能进 DEV。**

需要 REQ/DEV 补的：

1. `fwrite`/`stdout` 的具体 `.m.ct`/shim 路径、声明与失败语义（P1）；
2. 零分配的分配计数判据 + 内嵌 NUL/空视图用例（P1）；
3. 文件落点按当前 `Str.h.ct` 或 SH-120 后的 `String.h.ct`/`Str.h.ct` 二选一（P2）；
4. spec 新节、glossary、tutorial、README 0.5 段同批更新（P2）。

补完后由 DEV 实施，TEST-27 H4/E3 再跟进。本报告不改代码、不改 status；`LANG-30` 仍 `open`。

> 签收: REVIEW 2026-11-27（待 EDITOR）。
