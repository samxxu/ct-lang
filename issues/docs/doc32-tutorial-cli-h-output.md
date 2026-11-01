# DOC-32 · 教程命令表称普通 `.ct` 同时产出 `.h`，与同文 §1 和 README 相反

| 项 | 值 |
| --- | --- |
| 模块 | docs（教程） |
| 严重度 | Medium |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [docs/tutorial.md:442](../../docs/tutorial.md#L442)（中文）、[docs/tutorial.md:917](../../docs/tutorial.md#L917)（英文） |
| 状态 | 已修（2026-10-31）：文档已按建议更新（见 [issues/README.md](../README.md) 的 2026-10-31 处置表） |

## 现象

§10 命令行速查第一行：

> `ct <in.ct>` / `ct compile <in.ct>` ｜ 单文件编译，产出同名 `.c`/`.h`

但同一篇教程 §1（[:78](../../docs/tutorial.md#L78)）写的是「生成 hello.c（普通 `.ct` 不写 `.h`；
只有 `.h.ct` 单元才写）」，README 的 CLI 表（[README.md:54](../../README.md#L54)）也只对 `.h.ct`
输入承诺 `.h`。batch 30 之后 ct-ast 对普通 `.ct` 不再产头文件，命令表这一行是 DOC-24 修复时漏掉的残留。

## 证据

```text
$ ./ct-ast deref.ct -o deref.c ; echo $?
0
$ ls deref.h
ls: deref.h: No such file or directory
```

`emit_unit` 只在 `self->units[u].is_hdr` 时 `#include "<base>.h"`，`write_unit_header` 只对
`.h.ct` 单元调用（[Module.h.ct:944](../../selfhost/ct-ast/frontend/module/Module.h.ct#L944)）。

## 建议

把该行改为「单文件编译，产出 `<in>.c`；`.h.ct` 单元另产同名 `<in>.h`」，中英同步；
顺带核对 §10 表内 `ct build` 行的「每单元一份 `.c`/`.h`」是否也应加同样的限定（实际只有 `.h.ct` 单元出 `.h`）。
