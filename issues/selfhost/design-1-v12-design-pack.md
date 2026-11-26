# DESIGN-1 · v1.2 设计包（S1b TIR/LIR + S2/S3 ADR + S4–S6 模式规范）

| 项 | 值 |
| --- | --- |
| 模块 | design（架构/契约；不写 `selfhost` 代码） |
| 定性 | 并行准备（S1a-0 期间的 C 轨道） |
| 严重度 | **P1**（S1b 开工前必须完成，避免代码等人） |
| 锚点 | `2026-11-26` |
| 依据 | [`v1-PH-2` 并行轨道](../../docs/phases/v1-PH-2/card.md)、[typed-lowered-ir](../../docs/proposals/typed-lowered-ir.md)、[D-026](../../docs/decisions/D-026.md) |
| 状态 | open |
| 负责人 | REQ / REVIEW |
| 处置证据 | 2026-11-26：D1–D3 落 [tir-lir-contract](../../docs/design/tir-lir-contract.md)，D7 落 [tir-lir-fixtures](../../docs/design/tir-lir-fixtures.md)；D4/D5（S2/S3 ADR）与 D6（ADT 模式规范）未写，写法见 §7。不改 `selfhost/**`，不触发 seed。 |

## 1 目标

在 S1a-0（C2 剩余数组）收口之前，把 S1b 与后续功能阶段的**设计输入**做完：

1. TIR/LIR 契约与不变量；
2. 清理 CFG 的出口与清理集规则；
3. `E-IR-1xx` 诊断码清单；
4. 下标协议 ADR（S2）；
5. 函子 ADR（S3）；
6. ADT 模式扩展规范（S4–S6）与负例清单。

## 2 交付

| # | 交付 | 目标文件 | 判据 |
| --- | --- | --- | --- |
| D1 | TIR/LIR 契约 | `docs/design/tir-lir-contract.md` | 类型/值类别/临时值/实例化字段齐全；emitter 只消费 LIR 的边界明确；与 typed-lowered-ir §4–§8 一致 |
| D2 | 清理 CFG 规则 | 同上 §清理 | 六类出口（`return`/`break`/`continue`/合法 `goto`/`?` 失败/正常落底）各有清理边；deferred LIFO、errdefer 只走错误边；`goto` 逃逸硬错 |
| D3 | 验证器与码表 | `docs/design/tir-lir-contract.md` + `docs/diagnostics/codes.md` | TIR/LIR 各一个检查点；`E-IR-1xx` 命名、触发条件、负例一一对应 |
| D4 | 下标协议 ADR | `docs/decisions/D-028.md`（拟） | `v[0]` / `v["k"]` 按参数类型匹配；读/写/借写三形态；无匹配硬错并列候选；`+=`/`++`/`&x[k]` 二值化 |
| D5 | 函子 ADR | `docs/decisions/D-029.md`（拟） | `(A,B) => R` 与 trait/闭包/函数指针关系；类型语法、ABI、IDE 展开、与 `fn` 指针的互操作 |
| D6 | ADT 模式规范 | `docs/language-spec.md` 草案 + `docs/design/adt-patterns.md` | 字面量/嵌套/结构体/or/守卫/泛型 ADT 的文法与穷尽算法；每项至少 3 个负例（漏分支、守卫不穷尽、未绑定变量） |
| D7 | 夹具清单 | `docs/design/tir-lir-fixtures.md` | S1b/S2/S3/S4–S6 的 golden 与负例文件清单，供 TEST 提前准备 |

## 3 顺序

`D1 → D2 → D3 → D4 → D5 → D6 → D7`；D4/D5 可并行，D6 依赖 S4 的语法草案。

## 4 约束

- **不写 `selfhost/**` 代码**，不改 `bootstrap/**`，不跑 `gen-seed.sh`；
- 设计结论必须与现有 ADR/提案一致；冲突时先开裁定，不在实现中夹带；
- 每份交付走 REVIEW 复核；未复核的不作为 S1b 输入；
- 新 ADR 编号在写之前先查 `docs/decisions/`，避免撞号。

## 5 非目标

- 不实现 TIR/LIR、不写 parser/emitter 代码；
- 不改用户语法（除 D6 的规范草案）；
- 不决定 S8b/S8c 的具体改写范围。

## 6 关联

- [`v1-PH-2` 并行轨道](../../docs/phases/v1-PH-2/card.md)
- [typed-lowered-ir](../../docs/proposals/typed-lowered-ir.md)
- [D-026](../../docs/decisions/D-026.md)
- [TEST-27](../testing/test27-feature-examples-pointer-free.md)（B 轨道，样例/文档）
- [SH-94](../selfhost/sh94-giant-units-duplicate-constants.md)（A 轨道，编译器代码）

## 7 进度（2026-11-26）

| # | 交付 | 状态 | 落点 |
| --- | --- | --- | --- |
| D1 | TIR/LIR 契约 | **已交** | [docs/design/tir-lir-contract.md](../../docs/design/tir-lir-contract.md) §2–§4 |
| D2 | 清理 CFG 规则 | **已交** | 同上 §4.3–§4.4（六类出口 + 错误边） |
| D3 | 验证器与码表 | **已交（草）** | 同上 §5；`E-IR-101..110` 只在草表，S1b 与 registry 同批登记 |
| D4 | 下标协议 ADR | 待写 | 拟 `docs/decisions/D-028.md`；编号写前再核 |
| D5 | 函子 ADR | 待写 | 拟 `docs/decisions/D-029.md`；编号写前再核 |
| D6 | ADT 模式规范 | 待写 | 依赖 S4 的语法草案；草案落 `docs/design/adt-patterns.md` |
| D7 | 夹具清单 | **已交** | [docs/design/tir-lir-fixtures.md](../../docs/design/tir-lir-fixtures.md) |

D4/D5 以 ADR 成文时会触发 T-8（2026-11-20 之后的 ADR 需非作者角色 `签收:`），
所以**成文与签收同批提交**，不先落一份无签收的 ADR 让门禁变红。
