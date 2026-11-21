# Phase 84 — 最小 ADT / `match`（v1-pre 前置）

> **状态：完成（S84a–S84e；`v0.84.0`）**（2026-11-21 立项并开卡；2026-11-21 收口）。
> S84e 的范围由 [battle doc-consistency-1](../../battle/doc-consistency-1/verdict.md) 判为
> **B（最小集 + 增量补丁）**并已执行；E84-9 按该最小集判定通过，A 的全量审计仍归
> DOC-77 / DOC-78 / DOC-79。
> **签收：EDITOR 2026-11-21**（主编统一签收；卡作者 REQ）。
> **施工闸门**：PH-83 已收口（`v0.83.3`）；本卡是 v1-pre 的第一步，完成后才进 PH-85。
> **前置**：[D3 裁定](../reviews/2026-11-21-v1-campaign-eval.md)（最小 ADT 先行）、
> [LANG-21](../../issues/lang/lang-21-minimal-adt-match.md)、
> [v1 路线 §2.3](../planning/v1-release-plan.md)。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase84.md`。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-84（legacy 文件 `phase84.md`） |
| 目标 | 为 ct-ast 重写提供穷尽判别：名义和类型 + 构造器负载 + 穷尽 `match` + 变量绑定 |
| 范围 | `enum` 负载变体、构造 `Type.Variant(...)`、`match` 语句、穷尽检查、payload 绑定、确定性布局；**v1-pre 前文档一致性审计与优化**（范围由 battle doc-consistency-1 定） |
| 非目标 | 泛型 ADT；or/守卫/字面量/嵌套/结构体模式；表达式形式的 `match`；`Option`/`Result` 替代；借用模式 |
| 交付物 | 编译器改动、`test/ast/p84_*`、spec/tutorial、冻结清单登记、文档一致性清单 |
| 任务清单 | §2（S84a–S84e） |
| 退出判据 | E84-1…E84-9（§3） |
| version-minor | 84（PH-84，`d=0`） |
| 已知风险 | R84-1…R84-6（§4） |

## 1 需求与边界

### 1.1 语法（冻结）

```ct
enum Shape {
    Circle(int r),
    Rect(int w, int h),
}

