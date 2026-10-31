# 设计模式在 CT 里的写法

> 目的：验证「OO 所需的语言特性已经齐了」。CT 不为设计模式新增语言特性——
> `trait` / `impl`、接口值 / 数组 / 字段、组合、`namespace` / `import`、`map`、
> `own` / `Drop` 这些机制一旦确立，就足够表达模式的主干。
> language-spec §8 的「明确不支持」（继承、泛型、类型检查、完整可见性修饰符）
> 是**设计决定**，不是待办。

## 1. 可运行的验证

`test/patterns/` 下每个模式是一个单文件程序，由 `selfhost/check-ast.sh` 的
「design patterns」一节编译、零告警构建、运行并比对输出：

| 模式 | 文件 | 用到的机制 |
| --- | --- | --- |
| Strategy | [strategy/prog.ct](../test/patterns/strategy/prog.ct) | trait + `impl` + 接口参数 |
| Observer | [observer/prog.ct](../test/patterns/observer/prog.ct) | 接口数组字段 + Subject 指针 |
| Decorator | [decorator/prog.ct](../test/patterns/decorator/prog.ct) | 接口字段持有同接口实现 |
| Composite | [composite/prog.ct](../test/patterns/composite/prog.ct) | 接口数组字段 + 递归调用 |
| Factory Method | [factory_method/prog.ct](../test/patterns/factory_method/prog.ct) | 返回接口的工厂函数 + 堆对象装箱 |
| Template Method | [template_method/prog.ct](../test/patterns/template_method/prog.ct) | 自由函数持有骨架，步骤抽成 trait |

运行：`bash selfhost/check-ast.sh`（只跑模式：看输出里的 `pattern/<名字>`）。
单个程序也可以直接 `ct compile prog.ct -o prog.c && cc prog.c -o prog`。

## 2. 无继承、无泛型时的三条替换规则

1. **继承 → 组合 + 接口字段。** 需要「复用父类行为」时，把被复用的部分做成
   trait，用接口字段持有；Decorator / Composite / Bridge / Proxy 都是这个形状。
2. **泛型 → 单态或类型擦除。** 容器和算法对具体类型各写一份（CT 的写法），
   或者只接收接口值（擦除到 trait）。没有类型参数，也没有模板实例化。
3. **模板方法 → 骨架放自由函数。** 继承里的「父类调用子类步骤」改成
   「自由函数接收一个步骤接口」，骨架只有一份，步骤由不同 `impl` 提供。

## 3. 其余模式怎么落

| 模式 | 写法 |
| --- | --- |
| State | 状态做成 trait 实现；上下文持有 `State` 字段或按需换成新实现 |
| Command | 命令 trait（`execute` / `undo`），调用方持有接口值或数组 |
| Chain of Responsibility | 处理器 trait，每个实现持有后继接口字段 |
| Visitor | 元素 trait 的 `accept(Visitor)` 回调访问者的每类型方法（两次单派发） |
| Adapter | 组合一个既有实现，实现目标 trait 并转发 |
| Proxy | 与 Decorator 同形：实现目标 trait，内部决定是否/何时转发 |
| Facade | 一个 `namespace` 导出少量 `pub` 函数，隐藏内部单元 |
| Singleton | 命名空间里的 `pub` 全局实例（bindings 的实例写法），或文件作用域对象 |
| Iterator | trait（`next` / `done`）+ 结构体保存游标状态 |
| Builder | 结构体累积字段，构建函数返回对象或接口 |
| Prototype | trait 的 `clone` 方法返回接口，各实现复制自身 |
| Abstract Factory | 一个工厂结构体，成员是一组接口（产品族） |
| Memento | 普通结构体保存快照，由发起者自行存取 |
| Mediator | 中介 trait，同事持有中介接口字段 |
| Interpreter | Composite 的变体：终结符与组合节点共用 `eval` 接口 |
| Flyweight | 全局池 + 接口值复用，池的容量按固定上限约定 |

## 4. 边界（不是缺口，是取舍）

- **没有编译期类型检查**：参数错配、返回类型不符要到 C 编译器才报；
  CT 的定位是「把 CT 翻译成可读的 C」，不改变这个性质。
- **接口数组是固定容量**：语言没有动态容器；需要可变数量时用 `malloc` 或
  自行约定容量（Observer / Composite 的 fixture 用固定上限演示结构）。
- **没有继承**：需要「is-a」时用 trait + 组合；需要复用实现时把实现提成
  自由函数或另一个 trait。
- **没有泛型**：需要类型参数时单态化，或用接口擦除；这也是 CT 保持简单的
  关键取舍。

如果某个模式确实写不出来，正确的顺序是：先记录**具体卡点**（哪里写不出、
最小复现），再评估是否值得动语言；而不是先加特性再找用途。
