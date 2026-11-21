# PH-84（v0.84.0）REV 复核

> 复核席位：REV（`rev-ph84`） · 2026-11-21
> 对象：`d863fedb3580e3ac7dbebb6e77e9e9dce92288db`（HEAD，未 push、未 tag）
> 环境：macOS arm64；Apple clang 21.0.0；Python 3.15.2
> 方法：`git archive d863fedb` 解到 `/tmp/rev84.pqwAG8/src`，按 L0→L1→L2→ct-ast 自举链独立重建；所有探针只用该归档产物 `/tmp/rev84.pqwAG8/work/ct-ast`，未用工作树二进制；未改实现。
> 结论：**REV: 不通过（打回）**。E84-1/2/4/6/7/8 的核心行为通过；E84-3、E84-5、E84-9 在 **typedef ADT** 形态上不满足（F1/F2）。
>
> **v0.84.1 复核（2026-11-21）：`REV: 通过`**，见文末 §9；§0–§8 为首轮记录，保留不改写。

## 0. 结论摘要

- **F1（阻断）**：`typedef enum Shape { … } Alias;` 的别名不能作 `match` 主语。同单元 `Alias`、`Alias *` 与跨单元 `lib_Alias` 都被拒，错误为 `match needs an ADT value, but 'Alias' is not an ADT`；spec §4.73 与卡 D84-1 都写明“tag 和别名都命名同一个和类型”。合法穷尽 `match` 被误拒，E84-3 不满足。
- **F2（阻断）**：`pub typedef enum Shape { … } Alias;` 跨单元时，消费者使用 tag 名 `Shape` 被 ct 接受，但生成的 `prog.c` 仍写 `Shape`；头文件只发布 `typedef struct lib_Shape … lib_Alias;`，没有 `Shape`，`cc` 报 `unknown type name 'Shape'`。这是可复现的错发射；`ct build` 只有靠 `cc` 才失败。E84-5 的“`pub` ADT 跨单元产物干净”对 typedef 形态不成立。
- 通过项：E84-1（无负载 enum 5/5 产物与 ec355f40 一致）、E84-2（构造/arity/可判定类型）、E84-4（按值绑定/无 fallthrough/`break` 属外层循环）、E84-6（291 与 switch 同值）、E84-7（check-all/warnings/sanitizer）、E84-8（文档/冻结清单/回滚演练）。
- 新增反例（正向）：嵌套 match、分支内改 payload、ADT 副本语义、`pub` ADT（非 typedef）跨单元、混合 payload、`continue` 在臂内；全部 ASan/UBSan 干净，未发现 UAF/错发射（F2 除外）。

## 1. 自举（独立构建）

```console
$ R=$(mktemp -d /tmp/rev84.XXXXXX); mkdir -p "$R/src" "$R/work"
$ git archive d863fedb | tar -x -C "$R/src"
$ cc -Wall -Wextra -std=c99 "$R/src/selfhost/l0/ctc.c" -o "$R/work/ctc"
$ "$R/work/ctc" "$R/src/selfhost/l1/ctc.ct" -o "$R/work/l1.c"
$ cc -Wall -Wextra -std=c99 "$R/work/l1.c" -o "$R/work/l1"
$ (cd "$R/src" && "$R/work/l1" build selfhost/l2/driver.ct -o "$R/work/l2src")
$ cc -Wall -Wextra -std=c99 "$R/work/l2src"/*.c -o "$R/work/l2"
$ (cd "$R/src" && "$R/work/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$R/work/astsrc")
$ cc -Wall -Wextra -std=c99 "$R/work/astsrc"/*.c -o "$R/work/ct-ast"
$ "$R/work/ct-ast" -v
ct-ast v0.84.0
```

L0/L1/L2/ct-ast 各步 `cc` 零警告、退出码 0。以下 `$CT` 指该归档产物。

## 2. E84-1…9 逐条

