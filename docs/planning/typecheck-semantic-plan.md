# 类型检查与语义检查方案（规划中）

| 项 | 值 |
| --- | --- |
| 性质 | 规划/施工序列；**未开卡**，不占 phase、不 bump |
| 日期 | 2026-11-18 |
| 基线 | `ed172075`（`v0.65.1`；Phase 66 已收口） |
| 依据 | [battle typecheck-1](../../battle/typecheck-1/verdict.md)（B′）、[verify](../../battle/typecheck-1/verify.json) |
| 结论 | **不全量进编译路径**；分 4 相 opt-in：类型核心 → 跨单元/泛型 → CFG → own/borrow；B1 先修 `char s[]` 误报 |
| 版本位 | PH-67 → v0.66.0；PH-68 → v0.67.0；PH-69 → v0.68.0；PH-70 → v0.69.0（`d=1`，见 AGENTS §0.3） |

## 0. 一句话

先把 `ct check --types` 从“12 类表达式节点的三处粗检”扩成可核验的类型检查，再补跨单元、控制流和
own/borrow；全部 opt-in，合法语料零误报后才讨论是否进 `ct build`。**不承诺 1.0 前全量类型系统。**

## 1. 现状（实测）

| 项 | 数字 |
| --- | --- |
| `ct check --types` | 4 个判定位置 / 6 条 L32 诊断；`chk_type` 覆盖 12 个表达式节点，`expr_type` 18 个 |
| `ct build` / `ct compile` | **不做类型检查**；struct 互赋、`p+p`、错误 return、break 越界、重复 case 均 rc=0（`ct build` 的 rc=1 来自 cc） |
| 合法语料误报 | `char s[]="x"` / `char s[2]="x"` 误报；234 是唯一合法语料 FP，FP=1/438≈0.23% |
| 跨单元 | `ct check` 单单元；41/530 旧语料、123 个 import 单元不可检 |
| 语义 | 无 CFG/基本块/pass 框架；own/borrow 只有作用域台账、局部硬错、泄漏 warning；break/重复 case/缺 return/未初始化不抓 |
| 规模 | TypeCheck 1,061 / Expr 7,217 / Stmt 4,144 / Parser 3,978 / Memory 481 行；全仓 70 个 N_*，真实缺口约 58 |
| 兼容面 | `check-all` 11 门禁绿；check-ast 1477/0；examples 151/45/20；`expected.*` 445 个 |

## 2. 目标 / 非目标

**目标**

- 让 `ct check --types` 能机械回答“这个表达式/调用/返回/赋值在 CT 语义下类型是否成立”；
- 让 `ct check --semantics` 覆盖控制流可判定子集与 CT 现有 own/borrow/Drop 契约；
- 每相独立可交付、可回退、可进 CI；
- 误报率可统计，合法语料零误报后逐相收紧。

**非目标**

- 不把全量类型检查塞进 `ct build`/`ct compile`；
- 不做 Rust 级借用检查、别名/并发完整证明；
- 不做 C UB/ABI/格式串检查；
- 不要求所有 C 合法写法通过 strict；strict 是 opt-in；
- 不承诺 1.0 前完成。

## 3. 四相

### PH-67 · 类型核心（v0.66.0）

| 项 | 内容 |
| --- | --- |
| 范围 | 表达式类型/转换：字面量、算术/比较/逻辑、指针/数组衰减、struct/union/enum、函数指针、cast、三元、闭包入口；四个位置（初值/赋值/return/容器实参） |
| 先修 | `char s[]` / `char s[2]` 的维度丢失（`typebuf` 丢维度，234） |
| 出口 | 438 个可检合法件 FP=0；234 转绿；`check-all` 零 golden 变化；skip 表逐条入账 |
| 估算 | 1,000–1,500 LOC + 夹具；3–4 周 |

### PH-68 · 调用/泛型/trait/跨单元（v0.67.0）

| 项 | 内容 |
| --- | --- |
| 范围 | 函数原型/变参/函数指针调用；trait 方法选择/歧义；泛型实例替换；容器方法；跨单元签名 |
| 机制 | `ct check` 复用 build 的单元图，读到 `import` 后再判；不写产物；单单元模式保留 |
| 出口 | 123 个 import 单元可检；跨单元夹具；FP 仍为 0；无产物 |
| 估算 | 1,200–2,000 LOC；4–6 周（Module 2,858 行，B2 是最大不确定项） |

