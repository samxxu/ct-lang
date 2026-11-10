# DOC-60 · README 首句「不做类型检查」与 `ct check` 的存在矛盾

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Medium |
| 锚点 | commit `4b9946b`（2026-11-03，`v0.19.0` + 1 commit） |
| 文件 | [README.md:5-6](../../README.md#L5-L6)；CLI 表 [L39](../../README.md#L39)（英文 [L118](../../README.md#L118)） |
| 状态 | 已修复（本轮，2026-11-03）；v0.26.4 复检再修「泛型」口径，见文末「复检」 |

## 现象

README 顶部用「不做类型检查、不做优化」概括 ct 的定位（中英两版同义）。但同一份 README 的 CLI 表
已列出 `ct check`，它会报 19.1–19.3 的四类发现（调用点 arity、实参类型粗粒度兼容、trait 方法歧义、
跨单元 impl 签名漂移），并以 `error:` + 退出码 1 表示「有发现」。

首句是全局断言，没有区分「默认编译路径」与「可选的检查入口」。

## 证据

- 中文首段 [README.md:5-6](../../README.md#L5-L6)；英文对照段同义。
- 同一文件的 CLI 行 [README.md:39](../../README.md#L39)（英文 [L118](../../README.md#L118)）：

  ```text
  ct check <in.ct>   只跑受限语义检查、不写 .c，四类发现以 error: 报告，退出 1 / 0
  ```

- 实测（副本环境，同一份签名漂移夹具）：

  ```text
  $ ct-ast compile drift.ct -o drift.c
  drift.ct:3: warning: signature mismatch ...
  rc=0

  $ ct-ast check drift.ct
  drift.ct:3: error: signature mismatch ...
  rc=1
  ```

  `compile` 只告警，`check` 直接判错并退出 1——这正是「做检查」的证据，与首句相反。

## 影响

按 README 首段判断的人会认为 ct 没有检查能力，不会发现 `ct check` 的用途；反过来，看到 `ct check`
的人会怀疑首句是否过期。两种读法都指向同一处文案缺口，属于对外失真（但未到 High：CLI 表可自证）。

## 修复建议

1. 首句限定作用域：「默认编译路径（`ct compile` / `ct build`）不做类型检查、不做优化；
   `ct check` 提供受限语义检查」；
2. 英文首段同改，措辞与 CLI 表一致；
3. 若不改首句，至少在 `ct check` 行注明「这是 ct 唯一的语义检查入口」。

## 验证

- 改后 `grep -n "不做类型检查" README.md` 的上下文含限定语；
- 首段与 CLI 表不再互相否定；
- `ct compile` / `ct build` 行为与产物不变（`test/run.sh` + `check-ast.sh` 全绿）。

## 处置

**认可，已修。** 采纳建议 1、2；建议 3 不必要（CLI 表本身已自证）。

- 中文首段改为「编译路径（`ct compile` / `ct build`）不做类型检查、不做优化；可选的 `ct check` 只做
  受限语义检查（调用点 arity、实参类型、trait 方法歧义、impl 签名漂移）」，见
  [README.md:5-8](../../README.md#L5-L8)。
- 英文首段同改，见 [README.md:87-91](../../README.md#L87-L91)。
- 顺带修掉同一矛盾的「not done by design」清单项：改为 `type checking beyond ct check's bounded
  checks`，见 [README.md:136](../../README.md#L136)。
- 验证：`python3 test/docs/check-docs.py` 绿；12 道门禁全绿，compile/build 行为未动。

## 复检（v0.26.4，2026-11-10）

Phase 26 落地泛型**函数**后，同一处清单项又漂了：README 仍把「泛型」整体列为「明确不做」，
与 [language-spec.md §8](../../docs/language-spec.md) 的口径（泛型函数已落地；泛型结构体 / trait /
约束 / 推导 / 多类型参数仍不在范围）相反。

按规范口径重写中英两条「明确不做」，并各补一条「泛型函数」能力项；同一份文档树里
`docs/patterns.md`（§2 标题与替换规则）、`docs/polymorphism.md`（非目标）、`docs/roadmap.md`
（Phase 5 待定项与 Batch 35 记录）里同样的「不做泛型」表述一并限定为「泛型结构体 / trait」。

验证：`python3 test/docs/check-docs.py` 绿；`./test/run.sh` 与 `bash selfhost/check-all.sh` 全绿。
