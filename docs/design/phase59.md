# Phase 59 · 模型导出 `--emit-model`（S0：无 import 单单元端到端）

**状态：规划中**（已立项，待实施；M1 = 无 import 单单元端到端）

| 项 | 值 |
| --- | --- |
| 依据 | [模型导出提案](../proposals/ct-model-export-proposal.md) §3 方案 B、§4 格式、§9 M1–M7；[静态映射可行性与决策](static-mapping-feasibility.md) §2；[研判 §4](../review/swiftct-mapping-proposal-review.md) |
| 版本位 | **待定**：PH-54 已占用 v0.54.0–v0.60.0；候选 v0.61.0，需负责人确认后再 bump |
| 只动 | `selfhost/ct-ast/tool/driver/Driver.h.ct`、`selfhost/ct-ast/backend/emit/Emitter.h.ct`、`selfhost/ct-ast/main.ct`、`test/model/**`、`docs/**` |
| 不碰 | `selfhost/ct-ast/frontend/TypeCheck.h.ct`、`selfhost/l2/**`、`golden/**`、`.ai-engineering` |
| 在途冲突 | 当前工作树有他人在改 `Driver.h.ct` / `main.ct` / `Pkg.h.ct` / `test/pkg/run.sh`；开工前须等其落定，提交用显式路径 |

## 1. 目标

给外部生成器一个**语言无关、版本化、确定性**的声明层出口，且首版只覆盖一条最窄的可用链路：

```
case1/box.h.ct  →  ct --emit-model m.json  →  夹具生成器  →  box_gen.h/.c  →  cc  →  运行
```

三条硬边界：

1. **无 import、单单元**。首版不接受多单元、多根、`import`。
2. **CT 侧自有运行时 0 行**。不提供 Swift 运行时、holder、事件分发器；样例里的生成器是**夹具**，不是产品。
3. **不自己拼模型图**。多单元不靠包侧遍历补，等 SH-79（0.53.8）修好出口后进 M2。

**不做**：见 §1.1 非目标。判据只覆盖 §1 的同步单向最小链路（J8），非目标不设判据、也不设「预留」断言。

### 1.1 非目标（首版一律不做，不留钩子）

| 非目标 | 说明 |
| --- | --- |
| 异步数据 | 模型里不表达异步事件，schema 不预留 `async` 字段 |
| 流式推送 | 不做流式数据通道、不做增量推送 |
| 运行时增删节点 | 不做节点级增删语义；**不预留**「稳定 id + 整子树替换」这类本期不实现的钩子 |
| 多单元 / 多根 | 见 §5 M2，只登记不实现 |
| 字段级回指 | 见 §8 待定项，`fields[]` 不写 `loc` |
| 可见性过滤 | 全字段导出（决策 §2.2），不做过滤 |
| AST / IR 导出、`--emit-map` 语义变更 | 不在本卡范围 |

非目标一律「不实现 + 不预留」，等有真实消费者再按实际用例立需求；不得以「先留个字段」的方式夹带。

## 2. 交付物

| # | 交付 | 文件 |
| --- | --- | --- |
| D1 | `--emit-model <file\|->` 开关与 `schema` 信封 | `tool/driver/Driver.h.ct`、`main.ct` |
| D2 | 模型序列化：struct 全字段、函数签名、相对路径、确定性 | `backend/emit/Emitter.h.ct` |
| D3 | 端到端夹具 `test/model/case1/`（输入 + 期望 JSON + 期望运行输出；**含一个枚举字段**） | `test/model/**` |
| D4 | 夹具生成器（最小实现，明确标注「仅夹具」） | `test/model/gen.sh` |
| D5 | 门禁段 `== PH59 ==`（J1–J9 断言） | `test/model/run.sh` |
| D6 | 文档：可行性与决策、本卡、`--emit-model` 用法 | `docs/design/static-mapping-feasibility.md`、本文件、`docs/package-guide.md` 或 CLI 文档 |

## 3. 任务清单

每项可单独回滚；夹具先落、跑出红，再实现，夹具与实现同一次提交转绿。

