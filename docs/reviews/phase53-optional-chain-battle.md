# PH-53 `?.` 第二轮 battle：struct 值接收者与切词策略

> **状态：裁定记录（2026-11-15）**。两席实测 + 裁定；不改实现、不改 golden、不 bump。
> **基准**：仓库 `1d49bb1a`（未构建）；CT 行为用 `/tmp/ctgap/bin/ct`（`ct v0.44.1`）实测。
> `?` 的解析/诊断路径自 PH-44（`99e9e754`）后未再改动，故该副本对这两个语法用例有代表性。
> **探针**：`/tmp/battle53`；未执行仓库内脚本或二进制（工作区未受信）。
> **前置裁定（负责人已定，不再争）**：map 键缺失整链跳出、结果 NULL，对齐 `Map::get`；
> 指针接收者 `p?.field` 展开为 `(p ? p->field : 0)`；切词按下文 §4，不合成 `?.` token。

---

## 1 两席主张

### 1.1 主张席：struct 值接收者可以支持吗？

主张席按「先证明不存在，再证明展开可编译」逐条尝试，结果如下。

| 尝试 | 方案 | 实测 | 结论 |
| --- | --- | --- | --- |
| 1 | 直接把 struct 值当条件：`s ? s.b : 0` | `cc` rc=1：`used type 'struct S' where arithmetic or pointer type is required`（`p1_value_cond.c:8`） | 不成立 |
| 2 | 用户自定 `present` 字段作哨兵 | `cc` rc=0；`absent=0 zero=0`（`p2_sentinel.c`） | 能编译，但编译器无法知道哪个字段是哨兵；缺失与合法零值不可分 |
| 3 | 显式包装 `MaybeS { has, v }`，结果用 `int` + 0 哨兵 | `cc` rc=0；`absent=0 present_zero=0`（`p3_maybe.c`） | 包装只把「不存在」挪到 `has`；结果仍把「缺失」和「值为 0」压成同一个 `0` |
| 4 | 结果改用 `Maybe<T>`（`has` + payload） | 可表达缺失，但每个值字段的结果类型都变成 `Maybe<T>`；`a?.b.c` 每跳都要再包一层 | 不是语法糖；`?.` 从「零运行时」变成新类型族 |
| 5 | `Maybe<D>` 承载带 Drop 的 struct 字段 | ASAN：`attempting double-free`，rc=134（`p11_maybe_drop.c`） | 三元/包装都是浅拷贝；没有 move/部分移动规则就会双释放 |
| 6 | 返回字段地址 `p ? &p->b : 0`，结果为指针 | `cc` rc=0；`present=5 missing=0`（`p10_ptr_field.c`） | 成立，但结果是 `T*` 而不是值；且值接收者的 `&a.b` 恒非空（`p6_addr_field.c`：`nonnull=1`），没有 false 分支 |

**主张席结论**：普通 struct 值接收者没有一条「值语义 + 可表达不存在 + 不新增类型」的路径。
唯一成立的形态是「显式可空类型 + 返回指针/布尔标记」，那已经是一个新的类型特性，不是 `?.` 语法糖。
若负责人接受该成本，可以单独立相；本卡不应把它当作 `?.` 的附赠能力。

### 1.2 反证席：逐条打「能支持」

| # | 「能支持」的说法 | 反证（实测） | 判定 |
| --- | --- | --- | --- |
| 1 | 值类型也能作条件 | `cc` rc=1，struct 不能作三目条件（`p1`） | 不成立 |
| 2 | 用零值表示「不存在」 | `(struct S){0}` 与合法零值同形；`p2`/`p3`/`p8` 均输出 `0`，无法区分 | 不可判定 |
| 3 | 加一个 `has` 字段即可 | 编译器不知道哪个字段是 `has`；必须引入类型标记，否则每个类型各写一套 | 不是通用规则 |
| 4 | 含 Drop 字段也能拷贝 | 三元浅拷贝 + 双方 drop → ASAN double-free rc=134（`p4`）；`Maybe<D>` 同样 rc=134（`p11`） | 不成立 |
| 5 | 零值可作「不存在」的默认值 | 带 vptr 的 struct 零值 vptr 为 NULL，调用即段错误 rc=139（`p5`） | 不成立 |
| 6 | 值接收者也能走 `(p ? p->field : 0)` | 值接收者没有空指针；`&a.b` 恒非空（`p6`），false 分支不可达 | 语义空洞 |
| 7 | 结果仍是值 | 要保留「缺失」，结果必须是 `Maybe<T>` 或 `T*`；前者是值但每跳变类型，后者不是值 | 二选一，均非原语义 |

