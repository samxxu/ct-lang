# 设计模式在 Ct 里的写法

> 目的：验证「OO 所需的语言特性已经齐了」。Ct 不为设计模式新增语言特性——
> `trait` / `impl`、接口值 / 数组 / 字段、组合、`namespace` / `import`、`map`、
> `own` / `Drop` 这些机制一旦确立，就足够表达模式的主干。
> language-spec §8 的「明确不支持」（继承、全量类型检查、完整可见性修饰符、模板参数推导）
> 是**设计决定**，不是待办；泛型**函数**、泛型 struct 与泛型 trait 已分别落地（Phase 26 / 29 / 35），
> 可用来替掉一部分单态化。

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

## 2. 无继承时的三条替换规则

1. **继承 → 组合 + 接口字段。** 需要「复用父类行为」时，把被复用的部分做成
   trait，用接口字段持有；Decorator / Composite / Bridge / Proxy 都是这个形状。
2. **泛型容器 → 单态或类型擦除。** 优先用内置 `Vec<T>` / `Map<K, V>`，或自己写泛型 struct
   （`struct Name<T>`，Phase 29）；也可以只接收接口值（擦除到 trait）。泛型函数与泛型 trait
   同样可用（Phase 26 / 35）。
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
| Builder | 字符串起手 → factory → trait 定义的对象类型 → 接口链；完整定义与两档判断见 [language-spec §4.10.1](language-spec.md)，HTTP 配方见 [bindings-and-patterns §8](bindings-and-patterns.md)，无状态转换走轻量路径（[examples/48_string_steps](../examples/48_string_steps/src/main.ct)） |
| Prototype | trait 的 `clone` 方法返回接口，各实现复制自身 |
| Abstract Factory | 一个工厂结构体，成员是一组接口（产品族） |
| Memento | 普通结构体保存快照，由发起者自行存取 |
| Mediator | 中介 trait，同事持有中介接口字段 |
| Interpreter | Composite 的变体：终结符与组合节点共用 `eval` 接口 |
| Flyweight | 全局池 + 接口值复用，池的容量按固定上限约定 |

## 4. 边界（不是缺口，是取舍）