int area(Shape s)
{
    match (s) {
        Shape.Circle(r) => { return 3 * r * r; }
        Shape.Rect(w, h) => { return w * h; }
    }
}
```

- **负载变体**：`enum` 任一成员带括号负载即为 ADT；所有成员都不带负载时保持现行 C `enum` 语义；
- **构造**：`Type.Variant(args)`；bare variant 名不引入（避免与 C 枚举常量冲突）；
- **match**：语句形式；每个分支是 `Type.Variant(bindings) => { ... }`，无 fallthrough；
- **穷尽**：必须覆盖全部变体，或显式 `_ => { ... }`；缺少分支编译错；
- **绑定**：负载按值绑定到局部名（owning 负载按 move）；本轮不做借用模式。

### 1.2 布局与 ABI

```c
struct Shape {
    int tag;
    union { struct { int r; } Circle; struct { int w; int h; } Rect; } u;
};
```

- 布局确定：`tag` 在前，payload union 在后；对齐取各成员最大对齐；
- `pub` ADT 类型进入 ABI 头时，布局与 `_Static_assert` 一起进 golden；
- 不引入 vtable；ADT 不是 trait 接口值。

### 1.3 非目标（明确不做）

- 泛型 `enum Option<T>`、or 模式、守卫、字面量模式、嵌套/结构体模式；
- `match` 作为表达式返回值的形态（本轮只用语句；需要时先绑局部再 match）；
- 自动把 `Option`/`Result` 改成 ADT；
- 借用/`ref` 模式与穷尽之外的流分析。

### 1.4 文档一致性（v1-pre 前）

用户 2026-11-21 指令：v1-pre 前必须处理文档落伍，重点是新语法特性。**具体范围与重写深度由
[battle doc-consistency-1](../../battle/doc-consistency-1/question.md) 决定**；本卡只固定：

- 审计对象至少覆盖 README、language-spec、tutorial、patterns、llm-guide、glossary、architecture、package-guide；
- 逐特性核对：String/Str、切片 `T[]`、`ref`/`out`、`box`/`new`、ADT/match（随本卡实现补齐）；
- 过期段落允许重写，但必须保持“能力与实现一致”，不得写未实现能力；
- 文档改动不改代码/ABI/语言语义，可单卡回滚；
- battle 结论已落地（[verdict B](../../battle/doc-consistency-1/verdict.md)）：最小集 =
  spec §4.68/§4.69/§4.70/§4.71/§4.73 + tutorial §15/§17/§18 + patterns §5/§6，加
  llm-guide 的内置层清单/`std::str` 事实修正、glossary 的 `Str`/`String`/ADT/变体/`match`
  行、architecture 的「ct-ast 特性不在 L0」边注、README 的 spec/tutorial/patterns 指针；
  未列入项不得顺手扩写。

## 2 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S84a 语法/类型 | `enum` 负载变体、`Type.Variant(...)`、类型检查 | `p84_syntax` | M |
| S84b 穷尽/诊断 | `match` 语句、穷尽检查、重复/未知变体/arity 错误 | `p84_match` / `p84_errors` | M |
| S84c 布局/发射 | tag+union 布局、绑定与 move、`_Static_assert` | `p84_layout` | M |
| S84d ADT 文档/迁移 | ADT/match 的 spec/tutorial/patterns、冻结清单、C enum 不变说明 | `p84_docs` | S（`no-test: 纯文档`；红证不适用，探针只做文档断言） |
| S84e 文档一致性 | 按 battle 判决 B 的最小集审计（必需节 + 4 份入口文档事实/链接修正） | `p84_docs_audit` | S（`no-test: 纯文档`） |

每项任务先提 `test(<scope>): <task-id> 红`（含 `baseline: <sha>`），实现提交随后转绿；
S84d/S84e 为纯文档任务，写 `no-test:` 并由 REVIEW 签字。S84e 的范围以
[battle doc-consistency-1](../../battle/doc-consistency-1/question.md) 的判决为准。

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E84-1 | 带负载 `enum` 解析为 ADT；无负载 `enum` 的 C 语义与 golden 不变 |
| E84-2 | `Type.Variant(args)` 构造类型正确；arity/类型不符硬错 |
| E84-3 | `match` 覆盖全部变体才通过；漏分支、重复分支、未知变体均编译错并给位置 |
| E84-4 | payload 绑定按值/move；无 fallthrough；`_` 必须显式书写才允许兜底 |
| E84-5 | 布局为 tag+union 且确定；`pub` ADT 的 ABI 头 + `_Static_assert` 进 golden |
| E84-6 | 重写切片中的 `node->kind` 判别可机械替换为穷尽 `match`（以词法/AST 判别样例验证） |
| E84-7 | 既有测试/示例全绿；`check-all` 与 ASan 通过；无新增警告 |
| E84-8 | spec/tutorial/patterns 成文；冻结清单登记；单卡回滚不影响 `enum`/`switch` 旧代码 |
| E84-9 | 文档一致性：battle 结论落地；审计清单内的文档与实现一致；新特性在 spec/tutorial/patterns 可定位；示例可编译或为明确负例；check-docs 通过 |


## 5 决策记录（本卡内，`D84-*`）

| ID | 决策 | 理由 |
| --- | --- | --- |
| D84-1 | `enum` 两形态判据写死：**任一**成员带括号负载即整条声明为 ADT，全部不带负载才是 C enum；两者不混用（有负载后显式值/无负载成员硬错）；ADT 必须有 tag 名 | 卡 §1.1/R84-1 已冻结；成员先读进临时节点再判定，负载可自引用（tag 在成员前入表）。`typedef enum Tag { … } Alias;` 的 ADT 形态保留：产物为 `typedef struct Tag { … } Alias;` |
| D84-2 | ADT 的变体/负载放 **build-wide 注册表**（不复制进 per-unit 符号表），ADT 行号与 `path` 记录声明位置；`pub` ADT 的消费单元靠注册表 + 生成头拿布局 | 与模板/实例注册表同构：per-unit 表会 reset，而消费者必须看见头单元声明的变体（292 夹具验证） |
| D84-3 | `match` 只做**语句**；构造必须是 `Type.Variant(args)`（零负载也带 `()`），裸变体名不引入；`match` 保持普通标识符，只有 `match (...) {` 是语句 | 避免与 C 枚举常量/宏冲突；`match(x);` / `int match(int)` 等既有写法不破（p84_match 钉住） |
| D84-4 | `match` 发射为 **if / else-if / else 链**，不发射 C `switch`；最后一支即 `else`（穷尽由解析期证明） | 分支里的 `break` 必须仍表示外层循环的 break；if/else 链无 fallthrough，也不产生 `-Wreturn-type` 告警 |
| D84-5 | 每单元 import alias 上限 16 → **24** | Emitter 新增 `Symbols::Adt` 后到 17，自编译被旧上限挡住；只放大容量，不改 alias 语义 |

## 4 风险与回滚

| ID | 风险 | 缓解 |
| --- | --- | --- |
| R84-1 | `enum` 扩展与 C 枚举二义 | 规则写死：有负载=ADT，无负载=C enum；显式枚举值只允许 C enum；负例 |
| R84-2 | `_` 兜底掩盖漏分支 | `_` 必须显式；`ct check --types` 对“可穷尽却用 `_`”给 lint |
| R84-3 | 布局/ABI 不稳定 | tag+union 写死；`_Static_assert` 进 golden；不承诺跨版本 ABI |
| R84-4 | payload 所有权/move 语义不清 | 本轮按值/move；借用模式留后续；文档与负例 |
| R84-5 | 范围蔓延到泛型/全模式 | 非目标写死；需要时另立提案，不在本卡加 |
| R84-6 | 文档重写范围蔓延、写成未实现能力 | battle 冻结清单与深度；只写已验证行为；示例进门禁；越界打回 |

回滚：单卡回滚；`enum`（无负载）与 `switch` 行为不变。

## 7 收口对照表（2026-11-21，v0.84.0）

> 构建方式：`git archive <sha> | tar -x -C /tmp/...` 后按 `selfhost/check-ast.sh` 的
> L0→L1→L2→ct-ast 链构建，不得用工作树产物。最终构建的 `ct-ast -v` 为 `ct-ast v0.84.0`。

### 7.1 任务逐项

| 任务 | 提交（test → impl） | 验收命令 | 结果 |
| --- | --- | --- | --- |
| S84a 语法/类型 | `92a44728` → `086d7762` | `bash test/ast/p84_syntax.sh <ct-ast>` | `p84syntax: 14 passed, 0 failed` / `OK p84syntax`（exit 0） |
| S84b 穷尽/诊断 | `4c4648ae` → `0d35f756` | `bash test/ast/p84_match.sh <ct-ast>` + `p84_errors.sh` | `p84match: 10 passed, 0 failed` / `OK p84match`；`p84errors: 11 passed, 0 failed` / `OK p84errors`（exit 0） |
| S84c 布局/发射 | `6d5dd5cc` → `5bd8be60` | `bash test/ast/p84_layout.sh <ct-ast>` | `p84layout: 21 passed, 0 failed` / `OK p84layout`（exit 0） |
| S84d ADT 文档 | `ba330d9e`（纯文档，`no-test: 纯文档`） | `bash test/ast/p84_docs.sh` | `OK p84docs`（exit 0） |
| S84e 文档一致性 | 收口提交（纯文档 + 探针，`no-test: 纯文档`；battle verdict B） | `bash test/ast/p84_docs_audit.sh` | `OK p84docs_audit`（exit 0）；`check-battle.py doc-consistency-1` → PASS (0 errors, 0 warnings) |

### 7.2 红证（T-7；baseline `ec355f40`，实现前）

`ec355f40` 的 ct-ast 由 `git archive` + 同一 bootstrap 链构建，二进制为 `ct-ast v0.83.3`。

**S84a — `bash test/ast/p84_syntax.sh <baseline>`**

```console
p84syntax: 1 passed, 13 failed
FAIL p84syntax: an ADT parses, types and constructs: expected a clean check
    …/ok.ct:2:11: error: unexpected token
FAIL p84syntax: the constructor answers 'struct Shape': expected a clean check
    …/ok.ct:2:11: error: unexpected token
FAIL p84syntax: a zero-field variant parses: expected a clean check
    …/unit.ct:2:8: error: unexpected token
FAIL p84syntax: the constructor answers the ADT type: missing 'initializer: expected 'int', got 'struct Shape''
    …/bad_assign.ct:1:20: error: unexpected token
FAIL p84syntax: a missing payload argument is an arity error: missing ''Shape.Circle' takes 1 argument, but 0 given'
FAIL p84syntax: an extra payload argument is an arity error: missing ''Shape.Circle' takes 1 argument, but 2 given'
FAIL p84syntax: a payload type mismatch is a hard error: missing 'argument 1 of 'Shape.Circle': expected 'int', got 'char *''
FAIL p84syntax: an unknown constructor variant is refused: missing 'unknown variant 'Nope' of ADT 'Shape''
FAIL p84syntax: an ADT variant cannot carry an explicit value: missing 'an ADT variant cannot carry an explicit value'
FAIL p84syntax: a mixed payload / plain enum is refused: missing 'every variant of an ADT must carry a payload list'
FAIL p84syntax: a typedef'd ADT parses and types: expected a clean check
（1 passed = C enum 产物/运行不变；该断言在基线上本就通过，本阶段要求它保持通过）
exit 1
```

**S84b — `bash test/ast/p84_match.sh <baseline>` / `p84_errors.sh <baseline>`**

```console
p84match: 1 passed, 9 failed
FAIL p84match: an exhaustive match passes: expected a clean check
    …/full.ct:2:11: error: unexpected token
FAIL p84match: the arm order is free: expected a clean check
…
FAIL p84match: the redundant wildcard lint has the wrong text
exit 1

p84errors: 1 passed, 10 failed
FAIL p84errors: a missing variant is an error: missing 'match does not cover variant 'Shape.Rect''
    …/missing.ct:1:20: error: unexpected token
FAIL p84errors: a duplicate variant arm is an error: missing 'duplicate match arm for variant 'Shape.Circle''
FAIL p84errors: a variant of another ADT is an error: missing 'match arm names ADT 'B', but the subject is 'A''
…
exit 1
```

**S84c — `bash test/ast/p84_layout.sh <baseline>`**

```console
FAIL p84layout: the ADT program did not compile
    …/adt.ct:4:11: error: unexpected token
FAIL p84layout: the typedef'd ADT did not compile
FAIL p84layout: the cross-unit ADT build failed
    ./lib/lib.h.ct:4:11: error: unexpected token
p84layout: 2 passed, 3 failed
exit 1
```

（2 passed 正是本阶段要求“不变”的 C enum / `switch` 断言。）

### 7.3 退出判据（E84-1…8）

| ID | 证据（原始输出/命令） | 结果 |
| --- | --- | --- |
| E84-1 | `p84_syntax` 的 C enum 段：编译 `test/ast/30_enum/prog.ct` 后 `grep -qE '^enum Color \{'` 通过，运行输出与 `prog.expected.out` 一致；另对 `30_enum` / `54_attribute` / `271_qualified_enum` / `examples/c-superset/{s01_switch,s04_enum}` 与 ec355f40 构建产物做 banner 归一化 `cmp`，五个 `same:` | ✅ |
| E84-2 | `p84_syntax`：`Shape s = Shape.Circle(2)` clean；`int n = Shape.Circle(4)` → `error: initializer: expected 'int', got 'struct Shape'`；`Shape.Circle()`/`(1,2)` → `'Shape.Circle' takes 1 argument, but 0/2 given`；`Shape.Circle("x")` → `argument 1 of 'Shape.Circle': expected 'int', got 'char *'` | ✅ |
| E84-3 | `p84_match` 10/10（穷尽、任意顺序、指针主语、零负载、`_` 兜底、嵌套、循环内 break）；`p84_errors` 11/11（漏/重复/未知/跨 ADT/绑定数/重名/`_` 非末位/重复 `_`/非 ADT/指向非 ADT），均带位置 | ✅ |
| E84-4 | `p84_layout`：生成 C 为 `__ct_match0.tag == 0` 的 if/else 链、无 `switch (`；`290_adt_match` 运行 `102 12 -1 / 2 102 / 2 3`（绑定副本、无 fallthrough、循环内 `break` 仍属循环）；`--types` 多余 `_` lint 文本通过 | ✅ |
| E84-5 | `p84_layout`：`struct Shape { int tag; union { … } u; }`、tag 行先于 union 行；`grep -c '^_Static_assert(' == 4`；`pub` ADT 构建产物 `lib.h` 含 `struct lib_Shape` + `offsetof(struct lib_Shape, tag) == 0`，`lib.c` 不重复定义，`no vtable`；跨单元产物 `cc -Wall -Wextra` 干净并运行 `12 12` | ✅ |
| E84-6 | `test/ast/291_adt_kind_rewrite` 运行 `3 3 / 6 6`：同一棵树用 `switch (n->kind)` + `case K_NUM:` 与 `Node.Num(v) => …` 求值一致（E84-6 的“词法/AST 判别样例”）；patterns §6 给出逐项替换表 | ✅ |
| E84-7 | `bash selfhost/check-all.sh`：见 §7.4；`check-warnings` 见 §7.4；`check-sanitizers.sh` 见 §7.4 | 见 §7.4 |
| E84-8 | `p84_docs` OK（spec §4.73 / tutorial §18 / patterns §6 / 冻结清单 / C enum 不变节）；`check-goldens` 25/25 无回归；单卡回滚演练：回退 S84c 的 emitter 提交后 C enum/switch 产物仍与 ec355f40 一致（§7.5） | ✅ |
| E84-9 | 按 [battle doc-consistency-1 判决 B](../../battle/doc-consistency-1/verdict.md) 的最小集：`p84_docs_audit` `OK p84docs_audit`（spec §4.68/69/70/71/73、tutorial §15/17/18、patterns §5/6 可定位；llm-guide 内置层清单与 `std::str` 事实修正；glossary `Str`/`String`/ADT/变体/`match` 行；architecture 的 L0 边界；README 指针）；`check-docs` 绿（2265 相对链接）；`check-battle` PASS。**A 的全量审计仍归 DOC-77/78/79**，不在本判据内 | ✅（B 范围） |

### 7.4 总门禁（收口实跑）

```console
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)

$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)

