# 提案：`MAX_FUNCS` 按需增长（初始 512，安全阀 65536）

| 项 | 值 |
| --- | --- |
| 状态 | **已定（2026-11-23 所有者改判：当前 pre 窗口落地；初值 512、动态增长、65536 安全阀）** |
| 目标 | 当前 pre 窗口（v1.1 前；2026-11-23 所有者改判，不再等 `v1-PH-1 / S0`） |
| 依据 | [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md)、[v1 路线](../planning/v1-release-plan.md)、[D-014](../decisions/D-014.md) 的容量先例 |
| 范围 | 只改函数签名表的容量策略；不改语言语义/发射格式/其他上限 |

## 1. 背景

`MAX_FUNCS` 是整程序顶层 plain-C 签名预算（`static` helper 与 `pub` 包装器都算，
`impl` 方法不算）。PH-88 新增 76 个 `em_*` 自由函数后实测 **501/512，余 11**。

`v1-PH-0` 计划把 76 个切片改成穷尽 `match`，会新增 helper；固定 512 不应再作为功能上限。
所有者 2026-11-21 决定改为“按需增长 + 高安全阀”；2026-11-23 进一步改判：**提前到当前
pre 窗口落地，不再等 `v1-PH-1 / S0`**。`v1-PH-0` 不再按 501/512 施工，也不设 ≤11 预算。

## 2. 决策

- `MAX_FUNCS` 保留为**初始容量**（512）；
- 函数表按需增长：容量不足时 **翻倍**（512 → 1024 → 2048 …），
  `realloc` 后把新增区间清零；
- 新增 **安全阀 `MAX_FUNCS_MAX = 65536`**：到顶才报
  `too many functions (limit 65536, whole program)`，避免病态输入把宿主内存吃光；
- 小项目只占初始表（约 3–4MB）；大项目按实际函数数增长，不再被 512/4096 这种
  人为数字卡住；
- L0/L1 不动（冻结种子，只编译 L1/L2，源码函数数远小于 64）。

## 3. 精确改动

| 文件 | 改动 |
| --- | --- |
| `selfhost/ct-ast/frontend/sym/Symbols.h.ct` | `Symbols` 增 `fncap`；初始 `calloc(MAX_FUNCS + 64, sizeof(struct Fn))`；新增 `ensure_fn_capacity(need)`（**impl 方法**，不占 `MAX_FUNCS`）：`need > fncap` 时翻倍到至少 `need`，封顶 `MAX_FUNCS_MAX`，`realloc` + 清零新增区；`MAX_FUNCS_MAX 65536` |
| `selfhost/ct-ast/frontend/parse/ParseSupport.h.ct:336` | 追加前调用 `ensure_fn_capacity(nfunc + 1)`；删除“到 512 硬错”，只在安全阀报错 |
| `selfhost/ct-ast/frontend/parse/Expr.h.ct:2036` | 泛型单态化追加前同样扩容；`memcpy(&funcs[ni], …)` 在扩容之后按下标重取 |
| `selfhost/l2/core.ct:1257/5242` | `FuncSig` 表加 `fncap` + 增长 helper（**impl 方法**，避免 L2 自己撞 L1 的 64）；初始 512，封顶 65536 |
| `selfhost/l0/ctc.c` / `selfhost/l1/ctc.ct` | **不动**（64；只编译下一层种子） |
| `docs/language-spec.md` §7 | 把 `MAX_FUNCS` 从“用户可见固定上限”改为“初始容量 512 / 安全阀 65536”；越界文案同步 |
| `AGENTS.md` / `docs/history/phase-log.md` | 记录容量策略变更与 v1-PH-1/S0 |
| `test/ast/**` 容量夹具 | 增长测试（512→1024→2048）+ 安全阀 65536/65537 负例 |

同步检查：`grep -rn 'MAX_FUNCS' selfhost/` 应只剩初始容量、安全阀与增长判界；
`calloc(MAX_FUNCS + 64)` 的 `+64` 只作为初始余量，不再承担硬上限。

## 4. 指针与自举安全