### PH-69 · CFG/定值/控制流（v0.68.0）

| 项 | 内容 |
| --- | --- |
| 范围 | CFG/基本块；definite assignment；所有路径 return；break/continue/goto/switch；重复 case；不可达 |
| 边界 | 只做控制流可判定子集；不做完整数据流/别名 |
| 出口 | 控制流探针矩阵；`ct check --semantics`；合法 C 零误报；无 golden 变化 |
| 估算 | 800–1,500 LOC；3–5 周 |

### PH-70 · own/borrow/Drop + 包级 strict（v0.69.0）

| 项 | 内容 |
| --- | --- |
| 范围 | 作用域/逃逸/初始化/释放顺序；`own` 转移、`borrow` 回手、Drop 可达性；跨单元资源 |
| 边界 | 不做 Rust 级借用检查；不做别名/并发完整证明 |
| 出口 | own/borrow/Drop 探针；`ct.pkg` 包级 strict；仍 opt-in |
| 估算 | 500–1,000 LOC；3–5 周 |

## 4. 总量与对比

| 方案 | 编译器 LOC | phase 数 | 周期 | 兼容风险 |
| --- | --- | --- | --- | --- |
| B′ 四相 opt-in | **3,500–6,000** | 4 | 4–6 个月 | 低；不改编译路径 |
| A 全量进编译路径 | 4,000–8,000+ | ≥5 | 5–8 个月 | 高；FP/诊断/golden/包生态 |

A 的“一次清零”不可行：234 类 FP 未修、123 个 import 单元未覆盖、无 CFG；B′ 每相都有可回退边界。

## 5. 门禁与指标

| 指标 | 定义 | 门槛 |
| --- | --- | --- |
| 合法 FP | plain `ct check` 绿、`--types` 红的文件数 / plain 绿文件数 | B1 后 0；每相不得回退 |
| 覆盖 | 可检 `.ct` / 有 import 的 `.ct` / 跨单元夹具 | B1 438；B2 123 import |
| 漏报 | 固定探针矩阵（错误程序） | 每相新增，只增不减 |
| 回归 | check-all 11 门禁、golden、examples | 零非预期变化 |
| CI | `check-types` / `check-semantics` 进 check-all | 每相接入；opt-in 也要跑 |

## 6. Roadmap 与开卡条件

| 阶段 | 主题 | 版本 | 状态 |
| --- | --- | --- | --- |
| PH-67 | 类型核心 + 修 234 误报 | v0.66.0 | 规划中（未开卡） |
| PH-68 | 跨单元/泛型/trait | v0.67.0 | 规划中 |
| PH-69 | CFG/定值/控制流 | v0.68.0 | 规划中 |
| PH-70 | own/borrow/Drop + 包级 strict | v0.69.0 | 规划中 |

开卡条件：B1 先出 `char s[]` 红夹具与 FP 统计脚本；`check-all` 基线与 234 白名单锁定。
编译路径切换另立决策，不在本方案承诺。

## 7. 风险

| 风险 | 处置 |
| --- | --- |
| B2 低估（Module/import） | 先做单单元→build 图复用探针；超 6 周则拆 B2a/B2b |
| 误报把用户赶走 | 合法 FP=0 才进下一相；白名单只减不增 |
| 语义检查被当成 sound | UI/文档写“opt-in、非 sound”；不默认 `ct build` |
| C 超集兼容 | strict 只在 `ct check`；不拒普通 C |
| 包生态 ct/std 缺失 | B2 只验本仓；跨包另立验收 |
| 1.0 日期压力 | 只交付 B1/B2；B3/B4 不阻塞 1.0 |

## 8. 第一批任务（B1）

1. 红夹具：`char s[]="x"`、`char s[2]="x"`、234、struct 互赋、`p+p`、错误 return；
2. 修 `typebuf` 维度传递；
3. 扩 `chk_type` 的 12 节点到指针/数组/struct/union/enum/fnptr/cast；
4. FP 统计脚本 + 438 合法件扫描；
5. 保持 `ct compile/build` 输出与 golden 不变。

B1 不碰 `ct build` 默认路径，不碰 import 图，不碰 own/borrow。
