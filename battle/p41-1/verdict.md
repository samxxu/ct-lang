# battle/p41-1 判决书（EDITOR）

| 字段 | 值 |
| --- | --- |
| battle | p41-1（原子命名与 C 标准） |
| judge | EDITOR |
| 锚定 HEAD | `bd8b74f3` |
| 证据 | `verify.json` V1–V5；独立评审 P0/P1 |
| 判决 | **A `rejected`；C `rejected`；D `rejected`；B 接受为 B′** |

## 0 判决

1. **A 不成立（J-1/J-4）**：`atomic` 关键字 + `atomic_load/store/cas` 保留名会破坏 `<stdatomic.h>` 正例与同名函数；`_Atomic` 在严格 C99 下是 C11 扩展，A 没有标准切换。保留名不是“调用点更短”能补偿的兼容性破坏。
2. **C 不成立（J-3）**：保留 `atomic_load/store/cas` 但按静态类型 fallback，需要把 `atomic_int` 等 `<stdatomic.h>` typedef 在 CT 不解析头文件的前提下归一化；类型判不出时还要回退普通调用，诊断与兼容性边界不可机械审计。
3. **D 不成立（J-2/J-3）**：把 `atomic T` 映射为普通 `T` 会失去 `_Atomic` 类型与直接访问语义，并把“原子”降级为“只用助手”；与 O1 的“类型修饰符”目标不符，ABI/头文件也更难讲清。
4. **B 按 B′ 采纳**：
   - `atomic` 是**上下文类型修饰**，只在后跟 `int`/`long`/`void *`/`bool` 时生效；`int atomic = 1;` 与 `atomic;` 保持普通标识符。
   - 内建操作命名为 `ct_atomic_load` / `ct_atomic_store` / `ct_atomic_cas`；`atomic_load` / `atomic_store` 仍是普通调用，`<stdatomic.h>` 与用户同名函数不受影响。
   - 生成物 `_Atomic(T)`，但 PH-41 明确要求 **C11**：`ct compile` 文档要求 `-std=c11`；`ct build` 在存在原子单元时使用 C11（或新增 `--std=c11`）；`check-warnings` 的原子夹具以 C11 编译。
   - `ct_atomic_*` 第一实参按静态类型接受 `_Atomic(T) *`，包括 `&x` 与指针变量 `p`；不再要求语法上的左值形态。
   - `atomic_cas` 继续只收地址形态 `ct_atomic_cas(&x, &expected, desired)`；by-value L41-5。
   - 删除 L41-4（保留名）与 L41-9（`atomic` 非类型位置）作为硬错：`atomic` 不再是无条件关键字；`atomic_load` 不再保留。
   - 新增 L41-4′：`ct_atomic_*` 只接受 CT 原子实参，非原子实参报 L41-7；保留名冲突不再存在。
   - 补 `-pthread` 到通用 check-ast/test/run；TSan nightly 覆盖 Linux；编辑器 tmLanguage/check-grammar 增加 p41；类型诊断补 store/cas 的 expected/desired。
5. **执行条件**：卡面按 B′ 修订并重新评审后才能冻结；当前草案不得进入实现。

## 1 判据矩阵

| 判据 | A | B′ | 依据 |
| --- | --- | --- | --- |
| J-1 现有 `<stdatomic.h>`/同名函数 | 不成立 | 成立（名字不保留） | V1/V2 |
| J-2 解析期诊断 | 成立 | 成立（`ct_atomic_*`） | V3 |
| J-3 实现可审计 | 成立（但破坏面大） | 成立（上下文 + 前缀） | V3 |
| J-4 C 标准 | 不成立（C11 扩展） | 成立（显式 C11） | V4 |
| J-5 门禁/编辑器 | 不成立（缺口） | 需补 pthread/TSan/grammar | V5 |

## 2 反对意见保留

- B′ 的 `ct_atomic_*` 比 `atomic_load` 长；这是为避免保留名冲突的代价。
- C11 要求会让原子单元与非原子单元的标准不同；必须在 `--std`/文档中明写，不允许静默扩展。
- 本判决不修改 `v0.40.1`；Phase 41 仍是草案，待卡面修订后重新评审。
