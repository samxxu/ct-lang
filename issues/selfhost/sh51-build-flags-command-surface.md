# SH-51 · `--cflags` / `--ldflags` 经 `system()` 原样执行，透传面大于参数面

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | Info |
| 锚点 | commit `4b9946b`（2026-11-03，`v0.19.0` + 1 commit） |
| 文件 | [Module.h.ct:1087-1088](../../selfhost/ct-ast/frontend/module/Module.h.ct#L1087-L1088)（cflags）、[L1114](../../selfhost/ct-ast/frontend/module/Module.h.ct#L1114)（ldflags）、[L1120](../../selfhost/ct-ast/frontend/module/Module.h.ct#L1120)（`system(cmd)`）、[L1241](../../selfhost/ct-ast/frontend/module/Module.h.ct#L1241)（`ct_cmd_raw` 定义） |
| 状态 | 已采纳方案 B（文档标注，本轮，2026-11-03） |

## 现象

`ct build` 组装编译命令时，把 `--cflags` / `--ldflags` 的值经 `ct_cmd_raw` 原样拼进命令串，最后用
`system(cmd)` 执行。标志值不做转义或引号包裹，shell 元字符（`;`、`&&`、`$()`、反引号、重定向）
会被解释为命令的一部分。

```text
1087  ct_cmd_raw(cmd, ..., self->cflags);
1114  ct_cmd_raw(cmd, ..., self->ldflags);
1120  st = system(cmd);
1241  static int ct_cmd_raw(...)   /* 原样拼接 */
```

## 证据

- 静态可确认：`ct_cmd_raw` 只做字符串拼接（`:1241`），`system()` 走 `/bin/sh`（`:1120`）。
- 触发面：`ct build ... --cflags "<任意字符串>"`；同一路径也被 `test/pkg/run.sh` 与 `check-ast.sh`
  的 build 用例使用，说明这是公开入口而非内部细节。
- 正常用法（`--cflags "-Wall -O2"`）工作正常，问题只在输入含 shell 语法时出现。

## 影响

Info：2026-11-02 的复核已把「raw 透传」列为既定契约与治理决策，普通构建脚本无风险。但当前实现把
「编译参数透传」放大成了「命令片段透传」：在 CI 里拼接来自 `ct.pkg` 或环境变量的 flags 时，
不可信输入可直接执行任意命令。是否需要收紧属设计决策，不是缺陷判定。

## 修复建议

供决策，本轮不实施：

- **方案 A（收紧）**：改用 `execvp` + 参数数组，flags 仅按空白切分；不支持引号内含空格，
  需在文档写明。优点是无 shell 解释面；缺点是与现有「raw 透传」契约不完全兼容。
- **方案 B（维持 + 标注）**：保留 `system()`，在 README / 包指南中明确「`--cflags` / `--ldflags`
  是 shell 片段，勿传入不可信内容」，并把该条并入 `ct.pkg` 安全说明。

## 验证

若选 A：`test/pkg/run.sh`、`check-ast.sh` 的 build 用例全绿；`--cflags "-DFOO=1 -Wall"` 正常透传；
含 `;` 的 flags 被视为普通参数或被明确拒绝。
若选 B：文档新增说明，且 `test/docs/check-docs.py` 通过。

## 处置

**采纳方案 B；方案 A 暂不实施。**

- 教程中英两张表在 `--cflags` / `--ldflags` 行补「值按 shell 片段原样拼进命令，不要传入不可信内容」，
  见 [docs/tutorial.md:512](../../docs/tutorial.md#L512) 与 [L1070](../../docs/tutorial.md#L1070)。
- 不选 A 的理由：A 会把「raw 透传」契约改掉（引号内含空格的 flags 行为变化），而当前仍有用例依赖
  空格分隔与引号语义；真正要收紧时应与 `ct.pkg` 的不可信输入治理一起设计，而不是在单个 issue 里改。
- 方案 A 仍是正确方向：`execvp` + 参数数组能消除整类注入面。建议在 19.x/20 的 CLI 硬化里单独立项。
- 验证：`python3 test/docs/check-docs.py` 绿。
