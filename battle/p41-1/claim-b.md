# p41-1 主张席：B 上下文关键字 + `ct_atomic_*`

> 席位：REQ；方案 B；HEAD `bd8b74f3`；未改源码/测试/卡面。

## 0 方案

1. `atomic` 不是无条件关键字：只有 `atomic` 后跟 `int` / `long` / `void *` / `bool` 时进入类型修饰；其它位置保持普通标识符。这样 `int atomic = 1;`、`atomic;`、`atomic_load` 不被吃掉。
2. 内建操作命名为 `ct_atomic_load` / `ct_atomic_store` / `ct_atomic_cas`；`atomic_load` / `atomic_store` 仍是普通调用，`<stdatomic.h>` 宏与用户同名函数不受影响。
3. 生成物仍是 `_Atomic(T)`；但 PH-41 明确要求 C11：`ct compile` 文档要求 `-std=c11`，`ct build` 在检测到原子类型时使用 `-std=c11`（或新增 `--std=c11`）；`check-warnings` 的原子夹具用 C11。
4. `atomic_load` 的第一实参按**静态类型**接受两类：
   - `&atomic_lvalue`（`_Atomic(T) *`）
   - 任意 `_Atomic(T) *` 表达式，包括指针变量 `p`
   不再要求语法上必须是 `N_VAR` 等左值。
5. 保留 `atomic_cas` 的地址形态；`ct_atomic_cas(&x, &expected, desired)`。

## 1 证据

### E1 现有 `<stdatomic.h>` 正例（现状）

`docs/bindings-and-patterns.md` §7：

```ct
atomic_int total = 0;
atomic_store(&total, atomic_load(&hits));
```

A 把 `atomic_load/store` 设为保留名，并且 `atomic_int` 是 `<stdatomic.h>` typedef；CT 不解析头文件，A 无法同时满足“裸 C11 仍可用”和“4 基类型静态检查”。

### E2 C99 严格编译

```console
$ cc -std=c99 -pedantic-errors -c /tmp/atomic-c99.c
error: '_Atomic' is a C11 extension [-Werror,-Wc11-extensions]
```

A 的生成物 `_Atomic(T)` 与项目“C99”声明不一致；B 显式要求 C11，避免把扩展说成 C99。

### E3 现有 pthread 门禁

`selfhost/check-ast.sh` 的通用 `test/ast/*` 链接与 `test/run.sh` 的 examples 链接都没有 `-pthread`；A 只在 R41-8 提到 check-sanitizers/tsan，无法接住 p41 runtime 夹具。

### E4 `atomic_load(p)` 语义

C11 允许 `atomic_load(p)`，其中 `p` 是 `_Atomic(T) *`；A 的 L41-7 要求“可寻址的原子左值”，与 helper 的指针签名矛盾。B 按静态类型收敛。

## 2 代价

- 解析器：`atomic` 上下文识别 + 两个名字（`ct_atomic_*`）比 A 多一个 `is_atomic_type_ahead`，但不新增关键字。
- 文档/迁移：`atomic_load` 标准名不改，不需要迁移现有 `<stdatomic.h>` 用户；新增 `ct_atomic_*` 名称。
- 标准：需要 `--std=c11` 或 `ct build` 自动选择 C11；这是显式契约，不是隐藏扩展。
- 门禁：p41 runtime 需要 `-pthread`；B 把它列入 R6/R7。

## 3 结论

B 同时满足 J-1（不破坏现有名字）、J-2（仍可诊断）、J-4（标准明确）；实现成本高于 A 但低于 C 的 fallback 类型归一化。建议 EDITOR 采纳 B。
