# battle/p42-1 — PH-42 保留名豁免的范围

| 字段 | 值 |
| --- | --- |
| 争点 | 默认私有后，生成代码按名调用的元素方法（`retain` / `release`；`drop` / `handback` 已证明是 trait impl / static）如何保持可见：**A** 名字无条件公开（现稿 D42-6，10 条保留名）；**B** 协议判定（`retain` 返回自身类型且 `release` 同时存在，复用 `elem_has_life`）自动公开；**C** 取消豁免，全部由作者写 `pub`（迁移 52 条手工） |
| 当前 HEAD | `1b14b63a`（v0.40.1） |
| 触发理由 | 独立评审 P1-2 证明现稿的 `drop`/`handback` 保留名无证据，且「按名字无条件公开」会泄漏用户同名方法；三种方案都有判据，需裁决 |
| 相关 Issue/CR | PH-42（无独立 Issue） |
| proposer | REQ（主张 C） |
| opposition | REVIEW（主张 B） |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/design/phase42-draft.md`、`docs/decisions/**`；只写 `battle/p42-1/` 与 `/tmp` |

## 逐条判据

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 未写 `pub` 的方法不得进 `.h`、不得 external；用户自定义同名 `retain`/`release`/`drop`/`handback` 不被自动公开 | 夹具 + `nm`/`.h` |
| J-2 | 生成代码的跨单元元素调用可链接：`Vec`/`Map`/`Option`/`Result`/`Str` 的元素 `retain`/`release` 在消费者单元可解析 | `check-ast` 现有夹具 + 新的两单元夹具 |
| J-3 | 迁移可机械核对：每条需公开的方法都能在一个列表里列出并补 `pub`；不依赖名字特判 | 脚本输出（52 条）与源码 grep |
| J-4 | 实现代价与单一真源：不在 parser 与 emitter 复制两套协议谓词 | 改动点/行数 |
| J-5 | header/ABI 不变式：迁移后既有 `.h` 原型集合与 `expected.internal` 不变 | 消费者夹具 + `nm` 快照 |

## 证据要求

按主规范 §7.7 E1–E5：完整命令 + 原始输出、`file:line`（至少 1 条利于己方、1 条不利于己方）、可证伪预测、代价量化（文件/行数/门禁/回退）、对对方最强论点的 steelman。重点复现：

- `Emitter.h.ct` 的 `elem_has_life` / `emit_elem_protos` / `__elem_retain` 调用点；
- `lib/std` 的 `retain`/`release` 定义与 `drop`/`handback` 的实际链接性；
- 用户自定义 `impl Q { retain/release/drop/handback }` 的 `nm`/`.h`；
- 52 = 43 + 9 的清单；10 条保留名的来源；
- 显式 `pub` 迁移后 `Vec<int>`/`Map<char*,int>` 等消费者是否仍链接。