| ID | 结果 | 命令 / 原始输出 | 判定 |
| --- | --- | --- | --- |
| E84-1 | ✅ | `bash test/ast/p84_syntax.sh $CT` → `p84syntax: 14 passed, 0 failed`；另对 `30_enum`、`54_attribute`、`271_qualified_enum`、`c-superset/s01_switch`、`c-superset/s04_enum` 与 ec355f40 构建产物做 banner 归一化 `cmp`，五个 `same:` | 带负载 enum 解析为 ADT；无负载 enum 的 C 产物与旧构建一致 |
| E84-2 | ✅（注 O2） | `p84syntax: 14 passed`；arity/参数类型硬错见 §3.1；`int n = Shape.Circle(4)` 只在 `ct check --types` 下报 `initializer: expected 'int', got 'struct Shape'` | 构造与 arity 正确；可判定类型冲突按 §4.53 走 `--types` |
| E84-3 | ❌ | 核心 `p84match: 10 passed`、`p84errors: 11 passed`（漏/重/未知/跨 ADT/绑定数/重名/`_` 位置均带位置）；但 `Alias` 主语被拒（§3.2 F1） | 核心穷尽/诊断通过；typedef 别名合法穷尽 match 被误拒 |
| E84-4 | ✅ | `p84layout: 21 passed`；`290` 输出 `102 12 -1 / 2 102 / 2 3`；独立 `copy.ct` 输出 `99 5`、`1 2`；`loopcont.ct` 输出 `48` | 绑定按值、无 fallthrough、`break`/`continue` 仍属外层循环 |
| E84-5 | ❌ | 非 typedef `pub enum`：头含 `struct lib_Shape` + 4 条 `_Static_assert`、无 vtable，跨单元 `24 0`；但 `pub typedef` 跨单元产物非法 C（§3.3 F2） | tag+union/断言通过；typedef 形态的跨单元 ABI 不成立 |
| E84-6 | ✅ | `test/ast/291_adt_kind_rewrite` 输出 `3 3 / 6 6`，与 `switch (n->kind)` 同值；`patterns §6` 逐项替换表存在 | 机械替换样例成立 |
| E84-7 | ✅ | `bash selfhost/check-all.sh`（私有 `TMPDIR`）→ `== summary: 1556 passed, 0 failed, 6 skipped ==`、`check-all: OK (11 hard gates green)`；`check-warnings: 494 ok, 0 failed`；`check-sanitizers: OK (586 checks, no sanitizer report)`；`g0: OK`、`g8: OK` | 全绿（本机多 1 个 Renode skip，见 O5） |
| E84-8 | ✅ | `p84_docs: OK`；`p84_docs_audit: OK`；回滚演练见 §5.3：`p84_syntax/match/errors` 绿、`p84_layout` 2/3 红、C enum/switch 与基线 `same:` | 文档成文、冻结清单登记、单卡回滚不伤 C enum/switch |
| E84-9 | ❌ | B 最小集探针 `OK p84docs_audit`、`check-battle: PASS (0 errors, 0 warnings)`；但 spec §4.73 的 typedef 承诺与实现不一致（F1/F2） | 最小集文档可定位；“文档与实现一致”未满足 |

### 2.1 E84-2 独立诊断（摘录）

```console
$ $CT check arity0.ct
arity0.ct:4:15: error: 'Shape.Circle' takes 1 argument, but 0 given
$ $CT check arity2.ct
arity2.ct:4:15: error: 'Shape.Circle' takes 1 argument, but 2 given
$ $CT check badtype.ct
badtype.ct:4:28: error: argument 1 of 'Shape.Circle': expected 'int', got 'char *'
$ $CT check --types badassign.ct
badassign.ct:4:13: error: initializer: expected 'int', got 'struct Shape'
```

### 2.2 E84-3 独立诊断（摘录）

```console
$ $CT check missing.ct
missing.ct:4:5: error: match does not cover variant 'Shape.Rect' (add the arm or write '_ => { … }')
$ $CT check dup.ct
dup.ct:7:9: error: duplicate match arm for variant 'Shape.Circle'
$ $CT check unknown.ct
unknown.ct:6:15: error: unknown variant 'Triangle' of ADT 'Shape'
$ $CT check wlast.ct
wlast.ct:6:9: error: a wildcard match arm must be the last arm
$ $CT check bindn.ct
bindn.ct:5:9: error: match arm for 'Shape.Circle' binds 2 names, but the variant has 1 field
$ $CT check notadt.ct
notadt.ct:3:5: error: match needs an ADT value, but 'int' is not an ADT
```

## 3. §失败（阻断项最小复现）

### 3.1 F1：typedef 别名不能作 match 主语

