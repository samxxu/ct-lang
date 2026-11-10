# DOC-26 · 多处断言计数与 tag 布局过期（grammar 21→27、check-ast 105→317、v0.13.0 仍写旧布局）

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Medium |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 文件 | 见下表 |
| 状态 | 已修复（2026-10-31 落地；2026-11-10 复核：grammar 27 项、无 105 残留、tag 布局边界 `v0.12.0`） |

## 现象

三组可机械核对的事实性陈述已过期：

| 位置 | 文档说 | 实测 |
| --- | --- | --- |
| [README.md:293](../../README.md#L293)、[README.md:818](../../README.md#L818)、[AGENTS.md:178](../../AGENTS.md#L178)、[AGENTS.md:493](../../AGENTS.md#L493) | `check-grammar.py` **21 项断言** | `python3 editors/vscode/test/check-grammar.py` → **27 checks, 0 failed**；[check-all.sh:16](../../selfhost/check-all.sh#L16) 也写 27 |
| [docs/roadmap.md:28](../../docs/roadmap.md#L28)、[:65](../../docs/roadmap.md#L65)、[:945](../../docs/roadmap.md#L945)、[:1001](../../docs/roadmap.md#L1001) | `check-ast.sh`「Phase 10 现为 **105** 项」 | 当前 **317 passed**（同文件 [:904](../../docs/roadmap.md#L904) 已记 317） |
| [README.md:91](../../README.md#L91)、[README.md:554](../../README.md#L554) | `v0.13.0` 及更早 tag 仍是「`ctc.c` 在根、L2 在 `selfhost/src/**`、ct-ast 在 `selfhost/ast/**`」旧布局 | `git ls-tree v0.13.0` 只有 `selfhost/`，无根 `ctc.c`；旧布局止于 `v0.12.0`（[install.sh:83](../../install.sh#L83) 写对） |

## 证据

```bash
$ python3 editors/vscode/test/check-grammar.py
27 checks, 0 failed
$ bash selfhost/check-ast.sh | tail -1
== summary: 317 passed, 0 failed ==
$ git ls-tree --name-only v0.13.0 | head
LICENSE
LICENSE.EXCEPTION
README.md
...
selfhost
```

`install.sh` 的注释把边界写在 `v0.12.0`，与 git 事实一致，可作为 README 的对照。

## 影响

计数类漂移会让读者低估门禁规模（317 被读成 105，差三倍），也会让「新增断言」时的增量判断失真；
tag 布局写错会让离线安装用户对着不存在的 `ctc.c` 路径排错。这类陈述本可由一条命令核对，
持续错说明文档没有随门禁演进同步。

## 修复建议

- 把四处 grammar 计数改为 27（或改为「见 check-all.sh 的运行输出」避免再次漂移）。
- 把 roadmap 四处 `105` 改为当前值，并注明「计数随批次增长，以 `check-ast.sh` 末行 summary 为准」。
- 把 README 两处的布局边界改为 `v0.12.0`，与 `install.sh` 的注释对齐。

## 验证

修复后逐条执行上表的核对命令，文档陈述与输出一致；`bash selfhost/check-all.sh` 九关全绿。

## 处理（2026-10-31）

已修复：grammar 21→27；roadmap 的 105→317（4 处）；tag 布局边界改为 `v0.12.0`；另把版本表里 v0.12.0 的「当前版本」改为「由 v0.13.0 接替」。
