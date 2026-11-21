# 提案：`MAX_FUNCS` 512 → 1024（v1-PH-1 / S0 容量切片）

| 项 | 值 |
| --- | --- |
| 状态 | **草案（2026-11-21 所有者定：按 1024，落 v1-PH-1）** |
| 目标 | v1.1 `v1-PH-1 / S0`（容量切片；不阻塞 `v1-PH-0`） |
| 依据 | [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md)、[v1 路线](../planning/v1-release-plan.md)、[D-014](../decisions/D-014.md) 的容量先例 |
| 范围 | 只改 `MAX_FUNCS` 预算与镜像；不改语言语义/发射格式/其他上限 |

## 1. 背景

`MAX_FUNCS` 是整程序顶层 plain-C 签名预算（`static` helper 与 `pub` 包装器都算，
`impl` 方法不算）。PH-88 新增 76 个 `em_*` 自由函数后实测 **501/512，余 11**。

`v1-PH-0` 计划把 76 个切片改成穷尽 `match`，会新增 helper；若超过 11 个就会撞顶。
所有者 2026-11-21 决定：**容量切片不做在 `v1-PH-0`，改到 `v1-PH-1 / S0`**。
因此 `v1-PH-0` 必须按 501/512 约束施工；一旦预计新增 >11 个顶层函数，停止并把本切片提前。

## 2. 决策

`MAX_FUNCS` **512 → 1024**（翻倍）。理由：

- 直接给 `v1-PH-0` 的 `match` 改造留出 ~523 个槽，不需要再用 `impl` 方法绕；
- 1024 仍是有界预算，保留“越界硬报错”的确定性；
- 表已是 `calloc(MAX_FUNCS + 64)`，内存按行数线性增长，实测后登记。

## 3. 精确改动

| 文件 | 现状 | 改为 | 说明 |
| --- | --- | --- | --- |
| `selfhost/ct-ast/frontend/sym/Symbols.h.ct:36` | `#define MAX_FUNCS 512` | `1024` | ct-ast 主预算 |
| `selfhost/ct-ast/frontend/parse/Expr.h.ct:65` | `#define MAX_FUNCS 512` | `1024` | 解析判界镜像 |
| `selfhost/ct-ast/frontend/parse/ParseSupport.h.ct:27` | `#define MAX_FUNCS 512` | `1024` | 声明判界镜像 |
| `selfhost/l2/core.ct:45` | `#define MAX_FUNCS 512` | `1024` | **冻结层例外**：L2 编译 ct-ast，必须 ≥ ct-ast 预算 |
| `selfhost/l0/ctc.c` / `selfhost/l1/ctc.ct` | 64 | **不动** | 它们只编译 L1/L2，源码函数数远小于 64 |
| `docs/language-spec.md` §7 | ct-ast `MAX_FUNCS 512` | `1024` | 容量表与错误文案 |
| `AGENTS.md` / `docs/history/phase-log.md` | 501/512 | 1024 记录 | 版本/收口记录 |
| `test/ast/**` 容量夹具 | 501/512 | 1024/1025 | 临界 + 越界文案 |

同步检查：`grep -rn 'MAX_FUNCS' selfhost/` 只应剩上述四处 `#define` 与判界文案；
`Symbols.h.ct:1782` 的 `calloc(MAX_FUNCS + 64)` 自动跟随，无需改数字。

## 4. 自举链约束

安装链是 L0 → L1 → L2 → ct-ast：

- L0/L1 的 64 是它们**自己编译的程序**的预算；L1 编 L2 时 L2 源码函数数 < 64，不受影响；
- L2 编 ct-ast，所以 L2 的 512 必须 ≥ ct-ast 的实际函数数。只改 ct-ast 不改 L2，
  ct-ast 长到 513 就会先被 L2 拒绝；因此 L2 必须同改 1024；
- 改 L2 是**冻结层例外**：需要在本切片卡面记录批准（参照 Phase 18/54 的容量调整先例），
  并在自举链上验证 L2 行为不变（只放大预算，不改变 501 以下程序的产物）。

## 5. 门禁与证据

```sh
# 1) 容量临界 + 越界负例（生成 1024/1025 个顶层函数）
sh test/ast/<cap-fixture>.sh          # 1024 通过；1025 报 too many functions (limit 1024, whole program)

# 2) 自举链
bash selfhost/check-all.sh            # 11 门禁

# 3) 产物不变（501 以下程序）
# 66 语料逐字节、345 诊断逐字、fixed-point 2/3 轮

# 4) 内存/时间
# 记录 sizeof(Func) * 512 的增量、ct-ast 编译 RSS 与耗时
```

验收：

- `MAX_FUNCS` 四处同步为 1024，`grep` 无 512 残留；
- 1024 函数程序通过，1025 报错文案为 `too many functions (limit 1024, whole program)`；
- L0→L1→L2→ct-ast 自举成功；`check-all` 全绿；
- 501 以下程序的生成 C 与 v1.0 逐字节一致；诊断不变；
- 内存/时间增量有实测记录，未出现数量级退化；
- 单提交回滚（L2 + ct-ast 一起退）。

## 6. 与 `v1-PH-0` 的边界

- `v1-PH-0` **不包含**本切片；它按 501/512 施工，新增顶层函数预算 ≤11；
- 若 `match` 改造预计超过 11 个 helper：停止该切片，先把本提案的 S0 提前，
  再继续；不得在 `v1-PH-0` 内顺手提上限；
- 若最终用 `impl` 方法把新增量压到 ≤11，本切片仍可按计划在 `v1-PH-1` 做，
  但不阻塞 `v1-PH-0`。

## 7. 非目标

- 不做无界动态增长（仍保留固定预算 + 硬错）；
- 不改 `MAX_METHODS` / `MAX_IO_CALLS` / `MAX_NODES` 等其他上限；
- 不改 `impl` 方法不计数、`pub` 包装器计数的既有口径；
- 不在 v1.0 发布前实现。

## 8. 风险与回滚

| 风险 | 缓解 |
| --- | --- |
| L2 冻结层改动破坏 oracle | 只放大预算；501 以下产物逐字节比对；单提交回滚 |
| 内存/时间退化 | 启动时记录表大小与 RSS；超过阈值则回退 |
| `v1-PH-0` 先撞顶 | 施工前复算 helper 预算；>11 即停止并提前 S0 |
| 四处宏漂移 | `grep` 门禁 + 容量夹具；`Symbols.h.ct` 注释同步 |

回滚：`git revert` 本切片提交；L2 与 ct-ast 四处宏一起退回 512；重新跑 `check-all`。

## 9. 关联

- [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md)
- [v1 路线 §2.3](../planning/v1-release-plan.md)
- [PH-88 卡](../design/phase88.md) §7.5
- [p88_metrics](../history/p88_metrics.md) §4 #3