```ct
#include <stdio.h>

typedef enum Shape { Circle(int r), Rect(int w, int h) } Alias;

int area(Alias a)
{
    match (a) {
        Shape.Circle(r) => { return 3 * r * r; }
        Shape.Rect(w, h) => { return w * h; }
    }
    return 0;
}

int main(void)
{
    Alias c = Shape.Circle(2);
    Alias r = Shape.Rect(3, 4);
    printf("%d %d\n", area(c), area(r));
    return 0;
}
```

```console
$ CT_C_BOUNDARY=allow $CT check alias_match.ct
alias_match.ct:7:5: error: match needs an ADT value, but 'Alias' is not an ADT
ctc: 1 error(s) generated
exit=1
```

同根因的两个变体：

```console
$ $CT check alias_ptr.ct        # int area(Alias *a) { match (a) { … } }
alias_ptr.ct:5:5: error: match needs an ADT value, but 'Alias *' is not an ADT. exit=1
$ $CT build --emit-c prog.ct -o out   # 跨单元 pub typedef，消费者 match (Alias a)
prog.ct:5:5: error: match needs an ADT value, but 'lib_Alias' is not an ADT. ct exit=1
```

**期望**：`Alias` 与 `Shape` 是同一和类型（spec §4.73“tag 和别名都命名同一个和类型”；卡 D84-1），穷尽的 `match (Alias)` 应通过，并接受 `Alias *`。实现上 `expr_type` 返回 `Alias`，`parse_match` 只按 tag 名查 `ct_adt_find()`，未展开 typedef 别名。

### 3.2 F2：`pub typedef` 跨单元，tag 名产物非法 C

`lib/lib.h.ct`：

```ct
namespace lib;

pub typedef enum Shape { Circle(int r), Rect(int w, int h) } Alias;
```

`prog.ct` 使用 tag 名（与 spec 的“tag 和别名都命名同一个类型”一致）：

```ct
import lib::lib;

int area(Shape s)
{
    match (s) {
        Shape.Circle(r) => { return r; }
        Shape.Rect(w, h) => { return w * h; }
    }
    return 0;
}

int main(void)
{
    Shape s = Shape.Circle(2);
    return area(s);
}
```

```console
$ $CT build --emit-c prog.ct -o out
cc -std=c99 -I out out/prog.c out/lib.c -o a.out
ct build exit=0

$ grep -n 'Shape\|Alias' out/prog.c out/lib.h
out/prog.c:6:int area(Shape);
out/prog.c:8:int area(Shape s) {
out/prog.c:9:    struct lib_Shape __ct_match0 __attribute__((unused)) = (s);
out/prog.c:22:    Shape s = ((struct lib_Shape){ .tag = 0, .u = { .Circle = { .r = (2) } } });
out/lib.h:9:typedef struct lib_Shape {
out/lib.h:20:} lib_Alias;

$ cc -Wall -Wextra -std=c99 out/*.c -o out/prog.bin
prog.ct:3:10: error: unknown type name 'Shape'
prog.ct:17:5: error: use of undeclared identifier 'Shape'
4 errors generated.
cc exit=1
```

**期望**：头文件同时发布 tag 的 C 名（如 `typedef struct lib_Shape lib_Shape;`）或消费者把源码 `Shape` 映射为 `struct lib_Shape`；否则 ct 应在编译期拒绝 `Shape`，而不是接受后发射非法 C。当前 `pub typedef` ADT 在跨单元下两条路都不通：用别名 `Alias` 被 F1 拒绝，用 tag `Shape` 生成非法 C——`match` 无法跨单元使用。

**影响范围**：spec §4.73 typedef 段、卡 D84-1；E84-3/E84-5/E84-9。不是 C enum 回归（无负载 enum 仍 5/5 一致）。

## 4. 通过项与独立反例（正向）

```console
$ $CT nest2.ct -o nest2.c && cc -fsanitize=address,undefined nest2.c && ./nest2.bin
7                                   # 嵌套 match（臂内局部 ADT 副本）
$ $CT copy.ct -o copy.c && cc -fsanitize=address,undefined copy.c && ./copy.bin
99 5
1 2                                 # 改绑定不改被 match 的值；第二次仍是 5
$ $CT mixed.ct -o mixed.c && cc -fsanitize=address,undefined mixed.c && ./mixed.bin
num:3 / real:2.5 / text:hi / ref:7 / combo:x:9.2 / again 3
$ $CT once.ct -o once.c && ./once.bin
3 1                                 # 主语函数只求值一次
$ $CT loopcont.ct -o loopcont.c && ./loopcont.bin
48                                  # 臂内 continue 仍属外层循环
$ (cd x2 && $CT build --emit-c prog.ct -o out && cc out/*.c && ./out.bin)
24 0                                # 非 typedef pub ADT，跨单元 + 嵌套 ADT payload
```

