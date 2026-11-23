# 提案 · 视图节点注记语法（`view` 子句）

| 项 | 值 |
| --- | --- |
| 状态 | **提案（待研判）**；不排 phase 卡、不改 `selfhost/**` |
| 来源 | SwiftCT 静态映射评估（2026-11-15） |
| 拟占 | `v0-PH-60`（须等 v0-PH-59 模型导出定稿后再占号） |
| 关联 | [ct-model-export-proposal](ct-model-export-proposal.md)、LANG-9、v0-PH-58 |
| 第一个消费者 | SwiftCT 的 PHP 生成器（读模型里的 `view` 元数据） |

## 1 要解决什么

允许在 `.ct` 里声明「这个 struct 是视图节点、它的子节点是哪些字段、它绑定哪个状态字段」，
让编译期就能校验这层关系，并让模型导出把这份意图带给代码生成器；避免每个生成器各自维护
一份「哪个 struct 是视图、哪个字段是子节点」的外部清单。

## 2 现状与证据

- **没有注记语法**：`pub struct` 之后只有可选的 `use Trait` 子句；没有 attribute、没有 `@`、
  没有 `#[...]`。
- **`pub const` 能表达静态值，但不可替代声明**：实测 HEAD `v0.53.1`，在根 `.h.ct` 写

  ```ct
  pub const int LIMIT = 5;
  pub const struct Node ROOT = { 1, "root" };
  ```

  生成的头文件是

  ```c
  extern const int lib_LIMIT;
  extern const struct lib_Node lib_ROOT;
  ```

  即 `pub const` **会产生导出符号**，进入 ABI 面。
- **注释约定不可校验**：`//@view ...` 编译器不读，拼错字段名不会报错；模型导出只能再写一个
  注释解析器，工具链分裂。
- **外部清单会漂移**：SwiftCT 目前靠外部清单把 struct 映射成视图节点，重命名字段后清单不会红。

## 3 方案取舍

| 方案 | 做法 | 优点 | 代价 / 风险 | 结论 |
| --- | --- | --- | --- | --- |
| **A `view` 子句**（推荐） | 在 struct 体之后、`use` 子句之后加一个 `view { … }` | 编译期校验字段存在与绑定；零 C 符号；模型可直接导出；语法沿用既有「struct 后置子句」形状 | 解析器加一个上下文关键字；模型 schema 加一段 | **推荐** |
| **B `pub const` 描述符** | 用户写 `pub const struct ViewDesc USER_CARD_VIEW = { … }` | 零语法改动，今天就能写 | 产生 ABI 符号；字段名是字符串、无编译期校验；每个生成器自定义描述符形状；schema 重复 | 不采纳 |
| **C 注释 pragma** | `//@view state=user child=title` | 零语法改动、零 ABI | 编译器不校验；模型导出要解析注释；格式靠约定，重命名不报错 | 不采纳 |

推荐 A：只有 A 同时满足「编译期可校验」「零 ABI」「模型可导出」三条。

## 4 最小语法草案

```ct
pub struct UserCard {
    Str title;
    Str body;
    int likes;
} view {
    state user;
    child title;
    child body;
}
```

规则（第一版）：

1. `view` 是**上下文关键字**：只在 struct 体的 `}` 之后、可选 `use` 子句之后出现；
   普通字段名 / 变量名仍可叫 `view`。
2. `view { … }` 内只允许两类条目，每条以 `;` 结束：
   - `state <field>;`：恰好一条，字段必须存在且非 static；
   - `child <field>;`：0..n 条，字段必须存在且非 static；重复条目报错。
3. **嵌套由字段类型表达**：若 `child` 指向的字段类型本身带 `view`，树在模型里自然组合；
   不引入第二套树 DSL、不写内联节点。
4. 校验失败的错误必须带 `file:line:col` 与字段名：
   - `unknown field 'titel' in view of 'UserCard'`
   - `state must name exactly one field`
6. 注解**不改变**字段可见性、不改变布局、不生成 C 符号；它只进入模型。
7. 可见性策略：允许 `child` / `state` 指向私有字段；模型里字段仍标 `visibility`，
   由消费方决定是否生成访问器（此条列为研判开放问题）。

## 5 与 `pub const` 静态初始化的关系