**反证席结论**：这不是「缺一条规则」，而是**值类型没有「不存在」这个状态**。
零值、哨兵、包装都必须由用户或新类型提供额外信息；编译器无法在普通 `S` 上凭空判断。

### 1.3 对冲结论

两席在事实层面无分歧：普通 `S` 值接收者不支持；`Maybe<S>`/`S?` 支持需要新类型、布局、Drop 与
结果类型规则，成本独立。分歧只在「是否值得为此扩相」，而这不是本卡能顺带解决的。

---

## 2 裁定

**不支持普通 struct 值接收者的 `?.`；但值上取到的指针 / map 跳可以继续 `?.`。**

- `?.` 的接收者只收**指针**（含 `Map::get` 返回的 `T*`）；`p?.field` 展开为 `(p ? p->field : 0)`；
  map 键缺失时整链短路，结果 `0`/NULL，不引入新运行时。
- **普通 struct 值接收者本身**（`a?.b`，`a` 是 struct 值）：编译期硬错。错误必须写明
  「值类型没有空状态，请用指针或显式可空类型」。
- **值上取到的一跳**（`a.b?.c`，`a` 是 struct 值、`b` 是指针或 map）：允许。这里的 `?.` 接收者是
  `a.b`（指针），不是 `a`；它走的是指针规则，不是「值类型支持」。map 形态同理，但要求
  `Map<K, V>` 的 `V` 是值类型：`a.m["k"]?.c` 的接收者是 `get` 返回的 `V*`；若 `V` 本身是指针，
  `get` 返回 `V**`，`a.m["k"]?.c` 不成立（需 `(*a.m["k"])?.c`，不属于本正例）。
- **接收者只求值一次**：`a.b?.c` 的展开必须先把 `a.b` 落到临时量，再判空；直接写
  `a.b ? a.b->c : 0` 会在 `a.b` 含调用时求值两次（实测见 §5.2 `c3`）。
- 本卡**不引入** `Maybe<T>` / `T?` / 新的类型标记；若将来要做，单独立相，判据至少覆盖：
  布局与 ABI、`has` 的读写、含 Drop 字段的 move/部分移动、`?.` 结果类型、ASAN 双释放反例。
- 重新开启条件：出现「必须用值语义返回可缺失 struct」的真实下游需求，且接受新类型的成本；
  仅凭「最好能支持」不重开。

---

## 3 切词策略（负责人已裁定，两席共同遵守）

**规则**：不在词法层合成 `?.` token；`?` 仍是 `?`。parser 在 `?` 之后看下一个 token：

| `?` 后 | 判定 | 用例 |
| --- | --- | --- |
| `T_NUM` 且文本以 `.` 开头 | 三目 + 浮点字面量 | `c?.5 : 1.0` → `(c ? .5 : 1.0)` |
| `T_PUNCT "."`，再下一个是 `T_ID` | 可选链 | `a?.b` → `(a ? a->b : 0)` |
| 其他 | 维持 PH-44 的后缀 `?` / 三目规则 | `x?;`、`a ? b : c` |

**词法依据**（静态核对，`selfhost/ct-ast/frontend/lex/Lexer.h.ct`）：

- `.5` 在 `:244-271` 被整体扫成 `T_NUM`，不是 `.` + `5`；
- `?` 在 `:356` 走单字符 `T_PUNCT` 兜底，不与其他字符合并；
- 因此 `c?.5` 的 token 流是 `c` `?` `.5`，`a?.b` 是 `a` `?` `.` `b`，parser 可判定。

