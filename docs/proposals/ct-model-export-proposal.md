# 提案 · CT 模型图导出（供代码生成器消费）

| 项 | 值 |
| --- | --- |
| 状态 | **提案（待研判）**；不排 phase 卡、不改 `selfhost/**` |
| 来源 | SwiftCT 静态映射评估（2026-11-15） |
| 拟占 | `PH-59`（提案通过并完成需求定稿后再占号） |
| 关联 | [SH-79](../../issues/selfhost/sh79-build-lib-emit-map-silent.md)、[LANG-9](../../issues/lang/lang-9-struct-field-visibility-abi.md)、[LANG-10](../../issues/lang/lang-10-machine-readable-diagnostics.md)、PH-58 |
| 第一个消费者 | SwiftCT 的 PHP 生成器（读模型，不读 `.h`） |

## 1 要解决什么

把 CT 侧的结构化事实——**字段名、字段类型、可见性、声明 kind、函数形参类型、所属单元**——以
稳定、可版本化、可机器消费的格式导出，供外部代码生成器直接使用；目标是让生成器不再靠
`grep` 头文件、正则解析 `.h.ct` 或猜测可见性。

## 2 现状与证据（HEAD `v0.53.1` 重建）

### 2.1 `--emit-map` 是调试映射，不是模型

当前 `--emit-map` 的 JSON 形状（`ct build --emit-map nb.json main.ct` 实测）：

```json
{
  "compiler": "ct v0.53.1",
  "file": "/tmp/cthead/lib/std/Vec.h.ct",
  "traits": [],
  "structs": [{"name":"ct_buf","cname":"ct_buf","file":"/tmp/cthead/lib/std/Vec.h.ct","line":30,"uses":[]}],
  "functions": [],
  "impls": [],
  "calls": [],
  "maps": []
}
```

问题：

- `file` 指向**内置层**，输入单元的 `Box` / `main` 完全缺失（SH-79 facet 2）；
- 只有 `name` / `cname` / `line` / `uses`，**没有字段表**，更没有字段类型、可见性、kind；
- `functions` 不含形参类型；
- 路径是绝对路径，含构建机目录；`compiler` 是自由文本，不可做版本判断；
- 单文件单 `prog` 语义，多单元工程无法汇总。

### 2.2 现有替代路径都不可靠

- 读 `.ctbuild/*.h`：只有 `pub` 面，私有字段与 `kind`（struct/union/enum）丢失；
- 读 `.ctbuild/*.c`：是生成物，受优化/缓存影响，不是契约；
- 外部解析 `.h.ct`：要复刻 CT 语法与 `pub` 规则，等于再写一个前端。

### 2.3 代码生成器真正需要的字段

SwiftCT 侧列出的最小集：struct 名、字段名、字段类型、字段可见性、kind（struct/union/enum）、
函数名与形参类型、所属单元/命名空间。**不含**位置也能工作，但有了更好（与 PH-58 联动）。

## 3 方案取舍

| 方案 | 做法 | 优点 | 代价 / 风险 | 结论 |
| --- | --- | --- | --- | --- |
| **A 扩 `--emit-map`** | 在现有 JSON 上加 `fields` / `visibility` / `kind` / `params`，并修好多单元 | 一个开关、一套序列化 | 把**调试产物**升格成公开契约；现有 `maps`/`calls` 的调试语义会被冻结；无法独立演进版本；修 SH-79 时会被迫兼容旧形状 | 不推荐 |
| **B 新入口 `--emit-model`**（推荐） | 新增 `ct build --emit-model <file|->`，独立 schema，复用 `--emit-map` 的遍历数据但不复用其输出 | 契约与调试解耦；可独立版本化；多单元汇总语义清晰；旧 `--emit-map` 保持调试用途 | 第二套序列化；两份遍历逻辑需收敛到一个内部模型，避免漂移 | **推荐** |
| **C 外部工具 + `--emit-map`** | 外部解析 `.h.ct` 或头文件补字段 | 编译器零改动 | 需要复刻前端；可见性/kind 仍不可得；生成器与语言版本强耦合 | 不采纳 |

**推荐 B**，理由：`--emit-map` 的消费者是调试与测试夹具，`--emit-model` 的消费者是外部生成器，
两者的稳定性承诺不同；把两者合并会让「改调试字段」变成「破生成器契约」。

## 4 格式草案

```json
{
  "schema": "ct.model",
  "schema_version": 1,
  "compiler": { "version": "0.53.1" },
  "units": [
    { "name": "lib::lib", "namespace": "lib", "path": "lib/lib.h.ct", "kind": "header" }
  ],
  "structs": [
    {
      "unit": "lib::lib",
      "name": "Box",
      "cname": "lib_Box",
      "kind": "struct",
      "visibility": "pub",
      "fields": [
        { "name": "n", "type": "int", "visibility": "private", "line": 3, "col": 9 }
      ]
    }
  ],
  "functions": [
    {
      "unit": "lib::lib",
      "name": "box_get",
      "cname": "lib_box_get",
      "visibility": "pub",
      "returns": "int",
      "params": [ { "name": "b", "type": "struct Box *" } ]
    }
  ]
}
```

规则：