以上均 `-fsanitize=address,undefined` 重建运行，退出码 0，无 sanitizer 报告；`x2/out/lib.h` 含 `struct lib_Shape`/`struct lib_Wrap` 各 4 条 `_Static_assert`，`lib.c` 不重复定义，无 `vtable`/`vptr`。291 输出 `3 3`、`6 6`，与 golden 一致。

## 5. 门禁与回滚

### 5.1 总门禁

```console
$ TMPDIR=/tmp/rev84.../tmp/checkall bash selfhost/check-all.sh
== summary: 1556 passed, 0 failed, 6 skipped ==
check-all: OK (11 hard gates green)
exit 0

$ env -u CT_C_BOUNDARY bash selfhost/check-warnings.sh
check-warnings: 494 ok, 0 failed
exit 0

$ bash selfhost/check-sanitizers.sh
check-sanitizers: OK (586 checks, no sanitizer report)
exit 0

$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)

$ python3 test/docs/check-docs.py
check-docs: OK (2265 relative links in 372 files, v0.84.0, 11 hard gates, 12 phase status, 5 适用版本 header(s), 2 superseded link(s), 11 signoff(s))
```

`check-all` 的 p84 行：`p84/syntax`、`p84/match`、`p84/errors`、`p84/layout`、`p84/docs`、`p84/docs-audit` 全 `ok`。注意：这些探针未覆盖 F1/F2 的 typedef 形态，故不能据此通过 E84-3/E84-5/E84-9。

### 5.2 battle / 文档

```console
$ python3 tools/check-battle.py doc-consistency-1 --strict
check-battle: doc-consistency-1
  rounds: 1/3
  PASS (0 errors, 0 warnings)
$ python3 tools/check-battle.py doc-consistency-1 --rerun
PASS (0 errors, 0 warnings)
```

battle 判决 B（最小集）与 `p84_docs_audit` 一致；A 的全量审计归 DOC-77/78/79，本报告不扩张。

### 5.3 回滚演练（抽查）

`git archive d863fedb` 后 `git apply -R` 回退 `5bd8be60`（S84c emitter/driver/alias 三文件），同一自举链重建：

```console
$ bash p84_syntax.sh <回滚后 ct-ast>   → 14 passed, 0 failed
$ bash p84_match.sh  <回滚后 ct-ast>   → 10 passed, 0 failed
$ bash p84_errors.sh <回滚后 ct-ast>   → 11 passed, 0 failed
$ bash p84_layout.sh <回滚后 ct-ast>   → 2 passed, 3 failed（exit 1；布局/发射消失，符合预期）
$ C enum/switch banner 归一化 cmp：30_enum / s01_switch / s04_enum 均 same
```

与卡 §7.5 一致；C enum/switch 产物未受 S84c 回退影响。

## 6. 版本 / tag / Release

```console
$ grep -c 'CTC_VERSION "0.84.0"' selfhost/l0/ctc.c selfhost/l1/ctc.ct \
    selfhost/l2/core.ct selfhost/l2/driver.ct selfhost/ct-ast/main.ct
1 1 1 1 1                                  # 五处一致
$ git tag --list 'v0.84*'
（空；tag 由 lead 在复核后创建，本报告不要求 REV 打 tag）
$ shasum -a 256 dist/ct-linux-x64.tar.gz
b40d00c470cfcb9c1f32146bc475d255fddae0bcac6070e18b5eeaa114200532  dist/ct-linux-x64.tar.gz
$ sh test/ast/p83_dist.sh $CT
ok   sha256 matches b40d00c…
ok   unpacked ct -v prints 'ct v0.84.0'
ok   host compiler agrees on v0.84.0
p83_dist: OK
```

README / docs/README / AGENTS / phase-log / roadmap / session-map 均为 v0.84.0；dist 为 Linux x86-64、`ct`/`ctc` 两项、sha256 自洽，已于 QEMU 下跑 `ct -v`。未 push、未建 tag。

## 7. 非阻断观察