**现状实测**：

```text
$ CT_STD_DIR=<repo>/lib/std /tmp/ctgap/bin/ct /tmp/battle53/t1_ternary_dot5.ct -o /tmp/battle53/t1.c
ct_rc=0
$ grep -n '\.5\|1\.0' /tmp/battle53/t1.c
155:    double d = (c ? .5 : 1.0);
$ cc -Wall -Wextra -std=c99 /tmp/battle53/t1.c -o /tmp/battle53/t1 && /tmp/battle53/t1
run_rc=0

$ /tmp/ctgap/bin/ct /tmp/battle53/t2_value_optional.ct -o /tmp/battle53/t2.c
ct_rc=1
/tmp/battle53/t2_value_optional.ct:6:1: error: '?' needs a Result operand
no .c
```

指针接收者今天同样报 `'?' needs a Result operand`（`t3_ptr_optional.ct`，rc=1）；
目标展开 `(p ? p->b : 0)` 已用 C 探针验证可编译、可运行（`p10`：`present=5 missing=0`）。

---

## 4 可执行判据（进卡面）

| ID | 夹具 / 命令 | 通过条件 |
| --- | --- | --- |
| T1 | `c?.5 : 1.0`，`c=1` 与 `c=0` 各一份；`ct` 生成 C 后 `cc` 并运行 | `ct` rc=0；生成 C 含 `(c ? .5 : 1.0)`（`.5` 未被切开）；两个分支输出分别符合三目；运行 rc=0 |
| T2 | `p?.b`，`p` 为 `struct S *`；分别传有效地址与 `0` | `ct` rc=0；生成 C 含 `(p ? p->b : 0)`；有效时输出字段值，`0` 时输出 `0` |
| **N1** | `s?.b`，`s` 为普通 `struct S` 值 | `ct` rc=1；不落 `.c`；stderr 命中卡面指定的**值接收者**硬错文案；**不得**落成 `'?' needs a Result operand` |
| **P1** | `a.b?.c`，`a` 为 `struct H` 值、`b` 为 `struct B *`；`b` 有效 / `0` 各一份 | `ct` rc=0；生成 C 先把 `a.b` 落临时量再展开（`t ? t->c : 0`）；有效输出字段值，`0` 时输出 `0` |
| **P2** | `a.m["k"]?.c`，`m` 为 `Map<char *, B>`（`V` 是值类型）；键存在 / 缺失各一份 | `ct` rc=0；生成 C 只调用一次 `get`；存在输出字段值，缺失输出 `0` |
| **P2b** | `a.m["k"]?.c`，`m` 为 `Map<char *, B *>`（`V` 是指针） | `get` 返回 `B**`；该形态必须硬错，或要求显式 `(*a.m["k"])?.c`；不得把 `B**` 当 `B*` 去取 `.c` |
| **P3** | 接收者含副作用的 `a.b?.c`（如 `make().b?.c`） | 接收者表达式只求值一次；对照：naive 两遍展开会调用两次（`c3`） |
| T5 | `p?.5`（`?` 后是浮点字面量） | 按三目处理；若三目不完整则语法错误，**不得**被识别成可选链 |
| T6 | `a ? .5 : 1.0` 既有形态 | 与 T1 产物一致；作为回归控制 |

> N1 / P1 / P2 的文案与编号由卡面落定；本记录只钉行为，不替代卡面。
>
> **当前实现的事实（必须如实写进卡面 S0）**：`?.` 尚未实现。N1、P1、P2 三个用例在
> `ct v0.44.1` 上全部 rc=1，且报同一条 `'?' needs a Result operand`；**正例目前走不通**，
> 现有实现没有「值上取到的一跳」这个接收者类型判定，也没有把 `a.b` 落临时量的路径。
> 卡面必须先落接收者类型区分与单次求值，P1/P2 才可能转绿；不得把「现在 rc=1」解释成
> 「正例被类型系统拒绝」。

---

## 5 实测附录

### 5.1 CT 用例

