# DOC-38 · README 干净 clone 段对 `.gitignore` 的描述不成立

| 项 | 值 |
| --- | --- |
| 模块 | docs（README） |
| 严重度 | Medium |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [README.md:333](../../README.md#L333)（中文）、[README.md:865](../../README.md#L865)（英文） |
| 状态 | 已修（2026-10-31）：文档已按建议更新（见 [issues/README.md](../README.md) 的 2026-10-31 处置表） |

## 现象

两处都写「`.gitignore` 里的生成物（`ctc`、`*.c`/`*.h`、`vendor/`）都不入库」/ "every build product
(`ctc`, `*.c`/`*.h`, `vendor/`) is `.gitignore`d"。

实际 `.gitignore` 只忽略 `/ctc`、`*.o`、`a.out`、`examples/*/*.c`、`examples/*/*.h`、`.ctcache/` 等；
**没有**全局 `*.c` / `*.h`（注释里明确写「test/cases/*.expected.c 与 *.expected.h 是有意的 golden，
不要加全局规则」），也**没有** `vendor/` 规则。

## 证据

```text
$ cat .gitignore
/ctc
*.o
a.out
examples/*/*.c
examples/*/*.h
.ctcache/
…
# test/cases/*.expected.c and *.expected.h are golden fixtures on purpose —
# do NOT add a global *.c / *.h rule.

$ git check-ignore -v foo.c vendor/x
（无输出 = 未被忽略）
```

## 建议

改为「`ctc`、`*.o`、`examples/**` 的生成物与 `.ctcache/` 已在 `.gitignore` 中；`test/cases/**` 的
`.expected.c`/`.h` 是有意入库的 golden，因此没有全局 `*.c`/`*.h` 规则」，中英同步。
如确实希望 `vendor/` 不入库，则应同时补 `.gitignore` 规则（属行为变更，需另行确认）。