- **O1（T-7 红证口径）**：commit `92a44728` 的红证是 `p84syntax 1/11`，`6d5dd5cc` 是 `p84layout 2/2`；卡 §7.2 写 `1/13` 与 `2/3`。后者是收口时把新增 typedef/断言并入测试后对 `ec355f40` 的复跑，不是原 `test` 提交的红证；typedef 修复也未拆独立红/绿（卡 §8 #8 已登记）。建议修正卡中红证数字或在修复时补最小红/绿，不影响本次 F1/F2 的判定。
- **O2（E84-2 的 `--types`）**：`int n = Shape.Circle(4)` 只在 `ct check --types` 下是硬错；默认 `ct check` 按 §4.53 不做初值类型检查。卡 §7.3 E84-2 的证据应写明 `--types`，否则与“默认路径”读者的预期不符。
- **O3（主语表达式）**：`match (*p)` 与 `match (c ? a : b)` 报 `cannot determine the type of the match subject`；函数调用、字段、数组元素主语可用。spec 只承诺“ADT 值或 ADT * 指针”，但“主语求值一次”容易被读成任意表达式；建议在 §4.73 写清受支持的主语形态。
- **O4（探针盲区）**：`p84_syntax`/`p84_layout` 未覆盖 `typedef` 别名作 match 主语与 `pub typedef` 跨单元；`p84_docs`/`p84_docs_audit` 是 grep 断言，抓不到 spec-impl 不一致。F1/F2 修好后应把这两类加入探针。
- **O5（环境差异）**：本机 `check-all` 为 `1556 passed, 6 skipped`，卡 §7.4 为 `1557 passed, 5 skipped`；多出的 skip 是 Renode 相关（本机沙箱无法用其 user directory/JIT），不是产品失败。
- **O6（收口叙述）**：`docs/design/phase84.md`、roadmap、session-map 仍写“E84-1…9 通过 / ✅”；本报告打回后，这些叙述应由 DEV/REQ 在修复提交中同步，不属 REV 的交付范围。

## 8. 未覆盖 / 说明

- 未审查泛型 ADT、or/守卫/字面量/嵌套/结构体模式、表达式 `match`（明确非目标，R84-5）。
- 未把 F2 扩大为 C enum/switch 回归；无负载 enum 的 5 个对照全部 `same:`。
- 未修改实现、phase 卡、roadmap；只提交本报告与 LANG-21 的 `reopened` 状态。
- A 的全量文档审计仍归 DOC-77/78/79；本报告只按 battle B 的最小集判定 E84-9。

---

## 9. v0.84.1 复核（2026-11-21，REV `rev-ph84b`）

> 对象：`1cc20c25b30fdfc990c426ac74a6f68398deaa9a`（HEAD；工作树 clean；未 push、未 tag）
> 环境：macOS arm64；Apple clang 21.0.0；Python 3.15.2
> 方法：`git archive 1cc20c25` 解到 `/tmp/rev84b.2eABF0/src`，按 L0→L1→L2→ct-ast
> 自举链独立重建；以下 `$CT` 指 `/tmp/rev84b.2eABF0/work/ct-ast`，所有探针只用该归档
> 产物，未用工作树二进制；未改实现。

**REV: 通过。** F1/F2 的直接形态、红/绿证、跨单元产物与总门禁均独立复现；§3 的两项
阻断不再成立。

### 9.1 自举（`1cc20c25` 归档）

```console
$ R=/tmp/rev84b.2eABF0; mkdir -p "$R/src" "$R/work/l2src" "$R/work/astsrc"
$ git archive 1cc20c25 | tar -x -C "$R/src"
$ cc -Wall -Wextra -std=c99 "$R/src/selfhost/l0/ctc.c" -o "$R/work/ctc"
$ "$R/work/ctc" "$R/src/selfhost/l1/ctc.ct" -o "$R/work/l1.c"
$ cc -Wall -Wextra -std=c99 "$R/work/l1.c" -o "$R/work/l1"
$ (cd "$R/src" && "$R/work/l1" build selfhost/l2/driver.ct -o "$R/work/l2src")
$ cc -Wall -Wextra -std=c99 "$R/work/l2src"/*.c -o "$R/work/l2"
$ (cd "$R/src" && "$R/work/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$R/work/astsrc")
$ cc -Wall -Wextra -std=c99 "$R/work/astsrc"/*.c -o "$R/work/ct-ast"
$ "$R/work/ct-ast" -v
ct-ast v0.84.1
```