- **默认路径不做全量类型检查**：`ct compile` / `ct build` 不做全量类型检查；多数算术类错配
  仍要到 C 编译器才报（`ct build` 会转述 cc 的错误），但**按值 struct 的实参/返回不一致**
  （v0.53.2 起）与 **impl 签名漂移**（v0.45 起）已是硬错，`ct build --check-level=warn|error`
  还能把 B 的检查接进构建路径。需要更早发现时用可选的 `ct check --types`（**受限子集**，
  Phase 32 / [language-spec §4.53](language-spec.md#453-可选类型检查-ct-check---typesphase-32)），
  它不是全量类型系统，也不改变编译路径。Ct 的定位是「把 Ct 翻译成可读的 C」，不改变这个性质。
- **接口数组仍是固定容量**：`Vec<T>` / `Map<K,V>` 是内建动态容器，但接口值数组
  （`Iface a[N]`）仍是固定容量；需要可变数量时用 `Vec<Iface>`。Observer / Composite 的
  fixture 用固定上限演示结构，不是语言不能动态增长。
- **没有继承**：需要「is-a」时用 trait + 组合；需要复用实现时把实现提成
  自由函数或另一个 trait。
- **泛型函数 / struct / trait 已落地，但不做参数推导**：泛型函数、泛型 struct、泛型 trait 分别在
  Phase 26 / 29 / 35 落地；容器优先用内置 `Vec<T>` / `Map<K, V>`（不需要 import），其余按单态化
  或接口擦除处理。Ct 仍没有继承与模板参数推导，这是保持简单的取舍。

如果某个模式确实写不出来，正确的顺序是：先记录**具体卡点**（哪里写不出、
最小复现），再评估是否值得动语言；而不是先加特性再找用途。

## 5 父子结构（树）

`box<T>`（[language-spec §4.71](language-spec.md)）是唯一 owning 的单对象句柄；一棵树的
标准写法是**向下 owning、向上逃生**：

```ct
struct Node {                 /* ct: allow-cycle */
    box<Node> first_child;    /* owning：向下 */
    Node *parent;             /* 逃生层裸指针：向上，不参与计数，天然破环 */
}
```

- `first_child` 是 `box<Node>`：父节点释放时按静态类型递归 release 子节点，深度由树结构决定；
- `parent` 用裸指针：向上不拥有，不会与子节点的 refs 互相咬住；
- `struct` 这一行要带 `/* ct: allow-cycle */`，否则 v0.82.0 起会报
  `potential reference cycle: Node -> Node`（PH-82 / D-012）。检测只展开 `box<X>` 字段，
  所以把 `parent` 写成裸指针本身已经「手工破环」；标记是把作者意图写进代码，并让
  `ct check` 留一条 `note:` 供审计。
- 需要强制时在 `ct.pkg` 写 `leaks = error`：漏掉标记的直接环会让构建失败，带 `allow-cycle`
  的树不受影响。
- 兄弟链、多叉树同理：ownership 只沿 `box<>` 向下的边，向上的边一律裸指针或下标。

## 6. `kind` 判别改写成穷尽 `match`

树的 tag 判别有两种写法。旧写法把 `kind` 做成手编号的 C `enum`，负载摊平在同一个
struct 里，`switch` 靠人保证覆盖：

```ct
enum OldKind { K_NUM, K_ADD };

struct OldNode {
    int kind;
    int v;
    struct OldNode *l;
    struct OldNode *r;
};

int old_eval(struct OldNode *n)
{
    switch (n->kind) {
    case K_NUM:
        return n->v;
    case K_ADD:
        return old_eval(n->l) + old_eval(n->r);
    }
    return 0;                       /* 漏一个 kind 时这里静默兜底 */
}
```

新写法用最小 ADT（[language-spec §4.73](language-spec.md)）：tag 由变体本身承担，
负载按变体分组，`match` 漏一支就是编译错：

```ct
enum Node {
    Num(int v),
    Add(Node *l, Node *r),
}

int eval(Node *n)
{
    match (n) {
        Node.Num(v) => { return v; }
        Node.Add(l, r) => { return eval(l) + eval(r); }
    }
}
```

机械替换的对应关系：

| 旧写法 | 新写法 |
| --- | --- |
| `int kind;` 字段 | 删掉；tag 由变体决定 |
| `enum OldKind { K_NUM, K_ADD }` | `enum Node { Num(...), Add(...) }` |
| 摊平的 payload 字段（`v` / `l` / `r`） | 各变体自己的负载（`Num(int v)`、`Add(Node *l, Node *r)`） |
| `case K_NUM:` + `n->v` | `Node.Num(v) => { … v … }` |
| `default:` / 函数尾 `return 0` | 补一支变体，或显式 `_ => { … }` |
| `n->kind` 读 tag | `match (n)`（值 `n` 时为 `match (n)` 直接读 `.tag`） |

两条工程约束：

- 分支体没有 fallthrough：一支结束就离开 `match`，不再需要 `break`；分支里的 `break`
  仍表示**外层循环**的 break（发射是 if/else 链，不是 C `switch`）。
- `_` 只是**未穷尽时的兜底**；全部变体覆盖后不必写 `_`，写了会被 `ct check --types`
  提示“多余”，因为 wildcard 会掩盖以后新增的变体。

可运行的等价样例：[test/ast/291_adt_kind_rewrite/prog.ct](../test/ast/291_adt_kind_rewrite/prog.ct)
（同一棵树分别用旧 `switch` 与新 `match` 求值，输出一致）。

## 7. 句柄与借用视图选型

判据的单一权威是 `docs/idioms.md`（待入库；修正稿见 [DOC-85](../issues/docs/doc-85-idiom-priority-card.md)）。
本节只给模式选型时的一行判据；机制细节见 [language-spec](language-spec.md) §4.68–§4.71，不在此重复。

| 场景 | 选择 | 一行判据 | 权威 |
| --- | --- | --- | --- |
| 拥有还是借用 | `String` / `Str` | 过了这行还要活着 → `String`；只看一眼 → `Str` | `idioms.md` |
| 数组 / 容器传参 | `T[]` 切片 | 长度随指针走；不要 `T *a, int n` | `idioms.md` |
| 写回调用方 | `out T` / `ref T` | 出参用 `out`（定值分析），读写用 `ref`；不要裸出参指针 | `idioms.md` |
| 单个堆对象 | `box<T>` | 跨函数持有才 box；栈上值够用就别 box | `idioms.md` |
| 指针 | `T *` | 只在 shim / MMIO / extern 与逃生层；应用层先想 `Str` / 切片 / `box` | `idioms.md` |