| # | 任务 | 交付物 | 验收命令 | effort |
| --- | --- | --- | --- | --- |
| T1 | CLI 与信封 | `--emit-model` 解析；`schema=ct.model`、`schema_version=1`、`compiler.version` | `ct --emit-model /tmp/m.json test/model/case1/box.h.ct -o /tmp/b.c`；`python3 -c 'json.load(open("/tmp/m.json"))'` RC=0 | S |
| T2 | struct 全字段 + 枚举 | `structs[].fields[]` 含非 `pub` 字段，`name`/`type`/`visibility`；顺序 = 声明顺序；`kind == "enum"` 的条目含成员名与成员值 | case1 含 1 个私有字段 + 1 个枚举；断言私有字段出现且 `visibility=="unknown"`，枚举成员逐项匹配 | M |
| T3 | 函数签名 | `functions[].{name,cname,visibility,returns,params[].type}` | case1 含 2 个函数，断言形参类型逐个匹配 | S |
| T4 | 路径与确定性 | 相对路径；内置层不导出；重跑逐字节相同 | 断言 JSON 不含 `/tmp/`、不含 `lib/std`；`cmp` 两次输出 | S |
| T5 | 端到端样例 | `gen.sh` 从 JSON 生成 `box_gen.h/.c`，`cc` 编译运行 | `bash test/model/run.sh` 中 `== PH59-E2E ==` 全绿，stdout 匹配期望 | M |
| T6 | 负例与文档 | 非法输入 rc≠0 且不落半份文件；CLI 用法入文档 | `ct --emit-model /tmp/m.json bad.ct` RC≠0 且 `/tmp/m.json` 不存在；`test/docs/check-docs.py` RC=0 | S |

## 4. 判据（二值）

| # | 判据 | 验收 |
| --- | --- | --- |
| J1 | `--emit-model` 落文件可 `json.load`，`schema=="ct.model"`、`schema_version==1` | 直接跑 |
| J2 | **每个** struct 的**全部**字段（含非 `pub`）都在 `fields[]`，各有 `name`/`type`/`visibility`；顺序与声明一致 | case1 逐字段比对 |
| J3 | 每个函数含 `returns` 与 `params[].type`，与源码逐字一致 | case1 逐函数比对 |
| J4 | `kind` 取值集合为 `struct` / `union` / `enum`；`enum` 条目含每个成员的 `name` 与 `value`，且 `value` 与源码一致 | case1 逐成员比对 |
| J5 | 路径全为相对路径；不含 `/tmp/`、不含绝对根；`lib/std` 内置层不出现 | `grep` 断言 |
| J6 | 同一输入连续运行两次，输出逐字节相同 | `cmp` |
| J7 | 不带 `--emit-model` 时 `.c` / `.h` / `.abi.h` 零变化 | 既有 golden 全绿 |
| J8 | **端到端**：case1 → JSON → `gen.sh` → `cc` → 运行 rc=0，stdout 与期望逐字节一致 | `bash test/model/run.sh` |
| J9 | 非法输入 rc≠0，且目标文件不存在（不得留半份） | 负例夹具 |
| J10 | `bash selfhost/check-all.sh` 绿；`test/docs/check-docs.py` 绿 | 直接跑 |

> 说明：J1–J9 都以 **compile 模式**断言。`build` 模式的 `units[].path` 受 SH-79 facet 2 影响（`file` 固定写 `units[0].prog`），因此本卡只要求 `build --emit-model` 能落文件、不崩；`units` 正确性归 M2。

## 5 里程碑

| # | 里程碑 | 范围 | 依赖 |
| --- | --- | --- | --- |
| **M1** | 无 import 单单元端到端（本卡主体） | J1–J10 | 无 |
| **M2** | 多单元 / 多根 | `units[]` 正确、合并语义、`build` 模式判据 | **SH-79（0.53.8）两项 facet 落地**；§3.1 待定项（多根是否合并）定稿 |

M2 不在本卡实现，仅登记。**多单元不得用「生成器自己拼模型图」绕过**：那会把 CT 的出口缺陷固化进包。

## 6 红证

实现前先落夹具并真实跑出失败，记录退出码与原始文案；实现与夹具同一次提交转绿，提交正文带一行：

```
red: rc=<N>, "<失败文案>"
```

禁止用实现后的复跑顶替红证；禁止改判据、改 golden、改版本号凑绿。

## 7 回滚

只新增一个输出开关与一份夹具，不改代码发射；回滚 = `git revert` 单个提交。`.c` / `.h` / `.abi.h` 零影响（J7 兜底）。

## 8 未决（不阻塞本卡，禁止用默认值写死）

| 项 | 阻塞什么 |
| --- | --- |
| 字段级回指 | `fields[].loc`；本卡不写该键，Xcode 只能跳到 struct/函数级 |
| 版本位 | 与 PH-54 的 v0.54–v0.60 冲突，收口 bump 前须确认 |
