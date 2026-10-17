# DOC-8 · README 命令行表缺 L2 的四个开关

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Medium** |
| 锚点 | commit `ec97f99`（2026-10-17） |
| 文件 | [README.md](../../README.md#L44-L55) |
| 状态 | ✅ 已修复（2026-10-18） |

## 现象

README 的「命令行接口」表只列了基础用法与 Phase 6 的 `--emit-map` / `--std`，**完全没有**以下已在 L2 实现的开关：

| 开关 | 实现位置 | README 出现次数 |
| --- | --- | --- |
| `-I <dir>` | `driver.ct`（导入搜索根） | 0 |
| `--line` / `--no-line` | Phase 4（`#line` 覆盖） | 0 |
| `--ns-root <dir>` | Phase 5（目录 = namespace 校验） | 0 |
| `--diagnostics[=json]` | Phase 4（泄漏/签名告警格式） | 仅正文 1 次，无表项 |

## 证据

`grep -n -- "--line\|--ns-root\|-I <\|--diagnostics=" README.md` → **无匹配**。  
对应测试均存在：`test/modules/line`、`noline`、`ns_dir`、`ns_dir_mismatch`、`leak_json`、`sig_mismatch_json`，说明它们是受支持的一等能力。

## 影响

Phase 7 已宣布工具链形态完成，README 却是唯一面向用户的 CLI 参考；缺表意味着用户只能从 roadmap / 测试脚本反推用法。

## 修复建议

在 CLI 表中补四行（中英双语各一份），写清参数形态、默认值与作用域（compile / build），并与 `test/modules/*/args` 的实际拼写保持一致。

## 验证

表项与 `selfhost/src/driver.ct` 的参数解析分支一一对应；`grep` 上述四个开关在 README 均有命中。

## 处理（2026-10-18）

README 的 CLI 表（中英各一份）补齐 `-I` / `--line` / `--no-line` / `--ns-root` / `--diagnostics=json|text`，逐条与 `driver.ct` 的 `compile_main` / `build_main` 解析分支对齐：`--ns-root` 仅 build，其余两者皆可。