$ bash selfhost/check-all.sh
…
L1 golden coverage: 25 pass, 0 new, 0 pending, 0 regression (of 25 cases)
check-goldens: OK (no regression, and the self-hosted rebuild agrees)
check-archive: OK (no regression)
ct-tour: OK - you compiled CT with C, then CT with CT, and the outputs matched.
== summary: 1557 passed, 0 failed, 5 skipped ==        # gate 8: AST compiler
check-semantics: OK (23 assertions)
check-docs: OK (2265 relative links in 372 files, v0.84.0, 11 hard gates, 12 phase status, 5 适用版本 header(s), 2 superseded link(s), 11 signoff(s))
check-all: OK (11 hard gates green)
exit 0

$ env -u CT_C_BOUNDARY bash selfhost/check-warnings.sh
check-warnings: 494 ok, 0 failed
exit 0

$ bash selfhost/check-sanitizers.sh
check-sanitizers: OK (586 checks, no sanitizer report)
exit 0
```

- **`p83_dist`**：本机无 zig/qemu 交叉链，`dist/` 是上一版本留下的 gitignored 旧产物
  （`ct -v` = v0.83.3）；收口时把它移出工作树（`/tmp/p84-stale-dist`），探针按“无产物”走
  `skip`（77），与干净 checkout 一致。**未重新生成 Linux 产物**：需
  `selfhost/make-dist.sh --cross <zig>`，属发布动作，不在本卡范围（见 §8）。
- `check-all` 的 G0/G8 前置均绿；11 道门禁全部通过；gate 8 的 p84 行：
  `p84/syntax`、`p84/match`、`p84/errors`、`p84/layout`、`p84/docs`、`p84/docs-audit` 全 ok。

### 7.5 回滚（实跑演练）

演练方式：`git worktree add /tmp/p84-rb e9112cd4` 后 `git revert --no-commit 5bd8be60`
（只回退 S84c 的 emitter/driver/alias 三个文件），按同一 bootstrap 链重建 `ct-ast`：

```console
$ bash p84_syntax.sh <回滚后 ct-ast>   →  p84syntax: 14 passed, 0 failed (OK)
$ bash p84_match.sh  <回滚后 ct-ast>   →  p84match: 10 passed, 0 failed (OK)
$ bash p84_errors.sh <回滚后 ct-ast>   →  p84errors: 11 passed, 0 failed (OK)
$ bash p84_layout.sh <回滚后 ct-ast>   →  p84layout: 2 passed, 3 failed (exit 1，S84c 自身应红)
$ C enum/switch banner 归一化 cmp：30_enum / s01_switch / s04_enum 均 same
```

- S84a（语法/类型）与 S84b（穷尽/诊断）的 `ct check` 行为在回退 S84c 后保留；S84c 的探针
  按预期转红（布局/发射消失），其余任务门禁仍绿。
- C enum（无负载）与 `switch` 由未改路径发射，回滚前后产物一致。
- S84a 的 `086d7762` 单独回滚：ADT 语法消失，C enum 路径不受影响。

## 8 未覆盖 / 简化（诚实登记）

| # | 项 | 现状 | 去向 |
| --- | --- | --- | --- |
| 1 | ADT 的 Drop glue | **未生成**：owning payload 视为 move 进绑定，ADT 本身不自动释放 payload，作者需显式处理；与卡 R84-4 的“按值/move、借用留后续”一致但比“自动 drop”弱 | 后续增量提案（非本卡范围） |
| 2 | owning payload 的借用模式 | 未做 | v1.1+（R84-4） |
| 3 | `offsetof(<ADT>, tag)` 源码层 | 不支持（布局断言只在生成物）；`ParseSupport` 的 offsetof 校验只认 struct 表 | 文档已注明；生成物断言覆盖 |
| 4 | `--emit-model` 的 `enums` 列表 | 不含 ADT（`write_model` 跳过 `aux & 2`）；ADT 布局由 spec §4.73 + 生成头断言承载 | 模型导出扩展另立条目 |
| 5 | 泛型 ADT / or / 守卫 / 字面量 / 嵌套 / 结构体模式 / 表达式 `match` | 未做（非目标，R84-5） | v1.1+ 增量提案 |
| 6 | A 的全量文档审计（README/llm-guide/glossary/architecture 的逐段重写） | **不做**：battle 判 B，最小集只修事实与链接；其余系统性审计归 DOC-77 / DOC-78 / DOC-79 | 各自 issue 闭环 |
| 7 | `test/ast/p84_docs.sh` 的 REVIEW 签字 | S84d 为纯文档 `no-test:`；本会话单席位，未伪造 REVIEW 签字 | 由主控/REVIEW 席位补签（T-7 例外要求） |
| 8 | typedef ADT 的修复未拆独立红/绿提交 | 收口核验中发现 `typedef enum Tag { … } Alias;` 的 typedef 位覆盖 ADT 位；修复与断言（`p84_syntax` 的 check 正例、`p84_layout` 的 codegen 正例）并入收口提交，未按 T-7 拆成 `test 红` + `fix` 两提交（收口提交须为最后一提交） | 作为流程偏差登记；VERIFY 复核时按小循环口径补红证 |