各 `cc` 零警告、退出码 0。

### 9.2 F1 重跑：typedef 别名作 `match` 主语

`alias_match.ct` 同 §3.1；`alias_ptr.ct` 把主语改为 `Alias *`；`alias_ctor.ct` 的分支
与构造都用别名限定：

```ct
typedef enum Shape { Circle(int r), Rect(int w, int h) } Alias;

int area(Alias a)
{
    match (a) {
        Alias.Circle(r) => { return 3 * r * r; }
        Alias.Rect(w, h) => { return w * h; }
    }
    return 0;
}

int main(void)
{
    Alias c = Alias.Circle(2);
    Alias r = Alias.Rect(3, 4);
    return area(c) + area(r);
}
```

```console
$ CT_C_BOUNDARY=allow $CT check alias_match.ct; echo exit=$?
exit=0
$ CT_C_BOUNDARY=allow $CT check alias_ptr.ct; echo exit=$?
exit=0
$ CT_C_BOUNDARY=allow $CT check alias_ctor.ct; echo exit=$?
exit=0
$ CT_C_BOUNDARY=allow $CT alias_match.ct -o alias_match.c \
  && cc -Wall -Wextra -std=c99 alias_match.c -o alias_match.bin && ./alias_match.bin
12 12
$ CT_C_BOUNDARY=allow $CT check notadt_alias.ct
notadt_alias.ct:5:5: error: match needs an ADT value, but 'Num' is not an ADT
exit=1
$ CT_C_BOUNDARY=allow $CT check missing_alias.ct
missing_alias.ct:5:5: error: match does not cover variant 'Shape.Rect' (add the arm or write '_ => { … }')
exit=1
```

非 ADT 别名（`typedef int Num`）仍拒绝；别名主语的漏变体仍带 `file:line:col`。

### 9.3 F2 重跑：`pub typedef` 跨单元，tag + 别名两路

`lib/lib.h.ct` 同 §3.2；消费者 `by_tag(Shape)` 与 `by_alias(Alias)` 并存，构造分别用
`Shape.Circle` 与 `Alias.Rect`：

```console
$ (cd f2 && CT_C_BOUNDARY=allow $CT build --emit-c prog.ct -o out); echo exit=$?
cc -std=c99 -I out out/prog.c out/lib.c -o a.out
exit=0
$ grep -n 'Shape\|Alias' out/prog.c out/lib.h
out/prog.c:7:int by_tag(struct lib_Shape);
out/prog.c:8:int by_alias(lib_Alias);
out/prog.c:10:int by_tag(struct lib_Shape s) {
out/prog.c:11:    struct lib_Shape __ct_match0 __attribute__((unused)) = (s);
out/prog.c:23:int by_alias(lib_Alias a) {
out/prog.c:24:    struct lib_Shape __ct_match1 __attribute__((unused)) = (a);
out/prog.c:37:    struct lib_Shape c = ((struct lib_Shape){ .tag = 0, .u = { .Circle = { .r = (2) } } });
out/prog.c:38:    lib_Alias r = ((struct lib_Shape){ .tag = 1, .u = { .Rect = { .w = (3), .h = (4) } } });
out/lib.h:9:typedef struct lib_Shape {
out/lib.h:20:} lib_Alias;
$ cc -Wall -Wextra -std=c99 out/*.c -o out/prog.bin; echo cc_exit=$?
cc_exit=0
$ ./out/prog.bin
12 2 7
```

消费者产物只写 `struct lib_Shape` / `lib_Alias`，不再出现未声明的 `Shape`；头文件仍只有
`typedef struct lib_Shape { … } lib_Alias;` 与四条 `_Static_assert`。

### 9.4 红/绿证（T-7 对照）

红证按 `4f5b2cd2`（test 提交；实现前源码 = `bf88f4d9`）归档重建，`ct-ast v0.84.0`；
绿证用 §9.1 的 `1cc20c25` 产物：

