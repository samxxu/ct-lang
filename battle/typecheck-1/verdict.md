# battle/typecheck-1 判决

> **状态：`closed`**（2026-11-18；裁判 EDITOR；1 轮 claim/counter/evidence）。
> **结论：B 胜，但收窄为 B′：opt-in 分相；不承诺 1.0 前全量进编译路径。先修误报，再接跨单元，再做 CFG/own/borrow；进编译路径另立决策。**

## 1 逐项判决

| J | 结论 | 依据 |
| --- | --- | --- |
| J-1 覆盖/soundness | **A 的“窗口存在”成立，B 的“边界”成立；A 的“1.0 清零”未证** | `ct compile` / `ct build --emit-c` 对 struct 互赋、`p+p`、错误 return、break 越界、重复 case 全 rc=0；只有 `ct check --types` 的 4 个位置 / 6 条诊断在管。B 的 opt-in 不是 sound，但边界可写清。 |
| J-2 兼容性 | **B 胜** | 当前 `check-all` 11 门禁绿、check-ast 1477/0；全量进编译路径会让 `char s[]="x"` 类 0.23% 误报变成红线，并改 6 条 compile-warning / 3 类 semantics 断言。 |
| J-3 工作量 | **B 更可核；A 被低估** | TypeCheck 1061、Expr 7217、Stmt 4144、Parser 3978、Memory 481；`chk_type` 12 节点、`expr_type` 18、全仓 70 个 N_*（真实缺口约 58）。B 2,650–4,600 LOC 的算术成立但 B2 低估；现实 3,500–6,000，4 相 4–6 个月。A 4,000–8,000+、≥5 相。 |
| J-4 增量价值 | **B 胜** | B1 即可修 `char s[]` 误报、扩 4 位置；B2 可让 123 个 import 单元可检；B3 才做 CFG；B4 才碰 own/borrow。每相可独立回退。 |
| J-5 语义可行性 | **B 胜；A 的 scope 缺证据** | 当前无 CFG/IR/基本块/pass 框架；own/borrow 只有作用域台账 + 局部硬错 + 泄漏 warning；break/重复 case/缺 return/未初始化全不抓。A 声称的“全量语义”没有落地证据。 |
| J-6 roadmap/策略 | **B 胜** | 4 相 + 编译路径切换另立决策；A 的 phase 数自述 1–2 与 4 相冲突，不能直接排期。 |

## 2 采纳：B′

### B1 类型核心（PH-67，v0.66.0）

- 表达式类型/转换：字面量、算术/比较/逻辑、指针/数组衰减、struct/union/enum、函数指针、cast、三元、闭包入口。
- 四个位置：初值、赋值、return、容器/泛型固有方法实参；保持 6 条 L32 文案。
- **先修** `char s[] = "x"` / `char s[2] = "x"` 的维度丢失误报（`typebuf` 丢维度，234 是唯一合法 FP）。
- skip 表逐条入账；`import` 仍不检，明确边界。
- 出口：438 个可检合法件 FP=0；`check-all` 零 golden 变化。

### B2 调用/泛型/trait/跨单元（PH-68，v0.67.0）

- 函数原型/变参/函数指针调用；trait 方法选择/歧义；泛型实例替换；容器方法。
- `ct check` 复用 build 的单元图，读到 `import` 后再判，但不写产物；123 个 import 单元进入覆盖。
- 出口：41/530 旧语料中的 import 单元可检；跨单元夹具；零产物；FP 仍为 0。

### B3 CFG/定值/return/switch（PH-69，v0.68.0）

- 建 CFG/基本块；definite assignment、所有路径 return、break/continue/goto/switch、重复 case、不可达。
- 只做控制流可判定子集；不做完整数据流/别名。
- 出口：控制流探针矩阵；`ct check --semantics`；不误报合法 C。

### B4 own/borrow/Drop + 包级 strict（PH-70，v0.69.0）

- 作用域/逃逸/初始化/释放顺序；`own` 转移、`borrow` 回手、Drop 可达性；跨单元资源。
- 不做 Rust 级借用检查；不做别名/并发完整证明。
- 出口：own/borrow/Drop 探针；包级 `ct.pkg` strict；仍 opt-in。

### 编译路径切换（另立决策，不排进 1.0）

只有 B1–B4 全绿、合法语料 FP=0、跨单元覆盖、性能可接受，才讨论 `ct build` 默认 strict；否则保持 C 超集。

## 3 不采纳

- **A 的“1.0 前全量进编译路径”**：误报未清、跨单元未覆盖、无 CFG、golden/诊断面未定；不是 1–2 相。
- **把 B 说成 sound**：opt-in 不跑就没有保护；必须接 `check-all` 门禁并统计 FP/漏报。
- **Rust 级借用检查**：CT 的 `own/borrow` 不是完整所有权系统；本期只做可达子集。
- **全量 C 语义/UB 检查**：不在范围；C 超集兼容优先。

## 4 证据限制

- 语料 530 个当前 `.ct`，不是旧文写的 461/216；`expected.*` 445 个，不是 495。
- 包生态 `ct/std` 本机缺失，未验证；跨包单元图另算。
- `examples` 216 并非全绿（151/45/20），A 强制会放大迁移面。
- 当前 HEAD 被并发推进；证据基线 `ed172075`，selfhost/test diff 为 0。

## 5 下一步

- 写 `docs/planning/typecheck-semantic-plan.md`：4 相、验收、版本位、FP 指标、回退；roadmap 记规划中，不立即开卡。
- B1 先出 `char s[]` 红夹具，再改 `typebuf`/`chk_type`；不碰编译路径。