| 文件 | 命令 | 结果 |
| --- | --- | --- |
| `t1_ternary_dot5.ct` | `ct ... -o t1.c`；`cc`；运行 | `ct_rc=0`；`155: double d = (c ? .5 : 1.0);`；`run_rc=0` |
| `t2_value_optional.ct` | `ct ... -o t2.c` | `ct_rc=1`；`error: '?' needs a Result operand`；无 `.c` |
| `t3_ptr_optional.ct` | `ct ... -o t3.c` | `ct_rc=1`；同一文案；无 `.c` |
| `p1_field_ptr_optional.ct` | `ct ... -o p1.c`（`a.b?.c`，`b` 为指针） | `ct_rc=1`；同一文案；无 `.c`（正例当前走不通） |
| `p2_map_optional.ct` | `ct ... -o p2.c`（`a.m["k"]?.c`，`m` 为 `Map<char*, B*>*`） | `ct_rc=1`；同一文案；无 `.c`（正例当前走不通） |
| `p3_field_ptr_manual.ct` | `ct ... -o p3.c`；`cc`；运行（显式 `h.b ? h.b->c : 0`） | `ct_rc=0`；生成 `x = (h.b ? h.b->c : 0);`；`run_rc=0` |
| `p4_map_manual.ct` | `ct ... -o p4.c`；`cc`；运行（`Map<char*, B*>`，`V` 为指针） | `ct_rc=0`；`cc` 警告 `incompatible pointer types`（`B*` ← `B**`）；`run_rc=1` |
| `p5_map_value_manual.ct` | `ct ... -o p5.c`；`cc`；运行（`Map<char*, B>`，`V` 为值） | `ct_rc=0`；生成 `x = (t ? t->c : 0);`；`run_rc=0` |

### 5.2 C 探针（`cc -Wall -Wextra -std=c99`；ASAN 用 `-fsanitize=address`）

| 文件 | 结果 |
| --- | --- |
| `p1_value_cond.c` | `cc_rc=1`；`used type 'struct S' where arithmetic or pointer type is required` |
| `p2_sentinel.c` | `cc_rc=0`；`absent=0 zero=0` |
| `p3_maybe.c` | `cc_rc=0`；`absent=0 present_zero=0` |
| `p4_drop_ternary.c` | ASAN `double-free`；`run_rc=134` |
| `p5_vptr_zero.c` | `cc_rc=0`；`vptr=0x0`；`run_rc=139` |
| `p6_addr_field.c` | `cc_rc=0`；`nonnull=1 value=1` |
| `p7_map_chain.c` | `cc_rc=0`；`root=3 chain=7 missing=0` |
| `p8_val_result.c` | `cc_rc=0`；`present_zero_x=0 missing_x=0` |
| `p9_dot5.c` | `cc_rc=0`；`run_rc=0` |
| `p10_ptr_field.c` | `cc_rc=0`；`present=5 missing=0` |
| `p11_maybe_drop.c` | ASAN `double-free`；`run_rc=134` |
| `c1_field_ptr_target.c` | `cc_rc=0`；`present=7 missing=0`（`h.b ? h.b->c : 0`） |
| `c2_map_target.c` | `cc_rc=0`；`present=7 missing=0 calls=2`（两次调用各一次 `get`） |
| `c3_double_eval.c` | `cc_rc=0`；`naive=7 calls=2`、`hoisted=7 calls=1` |

---

## 6 对既有记录的影响

- [phase53-optional-chain-draft.md](../proposals/phase53-optional-chain-draft.md) §4.2 由「切词冲突」
  改为「切词策略」；§4.1 补「值上取到的一跳」；§2 / §5 同步接收者范围。切词不再作为阻塞或风险项。
- [phase53-scope-draft.md](../proposals/phase53-scope-draft.md) 的 B1 行同步：普通 struct 值接收者
  仍不支持；值上取到的指针/map 跳允许；当前实现两者走同一拒绝路径，卡面必须先补接收者判定。
- [phase46-52-plan.md](../design/phase46-52-plan.md) §4.2 的「独立 token 破坏 `c?.5`」不再是驳回理由；
  本记录只登记，不回改已冻结计划正文。