```console
$ git log --format='%h %p %s' -4
1cc20c25 53e0019f chore(ph84): v0.84.1——REV F1/F2 修复收口（LANG-21 fixed）
53e0019f 4f5b2cd2 fix(ct-ast): PH-84 F1/F2 修复（typedef ADT 的 match 与跨单元命名）
4f5b2cd2 bf88f4d9 test(ct-ast): PH-84 F1/F2 红（typedef ADT match / pub typedef 跨单元）
$ git merge-base --is-ancestor bf88f4d9 HEAD; echo ancestor=$?
ancestor=0

# 红（4f5b2cd2 源码，p84 新探针）
p84match:  10 passed, 3 failed (exit 1)
p84errors: 12 passed, 1 failed (exit 1)
p84layout: 21 passed, 2 failed (exit 1)
# 绿（1cc20c25）
p84match:  13 passed, 0 failed
p84errors: 13 passed, 0 failed
p84layout: 26 passed, 0 failed
```

红证与 DEV 处置段、卡 §7.6 的数字逐项一致。

### 9.5 六探针与总门禁（归档树，私有 TMPDIR）

```console
$ bash test/ast/p84_syntax.sh     $CT   → p84syntax: 14 passed, 0 failed (exit 0)
$ bash test/ast/p84_match.sh      $CT   → p84match: 13 passed, 0 failed  (exit 0)
$ bash test/ast/p84_errors.sh     $CT   → p84errors: 13 passed, 0 failed (exit 0)
$ bash test/ast/p84_layout.sh     $CT   → p84layout: 26 passed, 0 failed (exit 0)
$ bash test/ast/p84_docs.sh       $CT   → OK p84docs                   (exit 0)
$ bash test/ast/p84_docs_audit.sh $CT   → OK p84docs_audit             (exit 0)

$ TMPDIR=$R/tmp/checkall bash selfhost/check-all.sh
L1 golden coverage: 25 pass, 0 new, 0 pending, 0 regression (of 25 cases)
check-archive: OK (no regression)
ct-tour: OK - you compiled CT with C, then CT with CT, and the outputs matched.
  ok    p84/syntax
  ok    p84/match
  ok    p84/errors
  ok    p84/layout
  ok    p84/docs
  ok    p84/docs-audit
== summary: 1557 passed, 0 failed, 5 skipped ==
check-warnings: 494 ok, 0 failed
check-docs: OK (2267 relative links in 373 files, v0.84.1, 11 hard gates, 12 phase status, 5 适用版本 header(s), 2 superseded link(s), 11 signoff(s))
check-all: OK (11 hard gates green)
exit 0

$ env -u CT_C_BOUNDARY bash selfhost/check-warnings.sh
check-warnings: 494 ok, 0 failed (exit 0)
$ bash selfhost/check-sanitizers.sh
check-sanitizers: OK (586 checks, no sanitizer report) (exit 0)
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present) (exit 0)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets) (exit 0)
$ python3 tools/check-docs.py
check-docs: OK (2267 relative links in 373 files, v0.84.1, …) (exit 0)
$ python3 tools/check-battle.py doc-consistency-1 --strict
PASS (0 errors, 0 warnings)
```

本机 check-all 的 gate 8 为 `1557 passed, 0 failed, 5 skipped`；卡 §7.4 的 v0.84.1
记录为 `1556 passed, 0 failed, 6 skipped`。差异是 Renode 用例在两种环境下的
可用性（O5 已登记），两边的失败数均为 0，不是产品回归。

### 9.6 新增反例（独立于仓库探针）

**A. 别名与 tag 混用分支 + 混用构造**：分支一半写 `Shape.Circle`、一半写
`Alias.Rect`，构造同理；ASan/UBSan 重建运行。

```ct
typedef enum Shape { Circle(int r), Rect(int w, int h) } Alias;

int area(Alias a)
{
    match (a) {
        Shape.Circle(r) => { return 3 * r * r; }
        Alias.Rect(w, h) => { return w * h; }
    }
    return 0;
}

int main(void)
{
    Alias c = Shape.Circle(2);
    Shape s = Alias.Rect(3, 4);
    printf("%d %d\n", area(c), area(s));
    return 0;
}
```

```console
$ $CT check mixed.ct                       → exit 0
$ $CT mixed.ct -o mixed.c && cc -Wall -Wextra -std=c99 -fsanitize=address,undefined mixed.c -o mixed.bin
$ ./mixed.bin
12 12                                      # 零警告、无 sanitizer 报告
```

**B. 别名 payload 的 move/副本**：`Alias b = a` 复制；`match` 绑定按值改 `r` 不回写；
`q = Alias.Rect(5, 6)` 不影响 `p`；`Alias *` 主语与直接 `a.u.Circle.r` 对照。

