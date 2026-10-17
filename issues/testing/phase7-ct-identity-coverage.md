# TEST-4 · Phase 7 的 `ct` 身份只测了一半

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | **Low** |
| 锚点 | commit `ec97f99`（2026-10-17） |
| 位置 | [selfhost/ct-tour.sh](../../selfhost/ct-tour.sh#L251-L287) 第 7 步 |
| 状态 | ✅ 已修复（2026-10-18） |

## 现象

Phase 7 的全部自动化断言集中在 `ct-tour.sh` 第 7 步，只覆盖四条：

1. `ct -v` → `ct v…`
2. `ctc -v` → `ctc v…`
3. `ct compile <f>` 与 L0 产物逐字节一致
4. `ct <f>`（默认子命令）与 L0 产物逐字节一致

**未覆盖**：

- `ct build … -o <dir>`（单入口下的多文件模式，含建议 `cc` 命令里的 `ct` 身份/路径）；
- `ct -h` / `ct --help` 的 usage 文本（`usage: %s …` 的 `ct` 分支）；
- `ctc compile` 与 `ct compile` 的产物一致性（别名路径只验证了 `-v`）；
- `ct` 下的未知选项/缺参错误路径。

## 证据

`ct-tour.sh` 第 7 步只调用 `-v`、`compile`、默认子命令；`run.sh` 只驱动 L0（`ctc.c`），无法覆盖 `ct` 身份。全仓 `grep "ct build"` 无测试命中。

## 影响

`ct` 是 Phase 7 的旗舰交付物，但只有一处、四条断言；一旦 `argv[0]` 分流或 `build` 分支被改动，回归网很薄。

## 修复建议

在 `ct-tour.sh` 第 7 步追加（成本很低）：

1. `ct -h`，断言首行含 `usage: ct`；
2. `ct build selfhost/src/driver.ct -o <tmp>`，断言退出 0 且产物与 `ctc` 身份构建一致；
3. `ctc compile <f>` 与 `ct compile <f>` 的 `cmp`。

注意：`ct build` 会触发缓存与多单元产物，建议在 `$work` 下新建独立目录，避免污染其它步骤。

## 验证

新增断言后 `bash selfhost/check-all.sh` 仍为 `OK (6 hard gates green)`；故意把 `driver.ct` 的 `strcmp(base, "ct")` 改坏（本地实验，不提交）应使新断言失败。

## 处理（2026-10-18）

`ct-tour.sh` 第 7 步新增：`ct -h` / `ctc -h` 的 usage 首行断言、`ct build selfhost/src/driver.ct` 的产物与 L1 构建树逐字节比较、`ct compile` 与 `ctc compile` 产物 `cmp`。`bash selfhost/ct-tour.sh` → OK。