**视图树可以直接用 `pub const` 表达一个「值」，但不能表达「声明意图」。**

| 维度 | `pub const` | `view` 注记 |
| --- | --- | --- |
| 表达对象 | 运行期常量（可嵌套 struct/数组） | 编译期元数据 |
| 字段名校验 | 无（字符串/位置） | 有（必须是字段） |
| 状态字段类型校验 | 无 | 有（字段存在、非 static） |
| ABI | **产生导出符号**（实测 `lib_ROOT`） | 零符号 |
| 生成器消费 | 需约定描述符形状 | 统一进模型 schema |
| 重命名 | 不报错 | 编译错误 |

若将来需要「运行期视图树实例」，正确组合是：`view` 注记声明意图 + 由工具/生成器产出
`pub const` 实例；而不是用 `pub const` 取代注记。

## 6 代价与风险

| 项 | 估计 |
| --- | --- |
| 解析器 | 后置子句 + 上下文关键字，约 **S** |
| 符号/校验 | 字段存在性与非 static 校验，约 **S** |
| 模型导出 | schema 加 `view: {state, children}`，约 **S**（依赖 v0-PH-59） |
| 风险 1 | `view` 与既有标识符冲突 → 限定为 struct 体后，加回归（字段名 `view`、变量名 `view`） |
| 风险 2 | 语义蔓延成模板/运行时框架 → 非目标写死，评审守住 |
| 风险 3 | 私有字段进模型引发争议 → 研判时定「允许但标 visibility」或「只允许 pub」 |
| 风险 4 | 多级嵌套的循环引用 → 第一版允许环，模型原样导出；不做拓扑排序 |

## 7 非目标

- 不做 JSX / 模板语法 / 组件运行时；
- 不做数据绑定执行语义（只声明，不生成同步代码）；
- 不做属性访问协议（那是 v0-PH-56 的独立议题）；
- 不改变 struct 布局、字段可见性、构造方式；
- 不导出 enum 成员或函数注记（第一版只 struct）。

## 8 对 ABI / 兼容性的影响

- **预期零 ABI**，依据三条：
  1. 注记只写入 AST 元数据，不进入 Emitter 的声明/定义遍历；
  2. 不生成 C 符号（与 `pub const` 的实测对比见 §5）；
  3. 不改 struct 布局与头文件字段列表。
- **兼容性**：无 `view` 子句的 struct 输出逐字节不变；`view` 作为字段名/变量名不受影响。
- **验证方式**：`.abi.h` 与 `.ctbuild/*.c|h` 的 golden 在加注记前后逐字节相同；
  若某实现需要发射描述符，必须另行提案，不能夹带。

## 9 验收判据草案

| ID | 判据 |
| --- | --- |
| V1 | 带 `view` 子句的 struct 能编译；模型 JSON 含 `view.state` 与 `view.children` |
| V2 | 未知字段名 → 编译错误，消息含字段名与 `file:line:col`，不写 `.c` |
| V3 | `state` 缺失或重复 → 编译错误；`child` 重复 → 编译错误 |
| V4 | 无 `view` 子句的既有 struct 输出逐字节不变（`.c` / `.h` / `.abi.h` golden） |
| V5 | 字段名或变量名恰为 `view` 的既有代码零回归 |
| V6 | 嵌套：`child` 字段类型自身带 `view` 时，模型里形成父子关系，无需额外 DSL |
| V7 | 私有字段策略按研判结论执行，并有正/负例 |

## 10 排位与依赖

- 位置：**v0-PH-60**，在 v0-PH-59（模型导出）之后；
- 依赖：v0-PH-59 的 schema 与导出入口必须先冻结；否则注记写了没有统一出口；
- 与 v0-PH-58：字段 `line/col` 是可选增强（V2 的错误定位用编译器现有位置即可，不依赖 v0-PH-58）；
- 与 v0-PH-57：无依赖；
- 与 SH-79：无依赖（注记不进 `--emit-map`）。

## 11 研判与后续

- 研判记录见 [swiftct-mapping-proposal-review](../../docs/review/swiftct-mapping-proposal-review.md)；
- 研判通过后再写需求定稿、进 roadmap、开 phase 卡；
- 提案阶段不改 `selfhost/**`、不排 phase 卡。
