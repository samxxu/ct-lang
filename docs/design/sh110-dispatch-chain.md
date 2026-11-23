# SH-110 动态派发链：接收者物化判据卡

| 项 | 值 |
| --- | --- |
| 条目 | [SH-110](../../issues/selfhost/sh110-dynamic-dispatch-chain-fix.md)、[SH-73](../../issues/selfhost/sh73-temp-receiver-dynamic-dispatch.md) |
| 基线 | `a0ce8ef1`（`issue/chain`） |
| 结论 | 方法调用（`N_MCALL`）的结果在其静态类型可物化时，可作下一跳接收者 |
| 非目标 | 不放开任意表达式接收者；不改静态宿主链 / `map` 派发；不新增语法 |

本卡是 SH-110「修复前置」要求的判据，先于发射器改动落库。三节分别钉住求值顺序、临时值
生命周期、可物化接收者形态；实现与测试都按本卡判定。

## 1 求值顺序

- 链上每个 `->` / `.` 的接收者表达式**恰好求值一次**；物化后各 hop 都只读临时量。
- hop 的编号与声明顺序为**自内向外**，因而运行顺序与源码从左到右一致。以
  `a.m(x)->n(y)->status()` 为例（`m`、`n` 都返回接口值）：

  ```c
  struct I_iface __ct_tmp0 = a_state.m(x);
  struct I_iface __ct_tmp1 = __ct_tmp0.n(y);
  return __ct_tmp1.vt->status(__ct_tmp1.self);
  ```

  `m` 先于 `n`，`n` 先于 `status`；`m` 的实参 `x` 严格早于 `n` 的实参 `y`。
- 物化位置沿用既有规则：只在**语句行首**、或**赋值 / 声明初始化式的右值行首**把整条接收者链
  提到前一行。链外的兄弟表达式不移动，所以 `g(f().m())`、`x = 1 + f().m()` 仍按原样硬错
  （`a method call on a temporary is only allowed at the start of a statement or of an assignment`）。
- 同一语句内出现多条链时，按各自语句位置从左到右物化；临时量名 `__ct_tmpN` 仍按文件中
  已发射的顺序递增。

## 2 临时值生命周期

- 每个可物化 hop 生成一个 `__ct_tmpN`，其 C 类型取该 hop 的**静态类型**，按值/指针/接口分别
  拼成 `struct S`、`struct S *`、`struct T_iface`。
- 临时量声明在闭合语句所在块的语句头，作用域到块结束；它**活到整条链结束**（含后续所有 hop 与
  使用该结果的语句），不会被后续 hop 的初始化提前销毁。
- 接口值按值复制 fat pointer（`vt` / `self`）；`self` 仍指向原对象，不复制载荷，也不 `malloc`。
  因此 `h.tap(1)->status()` 的临时接口值不会悬垂；ASan 探针覆盖该形态。
- 内层临时量先声明，外层初始化时可安全读取；`emit_hoists` 在语句正文前一次性写出全部声明。

## 3 可物化接收者形态

| 接收者形态 | 判定 | 处理 |
| --- | --- | --- |
| 变量 / 元素 / 普通调用 / 字段链（`N_VAR`、`N_INDEX`、`N_CALL`、`N_MEMBER`、`N_ARROW`、`N_INTO*`） | 既有形态 | 不变 |
| 方法调用结果（`N_MCALL`，静态类型为值 / 指针 / 接口） | **新增允许** | 静态类型可物化时记一个 `__ct_tmpN`；下一跳读临时量 |
| `N_MCALL` 且静态类型含 `[`（数组 / 指向数组）或 `(*`（函数指针） | 仍拒绝 | 物化判定失败，下一跳按接收者形态硬错 |
| `N_MCALL` 的静态宿主 / 类型宿主配方（`aux` 5 / 6） | 仍拒绝作动态接收者 | 配方只做一次文本替换，不参与临时物化 |
| 复合字面量（`N_COMPOUND`）、二元 / 三元 / 一元等其它表达式 | 仍拒绝 | 既有 `method receiver must be a variable, an element, a call or a field chain` |
| 返回 `void` 的方法 | 仍拒绝 | 无值可物化（静态类型读取失败） |

判定实现是一条纯函数：静态类型可读出、`array_depth == 0`、且拼写不含 `[` / `(*` 时才可物化。
函数指针与数组没有可拼进 `TYPE NAME = ...` 的简单声明，硬错优于产出坏 C。

## 4 实现落点

- [Emitter.h.ct](../../selfhost/ct-ast/backend/emit/Emitter.h.ct) `hoist_scan`：接收者链收集时
  对 `N_MCALL` 增加「静态类型可物化」判定；不可物化的 hop 不入链，错误仍由既有形态检查给出。
- 同文件 `em_expr_mcall`：接收者种类白名单接受**已物化**（`text3` 非空）的 `N_MCALL`；
  未物化的 `N_MCALL` 仍按原诊断硬错。
- 解析器 / 类型检查不变：可物化形态由 `static_ctype` 回答，全部在发射器内判定。

## 5 验收与回滚

- 正例：`test/ast/293_dispatch_chain` 覆盖一跳、两跳、固有 impl 返回接口后接调用、只求值一次、
  实参从左到右；探针 `test/ast/p110_dispatch_chain.sh` 另跑 `return` 位置的三形态。
- 负例：`test/ast/errors/dispatch_chain_{compound,fnptr,array}_recv.ct` 保持位置化硬错；
  既有 `temp_receiver_trait_chain.ct` 由「拒绝」改为正例来源，不再作为动态链的边界。
- 语料：不含新形态的既有 `test/cases`、`examples`、`test/ast/*/prog.ct` 生成 C 逐字节不变。
- 回滚：实现集中在 `Emitter.h.ct`；回退该提交即恢复「`N_MCALL` 一律拒绝」。