```ct
typedef enum Shape { Circle(int r), Rect(int w, int h) } Alias;

int peek(Alias a)
{
    match (a) {
        Alias.Circle(r) => { r = r + 100; return r; }
        Alias.Rect(w, h) => { return w * h; }
    }
    return 0;
}

int peekp(Alias *p)
{
    match (p) {
        Shape.Circle(r) => { return r; }
        _ => { return 0; }
    }
}

int main(void)
{
    Alias a = Shape.Circle(2);
    Alias b = a;
    int x = peek(a);              /* 102，a 仍为 2 */
    int y = peek(b);              /* 102 */
    int z = peekp(&a);            /* 2 */
    Alias p = Shape.Rect(3, 4);
    Alias q = p;
    q = Alias.Rect(5, 6);         /* p 仍为 3×4 */
    int w = peek(p);              /* 12 */
    int v = peek(q);              /* 30 */
    printf("%d %d %d %d %d %d\n", x, y, z, w, v, a.u.Circle.r);
    return 0;
}
```

```console
$ $CT copy.ct -o copy.c && cc -Wall -Wextra -std=c99 -fsanitize=address,undefined copy.c -o copy.bin
$ ./copy.bin
102 102 2 12 30 2              # 零警告、无 sanitizer 报告
```

**C. `pub typedef` 跨单元按别名构造**：消费者只用 `Alias.Circle` / `Alias.Rect`
构造，再与 tag 构造的 `Shape` 混用：

```console
$ (cd xt && $CT build --emit-c prog.ct -o out)   → exit 0
$ cc -Wall -Wextra -std=c99 -fsanitize=address,undefined out/*.c -o out/prog.bin
$ ./out/prog.bin
12 12 30
```

**D. 负例（防过度接受）**：

```console
$ $CT check badstruct.ct   → badstruct.ct:5:5: error: match needs an ADT value, but 'struct Pair' is not an ADT (exit 1)
$ $CT check badptr.ct      → badptr.ct:5:5: error: match needs an ADT value, but 'IntPtr' is not an ADT (exit 1)
$ $CT check crossadt.ct    → crossadt.ct:8:9: error: match arm names ADT 'B', but the subject is 'A' (exit 1)
$ $CT check badctor.ct     → badctor.ct:5:21: error: unknown variant 'Triangle' of ADT 'Shape' (exit 1)
$ $CT check arity.ct       → arity.ct:5:15: error: 'Shape.Circle' takes 1 argument, but 2 given (exit 1)
```

另测 `typedef enum Shape { … } Shape;`（tag 与别名同名）：同单元编译运行 `12 12`；
`pub` 跨单元 `ct build --emit-c`、`cc -Wall -Wextra`、运行（输出 `0`，即 `c.tag`）
均通过，F2 的 bare 名导出未因重名而报错；`const Alias *` 主语亦通过。

### 9.7 版本 / 记录一致性

```console
$ grep -c 'CTC_VERSION "0.84.1"' selfhost/l0/ctc.c selfhost/l1/ctc.ct \
    selfhost/l2/core.ct selfhost/l2/driver.ct selfhost/ct-ast/main.ct
1 1 1 1 1
$ grep -n 'v0.84.1' README.md docs/README.md AGENTS.md docs/history/phase-log.md docs/roadmap.md docs/session-map.md
（六处均含 v0.84.1；0.84.0 只出现在历史条目与“fix v0.84.1”说明中）
```

`LANG-21` 状态原为 `reopened`，DEV 处置段主张 `fixed`（附红/绿证与提交 sha）；本轮复核
通过后由 REV 改为 `verified`。`git status` 在复核前后均为 clean；本次只改本报告与
`LANG-21` 状态，不 push、不打 tag。

### 9.8 非阻断观察（新增 O7）

- **O7（别名链）**：`typedef Alias Alias2;` 后 `match (Alias2)` 仍报
  `match needs an ADT value, but 'Alias2' is not an ADT`。spec §4.73 的 typedef 形态只
  冻结 `typedef enum Tag { … } Alias;` 一层，本轮 F1 判据也不含别名链；不影响本次通过。
  若后续要求任意 typedef 链可达，建议另立条目，在 `ct_adt_from_type()` 里递归解析
  `type_target`，而不是在本次修复中扩大范围。

**`REV: 通过`**；PH-84 可按 v0.84.1 收口，F1/F2 不再阻断 E84-3/E84-5/E84-9。
