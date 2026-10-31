# 第三十六批：Trait 默认方法（2026-10-31）

> 锚点：`f4c77b1`（第三十五批收口）。
> 目标（用户确认）：让 trait 方法可以带默认实现，`impl` 只写需要定制的部分。
>
> 定位（用户原话）：CT 的 trait 更像一个**可多采纳的抽象基类**——方法可以全 abstract、
> 全 default，或两者混合；全部是 default 时，**`impl` 整块都不需要**。
> 默认方法的目的只有一个：源码只写一次，产物按 struct 分开。

## 1. 做法

默认体在**每个采纳点各展开一份**，不在 trait 层共享。vtable / `_iface` / 装箱 / 派发结构
**零改动**：展开后的默认方法就是一个普通 impl 方法，vtable 槽照旧填它的函数指针。

| trait 形态 | 采纳处要写什么 |
| --- | --- |
| 全 abstract（现状） | 每个方法都实现 |
| 混合 | 只实现 abstract 的那几个，其余继承默认体 |
| 全 default | 什么都不写，`use Trait;` 即采纳 |

## 2. 语义

### 2.1 语法

trait 方法签名后可直接跟语句块：

```ct
trait Logger {
    int write(char *buf, int len);                 /* abstract */

    int write_all(char *buf, int len) {            /* default */
        int sent = 0;
        while (sent < len) sent = sent + self->write(buf + sent, len - sent);
        return sent;
    }
}
```

### 2.2 生成物（结构不变）

```ct
struct Conn { int fd; } use Logger;

impl Logger for Conn {
    int write(char *buf, int len) { return send(self->fd, buf, len); }
}
```

```c
static int Conn_Logger_write_all(void *self, char *buf, int len);
static struct Logger_vtbl Conn_Logger_vtable = {
    .write     = Conn_Logger_write,
    .write_all = Conn_Logger_write_all,     /* 默认体填进槽 */
};

static int Conn_Logger_write_all(void *self, char *buf, int len) {
    struct Conn *_self = (struct Conn *)self;
    int sent = 0;
    while (sent < len) sent = sent + _self->__logger_vptr->write(_self, buf + sent, len - sent);
    return sent;
}
```

`self->write(...)` 展开为 `_self->__logger_vptr->write(...)`，正是现有规则
（[Emitter.h.ct:1751-1755](../../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1751-L1755) 的发射期派发生成），
不新增任何派发逻辑。

### 2.3 全 default 的采纳

```ct
trait Logger {
    int write(char *buf, int len) { return 0; }
    int write_all(char *buf, int len) { ... }
}

struct Conn { int fd; } use Logger;   /* 没有任何 impl */
```

生成 `Conn_Logger_write`、`Conn_Logger_write_all`、`Conn_Logger_vtable`，全部 `static`，
与有 `impl` 时结构一致。

## 3. 决策

- **D-1 默认体按 (struct, trait) 各一份，不共享。** vtable 槽类型是 `(void *, ...)`，默认实现
  收到的是具体对象指针，**取不到自己的 vtable**，所以 `self->other()` 只有在知道具体 struct
  时才能生成 `_self->__<trait>_vptr->other(_self)`。这与 Java `default`（一份，`this` 自带类型信息）
  不同，更接近 PHP trait（每 use 一份）。默认体因此是 per-struct 特化，编译时要分开生成。
- **D-2 vtable / iface / 装箱 / 派发零改动。** 默认体展开后就是普通 impl 方法。
- **D-3 采纳声明必须存在**：`use Trait;`（自有类型）或空 `impl Trait for S { }`（外来类型）。
  vtable 需要唯一归属的翻译单元（Batch 2 的 SH-14 修复依赖这一点），`use` 本来就在 struct
  定义处，成本为零。
- **D-4 覆盖优先级**：impl 显式方法 > 默认方法；abstract 方法缺失仍按 SH-8 报
  `trait method 'x' is not implemented`。
- **D-5 默认体里 `self` 的能力**：展开后是 `struct <S> *`，可访问字段、可派发兄弟方法、
  可调自由函数。这比 Java `default` 更强，是展开语义的直接结果。
- **D-6 环检测**：默认体互相派发成环（`a` 调默认 `b`、`b` 调默认 `a`）且没有 abstract 叶子时，
  编译期报 `trait 'T' has no non-default method to break the cycle`，否则运行期无限递归。
- **D-7 诊断位置**：默认体归属 trait 声明处；展开失败报
  `trait T::m (declared at <path>:<line>) cannot be expanded for struct S: <reason>`，
  不要把错误落在用户没写过的方法上。
- **D-8 `Drop` 不受影响**：内建 trait 没有声明方法，也不产生默认体。

## 4. 边界与非目标

- 不做**字段注入**（PHP trait 那种把 `$this->prop` 也复制进来的形态）：会改变 struct 布局，
  而布局是 C ABI 与 `pub struct` 头文件的一部分。
- 不做 supertrait / trait 继承。
- 不做「trait 层共享一份默认体」的体积优化（D-1 已排除；体积真成问题时再议）。
- 不改 `map`：绑定外部 C 函数与默认方法是正交的两件事。
- 冻结层只动 `CTC_VERSION` 一行（用户授权的一次 bump：v0.13.0 → v0.14.0），行为与既有 golden
  不变；其余 L0 / L1 / L2 源码不动。

## 5. 风险

| 风险 | 说明 | 缓解 |
| --- | --- | --- |
| 代码体积 | O(structs × defaults) | 默认方法通常很短；关卡能看到真实规模，超出预期再考虑共享（D-1 复审） |
| 默认体在某个 struct 上不成立 | 例如默认体写 `self->fd`，另一个 struct 没有 `fd` | 展开期逐 struct 类型检查，按 D-7 指回 trait 声明 |
| 派发生成依赖发射上下文 | 派发按 `self_mode` 与接收者类型在发射期生成，默认体节点可被多个 impl 共享 | 确认默认体节点不被任何解析期改写；若有就地改写，改为按 impl 克隆 |
| 与 `pub` 导出交叉 | `pub trait` + `pub struct` 的 vtable 导出规则不变 | 复用 `vtable_exported`，默认方法不额外参与判定 |

## 6. 验证

见 [tasks.md](tasks.md) 与 [checklist.md](checklist.md)。出口是
`bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`，且现有 trait（全部无默认体）
的行为与所有既有 golden 完全不变。