- 当前所有 `funcs` 访问都是 `sym->funcs[i]` 下标（已 grep）；没有缓存 `struct Fn *`，
  `realloc` 不会留下悬垂指针；
- 唯一要小心的是 `Expr.h.ct:2061` 的 `memcpy(&funcs[ni], &funcs[gfi], …)`：
  必须在扩容之后按下标重新取地址；
- L2 由 L1 编译，增长 helper 必须是 `impl` 方法，不能新增 L2 顶层函数；
- L0/L1 的 64 只是种子链预算；它们编译的 L1/L2 源码函数数远小于 64。

## 5. 内存与耗时

`struct Fn` 约 6KB/行（名字、C 名、返回类型、16 个参数类型/维度、泛型/绑定等）：

| 容量 | ct-ast 表约 | L2 表约 |
| --- | --- | --- |
| 512 | ~3.5MB | ~0.5MB |
| 2048 | ~13MB | ~1.5MB |
| 4096 | ~25MB | ~3MB |
| 65536（安全阀） | ~400MB | ~50MB |

- 动态增长让常见项目停在 512/1024/2048，不会一启动就吃 25MB；
- 65536 只是防病态输入，不期望正常项目到达；
- 符号查找有 O(n) 线性扫描；增长后需记录编译耗时，必要时后续单独优化查找结构。

## 6. 门禁与证据

```sh
# 1) 增长：512 之后继续加函数，能编译并运行
sh test/ast/<growth-fixture>.sh        # 512/1024/2048 三档

# 2) 安全阀：65536 通过、65537 报
#    too many functions (limit 65536, whole program)

# 3) 自举链
bash selfhost/check-all.sh             # L0→L1→L2→ct-ast

# 4) 产物不变（≤501 函数）
# 66 语料逐字节、345 诊断逐字、fixed-point 2/3 轮

# 5) 内存/耗时
# 记录各档 RSS、ct-ast 编译耗时；与 v1.0 基线对比
```

验收：

- 增长到 512 以上不报错；到 65536 仍可编译；65537 报安全阀文案；
- `MAX_FUNCS`/`MAX_FUNCS_MAX` 在 ct-ast 与 L2 同步；`grep` 无旧的 512 硬错判界；
- L0→L1→L2→ct-ast 自举成功；`check-all` 全绿；
- ≤501 函数程序的生成 C 与 v1.0 逐字节一致；诊断不变；
- 单提交回滚（L2 + ct-ast 一起退）。

## 7. 与 `v1-PH-0` 的边界

- `v1-PH-0` **不再设** 501/512 或 ≤11 预算；本切片在当前 pre 窗口落地；
- 若本切片尚未合入，`v1-PH-0` 可按实测余量施工，但不得把 512 写成功能契约；
- 不再需要“预计超过 11 个 helper 就停止”的入口判据；容量由动态增长承担。

## 8. 非目标

- 不取消安全阀（仍保留确定性错误）；
- 不改 `MAX_METHODS` / `MAX_IO_CALLS` / `MAX_NODES` 等其他上限；
- 不改 `impl` 方法不计数、`pub` 包装器计数的既有口径；
- 不在 v1.0 发布前实现。

## 9. 风险与回滚

| 风险 | 缓解 |
| --- | --- |
| `realloc` 悬垂指针 | 已确认全部下标访问；`memcpy` 前扩容 |
| L2 冻结层改动破坏 oracle | 增长 helper 用 `impl`；≤501 函数产物逐字节比对；单提交回滚 |
| 65536 安全阀测试太慢 | 用生成器批量造函数；只在 nightly/容量门禁跑 |
| 线性查找变慢 | 记录 2048/4096/8192 编译耗时；必要时另立查找优化 |
| 安全阀仍被抱怨 | 先看实测；若确有 >65536 顶层函数的项目，再评估无上限或分表 |

回滚：`git revert` 本切片提交；L2 与 ct-ast 恢复固定 512 + 原硬错；重新跑 `check-all`。

## 10. 关联

- [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md)
- [v1 路线 §2.3](../planning/v1-release-plan.md)
- [PH-88 卡](../design/phase88.md) §7.5
- [p88_metrics](../history/p88_metrics.md) §4 #3
