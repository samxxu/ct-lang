# 提案：泄漏防护三板斧——直接环检测 / strict 升级 / 树模式


> 状态：已裁定并实现（2026-11-21 v0.82.0；判决见 [battle leak-guards-1](../../battle/leak-guards-1/verdict.md) 与 [D-012](../decisions/D-012.md)；L1/L2/L4 进 v0-PH-82，L3 descope）
> 基线：v0.77.x；与「指针退场」提案独立（对现行 own/句柄代码同样生效），可并行施工。
> 说明：文中 `ct.pkg strict`、header debug 字段、`--debug-leaks` 环扫描等表述与仓库现状不符；
> 实际落卡口径以 D-012 为准（`leaks = warn|error`；L3 descope；`--debug-leaks` 只报计数）。

---

## 1. 背景与动机

当前约定（D-011 J-4c）：引用计数环泄漏静默发生、无任何告警，责任归作者。
该约定成立的前提是「环很少见」——但直接环（两个 Box/句柄互为字段）大多来自手滑，
是可以静态抓的。本提案在**不引入 GC、不引入 weak 类型、不做跨过程分析**的三不原则下，
把环泄漏从「无声事故」变成「三层递减的可见风险」。

## 2. 三板斧设计

### 2.1 第一板斧：直接环的类型级检测（编译期，零运行时）

规则：展开 struct 的字段图（`Box<X>` 字段 → X），**限深 3 层**内若出现
`X → … → X` 的有向环，给出诊断：

```ct
struct A { Box<B> b; }
struct B { Box<A> a; }   /* warning: potential reference cycle: A → B → A */
```

- 诊断级别：默认 **warning**；`ct.pkg strict = on` 的包内为 **error**；
- 经 `Vec<Box<T>>`、泛型参数、方法转手的间接环**不在检测范围**（类型信息不足，不做猜测）；
- 深度 3 是保证可判定性的上限，也是覆盖率的甜点（实测后再校准）；
- 实现通道：复用 `--types` 的类型图基础设施，无新分析框架。

### 2.2 第二板斧：strict 模式泄漏告警升 error（配置级，零新机制）

- `ct.pkg strict = on` 的包内，`potential leak` 从 warning 升为 **error**；
- 非 strict 包维持 warning（渐进迁移路径不受影响）；
- 使「句柄代码基本不漏」从风格承诺变成**可强制的构建属性**。

### 2.3 第三板斧：`--debug-leaks` 环扫描（debug 专属，release 零成本）

- `--debug-leaks` 新增可选 mark 遍历：从全局根集出发标记可达句柄，refs>0 且不可达者
  报告「leaked cycle: 类型 + 分配点」（分配点取 header 里预留的 debug 字段）；
- **仅 debug 构建生效**，release 产物零代码、零数据开销；
- 明确性质：这是可见性工具，不是回收机制——发现环 ≠ 自动解环。

### 2.4 配套（文档层）：树模式固化

`patterns.md` 新增「父子结构」一节，固化标准写法：

```ct
struct Node {
    Box<Node> first_child;   /* owning：向下 */
    Node *parent;            /* 逃生层裸指针：向上，不参与计数，天然破环 */
}
```

把 C 程序员最熟的方案从个人经验升级为官方惯用法。

## 3. 判据（全部可机械化）

- J1：`test/ast/cycle_direct` 负例（A↔B 字段环）在 warning 通道报告、strict 包内 error；
   合法语料（含经 Vec 的间接环写法）零误报（沿用 Phase 19 出口标准）。
- J2：strict 包内引入泄漏路径 → 构建失败；同代码在非 strict 包内仅 warning。
- J3：`--debug-leaks` 下环检测探针输出包含分配点；不带该 flag 的产物与现状逐字节一致。
- J4：release 构建（不带 debug flag）的代码体积与现状差异为 0（grep 无新符号）。

## 4. 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| 字段环检测误报（如刻意设计的环+手动 break） | 提供显式豁免语法（如 `Box<B> b; /* ct: allow-cycle */`），豁免点进 lint 报告 |
| 深度 3 之外的环漏检造成假安全感 | 诊断文案明示「仅检测限深内的直接环」；第三板斧兜运行期可见性 |
| debug 扫描在巨型堆上耗时 | 触发方式改为显式（退出时跑），不周期自动跑；文档注明成本 |
| strict 升 error 阻塞存量包 | 仅对显式开 strict 的包生效，默认包不受影响 |

## 5. 非目标（重申三不原则）

- 不做运行期自动环回收（tracing GC 简化版也不做）；
- 不引入 weak 引用类型（直接环静态检测覆盖其 80% 价值，性价比不成立）；
- 不做跨过程/跨单元逃逸分析（v0-PH-71 非目标不动摇）；
- 不承诺间接环的静态检测。

## 6. 施工切片

| 切片 | 内容 | 依赖 | 建议版本位 |
| --- | --- | --- | --- |
| L1 | 第二板斧（strict 升 error） | 无 | patch 位 |
| L2 | 第一板斧（限深字段环检测 + 豁免语法） | L1 的 strict 通道 | 一个 MINOR |
| L3 | 第三板斧（debug mark 扫描） | L1 | 一个 MINOR，可并行 |
| L4 | 树模式文档 | 无 | 不占版本位 |

## 7. 开放问题

1. 字段环默认 warning 还是直接 error？（倾向 warning，与 CT「检测不强制」的气质一致；
   strict 包内才是 error。）
2. 限深 3 是否够用？需要先在仓内语料上跑一次统计（多少真实字段图超过 3 层）再定稿。
3. 豁免语法用注释还是属性式标记？注释零语法成本但容易被 refactor 丢掉，评审裁定。
4. debug 扫描的分配点字段（header 预留 8 字节）是否只在 debug 构建存在？
   倾向：header 布局不变，分配点存 side table（构建时选择），保持 release 头 8 字节不变。
