# SH-117 · J-6 本仓段收尾：`out/ref` 证据与 `ref/out` 逃逸条款

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（J-6 证据）/ spec 条款 |
| 定性 | 证据缺口（v1.0 闸门 E-V1-6） |
| 严重度 | Medium |
| 锚点 | `78477712`（2026-11-24） |
| 依据 | [J-6 台账](../../docs/planning/j6-evidence/ledger.md) 本仓段 3 缺失 / 3 部分；[SH-104](sh104-j6-evidence-ledger.md)（台账与拆段） |
| 状态 | open |
| 处置证据 | **accepted（2026-11-24 所有者同意开卡；承接 SH-104 未闭合的本仓段证据）** |

## 1. 范围

SH-104 已验证的是**台账结构、外部段拆出与 check-docs 断言**；下列 7 项证据仍属未闭合，
由本条承接。全部闭合后，台账本仓段应为 `passed=28 partial=0 missing=0 blocked=1 external=5`
（`blocked` 只剩 P-1.3，已由所有者裁定归 v1.x）。

| 判据 | 现状 | 要交付什么 |
| --- | --- | --- |
| P-3.5 C 边界 | 部分：`char *p = s`、`return s`（`String`/`Str`）仍被接受并发射坏 C | 先判定是修还是立 bug 卡；三类负例入库：赋值 / `return` / 变参 |
| P-5.2 旧值释放 / 别名 | 缺失：`out String` / `ref String` 的 owning 旧值释放轨迹无夹具 | `p80_retain` 增 out/ref 组合：retain 右值 → release 旧值 → 写入，ASan 无 UAF |
| P-5.3 `ref` 赋值 vs 显式 release | 缺失：两侧都没有夹具 | `ref String` 赋值合法；`release(ref)` 硬错，两例各一 |
| P-5.4 `out` 错误路径 | 部分：错误路径（提前 `return` / `err:`）缺用例 | out 在提前返回路径上“赋值即生效”的夹具 |
| P-5.5 `out/ref` 借用类型 | 缺失：`out Str` / `ref int[]` 无夹具 | 白名单正例 + 越界/写负例 |
| P-5.6 泄漏 / 双释放 | 部分：缺 out/ref 专项 ASan 组合 | 把上述夹具并入 ASan 组合，零报告 |
| J-4b `ref/out` 逃逸 | 缺失：契约文本未成文 | [spec §4.68](../../docs/language-spec.md#468-ref--out-参数phase-78仅-ct-ast) 增“可存储 / 可传更长寿命位置”的条款 + 存储负例 |

## 2. 约束

- **不混改**：P-3.5 若需要改编译器行为（拒绝隐式转换），先另立 bug 卡并在本卡记指针，
  不在本卡同时做“改行为 + 补夹具”；
- 夹具一律走既有探针目录与命名（`test/ast/p80_retain*` 等），不新造框架；
- 每行闭合时在同一次提交里更新 [台账](../../docs/planning/j6-evidence/ledger.md) 的状态、
  指针与 `<!-- j6:counts -->`；`check-docs` 必须绿。

## 3. 验收

- 上表 7 行全部为 `已过`，且“现有证据”列有可复跑路径；
- `check-docs` 计数为 `passed=28 partial=0 missing=0 blocked=1 external=5`；
- 新增的负例在对应探针里确实变红（至少一次红证，含 `baseline: <sha>`）；
- ASan/UBSan 组合零报告；
- 不改语言布局、不改 `Box`/`String` 的既有语义（J-4b 只写条款，不改行为）。

## 4. 非目标

- 不处理外部段（P-3.6 / P-6.x，已转 std 包）；
- 不处理 P-1.3（迁移 lint，归 v1.x）；
- 不做 `LANG-26` 的绑定点转换（归 v1.1）。

## 5. 关联

- [J-6 台账](../../docs/planning/j6-evidence/ledger.md)
- [SH-104](sh104-j6-evidence-ledger.md)（台账/拆段；verified 范围不含本条）
- [v1-PH-0](../../docs/phases/v1-PH-0/card.md)（E-V1-6）
- [spec §4.68](../../docs/language-spec.md#468-ref--out-参数phase-78仅-ct-ast)