1. **schema 版本**：`schema` 固定 `ct.model`，`schema_version` 为整数；同一大版本内只允许
   增加字段 / 增加条目，消费方必须忽略未知字段；删除或改义必须 +1 大版本。
2. **确定性**：单元按输入顺序、单元内声明按源码顺序；同一输入重复运行逐字节相同。
3. **路径**：一律相对项目根（`-I` 根），不写绝对路径；`lib/std` 内置层默认不导出。
4. **可见性**：`pub` / `private`，以 LANG-9 修好后的字段可见性为准；LANG-9 未落地前该字段标
   `"visibility": "unknown"`，不猜。
5. **kind**：`struct` / `union` / `enum`（enum 的成员表第一版可不导出，列为非目标）。
6. **不含**：C 语句 AST、表达式树、内联汇编、注释、位置信息（位置是可选字段，随 PH-58 补）。

## 5 与 PH-58 / LANG-10 的边界（是否合并）

**不合并成一条「机器可读输出」总需求，但共享一节口径。** 三条通道：

| 通道 | 内容 | 消费者 | 稳定性 |
| --- | --- | --- | --- |
| 诊断 JSON（LANG-10 / PH-58） | 错误/警告 + 位置 | 编辑器、CI、门禁 | 诊断码与级别可依赖 |
| 代码模型（本提案） | struct/字段/函数/可见性 | 代码生成器 | schema 版本化契约 |
| `--emit-map`（SH-79） | 调试映射（prog ↔ 源） | 测试夹具、调试 | 不承诺 |

共享口径只包括：JSON 转义、路径归一化、确定性输出、`schema` / `schema_version` 信封。
三条通道的生命周期不同，合并会把「诊断码变更」与「模型契约变更」绑在一起，反而增加破坏面。

## 6 代价与风险

| 项 | 估计 |
| --- | --- |
| 实现 | 新遍历/序列化约 **S–M**；若同时把 `--emit-map` 的内部遍历收敛，约 **M** |
| 测试 | golden 1 份 + 多单元夹具 1 份 + 确定性重跑 1 条 + 负例（无可见字段仍输出空数组） |
| 风险 1 | schema 漂移：生成器依赖未写入契约的字段 → 用 golden + 版本规则约束 |
| 风险 2 | 与 `--emit-map` 两套遍历漂移 → 共用一个内部模型结构，只换序列化 |
| 风险 3 | 可见性依赖 LANG-9；未落地时导出的 `visibility` 不可信 → 先标 `unknown`，不猜 |
| 风险 4 | 绝对路径泄露构建机信息 → 强制相对路径，测试断言不含 `/tmp/` |

## 7 非目标

- 不做通用 AST / IR 导出；
- 不做类型推断或语义补全；
- 不做 LSP / 增量模型服务；
- 不导出 enum 成员与宏（第一版）；
- 不替代 `--emit-map` 的调试用途；
- 不引入运行时反射。

## 8 对 ABI / 兼容性的影响

- **零 ABI**：只新增一个输出文件，不改 `.c` / `.h` / `.abi.h` 的生成逻辑，不新增 C 符号；
  依据是导出面只由 `--lib` 的 `lib_scan` 与 Emitter 的函数遍历决定，模型序列化不参与发射。
- **CLI 兼容**：新开关 `--emit-model` 是增量；不带该开关时产物逐字节不变。
- **旧 `--emit-map`**：保持现状（修 SH-79 的两个 facet 后仍按调试语义），不承诺 schema 稳定。

## 9 验收判据草案

| ID | 判据 |
| --- | --- |
| M1 | `ct build --emit-model m.json` 落文件，`schema` / `schema_version` 正确，可 `json.load` |
| M2 | 多单元工程：输入单元的 struct/function 全部在，`lib/std` 内置层不出现 |
| M3 | 每个字段含 `name` / `type` / `visibility`；每个函数含 `returns` / `params[].type` |
| M4 | 路径全为相对路径（断言不含 `/tmp/` 与绝对根） |
| M5 | 同一输入连续运行两次，输出逐字节相同 |
| M6 | 不带 `--emit-model` 时 `.c` / `.h` / `.abi.h` 零变化（golden 全绿） |
| M7 | LANG-9 未落地时 `visibility` 为 `unknown`；落地后私有/pub 区分正确 |
| M8 | 至少一个外部消费者夹具（SwiftCT PHP 生成器的最小读取脚本）能解析并按名取到字段 |

## 10 排位与依赖

- 位置：现有序列 `PH-53 → PH-54 → PH-57 → PH-58` 之后，拟占 **PH-59**；
- 依赖：LANG-9（可见性）必须先落地；PH-58 的字段位置是可选增强（M8 不依赖位置）；
- 与 SH-79：只共享内部遍历，**不依赖**它的修复；SH-79 仍按 patch 0.53.8 独立发；
- 与 PH-60（注记）：PH-59 必须在前，注记产出的元数据才有出口。

## 11 研判与后续

- 本提案需经过一次研判（两席 battle 或逐条反证），记录在
  [swiftct-mapping-proposal-review](../../docs/review/swiftct-mapping-proposal-review.md)；
- 研判通过后才写需求定稿（`REQ-MODEL-*`）、进 roadmap、开 phase 卡；
- 提案阶段不改 `selfhost/**`、不排 phase 卡。
