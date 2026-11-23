# 57_check_types —— `check --types` 的近相样例

| 项 | 值 |
| --- | --- |
| 能力 | `ct-ast check <input> --types` |
| 源码 | `prog.ct`（一个纯函数、一次调用） |
| 门禁 | `test/run.sh` 的 near-phase 层跑 `check --types` 并要求退出码 0 |

`check` 是独立入口：`--types` 才打开类型检查，默认的 build 路径不受影响。
